#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/ops/notifications/notify-status.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TEMP/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$SSH_STUB_LOG"\nexit 1\n' > "$TEMP/bin/ssh"
chmod +x "$TEMP/bin/ssh"
: > "$TEMP/harness.env"
: > "$TEMP/ssh.log"

PATH="$TEMP/bin:$PATH" \
HARNESS_ENV_FILE="$TEMP/harness.env" \
SSH_STUB_LOG="$TEMP/ssh.log" \
bash "$SCRIPT" > "$TEMP/status.out"

call_count="$(wc -l < "$TEMP/ssh.log" | tr -d ' ')"
[[ "$call_count" -ge 1 ]] || fail "expected at least one configured NUC2 SSH check through the stub"
pass "all configured NUC2 checks ran through the SSH stub"

while IFS= read -r call; do
  [[ "$call" == -o\ BatchMode=yes\ -o\ ConnectTimeout=5\ nuc2\ * ]] || \
    fail "SSH call is missing the required non-interactive bounds"
done < "$TEMP/ssh.log"
pass "every runtime SSH call uses BatchMode=yes and ConnectTimeout=5"

source_count="$(grep -cF 'ssh -o BatchMode=yes -o ConnectTimeout=5 nuc2' "$SCRIPT")"
[[ "$source_count" == "2" ]] || fail "expected exactly two bounded NUC2 SSH invocations in source, got $source_count"
pass "source contains exactly two bounded NUC2 SSH invocations"
pass "no real NUC2 connection was attempted"

echo "notify-status SSH bounds PASS"
