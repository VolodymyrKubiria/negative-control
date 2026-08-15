#!/usr/bin/env bash
# probe — paired controls for a hook, plus a mutation that measures whether the
#         controls can actually fail.
#
# WHY THIS EXISTS
#   A hook is the one layer of an agent guardrail with no witness of its own. A
#   test goes red by itself. An alarm is silent in BOTH of its states: when
#   nothing happened, and when it has gone blind. Those two are byte-identical
#   from the outside, and the blind one is silent more reliably.
#
#   "The hook is written" is not "the hook fires".
#
# THE SHAPE OF A PROOF
#   Every branch gets a PAIR:
#     EXPECT — sensitivity. It must fire.
#     SILENT — specificity. It must stay quiet.
#   A branch with no negative control is not proven: an alarm that fires on
#   everything desensitises exactly as thoroughly as one that fires on nothing.
#
#   And then --mutate, which is the part almost nobody does: blind the hook on
#   purpose and require that every EXPECT goes quiet. A green run that was never
#   red measured nothing.
#
# USAGE
#   bash scripts/probe.sh <hook-name>            run the controls
#   bash scripts/probe.sh <hook-name> --mutate   blind the hook, expect silence
#   bash scripts/probe.sh --all                  every case file in probes/
#
# EXIT
#   0 — all controls passed (or, under --mutate, every EXPECT went silent)
#   1 — at least one control failed
#   2 — could not run (missing hook or case file)
#
# CASE FILE FORMAT — probes/<hook-name>.cases
#
#   # comments and blank lines are ignored
#   MUTATE s/^claimed=.*$/claimed=""/      <- sed expression that blinds the hook
#
#   EXPECT edit of a claimed file
#     {"tool_input":{"file_path":"/repo/docs/PLAN.md"}}
#
#   SILENT reading that same file
#     {"tool_input":{"command":"grep -n foo docs/PLAN.md"}}
#
#   EXPECT escalation on a trigger word
#     {"prompt":"please audit this"}
#     MATCH FULL-MARKER                    <- optional: substring that must appear
#                                             (on SILENT: must NOT appear)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$ROOT/hooks"
CASES_DIR="$ROOT/probes"

pass=0; fail=0; expect_fired=0; expect_total=0

# ── run every case file ─────────────────────────────────────────────────────
if [ "${1:-}" = "--all" ]; then
  rc=0
  for f in "$CASES_DIR"/*.cases; do
    [ -e "$f" ] || { echo "no case files in $CASES_DIR"; exit 2; }
    name="$(basename "$f" .cases)"
    bash "$0" "$name" || rc=1
    echo
  done
  exit $rc
fi

HOOK_NAME="${1:-}"
[ -z "$HOOK_NAME" ] && { echo "usage: probe.sh <hook-name> [--mutate] | --all"; exit 2; }
MUTATE=""
[ "${2:-}" = "--mutate" ] && MUTATE=1

HOOK="$HOOKS/$HOOK_NAME.sh"
CASES="$CASES_DIR/$HOOK_NAME.cases"
[ -f "$HOOK" ]  || { echo "❌ no hook at $HOOK"; exit 2; }
[ -f "$CASES" ] || { echo "❌ no case file at $CASES"; exit 2; }

# Portable extraction. An earlier version used `s/^MUTATE[[:space:]]\+//p`, and
# `\+` is a GNU extension: on BSD sed (macOS) it matched nothing, so the harness
# reported "no MUTATE line" for case files that had one. The instrument for
# measuring sensitivity was itself silently broken — which is the whole point of
# this repository, demonstrated on its own first run.
MUTATE_EXPR="$(grep '^MUTATE' "$CASES" 2>/dev/null | head -1 | sed 's/^MUTATE[[:space:]]*//')"
if [ -n "$MUTATE" ] && [ -z "$MUTATE_EXPR" ]; then
  echo "❌ $HOOK_NAME has no MUTATE line — sensitivity cannot be measured"
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TARGET="$HOOK"

