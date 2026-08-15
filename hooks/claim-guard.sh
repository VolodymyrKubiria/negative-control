#!/usr/bin/env bash
# claim-guard — keeps two agent sessions from editing the same file blind.
#
# THE FAILURE MODE IT EXISTS FOR
#   Two Claude Code sessions in one repository, working in different time
#   windows. Both edit the same file. The collision is discovered at commit time,
#   which is to say: after it happened. The usual advice — "check before you
#   commit" — detects the crash from inside the wreckage.
#
# WHAT IT DOES
#   Reads a claims board (a markdown table you keep in the repo) and warns when
#   the subject of an edit is claimed by another session.
#
# WHY ADVISORY, NOT "ask"
#   A claim is a signal, not a lock. Git grants no ownership of a file, and
#   escalating every touch of five files into a permission prompt desensitises
#   the human. Keep exactly one stop-cock in a project — and if you have
#   critical-path-guard, that is already it.
#
# BOTH ENTRANCES
#   file_path AND the text of a Bash command. The original version of this hook
#   watched only file_path, and an edit written through a python heredoc walked
#   straight past it while the file sat in the hook's own glob.
#
# THE BOARD LIVES IN ONE PLACE
#   The claims are NOT in this script. They are in the board file, deliberately:
#   two copies of a board drift apart, and then the guard defends a state nobody
#   is in.
#
# CONFIGURATION
#   config/claims.md — a markdown table; a row is an ACTIVE claim when it
#   contains 🔒 and its first cell is a backticked path. Rows with 🔓 are
#   released claims and are deliberately ignored.
#
#     | path | held by | since |
#     |---|---|---|
#     | `docs/PLAN.md`     | session-b | 2026-08-15 | 🔒
#     | `src/parser.ts`    | session-a | 2026-08-14 | 🔓
#
#   Override with NC_CLAIMS_FILE, or NC_CONFIG_DIR for the directory.
#
# CONTROLS
#   bash scripts/probe.sh claim-guard
#   bash scripts/probe.sh claim-guard --mutate

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${NC_CONFIG_DIR:-$HERE/../config}"
BOARD="${NC_CLAIMS_FILE:-$CONFIG_DIR/claims.md}"

[ -f "$BOARD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)"
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$fp" ] && [ -z "$cmd" ] && exit 0

# Talking ABOUT a file is not editing it. Commit messages and git plumbing
# mention paths by construction; the board itself is a list of paths. This hook
# fired on its own first commit message, which listed the claimed files.
if [ -n "$cmd" ] && printf '%s' "$cmd" \
   | grep -qE 'git[[:space:]]+(commit|log|diff|show|status|add|blame)|commit[[:space:]]+-[mF]' 2>/dev/null; then
  exit 0
fi

# Active claims only: rows carrying 🔒, first backticked cell.
claimed="$(grep '🔒' "$BOARD" 2>/dev/null \
  | sed -n 's/^|[[:space:]]*`\([^`]*\)`.*/\1/p' \
  | grep -v '^\*\*')"
[ -z "$claimed" ] && exit 0

hit=""
while IFS= read -r path; do
  [ -z "$path" ] && continue
  needle="$(printf '%s' "$path" | sed 's#\*\*/##g; s#\*##g')"
  [ -z "$needle" ] && continue

  if [ -n "$fp" ] && printf '%s' "$fp" | grep -qF "$needle" 2>/dev/null; then
    hit="$path"
  fi
  # Bash: the path must appear AND a positive write-sign must appear. Listing
  # read-only commands does not help inside a compound command (`cd x; grep y`).
  if [ -z "$hit" ] && [ -n "$cmd" ] \
     && printf '%s' "$cmd" | grep -qF "$needle" 2>/dev/null \
     && printf '%s' "$cmd" | grep -qE "(sed[[:space:]]+-i|tee[[:space:]]|>>?[[:space:]]*[^[:space:]|]|python3?[[:space:]]|node[[:space:]]|<<[[:space:]]*'?[A-Z]|mv[[:space:]]|cp[[:space:]]|rm[[:space:]])" 2>/dev/null; then
    hit="$path"
  fi
  [ -n "$hit" ] && break
done <<EOF
$claimed
EOF

[ -z "$hit" ] && exit 0

row="$(grep -F "\`$hit\`" "$BOARD" 2>/dev/null | head -1 | tr -s ' ')"

msg="🏛 CLAIMED FILE — \`$hit\` is held by another session.
Board row: $row

What to do: (1) if the edit is genuinely yours, release the claim on the board
first and say so out loud; (2) if you need one small change in someone else's
file, do NOT make it — write the request on the board instead, naming exactly
what is blocked; (3) otherwise move to an independent task; the answer arrives
in the other session's next window. The board is asynchronous by construction."

jq -n --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $m
  }
}' 2>/dev/null || exit 0
