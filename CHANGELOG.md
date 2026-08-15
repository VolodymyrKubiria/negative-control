# Changelog

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
