#!/usr/bin/env bash
set -uo pipefail

APP_DIR="${APP_DIR:-/AMP/BapCustomServer}"
LOBBY_PORT="${LOBBY_PORT:-5055}"
BASE_WS_PORT="${BASE_WS_PORT:-7777}"
BASE_KCP_PORT="${BASE_KCP_PORT:-7778}"
BASE_TCP_PORT="${BASE_TCP_PORT:-7779}"
BASE_HTTP_PORT="${BASE_HTTP_PORT:-7850}"
PUBLIC_HOST="${PUBLIC_HOST:-ark.atomi23.de}"
BASE_URL="${BASE_URL:-http://127.0.0.1:${LOBBY_PORT}}"
EXPECTED_MOD_DLL_SHA="${EXPECTED_MOD_DLL_SHA:-A3B0F0CDDEEE518D025D13AD7DDD4EA090633F5327DAE1395E73538A6A97C826}"

failures=0

ok() {
  printf 'OK: %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

require_file() {
  if [ -f "$1" ]; then
    ok "file exists: $1"
  else
    fail "missing file: $1"
  fi
}

require_executable() {
  if [ -x "$1" ]; then
    ok "executable: $1"
  elif [ -f "$1" ]; then
    fail "not executable: $1"
  else
    fail "missing executable: $1"
  fi
}

contains_text() {
  file="$1"
  text="$2"
  if grep -Fq "$text" "$file" 2>/dev/null; then
    ok "$file contains: $text"
  else
    fail "$file missing: $text"
  fi
}

if [ ! -d "$APP_DIR" ]; then
  fail "APP_DIR does not exist: $APP_DIR"
  exit 1
fi

cd "$APP_DIR" || exit 1

require_executable "./BapCustomServer"
require_executable "./amp-webpanel-start.sh"
require_executable "./start-linux-wine.sh"
require_executable "./start-match.sh"
require_file "./appsettings.json"
require_file "./deployment-info.json"
require_file "./game/Mods/BapCustomServerMelon.dll"
require_file "./game/Mods/BapCustomServer.ini"
require_file "./game/UserData/MelonPreferences.cfg"

if command -v sha256sum >/dev/null 2>&1 && [ -f "./game/Mods/BapCustomServerMelon.dll" ]; then
  actual_sha="$(sha256sum ./game/Mods/BapCustomServerMelon.dll | awk '{print toupper($1)}')"
  if [ "$actual_sha" = "$EXPECTED_MOD_DLL_SHA" ]; then
    ok "mod dll sha256: $actual_sha"
  else
    fail "mod dll sha256 mismatch: $actual_sha expected $EXPECTED_MOD_DLL_SHA"
  fi
else
  warn "sha256sum unavailable; skipped mod DLL hash check"
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$PUBLIC_HOST" "$LOBBY_PORT" "$BASE_WS_PORT" "$BASE_KCP_PORT" "$BASE_TCP_PORT" "$BASE_HTTP_PORT" <<'PY'
import json
import pathlib
import sys

public_host, lobby, ws, kcp, tcp, http = sys.argv[1:]
settings = json.loads(pathlib.Path("appsettings.json").read_text(encoding="utf-8-sig"))
custom = settings.get("CustomServer", {})
expected = {
    "PublicGameHost": public_host,
    "PublicBaseUrl": f"http://{public_host}:{lobby}",
    "BaseWsPort": int(ws),
    "BaseKcpPort": int(kcp),
    "BaseTcpPort": int(tcp),
    "BaseHttpPort": int(http),
    "PortSearchRange": 1,
    "MaxConcurrentMatches": 1,
    "RequireGameServerKcpPort": True,
    "GameLauncherPath": "./start-match.sh",
    "GameLauncherArguments": '"{gameExecutable}" {gameArguments}',
}
bad = []
for key, expected_value in expected.items():
    actual = custom.get(key)
    if actual != expected_value:
        bad.append(f"{key}={actual!r} expected {expected_value!r}")
if bad:
    print("FAIL: appsettings mismatch: " + "; ".join(bad), file=sys.stderr)
    sys.exit(13)
print("OK: appsettings public host/ports/update-safety values")
PY
  rc=$?
  if [ "$rc" -ne 0 ]; then
    failures=$((failures + 1))
  fi

  python3 - "$PUBLIC_HOST" "$LOBBY_PORT" "$BASE_WS_PORT" "$BASE_KCP_PORT" "$BASE_TCP_PORT" "$BASE_HTTP_PORT" <<'PY'
import json
import pathlib
import sys

public_host, lobby, ws, kcp, tcp, http = sys.argv[1:]
info_path = pathlib.Path("deployment-info.json")
if not info_path.exists():
    print("FAIL: deployment-info.json missing", file=sys.stderr)
    sys.exit(14)
info = json.loads(info_path.read_text(encoding="utf-8-sig"))
required = ["releaseLabel", "packageBuildUtc", "gitCommit", "gitBranch", "modDllSha256", "gameExeSha256", "startMatchSha256", "ports"]
missing = [key for key in required if not info.get(key)]
ports = info.get("ports", {})
expected_ports = {"lobby": int(lobby), "ws": int(ws), "kcp": int(kcp), "tcp": int(tcp), "http": int(http)}
bad_ports = [f"{key}={ports.get(key)!r} expected {value!r}" for key, value in expected_ports.items() if ports.get(key) != value]
if info.get("publicHost") != public_host:
    missing.append(f"publicHost={info.get('publicHost')!r} expected {public_host!r}")
if missing or bad_ports:
    print("FAIL: deployment-info invalid: " + "; ".join(missing + bad_ports), file=sys.stderr)
    sys.exit(15)
print(f"OK: deployment-info release={info.get('releaseLabel')} git={info.get('gitCommit')} packageUtc={info.get('packageBuildUtc')}")
PY
  rc=$?
  if [ "$rc" -ne 0 ]; then
    failures=$((failures + 1))
  fi
else
  warn "python3 unavailable; using weaker appsettings grep checks"
  contains_text "./appsettings.json" "\"PublicGameHost\": \"$PUBLIC_HOST\""
  contains_text "./appsettings.json" "\"BaseKcpPort\": $BASE_KCP_PORT"
  contains_text "./deployment-info.json" "\"releaseLabel\""
fi

contains_text "./game/Mods/BapCustomServer.ini" "Host=127.0.0.1"
contains_text "./game/Mods/BapCustomServer.ini" "Port=5055"
contains_text "./game/Mods/BapCustomServer.ini" "AutoGuestLogin=false"
contains_text "./game/Mods/BapCustomServer.ini" "UseNativeGameUi=false"
contains_text "./game/UserData/MelonPreferences.cfg" "NetTuneEnabled = false"
contains_text "./start-match.sh" "-force-glcore"
contains_text "./start-match.sh" "deploymentInfo="
contains_text "./start-match.sh" "glxinfo probe"
contains_text "./amp-webpanel-start.sh" "[amp-start] wineVersion="
contains_text "./start-linux-wine.sh" "[start-linux-wine] winePath="

if [ -d "./data" ]; then
  ok "runtime data directory exists and is outside update ZIP payload: ./data"
else
  warn "runtime data directory not present yet; it may be created on first start"
fi

if [ -d "./logs" ]; then
  ok "runtime logs directory exists and is outside update ZIP payload: ./logs"
else
  warn "runtime logs directory not present yet; it may be created on first start"
fi

if command -v curl >/dev/null 2>&1; then
  if health="$(curl -fsS --max-time 5 "$BASE_URL/health" 2>/dev/null)"; then
    ok "health endpoint: $BASE_URL/health -> $health"
  else
    fail "health endpoint not reachable: $BASE_URL/health"
  fi
else
  warn "curl unavailable; skipped health check"
fi

if command -v ss >/dev/null 2>&1; then
  if ss -lntp 2>/dev/null | grep -Eq "[:.]${LOBBY_PORT}[[:space:]]"; then
    ok "lobby TCP port visible in ss: $LOBBY_PORT"
  else
    fail "lobby TCP port not visible in ss: $LOBBY_PORT"
  fi

  if ss -lunp 2>/dev/null | grep -Eq "[:.]${BASE_KCP_PORT}[[:space:]]"; then
    ok "match KCP UDP port currently visible in ss: $BASE_KCP_PORT"
  else
    warn "match KCP UDP port not currently visible; this is expected unless a match process is running"
  fi
else
  warn "ss unavailable; skipped port visibility checks"
fi

latest_game_log="$(find ./logs/game-servers -type f -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')"
if [ -n "$latest_game_log" ]; then
  ok "latest game log: $latest_game_log"
  grep -E "Loaded Map|GAME_STARTED|Player On Start|game-ended|team-ended" "$latest_game_log" | tail -40 || true
else
  warn "no game-server log found yet; start a match to prove KCP/game lifecycle"
fi

if [ "$failures" -eq 0 ]; then
  echo "AMP_VERIFY_OK"
  exit 0
fi

echo "AMP_VERIFY_FAILED failures=$failures" >&2
exit 1
