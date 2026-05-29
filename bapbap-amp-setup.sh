#!/usr/bin/env bash
# BAPBAP Custom Server — One-shot AMP instance setup / repair script.
#
# What it does:
#   1. Stops the AMP instance
#   2. Backs up old kvp + configmanifest
#   3. Downloads kvp + configmanifest + ports + updates + metaconfig from GitHub raw
#      (so AMP's @IncludeJson resolves correctly)
#   4. (Optional, default ON) Pre-installs the 585 MB server bundle so the
#      first Start works immediately. After this, all future updates run
#      via the AMP UI "Update" button and only touch game files; user data
#      under data/ and logs/ is NOT in the update zip and stays untouched.
#   5. Starts the instance
#
# Re-runnable any time the kvp schema changes or you want to repair a stuck
# instance.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Sonic0810/BAPBAP-CustomServer-AMPTemplates/main/bapbap-amp-setup.sh | tr -d '\r' | sudo -u amp bash
#
# Skip the pre-install (just sync templates + restart, let AMP UI Update fetch the bundle):
#   curl -fsSL https://raw.githubusercontent.com/Sonic0810/BAPBAP-CustomServer-AMPTemplates/main/bapbap-amp-setup.sh | tr -d '\r' | sudo -u amp SKIP_BUNDLE=1 bash

set -euo pipefail

INSTANCE="${INSTANCE:-FinalesBattleRoyale01}"
REPO="${REPO:-Sonic0810/BAPBAP-CustomServer-AMPTemplates}"
BRANCH="${BRANCH:-main}"
SKIP_BUNDLE="${SKIP_BUNDLE:-0}"
BUNDLE_NAME="${BUNDLE_NAME:-bapcustomserver-amp-full-linux-wine.zip}"
BUNDLE_URL="${BUNDLE_URL:-https://github.com/$REPO/releases/latest/download/$BUNDLE_NAME}"

AMP_HOME="${AMP_HOME:-/home/amp/.ampdata}"
INST_DIR="$AMP_HOME/instances/$INSTANCE"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
TMP_ZIP="/tmp/bapbap-bundle-$$.zip"

