# Claims board

One row per claim. 🔒 = held, 🔓 = released. `claim-guard` reads only 🔒 rows.
The board lives here and nowhere else — two copies drift apart.

| path | held by | since | |
|---|---|---|---|
| `docs/ARCHITECTURE.md` | session-b | 2026-08-15 | 🔒 |
| `src/parser.ts`        | session-a | 2026-08-14 | 🔓 |
