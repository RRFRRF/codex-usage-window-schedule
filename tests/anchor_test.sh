#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

PROJECT_DIR="$TMP_DIR/project"
FAKE_BIN="$TMP_DIR/bin"
FAKE_HOME="$TMP_DIR/original-codex-home"
mkdir -p "$PROJECT_DIR/auths" "$FAKE_BIN" "$FAKE_HOME"

cat > "$PROJECT_DIR/auths/account-a.json" <<'JSON'
{
  "auth_mode": "chatgpt",
  "tokens": {
    "account_id": "acct-a"
  }
}
JSON

cat > "$PROJECT_DIR/auths/account-b.json" <<'JSON'
{
  "auth_mode": "chatgpt",
  "tokens": {
    "account_id": "acct-b"
  }
}
JSON

cat > "$FAKE_BIN/codex" <<'SH'
#!/bin/bash
set -euo pipefail

if [[ ! -f "$CODEX_HOME/auth.json" ]]; then
  echo "missing isolated auth.json" >&2
  exit 42
fi

node -e '
const fs = require("fs");
const auth = JSON.parse(fs.readFileSync(process.env.CODEX_HOME + "/auth.json", "utf8"));
fs.appendFileSync(process.env.CALL_LOG, `${process.env.CODEX_HOME}|${auth.tokens && auth.tokens.account_id}\n`);
'
SH
chmod +x "$FAKE_BIN/codex"

cat > "$FAKE_BIN/timeout" <<'SH'
#!/bin/bash
shift
exec "$@"
SH
chmod +x "$FAKE_BIN/timeout"

set +e
CALL_LOG="$TMP_DIR/calls.log" \
PATH="$FAKE_BIN:$PATH" \
CODEX_HOME="$FAKE_HOME" \
bash "$ROOT_DIR/anchor.sh" "$PROJECT_DIR" > "$TMP_DIR/output.log" 2>&1
status=$?
set -e

[[ $status -eq 0 ]] || fail "anchor.sh exited $status: $(tr '\n' ' ' < "$TMP_DIR/output.log")"

calls=()
while IFS= read -r line; do
  calls+=("$line")
done < "$TMP_DIR/calls.log"
[[ ${#calls[@]} -eq 2 ]] || fail "expected 2 codex calls, got ${#calls[@]}"

first_home="${calls[0]%%|*}"
first_account="${calls[0]##*|}"
second_home="${calls[1]%%|*}"
second_account="${calls[1]##*|}"

[[ "$first_account" == "acct-a" ]] || fail "first call used $first_account"
[[ "$second_account" == "acct-b" ]] || fail "second call used $second_account"
[[ "$first_home" != "$second_home" ]] || fail "accounts shared CODEX_HOME: $first_home"
[[ ! -f "$FAKE_HOME/auth.json" ]] || fail "original CODEX_HOME auth.json was overwritten"

DUP_PROJECT="$TMP_DIR/duplicate-project"
mkdir -p "$DUP_PROJECT/auths"
cp "$PROJECT_DIR/auths/account-a.json" "$DUP_PROJECT/auths/account-a.json"
cp "$PROJECT_DIR/auths/account-a.json" "$DUP_PROJECT/auths/account-b.json"

set +e
CALL_LOG="$TMP_DIR/duplicate-calls.log" \
PATH="$FAKE_BIN:$PATH" \
CODEX_HOME="$FAKE_HOME" \
bash "$ROOT_DIR/anchor.sh" "$DUP_PROJECT" > "$TMP_DIR/duplicate-output.log" 2>&1
dup_status=$?
set -e

[[ $dup_status -ne 0 ]] || fail "duplicate account IDs should fail"
grep -q "duplicate account" "$TMP_DIR/duplicate-output.log" || fail "duplicate failure was not explained"

echo "PASS"