cleanup() { rm -f "$TMP_ZIP" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> BAPBAP AMP one-shot setup"
echo "    instance:   $INSTANCE"
echo "    inst dir:   $INST_DIR"
echo "    repo:       $RAW"
echo "    bundle:     $BUNDLE_URL"
echo "    skip bundle: $SKIP_BUNDLE"
echo

if [ ! -d "$INST_DIR" ]; then
  echo "!! Instance directory not found: $INST_DIR"
  echo "   Create the instance in the AMP web UI first (Generic Module),"
  echo "   then re-run this script."
  exit 1
fi

if [ "$SKIP_BUNDLE" != "1" ] && ! command -v python3 >/dev/null 2>&1; then
  echo "!! 'python3' is not installed. Install it (apt-get install python3) and re-run,"
  echo "   or pass SKIP_BUNDLE=1 to skip the bundle pre-install (and use AMP UI Update instead)."
  exit 1
fi

echo "==> Stopping instance (if running)"
ampinstmgr stopinstance "$INSTANCE" 2>/dev/null || true
sleep 2

echo "==> Backing up old kvp + configmanifest"
ts="$(date +%Y%m%d-%H%M%S)"
[ -f "$INST_DIR/GenericModule.kvp" ]   && cp "$INST_DIR/GenericModule.kvp"   "$INST_DIR/GenericModule.kvp.bak.$ts"   || true
[ -f "$INST_DIR/configmanifest.json" ] && cp "$INST_DIR/configmanifest.json" "$INST_DIR/configmanifest.json.bak.$ts" || true

echo "==> Syncing AMP template files from GitHub raw"
curl -fsSL "$RAW/bapcustomservergithub.kvp"             -o "$INST_DIR/GenericModule.kvp"
curl -fsSL "$RAW/bapcustomservergithubconfig.json"      -o "$INST_DIR/configmanifest.json"
curl -fsSL "$RAW/bapcustomservergithubports.json"       -o "$INST_DIR/bapcustomservergithubports.json"
curl -fsSL "$RAW/bapcustomservergithubupdates.json"     -o "$INST_DIR/bapcustomservergithubupdates.json"
curl -fsSL "$RAW/bapcustomservergithubmetaconfig.json"  -o "$INST_DIR/bapcustomservergithubmetaconfig.json"
echo "    OK: 5 template files written"

echo "==> Sanity-checking kvp"
exec_line="$(grep '^App.ExecutableLinux=' "$INST_DIR/GenericModule.kvp" || true)"
if [ -z "$exec_line" ]; then
  echo "!! kvp missing App.ExecutableLinux — abort"; exit 3
fi
echo "    $exec_line"

if [ "$SKIP_BUNDLE" != "1" ]; then
  echo "==> Downloading server bundle (~585 MB) from latest GitHub Release"
  curl -fL "$BUNDLE_URL" -o "$TMP_ZIP" --progress-bar

  echo "==> Extracting bundle into $INST_DIR/BapCustomServer (python3 — handles backslash paths)"
  mkdir -p "$INST_DIR/BapCustomServer"
  python3 - <<PYEOF
import os, sys, zipfile
src = "$TMP_ZIP"
dst = "$INST_DIR/BapCustomServer"
count = 0
with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        name = info.filename.replace("\\\\", "/").lstrip("/")
        parts = [part for part in name.split("/") if part not in ("", ".")]
        if not parts or any(part == ".." for part in parts):
            print(f"    skipped unsafe zip entry: {info.filename}", file=sys.stderr)
            continue
        name = "/".join(parts)
        protected = (
            name.startswith("data/") or
            name.startswith("logs/") or
            name.startswith("data/players/") or
            name.endswith(".jsonl") or
            name.endswith("/admin-state.json") or
            name.endswith("/economy-state.json") or
            name.endswith("/friends-state.json") or
            name.endswith("/ranked-state.json") or
            name.endswith("/shop-state.json") or
            name in {
                "data/admin-state.json",
                "data/economy-state.json",
                "data/friends-state.json",
                "data/ranked-state.json",
                "data/shop-state.json",
            }
        )
        if protected:
            print(f"    preserved existing user-state path, skipped zip entry: {name}")
            continue
        if name.endswith("/"):
            os.makedirs(os.path.join(dst, name), exist_ok=True)
            continue
        target = os.path.join(dst, name)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with z.open(info) as src_f, open(target, "wb") as out_f:
            out_f.write(src_f.read())
        count += 1
print(f"    extracted {count} files")
PYEOF

  echo "==> Stripping CRLF + setting exec bits on scripts and binary"
  for f in "$INST_DIR/BapCustomServer"/*.sh; do
    [ -f "$f" ] && sed -i 's/\r$//' "$f"
  done
  for f in BapCustomServer createdump amp-webpanel-start.sh start-linux-wine.sh start-match.sh; do
    p="$INST_DIR/BapCustomServer/$f"
    [ -f "$p" ] && chmod +x "$p" || true
  done

  echo "==> Verifying critical files"
  required=(
    "$INST_DIR/BapCustomServer/BapCustomServer"
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
  echo "    OK: BapCustomServer binary + appsettings.json present"
fi

echo "==> Starting instance"
ampinstmgr startinstance "$INSTANCE"

cat <<EOF

=========================================================
==> SETUP COMPLETE.
=========================================================

Instance "$INSTANCE" is starting. Open the AMP web UI Console tab to watch
the live output. Within 10–30 seconds you should see:

  Now listening on: http://0.0.0.0:5055

— that's the regex AMP looks for to flip status to "Ready".

GOING FORWARD (no more SSH):

  • Daily start/stop      → AMP UI Start/Stop buttons
  • Server code update    → AMP UI Update button
                            (downloads new bundle, refreshes ONLY the
                             game/server files; data/ and logs/ are
                             excluded from the bundle and never touched)
  • AMP UI field changes  → AMP rewrites appsettings.json from your UI
                             values on every Start (via metaconfig). Your
                             UI changes survive every Update.

USER DATA THAT IS NEVER OVERWRITTEN:

  $INST_DIR/BapCustomServer/data/       (player accounts, economy, ranked, admin)
  $INST_DIR/BapCustomServer/logs/       (audit log, match history)

Dedicated game config files under game/Mods/ and game/UserData/ are mod/runtime
configuration and may be refreshed by updates so Wine/headless server defaults stay
correct. They do not store match history, purchases, ranked state, friends, or player
accounts.

Re-run this script ONLY when:
  • You see the kvp / Configuration UI is out of date, OR
  • The instance is broken and you want a clean reset.

EOF
