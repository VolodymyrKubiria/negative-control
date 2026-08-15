#!/usr/bin/env bash
# doctor — checks that this installation can actually do anything.
#
# WHY THIS EXISTS
#   Every guard here fails quiet and open: a missing dependency makes it silent
#   rather than broken. That is the right default for a hook — but it produces
#   exactly the silence this repository exists to distinguish from a clean result.
#
#   And there is a worse case. The shipped configs are EXAMPLES. They protect
#   `src/core/Ledger.ts`, a file that does not exist in your project. Install and
#   forget to edit them, and the guards run perfectly while guarding fiction.
#   Nothing complains. You get a green pipeline and zero protection.
#
#   Both failures look identical to a working install. So: check once, explicitly.
#
# USAGE
#   bash scripts/doctor.sh              check this installation
#   bash scripts/doctor.sh --self-test  prove the doctor can still see
#
# EXIT
#   0 — usable   ·   1 — something is broken or still guarding fiction

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${NC_CONFIG_DIR:-$ROOT/config}"

# Strings that appear ONLY in the shipped example configs. If one of these is
# still present, the config has not been adapted.
#
# 🔴 These must stay in step with config/. A control in --self-test asserts that
#    every marker below really does appear in the shipped examples — so if an
#    example is reworded and this list is not, the doctor goes red instead of
#    silently losing the ability to detect an unedited install.
PLACEHOLDERS=(
  "src/core/Ledger.ts"
  "SecurityRules.kt"
  "docs/ARCHITECTURE.md"
  "session-b"
)

ok=0; bad=0; warn=0
say_ok()   { echo "   ✅ $1"; ok=$((ok+1)); }
say_bad()  { echo "   ❌ $1"; bad=$((bad+1)); }
say_warn() { echo "   🟡 $1"; warn=$((warn+1)); }

# ── the two checks worth testing, written as functions so they can be ─────────
# ── exercised against fixtures rather than only against the real tree ─────────

# has_placeholder <config-dir> -> prints the first marker found, exit 0 if found
has_placeholder() {
  local dir="$1" m
  for m in "${PLACEHOLDERS[@]}"; do
    if grep -rqF "$m" "$dir" 2>/dev/null; then printf '%s' "$m"; return 0; fi
  done
  return 1
}

# dep_present <command> -> exit 0 if runnable
dep_present() { command -v "$1" >/dev/null 2>&1; }

# ── controls ────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--self-test" ]]; then
  fail=0
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

  # ① coupling: every marker must really exist in the shipped examples.
  #    Without this the list silently rots and the doctor stops detecting.
  for m in "${PLACEHOLDERS[@]}"; do
    grep -rqF "$m" "$ROOT/config" 2>/dev/null \
      || { echo "🔴 ① marker «${m}» is not in config/ — the list has rotted"; fail=1; }
  done

  # ② positive: a config that still holds an example must be detected
  mkdir -p "$tmp/dirty"; printf 'paths: src/core/Ledger.ts\n' > "$tmp/dirty/x.json"
  has_placeholder "$tmp/dirty" >/dev/null \
    || { echo "🔴 ② unedited config not detected"; fail=1; }

  # ③ VACUUM: an adapted config must NOT be flagged. Without this, a detector
  #    that always reports "unedited" would pass ② and be useless.
  mkdir -p "$tmp/clean"; printf 'paths: app/billing/Invoice.kt\n' > "$tmp/clean/x.json"
  has_placeholder "$tmp/clean" >/dev/null \
    && { echo "🔴 ③ adapted config wrongly flagged as unedited"; fail=1; }

  # ④ VACUUM: an empty directory must not be flagged either
  mkdir -p "$tmp/empty"
  has_placeholder "$tmp/empty" >/dev/null \
    && { echo "🔴 ④ empty config dir wrongly flagged"; fail=1; }

  # ⑤ positive: a dependency that certainly exists is seen
  dep_present bash || { echo "🔴 ⑤ dep_present cannot see bash"; fail=1; }

  # ⑥ VACUUM: an invented dependency is not seen. Without this, a checker that
  #    always answers "present" would pass ⑤.
  dep_present zzz-no-such-command-15082026 \
    && { echo "🔴 ⑥ dep_present claims an invented command exists"; fail=1; }

  if [[ $fail -eq 0 ]]; then
    echo "✅ doctor — 6/6 controls pass, its report may be trusted"
  else
    echo "❌ doctor UNSOUND — do not trust its report"
  fi
  exit $fail
fi

# ── the actual check ────────────────────────────────────────────────────────
echo "🩺 negative-control — install check"
echo

echo "── dependencies ──"
if dep_present bash; then say_ok "bash ($(bash --version | head -1 | sed 's/.*version //;s/ .*//'))"
else say_bad "bash not found"; fi

if dep_present jq; then say_ok "jq — required by critical-path-guard and claim-guard"
else say_bad "jq NOT FOUND — both guards will exit silently, which is indistinguishable from finding nothing. Install it: brew install jq"; fi

if dep_present python3; then say_ok "python3 — attention-anchor trigger words"
else say_warn "python3 missing — attention-anchor still prints its base text, but trigger-word escalation stops working"; fi

if dep_present node; then say_ok "node — needed only by scripts/lib/receipt.mjs"
else say_warn "node missing — the guards do not need it; only the receipt library does"; fi

echo
echo "── files ──"
for h in attention-anchor critical-path-guard claim-guard; do
  f="$ROOT/hooks/$h.sh"
  if [[ ! -f "$f" ]]; then say_bad "hooks/$h.sh missing"
  elif [[ ! -x "$f" ]]; then say_warn "hooks/$h.sh is not executable — run: chmod +x hooks/*.sh"
  else say_ok "hooks/$h.sh"; fi
done
[[ -x "$ROOT/scripts/probe.sh" ]] && say_ok "scripts/probe.sh" || say_warn "scripts/probe.sh is not executable"

echo
echo "── configuration ──"
if [[ ! -d "$CONFIG_DIR" ]]; then
  say_bad "no config directory at $CONFIG_DIR"
else
  for c in anchor.md critical-paths.json claims.md; do
    [[ -f "$CONFIG_DIR/$c" ]] && say_ok "config/$c" || say_warn "config/$c missing — the tool that reads it will exit silently"
  done
  if found="$(has_placeholder "$CONFIG_DIR")"; then
    say_bad "config still contains the shipped EXAMPLE «${found}» — the guards are protecting files that do not exist in your project. They will run, stay green, and defend nothing. Edit config/ before trusting them."
  else
    say_ok "config has been adapted (no shipped example values left)"
  fi
fi

echo
echo "── controls ──"
if bash "$ROOT/scripts/probe.sh" --all >/dev/null 2>&1; then say_ok "probe.sh --all passes"
else say_bad "probe.sh --all FAILS — run it directly to see which control broke"; fi
if bash "$ROOT/hooks/attention-anchor.sh" --self-test >/dev/null 2>&1; then say_ok "attention-anchor --self-test passes"
else say_bad "attention-anchor --self-test FAILS"; fi

echo
echo "passed $ok · warnings $warn · problems $bad"
if [[ $bad -eq 0 ]]; then
  echo "✅ installation is usable"
else
  echo "❌ installation is NOT usable as-is — see the ❌ lines above"
fi
[[ $bad -eq 0 ]] || exit 1
exit 0
