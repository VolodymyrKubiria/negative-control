# Changelog

## 0.1.0 — 2026-08-15

First release. Three hooks, one probe harness, one library.

**Found by the probe on its own first run, before anything shipped:**

- `critical-path-guard` stayed silent on `cat <<EOT > protected-file`. The read-command
  amnesty list began with `cat`, so a heredoc **write** was filtered out as a read.
- `probe.sh` could not find its own `MUTATE` line on macOS. It used `\+`, a GNU sed
  extension that BSD sed does not implement, so the harness reported "no MUTATE line" for
  case files that had one — the instrument for measuring sensitivity was itself blind.

**Known limits**

- The Claude Code plugin install path is **unverified against a live install**. Manifests
  validate as JSON and follow the documented layout; that is not the same as working.
- `attention-anchor` is proven to be *alive* and to escalate *conditionally*. It is not
  proven to change behaviour on the hundredth turn. An alarm that fires every time
  desensitises as thoroughly as one that never fires — measure it if you adopt it.
- Controls are hand-written fixtures. They can rot alongside the code they guard.
