#!/bin/bash
# codex-usage-window-schedule — Anchor Codex usage window to 05:00 daily
# Runs a minimal codex exec with each account to set the rate-limit window start.
# After anchoring, daily refresh cycle: 05:00 → 10:00 → 15:00 → 20:00 → 01:00
#
# Usage:
#   ./anchor.sh              # run with default paths
#   ./anchor.sh /path/to/dir # override CODEX_ANCHOR_DIR
#
# Crontab entry:
#   0 5 * * * /bin/bash /path/to/codex-usage-window-schedule/anchor.sh >> /path/to/codex-usage-window-schedule/anchor.log 2>&1

set -uo pipefail

# ─── Config ───────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_ANCHOR_DIR="${1:-${CODEX_ANCHOR_DIR:-$SCRIPT_DIR}}"
AUTHS_DIR="$CODEX_ANCHOR_DIR/auths"
CODEX_HOME_BASE="${CODEX_HOME:-$HOME/.codex}"
CODEX_BIN="$(which codex 2>/dev/null || echo '')"
TIMEOUT_SEC=60
MODEL="${CODEX_ANCHOR_MODEL:-gpt-5.4-mini}"
PROMPT="say hello"
RUNTIME_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-anchor.XXXXXX")"
trap 'rm -rf "$RUNTIME_ROOT"' EXIT

read_auth_account_id() {
  if ! command -v node >/dev/null 2>&1; then
    return 0
  fi

  node -e '
const fs = require("fs");
const auth = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
process.stdout.write((auth.tokens && auth.tokens.account_id) || "");
' "$1"
}

short_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum
  else
    cksum
  fi | awk '{print substr($1, 1, 12)}'
}

# ─── Pre-flight ───────────────────────────────────────
if [[ -z "$CODEX_BIN" ]]; then
  echo "[FATAL] codex not found in PATH. Install: npm install -g @openai/codex"
  exit 1
fi

if [[ ! -d "$AUTHS_DIR" ]]; then
  echo "[FATAL] auths directory not found: $AUTHS_DIR"
  exit 1
fi

# ─── Collect auth files ───────────────────────────────
AUTH_FILES=()
while IFS= read -r -d '' f; do
  AUTH_FILES+=("$f")
done < <(find "$AUTHS_DIR" -name '*.json' -print0 | sort -z)

if [[ ${#AUTH_FILES[@]} -eq 0 ]]; then
  echo "[FATAL] No auth JSON files found in $AUTHS_DIR"
  exit 1
fi

ACCOUNT_FINGERPRINTS_FILE="$RUNTIME_ROOT/account-fingerprints"
: > "$ACCOUNT_FINGERPRINTS_FILE"
for auth_file in "${AUTH_FILES[@]}"; do
  if ! account_id="$(read_auth_account_id "$auth_file")"; then
    echo "[FATAL] invalid auth JSON: $auth_file"
    exit 1
  fi

  if [[ -z "$account_id" ]]; then
    continue
  fi

  fingerprint="$(printf "%s" "$account_id" | short_hash)"
  while IFS="	" read -r seen_fingerprint seen_file; do
    if [[ -z "$seen_fingerprint" ]]; then
      continue
    fi
    if [[ "$seen_fingerprint" == "$fingerprint" ]]; then
      echo "[FATAL] duplicate account detected: $seen_file and $auth_file share account fingerprint $fingerprint"
      exit 1
    fi
  done < "$ACCOUNT_FINGERPRINTS_FILE"
  printf "%s\t%s\n" "$fingerprint" "$auth_file" >> "$ACCOUNT_FINGERPRINTS_FILE"
done

echo "=========================================="
echo "Codex Usage Window Anchor — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Accounts: ${#AUTH_FILES[@]}"
echo "=========================================="

# ─── Anchor each account ──────────────────────────────
SUCCESS=0
FAIL=0

for auth_file in "${AUTH_FILES[@]}"; do
  account_name="$(basename "$auth_file" .json)"
  echo ""
  echo "── [$account_name] ──"

  account_home="$RUNTIME_ROOT/$account_name"
  mkdir -p "$account_home"

  if ! cp "$auth_file" "$account_home/auth.json"; then
    echo "  ✗ FAILED to prepare isolated auth"
    ((FAIL++))
    continue
  fi
  chmod 600 "$account_home/auth.json" 2>/dev/null || true
  echo "  auth: $auth_file → isolated CODEX_HOME"

  # Run codex exec (headless, ephemeral, no git repo required)
  start_time="$(date +%s)"
  if CODEX_HOME="$account_home" timeout "$TIMEOUT_SEC" "$CODEX_BIN" exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    --ephemeral \
    --color never \
    --ignore-user-config \
    --ignore-rules \
    -m "$MODEL" \
    "$PROMPT" 2>&1; then
    if ! cp "$account_home/auth.json" "$auth_file"; then
      echo "  ✗ FAILED to save refreshed auth"
      ((FAIL++))
      continue
    fi
    elapsed=$(( $(date +%s) - start_time ))
    echo "  ✓ OK (${elapsed}s)"
    ((SUCCESS++))
  else
    exit_code=$?
    elapsed=$(( $(date +%s) - start_time ))
    if [[ $exit_code -eq 124 ]]; then
      echo "  ✗ TIMEOUT after ${TIMEOUT_SEC}s"
    else
      echo "  ✗ FAILED (exit $exit_code, ${elapsed}s)"
    fi
    ((FAIL++))
  fi
done

# ─── Summary ──────────────────────────────────────────
echo ""
echo "=========================================="
echo "Done: $SUCCESS ok, $FAIL fail — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Original CODEX_HOME preserved: $CODEX_HOME_BASE"
echo "=========================================="

exit $FAIL
