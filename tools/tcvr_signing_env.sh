#!/bin/bash
# Source this before exporting a store build:   source tools/tcvr_signing_env.sh
# Loads the release signing key from the local vault into the environment variables Godot and
# tools/build_quest.py read. The password never touches a file in git, argv, or the terminal.
# Custody rules + restore drill: knowledge-base intelligence/runbooks/store-signing-key-custody.md
TCVR_VAULT="${TCVR_VAULT:-F:/AgileLens/vault/tcvr-release}"
if [ ! -f "$TCVR_VAULT/tcvr-release.p12" ] || [ ! -f "$TCVR_VAULT/tcvr-release.password" ]; then
  echo "[signing] vault missing at $TCVR_VAULT -- restore from the private KB (credentials/signing-keys/tank-commander-vr)" >&2
  return 1 2>/dev/null || exit 1
fi
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$TCVR_VAULT/tcvr-release.p12"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="tcvr-release"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$TCVR_VAULT/tcvr-release.password")"
echo "[signing] release key loaded from $TCVR_VAULT (alias tcvr-release)"
