# negative-control

**A detector that found nothing and a detector that cannot see produce byte-identical output.**

Every tool in this repository refuses to report until it has proven it can still see.

---

## The problem

If you work with a coding agent you are accumulating detectors far faster than you notice.
Not tests — *detectors*. Pre-commit hooks. Custom lint rules. Audit scripts. "Check that no
doc references a deleted file." "Check that the test count in this commit message is real."

They cost one sentence to request, so you request them constantly. They run on every commit.
They almost always print nothing, which is exactly what you want them to print.

Silence is the success state. Silence is also the total-failure state. You cannot tell them
apart by looking — and the longer a detector stays quiet, the more you trust it, which is
precisely backwards: **a broken detector is silent more reliably than a working one.**

Mutation testing solves this for *test suites*. Nobody applies it to the 200-line script
their agent wrote on Tuesday. And LLM guardrail tooling watches whether the *model* does
something dangerous — not whether your own checker has gone blind.

## The fix, borrowed from lab science

Every assay ships with controls. A [negative control](https://www.nist.gov/glossary-term/36651)
is the assay run with everything *except* the sample: no signal is expected, and a signal
means the run is contaminated. A positive control must fire — if it doesn't, the instrument
is dead and every clean reading it gave you today means nothing.

So every hook here carries paired controls, and a mutation mode that blinds the hook on
purpose to check the controls can fail at all:

```console
$ bash scripts/probe.sh critical-path-guard

🧪 critical-path-guard — controls

   ✅ EXPECT · Edit of a protected file
   ✅ EXPECT · Bash: sed -i on a protected file
   ✅ EXPECT · Bash: heredoc overwriting a protected file
   ✅ SILENT · Bash: grep of a protected file
   ✅ SILENT · Bash: commit message naming a protected file
   ✅ SILENT · empty input

passed 11 · failed 0
✅ controls pass — hook may be trusted for this run
```

Note what that last line does **not** say. It does not say your codebase is clean. It says
that *for this run*, this tool's verdict is worth reading. If any control fails it prints
`❌ HOOK UNSOUND — do not trust its silence` and emits no verdict at all. Not a partial one.

### The part almost nobody does

A green suite that has never once been red may simply be incapable of failing. So:

```console
$ bash scripts/probe.sh critical-path-guard --mutate

🧪 critical-path-guard — controls  (MUTATED: hook deliberately blinded)

   ✅ went silent · Edit of a protected file
   ✅ went silent · Bash: heredoc overwriting a protected file
   ...
sensitivity: 0 of 5 EXPECT cases still fired while blinded (want 0)
✅ every EXPECT went silent — these controls can actually fail
```

The harness also controls *itself*: if the mutation doesn't change the file, it refuses to
run and says so, because a mutation that changed nothing looks exactly like one that worked.

## This is not a hypothetical

Two defects were found by this repository's own probe, on its first run, before anything
had ever shipped:

| # | Defect | Why it survived review |
|---|---|---|
| 1 | `cat <<EOT > protected.ts` did not trip `critical-path-guard` | The read-command amnesty list started with `cat`, so a heredoc **write** was filtered out as a read |
| 2 | `probe.sh` silently could not find its own `MUTATE` line | It used `\+`, a GNU sed extension. On BSD sed (macOS) it matched nothing — so the instrument for measuring sensitivity was itself broken, and reported "no MUTATE line" for files that had one |

Both look like working code when you read them. Only a control catches them.

## What's in here

| Tool | Kind | What it does | Controls |
|---|---|---|:---:|
| `attention-anchor` | UserPromptSubmit | Gates *reasoning*, not actions: injects a reminder that an unconditional word or a named number must be measured before it is asserted. The only hook here that fires when **no tool call happens at all**. | ✅ 6 |
| `critical-path-guard` | PreToolUse | Escalates edits to configured load-bearing paths into a permission prompt. Watches `file_path` **and** the text of Bash commands. | ✅ 11 |
| `claim-guard` | PreToolUse | Two agent sessions in one repo coordinate through a claims board instead of discovering the collision at commit time. Advisory, never blocking. | ✅ 11 |
| `probe.sh` | harness | Runs the paired controls. `--mutate` blinds a hook and requires every EXPECT to go silent. | self-checking |
| `lib/receipt.mjs` | library | A run leaves a trace, so "I ran the self-test" stops being an unverifiable claim. | — |

Everything is standalone bash plus a single `.mjs`. Take one tool, take all of them.

**Requirements, measured rather than asserted:**

| Tool | Needs | Without it |
|---|---|---|
| `critical-path-guard`, `claim-guard` | `bash`, `jq` | exits 0 silently — verified on a PATH with `jq` removed |
| `attention-anchor` | `bash`; `python3` **optional** | still prints the base anchor; only trigger-word escalation stops working |
| `probe.sh` | `bash`, `sed`, `grep`, `cmp`, `mktemp` | — |
| `lib/receipt.mjs` | **`node`** | not used by the hooks; the guards work without it |

Every guard fails *quiet and open*: a missing dependency makes it silent, never broken.
That is the correct default for a hook — but it also means an absent `jq` gives you exactly
the silence this whole repository is about. Check it once at install time.

## Install

**Vendor it** — the path this repository has actually been run through:

```bash
git clone https://github.com/VolodymyrKubiria/negative-control
cp -r negative-control/hooks  your-project/.claude/
cp -r negative-control/config your-project/.claude/
# then wire the hooks in your-project/.claude/settings.json — see hooks/hooks.json
```

**As a Claude Code plugin** — manifests are included:

```
/plugin marketplace add VolodymyrKubiria/negative-control
/plugin install negative-control
```

> ⚠️ The plugin path is **not yet verified against a live install**. The manifests validate
> as JSON and follow the documented layout, but shipping an untested claim in a repository
> about untested claims would be a poor joke. Verified in `v0.2.0` or corrected — whichever
> the evidence says.

## Configure

Nothing is hardcoded. Each tool reads `config/`, and `NC_CONFIG_DIR` overrides the location.

| File | Used by | What it holds |
|---|---|---|
| `config/anchor.md` | attention-anchor | text injected on every prompt — keep it **short** |
| `config/anchor-full.md` | attention-anchor | extra text, injected only on trigger words |
| `config/anchor.triggers` | attention-anchor | one ERE per line, matched case-insensitively |
| `config/critical-paths.json` | critical-path-guard | `{ "reason": "...", "paths": [...] }` |
| `config/claims.md` | claim-guard | markdown table; `🔒` = held, `🔓` = released |

The shipped configs are examples. Replace them with yours.

## Adding controls to your own tools

1. Add a `--self-test` flag that runs before anything else and exits non-zero on failure.
2. For every rule the detector enforces, write **two** fixtures: one that must trip it, one
   that looks similar and must not.
3. Add at least one **input-parse** control — assert the thing you're reading is non-empty
   and shaped as expected. Most silent blindness is not subtle logic error; it's a path that
   moved, and now you're matching against an empty string.
4. Anchor positive controls to the most redundant, least removable fact available. If the
   anchor is marginal, its absence is ambiguous, and an ambiguous control is not a control.
5. On any control failure, print **"unsound — do not trust this report"** and refuse to emit
   a verdict.
6. Every time the detector is wrong in real use, don't just fix it — turn that exact case
   into control #N+1.

Step 6 is where it compounds. The control lists in here read like a diary of every way each
tool has previously been wrong. **That diary is the asset; the tool is the thing it's
attached to.**

## What this is not

Not a replacement for tests. Not mutation testing — that perturbs the *subject* to grade the
*checker*, which is stronger and far more expensive. This perturbs nothing; it just refuses
to let a checker report until it has shown, on fixed fixtures, that it can still tell signal
from noise.

It does not escape the regress either. Who controls the controls? Nothing does. They are
hand-written fixtures and they rot alongside the code. What this buys is a **floor**: a
detector without controls can be blind from birth and never say so; a detector with controls
has to survive a named list of things it must catch and must ignore, and when one of those
breaks it breaks loudly instead of printing a reassuring nothing.

## Origin

Extracted from the tooling of a production Android application — 73k lines of Kotlin, 1,672
unit tests, built solo. The scripts here are generalized copies: the original project keeps
its own, because a hook that has been moved away is a hook that has gone quiet, and a hook
that has gone quiet does not announce it.

## License

MIT — see [LICENSE](LICENSE).
