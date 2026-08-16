# Changelog

## 0.7.0 — 2026-08-16

**Apache-2.0 instead of MIT, and provenance that travels with the file.**

MIT let anyone take these scripts, change them badly and ship the result without a
word — with the author's name still in a LICENSE file the copy left behind. Two
Apache clauses close exactly that:

- **§4(b)** — modified files must carry prominent notice of the change, so a degraded
  fork cannot be mistaken for the original;
- **§6** — no right is granted to use the author's name to endorse anything derived.

The patent grant is beside the point for shell scripts; these two clauses are not.

**Provenance in every file.** A vendored hook arrives without the LICENSE file, so
all six now carry a three-line header — repository URL, copyright, and an
`SPDX-License-Identifier`. Measured before the change: 0 of 6 files said where they
came from.

No `NOTICE` file. Apache requires propagating one only if the work already has it,
and its content would duplicate the headers — a root-level artifact earning nothing.

Nothing else changed: 12 control runs green, including all three mutation runs.

## 0.6.0 — 2026-08-16

**The headline demo was measuring nothing, for two of the three hooks.**

`probe.sh <hook> --mutate` is the thing this repository is *for*: blind a guard on
purpose, and require every `EXPECT` to go silent. Run it against `critical-path-guard`
or `claim-guard` in 0.5.0 and it printed a flawless score. It was theatre.

Both `MUTATE` expressions targeted the first line of a multi-line pipeline:

```
MUTATE s/^names="\$(jq.*$/names=""/
```

That left the continuation lines orphaned, so the mutant did not parse and bash never
started the hook. Every `EXPECT` "went silent" — for a reason that has nothing to do
with blindness — and the run concluded **`✅ every EXPECT went silent — these controls
can actually fail`**.

🔑 **The existing control could not see it, and the reason generalises.** The harness
already refused a mutation that changed *nothing*, and that check passed here: the file
*did* change. **Changed and still executable are two different questions.** Only the
second one makes the silence mean what the report says it means.

**What changed**

- `probe.sh` runs `bash -n` on the mutant and refuses to grade anything if it does not
  parse, printing `MUTANT DOES NOT PARSE` with the syntax error attached.
- Controls ⑨ and ⑨b hold that honest in both directions: an unparseable mutant must be
  refused, and a valid one must still be run — a parse check that rejected everything
  would have passed ⑨ alone.
- Both `MUTATE` lines rewritten to blind the *matching* instead of truncating an
  assignment. Verified the way it should have been the first time: the mutant is
  executable, and it still speaks when handed a blind config — proof it runs at all.
- `probe.sh` now **counts its own controls from its own source** instead of printing a
  hand-typed `8/8`. That number had already drifted the moment two controls were added.

**Guards now carry a run-time control, not only a bench one**

Controls that live in a mode nobody runs are controls in name only. Each guard now checks,
on every invocation, that its own config still parses — and says so when it does not:

- `critical-path-guard`: a `critical-paths.json` that parses to zero paths means the guard
  is armed and matching against an empty pattern. It announces that instead of exiting 0.
- `claim-guard`: the finer case. **No active claims is normal**; a board no row of which
  parses is blindness. Those two produce identical silence, so they are separated by a
  parse-health signal rather than by the claim count.
- Both hooks gained `--self-test` (4 controls each), including the negative control that
  matters most: a healthy config must never report itself blind.

**MATCH-based cases, closing a loop 0.5.0 opened**

The 0.5.0 entry ended by arguing for `MATCH` wherever output carries meaning — the Windows
CRLF corruption went past both guards precisely because their cases compared empty against
non-empty. Every `EXPECT` in `critical-path-guard.cases` and `claim-guard.cases` is now
anchored to the alarm text. Verified load-bearing by swapping the marker for one that never
appears: the suite goes red, then green again when restored.

**Origin figures are now dated.** `73,411` lines of Kotlin and `1,683` unit tests, measured
2026-08-16 — up 11 tests from the undated figure three days earlier. A repository that asks
for measured numbers should not ship unmeasured ones.

## 0.5.0 — 2026-08-15

**Three operating systems, and the Windows runner earned its keep on the first run.**

A CI matrix now runs every control suite on `ubuntu-latest`, `macos-latest` and
`windows-latest`. No `continue-on-error` anywhere: a badge kept green by ignoring
a failing platform is the thing this repository argues against.

