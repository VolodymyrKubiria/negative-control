// receipt — a tool leaves a trace of its own run: what, when, with which flags,
//           and how it ended.
//
// WHY
//   "I ran the self-test and it was green" is a claim, and nothing checks it.
//   A run that leaves no trace is indistinguishable from a run that never
//   happened, which means an invented claim and a true one look identical.
//
// 🔑 THE POINT IS THE RED RUN, NOT THE GREEN ONE
//   A green control suite that has never once been red proves nothing — it may
//   simply be incapable of failing. So the value of a receipt log is not that
//   the tool ran; it is that somewhere in the log there is a NON-ZERO exit. If
//   every receipt is exit 0, nobody ever blinded the detector on purpose, and
//   "I measured its sensitivity" is fiction.
//
//   Query it:  jq -r 'select(.exit != 0) | "\(.ts) \(.tool) \(.argv|join(" "))"' \
//                .claude/state/receipts.jsonl
//
// WHERE IT LIVES
//   Machine-local, outside version control: this is session state, not a project
//   artifact. Losing it means "not measured", never "broken". Trimmed so it
//   cannot grow without bound.

import { appendFileSync, mkdirSync, readFileSync, existsSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";

const REPO = process.env.CLAUDE_PROJECT_DIR || process.cwd();
export const RECEIPTS = join(REPO, ".claude/state/receipts.jsonl");
const MAX_LINES = 2000;

/**
 * Record one run. Call exactly once, immediately before exiting.
 * Never throws: a broken receipt has no right to stop the tool it is watching.
 */
export function stamp(tool, exitCode, argv = process.argv.slice(2)) {
  try {
    mkdirSync(dirname(RECEIPTS), { recursive: true });
    const rec = { ts: new Date().toISOString(), tool, exit: Number(exitCode) || 0, argv };
    appendFileSync(RECEIPTS, JSON.stringify(rec) + "\n");
    trim();
  } catch { /* a receipt is a convenience, not a dependency */ }
}

function trim() {
  try {
    const lines = readFileSync(RECEIPTS, "utf8").split("\n").filter(Boolean);
    if (lines.length > MAX_LINES) writeFileSync(RECEIPTS, lines.slice(-MAX_LINES).join("\n") + "\n");
  } catch { /* ignore */ }
}

/** Read the log back; empty if it does not exist yet. */
export function readReceipts() {
  if (!existsSync(RECEIPTS)) return [];
  try {
    return readFileSync(RECEIPTS, "utf8").split("\n").filter(Boolean)
      .map((l) => { try { return JSON.parse(l); } catch { return null; } })
      .filter(Boolean);
  } catch { return []; }
}

/**
 * Wrapper for a tool: stamp and exit in one call. Keeps the invariant that the
 * receipt carries EXACTLY the code the tool exited with — a stamp written
 * separately from the exit drifts from it the first time someone adds an early
 * return.
 */
export function stampAndExit(tool, code) {
  stamp(tool, code);
  process.exit(code);
}
