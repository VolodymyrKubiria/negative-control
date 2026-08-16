#!/usr/bin/env bash
# negative-control · https://github.com/VolodymyrKubiria/negative-control
# Copyright 2026 Volodymyr Kubiria
# SPDX-License-Identifier: Apache-2.0
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

# NC_ROOT exists so the controls below can aim this script at a fixture tree.
# Without it the harness could only ever be exercised against the real repository,
# and "it works here" is not the same claim as "it works".
ROOT="${NC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOKS="$ROOT/hooks"
CASES_DIR="$ROOT/probes"

pass=0; fail=0; expect_fired=0; expect_total=0

# ── controls for the harness itself ─────────────────────────────────────────
#
# The instrument that demands controls of every hook had none of its own. It
# could report "all controls pass" while being unable to parse a case file, and
# nothing would say otherwise — the same silence it exists to expose.
#
# Each control runs this script against a FIXTURE tree, not the real repository,
# so a green result here means the harness works, not that this repo happens to
# be in a good state.
if [ "${1:-}" = "--self-test" ]; then
  f=0
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/hooks" "$T/probes" "$T/config"

  # A fixture hook with exactly one branch: it speaks when it sees TRIP.
  cat > "$T/hooks/fixture.sh" <<'FIX'
#!/usr/bin/env bash
in="$(cat 2>/dev/null)"
case "$in" in *TRIP*) echo "FIXTURE-ALARM";; esac
exit 0
FIX
  chmod +x "$T/hooks/fixture.sh"
  run_probe() { NC_ROOT="$T" bash "$0" "$@" 2>&1; }

  # ① a well-formed case file passes, and the exit code says so
  cat > "$T/probes/fixture.cases" <<'C1'
MUTATE s|TRIP|ZZZZ|
EXPECT fires on the trip word
  {"tool_input":{"command":"TRIP"}}
SILENT stays quiet otherwise
  {"tool_input":{"command":"harmless"}}
C1
  out="$(run_probe fixture)"; rc=$?
  [ $rc -eq 0 ] || { echo "🔴 ① a passing case file returned $rc"; f=1; }
  printf '%s' "$out" | grep -q "passed 2 · failed 0" \
    || { echo "🔴 ① expected 2 passes, got: $(printf '%s' "$out" | grep passed)"; f=1; }

  # ② POSITIVE for failure detection: an EXPECT the hook cannot satisfy must be
  #    reported as failed. Without this, a harness hard-wired to say "pass" would
  #    sail through ① and be worthless.
  cat > "$T/probes/fixture.cases" <<'C2'
MUTATE s|TRIP|ZZZZ|
EXPECT demands firing on input the hook ignores
  {"tool_input":{"command":"harmless"}}
C2
  out="$(run_probe fixture)"; rc=$?
  [ $rc -eq 1 ] || { echo "🔴 ② a failing control did not exit 1 (got $rc)"; f=1; }
  printf '%s' "$out" | grep -q "UNSOUND" \
    || { echo "🔴 ② failure did not produce the UNSOUND verdict"; f=1; }

  # ③ MATCH on a SILENT case: the string IS present, so it must be reported.
  cat > "$T/probes/fixture.cases" <<'C3'
MUTATE s|TRIP|ZZZZ|
SILENT must not contain the alarm word
  {"tool_input":{"command":"TRIP"}}
  MATCH FIXTURE-ALARM
C3
  out="$(run_probe fixture)"; rc=$?
  [ $rc -eq 1 ] || { echo "🔴 ③ MATCH on SILENT did not catch a present string"; f=1; }

  # ④ MUTATE is actually extracted and applied. This is the control that would
  #    have caught the BSD/GNU sed bug: the line was there, the harness could not
  #    read it, and it reported "no MUTATE line" instead of failing loudly.
  cat > "$T/probes/fixture.cases" <<'C4'
MUTATE s|TRIP|ZZZZ|
EXPECT fires on the trip word
  {"tool_input":{"command":"TRIP"}}
C4
  out="$(run_probe fixture --mutate)"; rc=$?
  [ $rc -eq 0 ] || { echo "🔴 ④ --mutate on a blinded hook returned $rc"; f=1; }
  printf '%s' "$out" | grep -q "0 of 1 EXPECT cases still fired" \
    || { echo "🔴 ④ sensitivity not reported as 0 of 1"; f=1; }

  # ⑤ VACUUM: no MUTATE line means sensitivity cannot be measured — refuse.
  cat > "$T/probes/fixture.cases" <<'C5'
EXPECT fires on the trip word
  {"tool_input":{"command":"TRIP"}}
C5
  run_probe fixture --mutate >/dev/null; rc=$?
  [ $rc -eq 2 ] || { echo "🔴 ⑤ --mutate without a MUTATE line did not refuse (got $rc)"; f=1; }

  # ⑥ VACUUM, the control on the control: a mutation that changes no bytes looks
  #    identical to one that worked. It must be refused, not silently accepted.
  cat > "$T/probes/fixture.cases" <<'C6'
