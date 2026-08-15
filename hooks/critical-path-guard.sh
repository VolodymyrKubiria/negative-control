#!/usr/bin/env bash
# critical-path-guard — a stop-cock on files that have been broken quietly before.
#
# THE FAILURE MODE IT EXISTS FOR
#   Some code paths are load-bearing in a way the test suite does not express:
#   an invariant chain, a migration ladder, a security boundary. An agent editing
#   them "helpfully" does not look reckless in the diff — it looks like cleanup.
#   In the project this came from, one such chain was broken twice by silent
#   edits before this hook existed.
#
# WHAT IT DOES
#   Escalates any touch of a configured path into permissionDecision="ask" with
#   an alarm message. This is NOT a ban. It is a deliberate pause: the human
#   confirms, and the model gets told why this file is different.
#
# BOTH ENTRANCES
#   Reads tool_input.file_path AND the text of a Bash command. A guard that only
#   watches file_path is bypassed by `sed -i`, `tee`, a heredoc, or a redirect —
#   and those are exactly what an agent reaches for when Edit feels awkward.
#
# THE ECONOMY OF AN ALARM
#   Talking ABOUT a file is not editing it. Commit messages, `git log/diff/show`
#   and grep output mention paths by construction. An alarm that fires on those
#   desensitises exactly as fast as one that never fires — so reading commands
#   are excluded, and the Bash branch requires a POSITIVE sign of writing.
#
# CONFIGURATION
#   config/critical-paths.json
#     {
#       "reason": "text shown to the model when the guard fires",
#       "paths":  ["FileOne.kt", "src/core/**/Ledger.ts", "migrations/"]
#     }
#   Override the directory with NC_CONFIG_DIR.
#
# CONTROLS
#   bash scripts/probe.sh critical-path-guard
#   bash scripts/probe.sh critical-path-guard --mutate

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${NC_CONFIG_DIR:-$HERE/../config}"
CONF="$CONFIG_DIR/critical-paths.json"

[ -f "$CONF" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)"
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$fp" ] && [ -z "$cmd" ] && exit 0

# A positive sign that this command WRITES. Everything downstream keys off it.
WRITE_SIGN="(sed[[:space:]]+-i|tee[[:space:]]|>>?[[:space:]]*[^[:space:]|]|python3?[[:space:]]|node[[:space:]]|<<[[:space:]]*'?[A-Z]|mv[[:space:]]|cp[[:space:]]|rm[[:space:]])"

# Git plumbing is excluded unconditionally: commit messages and diffs name paths
# by construction, and an alarm on those desensitises as fast as one that never
# fires. This is how the original version of this hook first embarrassed itself.
if [ -n "$cmd" ] && printf '%s' "$cmd" \
   | grep -qE 'git[[:space:]]+(commit|log|diff|show|status|add|blame)|commit[[:space:]]+-[mF]' 2>/dev/null; then
  exit 0
fi

# Reading commands are excluded only when NOTHING in the command writes.
#
# 🔴 An earlier version excluded any command *starting with* cat/grep/ls…, and
# that amnesty was too broad: `cat <<EOT > protected.ts` is a write that opens
# with `cat`, so the guard stayed silent on a full file overwrite. Found by this
# repository's own probe, on its first run, before the hook had ever shipped.
if [ -n "$cmd" ] \
   && printf '%s' "$cmd" | grep -qE '^[[:space:]]*(grep|rg|cat|head|tail|less|echo|ls|find|wc)[[:space:]]' 2>/dev/null \
   && ! printf '%s' "$cmd" | grep -qE "$WRITE_SIGN" 2>/dev/null; then
  exit 0
fi

# Build one ERE from the configured paths. Globs collapse to a coarse substring:
# a false positive costs a line of text, a miss costs trust.
names="$(jq -r '.paths[]?' "$CONF" 2>/dev/null \
  | sed 's#\*\*/##g; s#\*##g; s#[.]#\\.#g' \
  | grep -v '^$' | paste -sd'|' -)"
[ -z "$names" ] && exit 0

reason="$(jq -r '.reason // "This path is protected by critical-path-guard."' "$CONF" 2>/dev/null)"

hit=""
if [ -n "$fp" ] && printf '%s' "$fp" | grep -qE "($names)" 2>/dev/null; then
  hit="$fp"
fi

# Bash branch: the path must appear AND a positive write-sign must appear.
if [ -z "$hit" ] && [ -n "$cmd" ] \
   && printf '%s' "$cmd" | grep -qE "($names)" 2>/dev/null \
   && printf '%s' "$cmd" | grep -qE "$WRITE_SIGN" 2>/dev/null; then
  hit="bash → $cmd"
fi

[ -z "$hit" ] && exit 0

msg="🚨 critical-path-guard: you are touching a protected path — $hit

$reason

Before changing it: (1) read the comments in the file and whatever rule document
explains why it is protected; (2) diff it against the last known-good tag;
(3) the guarding tests must stay green WITHOUT editing the tests themselves;
(4) if the change is genuinely needed, say out loud what you are changing and why
BEFORE making it."

jq -n --arg r "$msg" --arg f "$hit" '{
  systemMessage: ("critical-path-guard: attempted change to a protected path — " + $f),
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r,
    additionalContext: $r
  }
}' 2>/dev/null || exit 0
