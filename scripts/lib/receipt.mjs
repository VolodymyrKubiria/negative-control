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
//   every receipt is exit 0, nobody ever blinded a detector on purpose, and
//   "I measured its sensitivity" is fiction.
//
//   Query it:
//     jq -r 'select(.exit != 0) | "\(.ts) \(.tool) \(.argv|join(" "))"' \
//       .claude/state/receipts.jsonl
//
// WHERE IT LIVES
//   Machine-local, outside version control: this is session state, not a project
//   artifact. Losing it means "not measured", never "broken". Trimmed so it
//   cannot grow without bound.
//
// CONTROLS
//   node scripts/lib/receipt.mjs --self-test

import { appendFileSync, mkdirSync, readFileSync, existsSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";

const MAX_LINES = 2000;

// Resolved per call rather than once at import, so the controls below can point
// it at a scratch directory. A module that can only ever be exercised against
// the real location is a module whose behaviour is asserted, not measured.
function receiptsPath() {
  const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  return join(repo, ".claude/state/receipts.jsonl");
}

/** Current log location. Kept as a named export for callers that report paths. */
export const RECEIPTS = receiptsPath();

/**
 * Record one run. Call exactly once, immediately before exiting.
 * Never throws: a broken receipt has no right to stop the tool it is watching.
 */
export function stamp(tool, exitCode, argv = process.argv.slice(2)) {
  try {
    const p = receiptsPath();
    mkdirSync(dirname(p), { recursive: true });
    const rec = { ts: new Date().toISOString(), tool, exit: Number(exitCode) || 0, argv };
    appendFileSync(p, JSON.stringify(rec) + "\n");
    trim();
  } catch { /* a receipt is a convenience, not a dependency */ }
}

function trim() {
  try {
    const p = receiptsPath();
    const lines = readFileSync(p, "utf8").split("\n").filter(Boolean);
    if (lines.length > MAX_LINES) writeFileSync(p, lines.slice(-MAX_LINES).join("\n") + "\n");
  } catch { /* ignore */ }
}

/** Read the log back; empty if it does not exist yet. */
export function readReceipts() {
  const p = receiptsPath();
  if (!existsSync(p)) return [];
  try {
    return readFileSync(p, "utf8").split("\n").filter(Boolean)
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

// ── controls ────────────────────────────────────────────────────────────────
if (process.argv.includes("--self-test")) {
  const saved = process.env.CLAUDE_PROJECT_DIR;
  const box = join(tmpdir(), `receipt-controls-${process.pid}`);
  let bad = 0;
  const t = (name, cond) => { if (!cond) { console.log(`🔴 ${name}`); bad++; } };
  const fresh = () => {
    rmSync(box, { recursive: true, force: true });
    mkdirSync(box, { recursive: true });
    process.env.CLAUDE_PROJECT_DIR = box;
  };

  // ① a stamped run reads back, with its fields intact
  fresh();
  stamp("demo", 0, ["--all"]);
  let r = readReceipts();
  t("① a stamped run is readable", r.length === 1 && r[0].tool === "demo");
  t("① its argv survives", JSON.stringify(r[0]?.argv) === JSON.stringify(["--all"]));

  // ② the load-bearing one: a NON-ZERO exit is recorded as non-zero. If red runs
  //    were flattened to 0, the log could never answer "was this ever red?" —
  //    which is the only question it exists to answer.
  fresh();
  stamp("demo", 3);
  r = readReceipts();
  t("② a red run is recorded as red", r[0]?.exit === 3);

  // ③ VACUUM: an empty log yields nothing. Without this, a reader that invented
  //    entries would still pass ① and ②.
  fresh();
  t("③ vacuum — an empty log yields no entries", readReceipts().length === 0);

  // ④ VACUUM: a corrupt line is dropped, not turned into an entry
  fresh();
  stamp("good", 0);
  appendFileSync(receiptsPath(), "{ this is not json\n");
  r = readReceipts();
  t("④ vacuum — a corrupt line is skipped, not fabricated",
     r.length === 1 && r[0].tool === "good");

  // ⑤ the log cannot grow without bound
  fresh();
  const p = receiptsPath();
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, Array.from({ length: MAX_LINES + 50 },
    (_, i) => JSON.stringify({ ts: "x", tool: "t", exit: 0, argv: [String(i)] })).join("\n") + "\n");
  stamp("overflow", 0);
  t("⑤ the log is trimmed to its cap", readReceipts().length === MAX_LINES);

  // ⑥ VACUUM: an unwritable location must not throw. A receipt that can crash
  //    the tool it is watching is worse than no receipt at all.
  process.env.CLAUDE_PROJECT_DIR = "/dev/null/cannot-exist";
  let threw = false;
  try { stamp("demo", 0); } catch { threw = true; }
  t("⑥ vacuum — an unwritable path does not throw", threw === false);

  rmSync(box, { recursive: true, force: true });
  if (saved === undefined) delete process.env.CLAUDE_PROJECT_DIR;
  else process.env.CLAUDE_PROJECT_DIR = saved;

  console.log(bad === 0
    ? "✅ receipt — 7/7 controls pass"
    : "❌ receipt UNSOUND — its log cannot be trusted as evidence");
  process.exit(bad === 0 ? 0 : 1);
}
