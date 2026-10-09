"""oidc-issuer: sign short-lived OIDC tokens for local Unix users.

`serve` handles one connection. systemd starts it per connection
(oidc-issuer.socket, Accept=yes) with the accepted socket as stdin. The caller
is identified by the UID the kernel recorded when it connected (SO_PEERCRED).
Nothing is read from the connection, so there is no request to parse or forge.
A declared client gets one JSON line back: {"token": ..., "expires_at": ...};
anyone else gets {"error": ...}.

`keygen` creates a signing key on this machine, seals it with systemd-creds,
and prints the public half for the Nix config. The private key is only ever
on disk in sealed form, and the sealed file only decrypts on this machine.
"""

import argparse
import base64
import hashlib
import json
import os
import pwd
import socket
import struct
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import TypedDict

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

# ES256 is ECDSA over P-256, matching the JWKS in modules/common/oidc-issuer.nix.
ALGORITHM = "ES256"
CURVE = ec.SECP256R1
COORDINATE_BYTES = 32
# struct ucred: pid, uid, gid
UCRED = struct.Struct("3i")


class PublicKey(TypedDict):
    kid: str
    x: str
    y: str


class Config(TypedDict):
    """Written by machines/reaper/oidc-issuer/default.nix."""

    issuer: str
    audience: str
    subjectPrefix: str
    tokenLifetimeSeconds: int
    clients: list[str]
    activeKey: PublicKey | None
    stateDirectory: str
    credentialName: str
    systemdCreds: str


class IssuerError(Exception):
    pass


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def public_key_of(key: ec.EllipticCurvePrivateKey) -> PublicKey:
    numbers = key.public_key().public_numbers()
    x = b64url(numbers.x.to_bytes(COORDINATE_BYTES, "big"))
    y = b64url(numbers.y.to_bytes(COORDINATE_BYTES, "big"))
    # RFC 7638 thumbprint: the required members, sorted, without whitespace
    required = {"crv": "P-256", "kty": "EC", "x": x, "y": y}
    canonical = json.dumps(required, sort_keys=True, separators=(",", ":"))
    return {"kid": b64url(hashlib.sha256(canonical.encode()).digest()), "x": x, "y": y}


def load_signing_key(config: Config) -> tuple[ec.EllipticCurvePrivateKey, PublicKey]:
    active = config["activeKey"]
    if active is None:
        raise IssuerError("no active signing key is configured")
    # systemd decrypted the sealed key into this per-service, in-memory directory
    path = Path(os.environ["CREDENTIALS_DIRECTORY"]) / config["credentialName"]
    key = serialization.load_pem_private_key(path.read_bytes(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(
        key.curve, CURVE
    ):
        raise IssuerError(f"{path} is not a P-256 key")
    # A key AWS cannot find in the published JWKS yields tokens it rejects, so
    # refuse to sign with anything but the published active key.
    if public_key_of(key) != active:
        raise IssuerError(
            f"the sealed key is not the published key {active['kid']}; "
            "check my.oidcIssuer.activeKid and my.oidcIssuer.publicKeys"
        )
    return key, active


def peer_credentials(conn: socket.socket) -> tuple[int, int]:
    """(pid, uid) of the connecting process, as the kernel recorded at connect()."""
    pid, uid, _gid = UCRED.unpack(
        conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, UCRED.size)
    )
    return pid, uid


def describe_process(pid: int) -> str:
    """Best effort, for the audit log only: by now the PID may be another process."""
    try:
        command = Path(f"/proc/{pid}/comm").read_text().strip()
        cgroup = Path(f"/proc/{pid}/cgroup").read_text().strip().rpartition(":")[2]
    except OSError:
        return f"pid {pid}"
    return f"pid {pid} {command} in {cgroup}"


def reply(conn: socket.socket, message: dict[str, str | int]) -> None:
    conn.sendall(json.dumps(message).encode() + b"\n")


def serve(config: Config) -> int:
    conn = socket.socket(fileno=sys.stdin.fileno())
    pid, uid = peer_credentials(conn)
    try:
        user = pwd.getpwuid(uid).pw_name
    except KeyError:
        user = None
    caller = f"{user or f'uid {uid}'} ({describe_process(pid)})"

    if user is None or user not in config["clients"]:
        log(f"refused {caller}: not in my.oidcIssuer.clients")
        reply(conn, {"error": f"{user or f'uid {uid}'} is not an OIDC issuer client"})
        return 0

    try:
        key, public = load_signing_key(config)
    except IssuerError as error:
        log(f"refused {caller}: {error}")
        reply(conn, {"error": str(error)})
        return 1

    now = int(time.time())
    claims = {
        "iss": config["issuer"],
        "sub": f"{config['subjectPrefix']}:{user}",
        "aud": config["audience"],
        "iat": now,
        "exp": now + config["tokenLifetimeSeconds"],
        "jti": str(uuid.uuid4()),
    }
    token = jwt.encode(claims, key, algorithm=ALGORITHM, headers={"kid": public["kid"]})
    reply(conn, {"token": token, "expires_at": claims["exp"]})
    log(f"issued {claims['jti']} sub={claims['sub']} exp={claims['exp']} to {caller}")
    return 0


def keygen(config: Config) -> int:
    if os.geteuid() != 0:
        log(
            "oidc-issuer-keygen: run as root; systemd-creds seals with the root-only host key"
        )
        return 1
    key = ec.generate_private_key(CURVE())
    public = public_key_of(key)
    path = Path(config["stateDirectory"]) / f"{public['kid']}.cred"
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    # --with-key=auto seals with the host key in /var/lib/systemd plus the TPM2
    # when there is one; the embedded name must match LoadCredentialEncrypted=.
    subprocess.run(
        [
            config["systemdCreds"],
            "encrypt",
            "--with-key=auto",
            f"--name={config['credentialName']}",
            "-",
            str(path),
        ],
        input=pem,
        check=True,
    )
    print(f"""Sealed a new signing key into {path}.

Publish it by adding this entry to my.oidcIssuer.publicKeys:

  {{
    kid = "{public["kid"]}";
    x = "{public["x"]}";
    y = "{public["y"]}";
  }}

then sign with it by setting my.oidcIssuer.activeKid = "{public["kid"]}";
and deploy buoy (publishes the key) and reaper (signs with it).""")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="oidc-issuer")
    parser.add_argument("command", choices=["serve", "keygen"])
    parser.add_argument("config", type=Path, help="JSON config written by Nix")
    args = parser.parse_args()
    config: Config = json.loads(args.config.read_text())
    return serve(config) if args.command == "serve" else keygen(config)


if __name__ == "__main__":
    sys.exit(main())
