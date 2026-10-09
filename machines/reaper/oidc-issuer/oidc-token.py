"""oidc-token: get a token from reaper's OIDC issuer, or trade it for AWS credentials.

  oidc-token                      print a fresh token (a JWT) for the current user
  oidc-token claims               print the token's claims, e.g. to write a trust policy
  oidc-token aws --role-arn ARN   assume ARN with a fresh token, print credential_process JSON

AWS CLI and SDKs refresh such a profile on their own when the credentials expire:

  [profile lab]
  credential_process = oidc-token aws --role-arn arn:aws:iam::123456789012:role/lab
"""

import argparse
import base64
import json
import re
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

# substituted by machines/reaper/oidc-issuer/default.nix
SOCKET_PATH = "@socketPath@"
ISSUER_UNIT = "@issuerUnit@"

TIMEOUT_SECONDS = 30
STS_VERSION = "2011-06-15"
STS_NAMESPACES = {"sts": f"https://sts.amazonaws.com/doc/{STS_VERSION}/"}
# RoleSessionName allows [\w+=,.@-]{2,64}
SESSION_NAME_DISALLOWED = re.compile(r"[^\w+=,.@-]")
SESSION_NAME_MAX = 64


class Failure(Exception):
    pass


def fetch_token() -> str:
    # The issuer identifies this process by its UID; there is nothing to send.
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(TIMEOUT_SECONDS)
            conn.connect(SOCKET_PATH)
            chunks = []
            while chunk := conn.recv(4096):
                chunks.append(chunk)
    except FileNotFoundError:
        raise Failure(
            f"{SOCKET_PATH} does not exist: the issuer has no active signing key yet "
            "(sudo oidc-issuer-keygen, then set my.oidcIssuer.activeKid)"
        ) from None
    except PermissionError:
        raise Failure(
            f"no access to {SOCKET_PATH}: add this user to my.oidcIssuer.clients "
            "(a new group membership applies from the next login)"
        ) from None
    except ConnectionRefusedError:
        raise Failure(
            f"nothing is listening on {SOCKET_PATH}: is {ISSUER_UNIT}.socket running?"
        ) from None
    if not chunks:
        raise Failure(
            f"the issuer answered nothing; see journalctl -u '{ISSUER_UNIT}@*'"
        )
    reply = json.loads(b"".join(chunks))
    if "error" in reply:
        raise Failure(f"the issuer refused: {reply['error']}")
    return reply["token"]


def decode_claims(token: str) -> dict:
    """The token's payload, unverified: only for display and session naming."""
    payload = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


def sts_error(document: ET.Element, claims: dict) -> Failure:
    code = document.findtext("sts:Error/sts:Code", namespaces=STS_NAMESPACES)
    message = document.findtext("sts:Error/sts:Message", namespaces=STS_NAMESPACES)
    hint = {
        "InvalidIdentityToken": f"AWS could not fetch or match the signing key: is {claims['iss']}/.well-known/openid-configuration reachable, and is the key published?",
        "AccessDenied": f"the role's trust policy must allow sts:AssumeRoleWithWebIdentity for aud={claims['aud']} sub={claims['sub']}",
    }.get(code or "")
    return Failure(f"STS {code}: {message}" + (f"\n  {hint}" if hint else ""))


def assume_role(
    token: str,
    role_arn: str,
    session_name: str | None,
    duration: int,
    region: str | None,
) -> dict:
    claims = decode_claims(token)
    if session_name is None:
        # CloudTrail shows this next to the role: name the subject that assumed it
        session_name = SESSION_NAME_DISALLOWED.sub("-", claims["sub"])[
            :SESSION_NAME_MAX
        ]
    endpoint = (
        f"https://sts.{region}.amazonaws.com/"
        if region
        else "https://sts.amazonaws.com/"
    )
    # AssumeRoleWithWebIdentity is unsigned: the token is the only credential.
    body = urllib.parse.urlencode(
        {
            "Action": "AssumeRoleWithWebIdentity",
            "Version": STS_VERSION,
            "RoleArn": role_arn,
            "RoleSessionName": session_name,
            "WebIdentityToken": token,
            "DurationSeconds": str(duration),
        }
    ).encode()
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            document = ET.fromstring(response.read())
    except urllib.error.HTTPError as error:
        try:
            raise sts_error(ET.fromstring(error.read()), claims) from None
        except ET.ParseError:
            raise Failure(f"STS answered HTTP {error.code}") from None
    except urllib.error.URLError as error:
        raise Failure(f"could not reach {endpoint}: {error.reason}") from None

    credentials = document.find(
        "sts:AssumeRoleWithWebIdentityResult/sts:Credentials", STS_NAMESPACES
    )
    if credentials is None:
        raise Failure("STS answered without credentials")
    return {
        "Version": 1,
        "AccessKeyId": credentials.findtext(
            "sts:AccessKeyId", namespaces=STS_NAMESPACES
        ),
        "SecretAccessKey": credentials.findtext(
            "sts:SecretAccessKey", namespaces=STS_NAMESPACES
        ),
        "SessionToken": credentials.findtext(
            "sts:SessionToken", namespaces=STS_NAMESPACES
        ),
        "Expiration": credentials.findtext("sts:Expiration", namespaces=STS_NAMESPACES),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="oidc-token",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    commands = parser.add_subparsers(dest="command")
    commands.add_parser("token", help="print a fresh token (the default)")
    commands.add_parser("claims", help="print a fresh token's claims")
    aws = commands.add_parser(
        "aws", help="assume an AWS role; print credential_process JSON"
    )
    aws.add_argument("--role-arn", required=True)
    aws.add_argument(
        "--session-name", help="RoleSessionName (default: the token's subject)"
    )
    aws.add_argument(
        "--duration",
        type=int,
        default=3600,
        help="session seconds, at most the role's maximum (default: %(default)s)",
    )
    aws.add_argument(
        "--region", help="use this region's STS endpoint (default: the global one)"
    )
    args = parser.parse_args()

    try:
        token = fetch_token()
        if args.command == "claims":
            print(json.dumps(decode_claims(token), indent=2))
        elif args.command == "aws":
            credentials = assume_role(
                token, args.role_arn, args.session_name, args.duration, args.region
            )
            print(json.dumps(credentials))
        else:
            print(token)
    except Failure as failure:
        print(f"oidc-token: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