MUTATE s|zzz-matches-nothing-at-all|x|
EXPECT fires on the trip word
  {"tool_input":{"command":"TRIP"}}
C6
  out="$(run_probe fixture --mutate)"; rc=$?
  [ $rc -eq 2 ] || { echo "🔴 ⑥ a no-op mutation was accepted (exit $rc)"; f=1; }
  printf '%s' "$out" | grep -q "MUTATION DID NOT APPLY" \
    || { echo "🔴 ⑥ no-op mutation did not say so"; f=1; }

  # ⑨ VACUUM, control N+1 for a real defect: a mutation that CHANGES the file
  #    but leaves it unparseable. Every EXPECT then goes silent because bash
  #    never started the hook, and the report reads as a perfect score. Two of
  #    the three shipped MUTATE lines did exactly this until 2026-08-16.
  cat > "$T/probes/fixture.cases" <<'C9'
MUTATE s|^case |case( |
EXPECT fires on the trip word
  {"tool_input":{"command":"TRIP"}}
C9
  out="$(run_probe fixture --mutate)"; rc=$?
  [ $rc -eq 2 ] || { echo "🔴 ⑨ an unparseable mutant was accepted (exit $rc)"; f=1; }
  printf '%s' "$out" | grep -q "MUTANT DOES NOT PARSE" \
    || { echo "🔴 ⑨ unparseable mutant did not say so"; f=1; }

  # ⑨b NEGATIVE CONTROL on ⑨: a mutation that IS parseable must still be run.
  #     Without this, a parse check that rejected everything would pass ⑨.
  cat > "$T/probes/fixture.cases" <<'C9B'
MUTATE s|TRIP|ZZZZ|
EXPECT fires on the trip word
  {"tool_input":{"command":"TRIP"}}
C9B
  out="$(run_probe fixture --mutate)"; rc=$?
  [ $rc -eq 0 ] || { echo "🔴 ⑨b a valid mutant was rejected (exit $rc)"; f=1; }
  printf '%s' "$out" | grep -q "MUTANT DOES NOT PARSE" \
    && { echo "🔴 ⑨b a valid mutant was called unparseable"; f=1; }

  # ⑧ A case file with CRLF line endings must still work. This is control N+1
  #    for a real failure: on windows-latest, Git checks out CRLF by default, and
  #    `MATCH text\r` stopped matching the hook output. Every EXPECT in the
  #    anchor suite failed while both guards passed — they compare empty versus
  #    non-empty and never look at a string, so the same corruption went by them.
  printf 'MUTATE s|TRIP|ZZZZ|\r\nEXPECT crlf case file\r\n  {"tool_input":{"command":"TRIP"}}\r\n  MATCH FIXTURE-ALARM\r\n' \
    > "$T/probes/fixture.cases"
  out="$(run_probe fixture)"; rc=$?
  [ $rc -eq 0 ] || { echo "🔴 ⑧ a CRLF case file broke the harness (exit $rc)"; f=1; }

  # ⑦ VACUUM: an invented hook name must not produce a verdict at all.
  run_probe zzz-no-such-hook >/dev/null; rc=$?
  [ $rc -eq 2 ] || { echo "🔴 ⑦ a nonexistent hook did not exit 2 (got $rc)"; f=1; }

  # The count is READ FROM THE SOURCE, not typed. A hand-maintained "8/8" drifts
  # the first time a control is added — and a tool that ships an unmeasured
  # number has no standing to ask anyone else for measured ones.
  n="$(grep -cE '^  # [①②③④⑤⑥⑦⑧⑨]' "$0" 2>/dev/null)"
  if [ $f -eq 0 ]; then
    echo "✅ probe — $n/$n controls pass, the harness itself may be trusted"
  else
    echo "❌ probe UNSOUND — every report it produces is suspect"
  fi
  exit $f
fi

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
  # 🔴 CHANGED IS NOT ENOUGH — THE MUTANT MUST STILL RUN.
  #
  # A mutation that breaks the syntax makes every EXPECT go silent, and the
  # report reads exactly like a perfect sensitivity result. Measured 2026-08-16:
  # two of the three shipped MUTATE lines did this. `s/^names="\$(jq.*$/names=""/`
  # replaced the FIRST line of a multi-line pipeline and orphaned its
  # continuations, so bash refused to parse the file at all — and `probe --mutate`
  # printed «every EXPECT went silent — these controls can actually fail» for a
  # hook that had never started.
  #
  # The no-op check above could not catch it: the file DID change. Changed and
  # still executable are two different questions, and only the second one makes
  # the silence mean what the report says it means.
  if ! bash -n "$TMP/mutated.sh" 2>/dev/null; then
    echo "❌ MUTANT DOES NOT PARSE — the blinded hook cannot run at all."
    echo "   Every EXPECT below would go silent for the wrong reason, and the"
    echo "   result would read as a perfect score. Fix the MUTATE line in $CASES"
    echo "   so it produces a hook that still runs, only blind."
    bash -n "$TMP/mutated.sh" 2>&1 | sed 's/^/   /' | head -3
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
  line="${line%$'\r'}"          # a CRLF checkout must not silently break MATCH
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
