"""Provision over authenticated Noise; secrets are read privately, never argv."""

import argparse
import asyncio
import base64
import getpass
import logging

from aioesphomeapi import APIClient


def validate_key(key):
    raw = base64.b64decode(key, validate=True)
    if len(raw) != 32 or not any(raw):
        raise ValueError("A nonzero, already-provisioned API Noise key is required")
    return key


def validate_token(token):
    if len(token) > 256 or any(not 33 <= ord(c) <= 126 for c in token):
        raise ValueError(
            "Token must be at most 256 printable non-whitespace ASCII characters"
        )
    return token


async def provision(host, key, token):
    client = APIClient(host, 6053, None, noise_psk=validate_key(key))
    try:
        await client.connect(login=True, log_errors=False)
        _, services = await client.list_entities_services()
        service = next(s for s in services if s.name == "provision_voice_broker_token")
        await client.execute_service(service, {"token": validate_token(token)})
        # Service is deliberately write-only; no token or token-derived state returned.
        await asyncio.sleep(0.5)
    finally:
        await client.disconnect()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host")
    args = parser.parse_args()
    logging.disable(logging.CRITICAL)
    key = getpass.getpass("Existing API Noise key: ")
    token = getpass.getpass("Broker token (empty clears it): ")
    try:
        asyncio.run(provision(args.host, key, token))
    except Exception:
        raise SystemExit(
            "Provisioning failed; details suppressed to protect credentials"
        ) from None
    print(
        "Credential action sent. Confirm the device was idle; verify a new Live conversation separately."
    )


if __name__ == "__main__":
    main()
