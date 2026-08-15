# Changelog

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