if [ -n "$MUTATE" ]; then
  sed "$MUTATE_EXPR" "$HOOK" > "$TMP/mutated.sh"
  # A mutation that did not change the file measures nothing — and looks
  # identical to a mutation that did. This check is the control ON the control.
  if cmp -s "$HOOK" "$TMP/mutated.sh"; then
    echo "❌ MUTATION DID NOT APPLY — the sed expression matched nothing."
    echo "   Everything below would be theatre. Fix the MUTATE line in $CASES."
    exit 2
  fi
  TARGET="$TMP/mutated.sh"
fi

run() { printf '%s' "$1" | NC_CONFIG_DIR="${NC_CONFIG_DIR:-$ROOT/config}" bash "$TARGET" 2>/dev/null; }

check() { # $1=kind $2=name $3=json $4=match
  local out; out="$(run "$3")"
  if [ "$1" = "EXPECT" ]; then
    expect_total=$((expect_total+1))
    local fired=0
    if [ -n "$4" ]; then
      printf '%s' "$out" | grep -qF "$4" 2>/dev/null && fired=1
    else
      [ -n "$out" ] && fired=1
    fi
    [ "$fired" = 1 ] && expect_fired=$((expect_fired+1))

    if [ -n "$MUTATE" ]; then
      # Under mutation the hook is blind on purpose: firing is the failure.
      if [ "$fired" = 1 ]; then
        echo "   ❌ EXPECT · $2 — still fired though the hook was blinded"; fail=$((fail+1))
      else
        echo "   ✅ went silent · $2"; pass=$((pass+1))
      fi
    else
      if [ "$fired" = 1 ]; then
        echo "   ✅ EXPECT · $2"; pass=$((pass+1))
      else
        echo "   ❌ EXPECT · $2 — the hook stayed silent${4:+ (looking for «$4»)}"; fail=$((fail+1))
      fi
    fi
    return
  fi

  # SILENT cases are not re-judged under mutation: a blinded hook is silent for
  # the wrong reason, and counting that as a pass would inflate the result.
  [ -n "$MUTATE" ] && return

  local noisy=0
  if [ -n "$4" ]; then
    printf '%s' "$out" | grep -qF "$4" 2>/dev/null && noisy=1
  else
    [ -n "$out" ] && noisy=1
  fi
  if [ "$noisy" = 1 ]; then
    echo "   ❌ SILENT · $2 — fired when it should not have"; fail=$((fail+1))
  else
    echo "   ✅ SILENT · $2"; pass=$((pass+1))
  fi
}

kind=""; name=""; json=""; match=""
flush() { [ -n "$kind" ] && check "$kind" "$name" "$json" "$match"; kind=""; json=""; match=""; }

echo "🧪 $HOOK_NAME — controls${MUTATE:+  (MUTATED: hook deliberately blinded)}"
echo

while IFS= read -r line || [ -n "$line" ]; do
  trimmed="${line#"${line%%[![:space:]]*}"}"
  case "$trimmed" in
    ''|'#'*|MUTATE\ *) continue ;;
    EXPECT\ *) flush; kind="EXPECT"; name="${trimmed#EXPECT }" ;;
    SILENT\ *) flush; kind="SILENT"; name="${trimmed#SILENT }" ;;
    MATCH\ *)  match="${trimmed#MATCH }" ;;
    *)         [ -n "$kind" ] && [ -z "$json" ] && json="$trimmed" ;;
  esac
done < "$CASES"
flush

echo
if [ -n "$MUTATE" ]; then
  echo "sensitivity: $expect_fired of $expect_total EXPECT cases still fired while blinded (want 0)"
  [ "$fail" -eq 0 ] \
    && echo "✅ every EXPECT went silent — these controls can actually fail" \
    || echo "❌ some EXPECT survived the mutation — those branches are not proven"
else
  echo "passed $pass · failed $fail"
  [ "$fail" -eq 0 ] \
    && echo "✅ controls pass — hook may be trusted for this run" \
    || echo "❌ HOOK UNSOUND — do not trust its silence"
fi

[ "$fail" -eq 0 ] || exit 1
exit 0
