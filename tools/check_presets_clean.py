"""Fail if export_presets.cfg carries signing secrets (this repo is public).

Run before committing:  python tools/check_presets_clean.py
"""
import re
import sys

text = open("export_presets.cfg", encoding="utf-8").read()
bad = [m.group(0).split("=")[0] for m in re.finditer(r'^keystore/(release|debug)(_user|_password)?="(.+)"$', text, re.M)]
if bad:
    print("export_presets.cfg has non-blank signing fields: " + ", ".join(bad) +
          " -- keep them blank and use GODOT_ANDROID_KEYSTORE_RELEASE_* env vars (tools/tcvr_signing_env.sh).")
    sys.exit(1)
print("export_presets.cfg signing fields are blank: OK")
