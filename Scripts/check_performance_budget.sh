#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE="$ROOT_DIR/.build/release/Madedown"
APP_DIR="$ROOT_DIR/dist/Madedown.app"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

BINARY_BUDGET_BYTES="${MADEDOWN_BINARY_BUDGET_BYTES:-8388608}"
APP_BUDGET_KIB="${MADEDOWN_APP_BUDGET_KIB:-12288}"
STARTUP_BUDGET_MS="${MADEDOWN_STARTUP_BUDGET_MS:-750}"
RSS_BUDGET_BYTES="${MADEDOWN_RSS_BUDGET_BYTES:-83886080}"

"$ROOT_DIR/Scripts/build_app_bundle.sh" >/dev/null

binary_bytes="$(stat -f '%z' "$EXECUTABLE")"
app_kib="$(du -sk "$APP_DIR" | awk '{print $1}')"

time_output="$(
  MADEDOWN_SESSION_PATH="$TEMP_DIR/session.json" \
    /usr/bin/time -l "$EXECUTABLE" --startup-probe 2>&1
)"
startup_ms="$(printf '%s\n' "$time_output" | awk '/ real / {printf "%.0f", $1 * 1000; exit}')"
rss_bytes="$(printf '%s\n' "$time_output" | awk '/maximum resident set size/ {print $1; exit}')"

if [[ "$time_output" != *"startup_probe=ready"* || -z "$startup_ms" || -z "$rss_bytes" ]]; then
  printf '%s\n' "$time_output"
  echo "performance-budget: unable to parse startup metrics" >&2
  exit 1
fi

failed=0
if (( binary_bytes > BINARY_BUDGET_BYTES )); then
  echo "performance-budget: release binary exceeds budget ($binary_bytes > $BINARY_BUDGET_BYTES)" >&2
  failed=1
fi
if (( app_kib > APP_BUDGET_KIB )); then
  echo "performance-budget: app bundle exceeds budget (${app_kib} KiB > ${APP_BUDGET_KIB} KiB)" >&2
  failed=1
fi
if (( startup_ms > STARTUP_BUDGET_MS )); then
  echo "performance-budget: startup exceeds budget (${startup_ms} ms > ${STARTUP_BUDGET_MS} ms)" >&2
  failed=1
fi
if (( rss_bytes > RSS_BUDGET_BYTES )); then
  echo "performance-budget: startup RSS exceeds budget ($rss_bytes > $RSS_BUDGET_BYTES)" >&2
  failed=1
fi

echo "performance-budget: binary=${binary_bytes}B app=${app_kib}KiB startup=${startup_ms}ms rss=${rss_bytes}B"
exit "$failed"
