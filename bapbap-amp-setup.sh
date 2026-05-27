#!/usr/bin/env bash
# BAPBAP Custom Server — One-shot AMP instance setup / re-sync script.
#
# What it does:
#   1. Stops the AMP instance (if running)
#   2. Downloads latest kvp + configmanifest directly from GitHub raw
#      (bypasses any broken git-clone in DeploymentTemplates)
#   3. Writes them to the instance dir as GenericModule.kvp + configmanifest.json
#   4. Restarts the instance
#
# Run as the amp user (or via sudo -u amp bash). Re-runnable any time the
# config schema changes; idempotent.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Sonic0810/BAPBAP-CustomServer-AMPTemplates/main/bapbap-amp-setup.sh | sudo -u amp bash
#
# Or with a custom instance name:
#   curl -fsSL https://raw.githubusercontent.com/Sonic0810/BAPBAP-CustomServer-AMPTemplates/main/bapbap-amp-setup.sh | sudo -u amp INSTANCE=MyOtherInstance bash

set -euo pipefail

INSTANCE="${INSTANCE:-FinalesBattleRoyale01}"
REPO="${REPO:-Sonic0810/BAPBAP-CustomServer-AMPTemplates}"
BRANCH="${BRANCH:-main}"

AMP_HOME="${AMP_HOME:-/home/amp/.ampdata}"
INST_DIR="$AMP_HOME/instances/$INSTANCE"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

echo "==> BAPBAP AMP setup"
echo "    instance:  $INSTANCE"
echo "    repo:      $REPO@$BRANCH"
echo "    inst dir:  $INST_DIR"
echo

if [ ! -d "$INST_DIR" ]; then
  echo "!! Instance directory not found: $INST_DIR"
  echo "   Create the instance in the AMP web UI first (Generic Module),"
  echo "   then re-run this script."
  exit 1
fi

echo "==> Stopping instance (if running)"
ampinstmgr stopinstance "$INSTANCE" 2>/dev/null || true
sleep 2

echo "==> Backing up existing kvp + configmanifest"
ts="$(date +%Y%m%d-%H%M%S)"
[ -f "$INST_DIR/GenericModule.kvp" ]   && cp "$INST_DIR/GenericModule.kvp"   "$INST_DIR/GenericModule.kvp.bak.$ts"   || true
[ -f "$INST_DIR/configmanifest.json" ] && cp "$INST_DIR/configmanifest.json" "$INST_DIR/configmanifest.json.bak.$ts" || true

echo "==> Downloading latest kvp from GitHub raw"
curl -fsSL "$RAW/bapcustomservergithub.kvp"       -o "$INST_DIR/GenericModule.kvp"

echo "==> Downloading latest configmanifest from GitHub raw"
curl -fsSL "$RAW/bapcustomservergithubconfig.json" -o "$INST_DIR/configmanifest.json"

echo "==> Verifying kvp content"
if grep -q '^App.UpdateSources=\[' "$INST_DIR/GenericModule.kvp"; then
  echo "    OK: UpdateSources is inlined JSON"
elif grep -q '^App.UpdateSources=@IncludeJson' "$INST_DIR/GenericModule.kvp"; then
  echo "!!  UpdateSources still uses @IncludeJson — that means GitHub raw served the old version."
  echo "    Try again in 30 seconds (CDN cache) or check the repo state."
  exit 2
else
  echo "!!  No App.UpdateSources line found at all — abort"
  exit 3
fi

echo "==> Starting instance"
ampinstmgr startinstance "$INSTANCE"

cat <<EOF

==> Setup complete.

Next steps (in the AMP web UI for the instance):
  1. Open the instance ($INSTANCE)
  2. Click "Update"   — downloads the 585 MB server bundle from the latest GitHub release
  3. Wait for the update to finish (about 1-2 minutes on a Hetzner box)
  4. Click "Start"    — server comes up on the configured ports

For future updates:
  - Server code / mod / game files: just click Update + Start in the AMP UI.
  - kvp / configmanifest schema changes (rare): re-run this script.

EOF
