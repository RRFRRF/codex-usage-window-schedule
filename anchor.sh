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

set -euo pipefail

# ─── Config ───────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_ANCHOR_DIR="${1:-$SCRIPT_DIR}"
AUTHS_DIR="$CODEX_ANCHOR_DIR/auths"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_BIN="$(which codex 2>/dev/null || echo '')"
TIMEOUT_SEC=60
MODEL="${CODEX_ANCHOR_MODEL:-gpt-5.4-mini}"
PROMPT="say hello"

# ─── Pre-flight ───────────────────────────────────────
if [[ -z "$CODEX_BIN" ]]; then
  echo "[FATAL] codex not found in PATH. Install: npm install -g @openai/codex"
  exit 1
fi

if [[ ! -d "$AUTHS_DIR" ]]; then
  echo "[FATAL] auths directory not found: $AUTHS_DIR"
  exit 1
fi

mkdir -p "$CODEX_HOME"

# ─── Collect auth files ───────────────────────────────
AUTH_FILES=()
while IFS= read -r -d '' f; do
  AUTH_FILES+=("$f")
done < <(find "$AUTHS_DIR" -name '*.json' -print0 | sort -z)

if [[ ${#AUTH_FILES[@]} -eq 0 ]]; then
  echo "[FATAL] No auth JSON files found in $AUTHS_DIR"
  exit 1
fi

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

  # Swap auth
  cp "$auth_file" "$CODEX_HOME/auth.json"
  echo "  auth: $auth_file → $CODEX_HOME/auth.json"

  # Run codex exec (headless, ephemeral, no git repo required)
  start_time="$(date +%s)"
  if timeout "$TIMEOUT_SEC" "$CODEX_BIN" exec \
    --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    --ephemeral \
    --color never \
    --ignore-user-config \
    --ignore-rules \
    -m "$MODEL" \
    "$PROMPT" 2>&1; then
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
echo "=========================================="

exit $FAIL
