"""Embed public connection settings in Info.plist. No credentials or deployment."""
import argparse
import json
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("config", type=Path)
args = parser.parse_args()
config = json.loads(args.config.read_text())
expected = {"issuer", "domain", "clientID", "api", "artifactHosts", "redirect"}
if set(config) != expected or "REPLACE" in json.dumps(config) or "replace." in json.dumps(config):
    parser.error("Supply actual approved public settings; secrets are not accepted")
path = Path(__file__).resolve().parents[1] / "PresentationViewer/Info.plist"
info = plistlib.loads(path.read_bytes())
info["CloudConnectionJSON"] = json.dumps(config, separators=(",", ":"))
path.write_bytes(plistlib.dumps(info, sort_keys=False))
print("Public settings embedded. Runtime validates HTTPS/issuer/callback before login.")