**What Windows caught**

`probe.sh --all` failed there while all four dependency gates passed — jq, bash,
python3 and node are all present on that runner. Git for Windows checks out CRLF
by default, so `MATCH some string\r` stopped matching hook output, and every
EXPECT in `attention-anchor.cases` failed.

🔑 **Which suites survived is the instructive part.** Both guards passed under the
identical corruption, because their cases only compare empty versus non-empty
output and never examine a string. A control that never looks at content cannot
notice content being wrong. Only the suite asserting on text could see it — an
argument for MATCH-based cases wherever the output carries meaning.

**Fixed, in two layers**

- `.gitattributes` forces LF for `sh`/`cases`/`mjs`/`json`/`md`/`yml`.
- `probe.sh` strips a trailing `\r` when parsing, so a case file that arrives with
  CRLF anyway still works instead of reporting "the hook stayed silent" about a
  hook that was never asked.
- Control ⑧, per this repository's own rule that a real failure becomes the next
  control: a fixture written with explicit `\r\n` must still pass. Inverted —
  removing the strip turns exactly that one control red.

**Now verified on real machines**

| Platform | Status |
|---|---|
| Linux (`ubuntu-latest`) | ✅ all suites, all inversions |
| macOS (`macos-latest`) | ✅ all suites, all inversions |
| Windows (`windows-latest`, Git Bash) | ✅ all suites, all inversions |

The workflow's first step measures the environment rather than assuming it —
bash version, which tools exist, and which `sed` dialect, decided by feeding
`\+` to sed and looking.

**Still not verified**

- The `/plugin marketplace add` + `/plugin install` route. The plugin load was
  exercised through `--plugin-dir` on macOS only.
- Any machine without `jq`. The guards exit 0 silently there; `doctor` says so,
  but only if it is run.

## 0.4.0 — 2026-08-15

**The plugin never loaded. Nothing said so.**

`plugin.json` declared `"hooks": "./hooks/hooks.json"`. That file is loaded
automatically by convention, so the explicit declaration was a duplicate — and a
duplicate hooks file aborts hook loading for the whole plugin:

```
Status: ✘ loaded with errors
Error: Duplicate hooks file detected … The standard hooks/hooks.json is loaded
       automatically, so manifest.hooks should only reference ADDITIONAL files.
```

🔴 **`claude plugin validate --strict` returned "Validation passed" on both
manifests while this was true.** A validator reporting clean on a broken artifact
is precisely the failure this repository exists to name, encountered from the
other side. Two lessons, both now mechanised rather than written down:

- **Validation is not loading.** `doctor` now runs `claude --plugin-dir . plugin
  list` when the CLI is present and fails on `loaded with errors`. Inverted:
  restoring the defect turns the line red, removing it turns it green.
- **"Unverified" was the correct label**, not excess caution. Had this shipped as
  "verified" on the strength of a passing validator, the first person to install
  it would have got silent, dead hooks.

**Fixed**

- `plugin.json` no longer declares `hooks` — the standard path is auto-discovered.
- `marketplace.json` gained the `description` that `validate --strict` required.

**Verified on a fresh clone from GitHub** (not the working copy): manifests pass
`--strict`; `probe --self-test`, `doctor --self-test` and `probe --all` all exit 0;
executable bits survive the clone; the plugin reports `✔ loaded` with
`Hooks (2) UserPromptSubmit, PreToolUse` registered.

**Still not verified** — stated precisely rather than rounded off:

- Only macOS, only CLI 2.1.232, only via `--plugin-dir`. Installation through
  `/plugin marketplace add` + `/plugin install` has not been exercised.
- No Linux or Windows run. No run on a machine without `jq`.

## 0.3.0 — 2026-08-15

The repository now meets its own standard. It did not before.

**The gap, stated plainly**

`probe.sh` demanded paired controls of every hook and had none of its own. It
could have been unable to parse a case file and would still have printed
`controls pass` — the precise silence this project exists to expose, in the one
tool everything else depends on. `lib/receipt.mjs` had no controls either, and
nothing in the repository called it.

**Added**

- **`probe.sh --self-test`** — 7 controls, run against a fixture tree rather than
  this repository, so a green result means the harness works and not that this
  repo happens to be tidy. Includes the control that would have caught the
  BSD/GNU sed bug shipped in 0.1.0, and a vacuum control for a mutation that
  changes no bytes.
