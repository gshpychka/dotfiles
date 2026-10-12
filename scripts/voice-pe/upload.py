"""Upload a prebuilt OTA image only; no configuration/code generation."""

import argparse
import getpass
from pathlib import Path

from esphome.espota2 import run_ota

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path)
parser.add_argument("host")
parser.add_argument("--ask-password", action="store_true")
args = parser.parse_args()
password = getpass.getpass("OTA password: ") if args.ask_password else None
code, _ = run_ota(args.host, 3232, password, args.image)
raise SystemExit(code)
