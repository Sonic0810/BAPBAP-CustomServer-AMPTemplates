#!/usr/bin/env bash
# BAPBAP Custom Server — One-shot AMP instance setup / re-install / update.
#
# Does EVERYTHING:
#   1. Stops the AMP instance
#   2. Downloads the latest server bundle (~585 MB) from GitHub Releases
#   3. Extracts into the instance dir, fixes line-endings + exec bits
#   4. Writes a fresh kvp + configmanifest (no AMP auto-update, AMP only runs the binary)
#   5. Starts the instance
#
# Re-runnable any time. Use it for first install, re-install after corruption,
# or pulling new server code.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Sonic0810/BAPBAP-CustomServer-AMPTemplates/main/bapbap-amp-setup.sh | tr -d '\r' | sudo -u amp bash
#
# Or with a custom instance name:
#   curl -fsSL https://raw.githubusercontent.com/Sonic0810/BAPBAP-CustomServer-AMPTemplates/main/bapbap-amp-setup.sh | tr -d '\r' | sudo -u amp INSTANCE=MyOtherInstance bash

set -euo pipefail

INSTANCE="${INSTANCE:-FinalesBattleRoyale01}"
REPO="${REPO:-Sonic0810/BAPBAP-CustomServer-AMPTemplates}"
BRANCH="${BRANCH:-main}"
BUNDLE_NAME="${BUNDLE_NAME:-bapcustomserver-amp-full-linux-wine.zip}"
BUNDLE_URL="${BUNDLE_URL:-https://github.com/$REPO/releases/latest/download/$BUNDLE_NAME}"

AMP_HOME="${AMP_HOME:-/home/amp/.ampdata}"
INST_DIR="$AMP_HOME/instances/$INSTANCE"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
TMP_ZIP="/tmp/bapbap-bundle-$$.zip"

cleanup() { rm -f "$TMP_ZIP" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> BAPBAP AMP one-shot setup"
echo "    instance:  $INSTANCE"
echo "    inst dir:  $INST_DIR"
echo "    bundle:    $BUNDLE_URL"
echo "    kvp src:   $RAW/bapcustomservergithub.kvp"
echo

if [ ! -d "$INST_DIR" ]; then
  echo "!! Instance directory not found: $INST_DIR"
  echo "   Create the instance in the AMP web UI first (Generic Module),"
  echo "   then re-run this script."
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "!! 'unzip' is not installed. Install it (apt-get install unzip) and re-run."
  exit 1
fi

echo "==> Stopping instance (if running)"
ampinstmgr stopinstance "$INSTANCE" 2>/dev/null || true
sleep 2

echo "==> Backing up old kvp + configmanifest"
ts="$(date +%Y%m%d-%H%M%S)"
[ -f "$INST_DIR/GenericModule.kvp" ]   && cp "$INST_DIR/GenericModule.kvp"   "$INST_DIR/GenericModule.kvp.bak.$ts"   || true
[ -f "$INST_DIR/configmanifest.json" ] && cp "$INST_DIR/configmanifest.json" "$INST_DIR/configmanifest.json.bak.$ts" || true

echo "==> Downloading server bundle (~585 MB) from GitHub Releases"
curl -fL "$BUNDLE_URL" -o "$TMP_ZIP" --progress-bar

echo "==> Extracting into $INST_DIR"
unzip -oq "$TMP_ZIP" -d "$INST_DIR"

echo "==> Stripping CRLF from shell scripts (safe even if already LF)"
for f in "$INST_DIR/BapCustomServer"/*.sh; do
  [ -f "$f" ] && sed -i 's/\r$//' "$f"
done

echo "==> Setting exec bits on scripts + binaries"
for f in BapCustomServer createdump amp-webpanel-start.sh start-linux-wine.sh start-match.sh; do
  p="$INST_DIR/BapCustomServer/$f"
  [ -f "$p" ] && chmod +x "$p" || true
done

echo "==> Downloading fresh kvp + configmanifest from GitHub raw"
curl -fsSL "$RAW/bapcustomservergithub.kvp"       -o "$INST_DIR/GenericModule.kvp"
curl -fsSL "$RAW/bapcustomservergithubconfig.json" -o "$INST_DIR/configmanifest.json"

echo "==> Sanity-checking kvp"
if grep -q '^App.UpdateSources=\[{"UpdateStageName":"Download' "$INST_DIR/GenericModule.kvp"; then
  echo "!!  kvp still has the GithubRelease download stage. That stage is what causes the"
  echo "    'Updating now / Unable to run' loop. Pulling a newer kvp from origin/main..."
  exit 4
fi
if grep -q '^App.UpdateSources=' "$INST_DIR/GenericModule.kvp"; then
  echo "    OK: kvp UpdateSources contains only chmod stages (no auto-download)."
fi

echo "==> Verifying critical files exist"
required=(
  "$INST_DIR/BapCustomServer/BapCustomServer"
  "$INST_DIR/BapCustomServer/amp-webpanel-start.sh"
  "$INST_DIR/BapCustomServer/appsettings.json"
)
missing=0
for f in "${required[@]}"; do
  if [ ! -f "$f" ]; then
    echo "    !! MISSING: $f"
    missing=1
  fi
done
[ $missing -eq 0 ] || { echo "Bundle extraction incomplete. Aborting."; exit 5; }
echo "    OK: server binary + start script + appsettings.json present"

echo "==> Starting instance"
ampinstmgr startinstance "$INSTANCE"

cat <<EOF

==> DONE.

Instance "$INSTANCE" is starting. The AMP web UI Console tab shows live output.

You should NOT need to click "Update" in the AMP UI anymore — this script
handled the download. If you want fresh code in the future, just re-run:

  curl -fsSL $RAW/bapbap-amp-setup.sh | tr -d '\r' | sudo -u amp bash

That fetches a new bundle + kvp + configmanifest and restarts the instance.

EOF