- **`NC_ROOT`** — lets the harness be aimed at a fixture tree. Without it the
  harness could only ever be exercised against the real repo.
- **`receipt.mjs --self-test`** — 7 controls. The load-bearing one: a **non-zero**
  exit must be recorded as non-zero. A log that flattens red runs to green cannot
  answer the only question it exists for — *was this detector ever actually red?*
  Also vacuum controls for an empty log, a corrupt line, and an unwritable path.
- **`probes/attention-anchor.cases`** — all three hooks are now covered the same
  way by `probe.sh --all`, instead of two through the harness and one apart from
  it. This hook prints on every prompt, so "no output" cannot be its quiet state;
  every case pins a MATCH instead.
- `doctor` now runs the `probe` and `receipt` control suites too.

**Changed**

- `receipt.mjs` resolves its path per call instead of once at import. A module
  that can only run against one hard-coded location has behaviour that is
  asserted, not measured.
- In a fresh clone `doctor` ends with one ❌ — and now says so, explicitly, as a
  demonstration rather than a defect: `config/` holds examples, so the guards
  would defend a file your project does not have.

**Control coverage, measured**

| Tool | Controls |
|---|---|
| `attention-anchor` | 6 self-test + 6 probe cases |
| `claim-guard` | 11 |
| `critical-path-guard` | 11 |
| `doctor` | 6 |
| `probe` | 7 |
| `receipt.mjs` | 7 |

Every suite was inverted with a deliberate mutation, and the count of failures
predicted before the run.

## 0.1.0 — 2026-08-15

First release. Three hooks, one probe harness, one library.

**Found by the probe on its own first run, before anything shipped:**

- `critical-path-guard` stayed silent on `cat <<EOT > protected-file`. The read-command
  amnesty list began with `cat`, so a heredoc **write** was filtered out as a read.
- `probe.sh` could not find its own `MUTATE` line on macOS. It used `\+`, a GNU sed
  extension that BSD sed does not implement, so the harness reported "no MUTATE line" for
  case files that had one — the instrument for measuring sensitivity was itself blind.

## 0.2.0 — 2026-08-15

Adoption pass. Nothing about the guards changed; everything about getting them running did.

- **`scripts/doctor.sh`** — answers the question a silent guard cannot: can this install do
  anything at all. Checks deps, permissions, and — the one that matters — whether `config/`
  still holds the shipped examples. A guard defending `src/core/Ledger.ts` in a project that
  has no such file runs perfectly, stays green, and protects nothing. `doctor` fails loudly
  on that. Six controls of its own, two of them vacuum controls, plus a coupling control that
  goes red if the example configs are reworded without updating the marker list.
- **Quickstart at the top of the README** — clone, two commands, visible result, no install.
- **A ready-to-paste `settings.json` block**, because the previous instruction (*"wire the
  hooks — see hooks/hooks.json"*) quietly handed the user a translation job. The two files
  are different dialects: `${CLAUDE_PLUGIN_ROOT}` versus `${CLAUDE_PROJECT_DIR}`, and a
  project needs an explicit `bash` prefix. Paste the wrong one and the hooks never fire —
  which looks exactly like hooks that found nothing.

**Fixed**

- `doctor.sh` mis-parsed `«$var»` on bash 3.2 (still the system bash on macOS): the
  multibyte guillemet was absorbed into the identifier, giving `unbound variable`. Braces
  fix it. Worth knowing if you write user-facing messages with typographic quotes.

**Now verified**

- The **vendoring path is measured end to end**: a scratch project, files copied per the
  README, `settings.json` extracted verbatim from the README, and the hook invoked exactly
  as the harness would invoke it. Positive control fires from the vendored location; vacuum
  control stays silent; `doctor` correctly reports the fresh install as *not usable* because
  the config is still the example.

**Known limits**

- The Claude Code plugin install path is **still unverified against a live install**.
  Manifests validate as JSON and follow the documented layout; that is not the same as
  working. The vendoring path above is the one with evidence behind it.
- `attention-anchor` is proven to be *alive* and to escalate *conditionally*. It is not
  proven to change behaviour on the hundredth turn. An alarm that fires every time
  desensitises as thoroughly as one that never fires — measure it if you adopt it.
- Controls are hand-written fixtures. They can rot alongside the code they guard.
