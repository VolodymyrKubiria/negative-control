#!/usr/bin/env bash
# attention-anchor — a gate on the axis no other hook watches.
#
# THE FAILURE MODE IT EXISTS FOR
#   The model states a verdict in prose ("never happened", "eight defects", "the
#   code drifted from the comment") or picks a next step without checking it
#   against anything. No tool call happens. So every PreToolUse hook you have is
#   silent BY CONSTRUCTION — they all sit on Edit|Write|Bash and judge the
#   content of an EDIT. Nothing judges a SENTENCE.
#
# WHY UserPromptSubmit
#   It is the only event that precedes REASONING rather than action. The anchor
#   lands in context before the first sentence of a verdict is composed.
#
# CONTRACT
#   Never blocks, never fails the turn. stdout only, always exit 0.
#
# CONFIGURATION
#   config/anchor.md         the text injected on every prompt (keep it SHORT)
#   config/anchor-full.md    extra text injected only on trigger words (optional)
#   config/anchor.triggers   ERE regex, one per line, matched case-insensitively
#                            against the user's prompt (optional)
#   Override the directory with NC_CONFIG_DIR.
#
# A NOTE ON HONESTY
#   This hook is a NOTE-level control, not a proven one. The probes below show it
#   is ALIVE and that escalation is CONDITIONAL. They do not show that it changes
#   behaviour on the hundredth turn. An alarm that fires every single time
#   desensitises exactly as thoroughly as one that never fires. If you adopt this,
#   measure two numbers periodically: how often it fired, and how often it
#   actually changed a step. A second number of zero, twice running, means it has
#   become wallpaper — narrow the triggers or drop it.
#
# CONTROLS
#   bash hooks/attention-anchor.sh --self-test

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${NC_CONFIG_DIR:-$HERE/../config}"

ANCHOR_FILE="$CONFIG_DIR/anchor.md"
FULL_FILE="$CONFIG_DIR/anchor-full.md"
TRIGGER_FILE="$CONFIG_DIR/anchor.triggers"

# ── controls ────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--self-test" ]]; then
  fail=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  printf 'ANCHOR-MARKER base line\n' > "$tmp/anchor.md"
  printf 'FULL-MARKER escalated block\n'  > "$tmp/anchor-full.md"
  printf 'audit|prove\n' > "$tmp/anchor.triggers"
  run() { printf '%s' "$1" | NC_CONFIG_DIR="$tmp" bash "$0"; }

  # ① the base anchor prints on any input
  out="$(run '{"prompt":"do something"}')"
  grep -q "ANCHOR-MARKER" <<<"$out" || { echo "🔴 ① base anchor did not print"; fail=1; }

  # ② escalation fires on a trigger word
  esc="$(run '{"prompt":"please audit this"}')"
  grep -q "FULL-MARKER" <<<"$esc" || { echo "🔴 ② escalation did not fire on a trigger"; fail=1; }

  # ③ NEGATIVE CONTROL: without a trigger the escalated block must NOT appear.
  #    Without this, a hook that always prints everything would pass ① and ②.
  #    Anchor the grep to a marker UNIQUE to the escalated block — an earlier
  #    version of this control grepped for a string the base anchor also carried,
  #    so the control could not fail even in principle.
  grep -q "FULL-MARKER" <<<"$out" && { echo "🔴 ③ escalated block printed with no trigger"; fail=1; }

  # ④ NEGATIVE CONTROL: a trigger-shaped word that is not in the trigger list
  #    must stay silent — proves matching is by list, not by "any long word".
  noesc="$(run '{"prompt":"refactor the parser"}')"
  grep -q "FULL-MARKER" <<<"$noesc" && { echo "🔴 ④ escalation fired on a non-trigger"; fail=1; }

  # ⑤ malformed and empty input must not kill the turn
  printf 'not json' | NC_CONFIG_DIR="$tmp" bash "$0" >/dev/null 2>&1 \
    || { echo "🔴 ⑤ hook died on non-JSON"; fail=1; }
  printf '' | NC_CONFIG_DIR="$tmp" bash "$0" >/dev/null 2>&1 \
    || { echo "🔴 ⑤ hook died on empty input"; fail=1; }

  # ⑥ VACUUM CONTROL: with no config present at all the hook prints nothing and
  #    still exits 0. A hook that invented output from an absent config would be
  #    reporting on a corpus it never read.
  empty="$(mktemp -d)"
  vac="$(printf '%s' '{"prompt":"audit"}' | NC_CONFIG_DIR="$empty" bash "$0")"
  [[ -z "$vac" ]] || { echo "🔴 ⑥ produced output with no config: $vac"; fail=1; }
  rm -rf "$empty"

  if [[ $fail -eq 0 ]]; then
    echo "✅ attention-anchor — 6/6 controls pass, hook may be trusted for this run"
  else
    echo "❌ attention-anchor UNSOUND — do not trust it"
  fi
  exit $fail
fi

# ── runtime ─────────────────────────────────────────────────────────────────
[[ -f "$ANCHOR_FILE" ]] || exit 0

payload="$(cat 2>/dev/null || true)"
prompt="$(printf '%s' "$payload" | python3 -c \
  'import sys,json
try:
    print((json.load(sys.stdin) or {}).get("prompt","") or "")
except Exception:
    print("")' 2>/dev/null || printf '')"

cat "$ANCHOR_FILE"

if [[ -f "$FULL_FILE" && -f "$TRIGGER_FILE" ]]; then
  # Triggers are one ERE per line; blank lines and # comments ignored.
  pattern="$(grep -vE '^\s*(#|$)' "$TRIGGER_FILE" 2>/dev/null | paste -sd'|' -)"
  if [[ -n "$pattern" ]] && printf '%s' "$prompt" | grep -qiE "$pattern" 2>/dev/null; then
    cat "$FULL_FILE"
  fi
fi

exit 0
