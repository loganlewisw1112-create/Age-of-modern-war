# Shared rules for the G7.1 wave-1 fixers (ARTFIX71, UIFIX71, SPEEDFIX71, SPEEDCN71), ORCH 2026-11-10

Read `G71_COMMON.md` first (and through it `G7_COMMON.md`) and follow it. These rules add to it.

## Why you exist
ORCH ran the wave-1 gate suite (one Godot process per test file, 6 lanes, `C:/CODING/orch71_check/suite71.sh`) on the
frozen copy `C:/CODING/g71_clean` (HEAD fda25f9 + the wave-1 files): **177 files, 157 green**. The owner chose
**"Fix all 18 first"** (DECISIONS.md 2026-11-09): wave 1 is committed only when all 177 files are green. Two of the 20
red files are already fixed in the live tree (test_airfield via rts_core 0.6.3, test_perfdraw71). The other 18 are yours,
split by brief. Per-file logs: `C:/CODING/orch71_check/suite71/<test>.log` (wave 1), `.../head71/<test>.log` (HEAD
fda25f9, no wave 1), `.../g7ref71/<test>.log` (G7 3a66ffc, no A5 speed rule).

## Trees
- **Live tree (where you work):** `C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`.
- **Read-only reference worktrees** (imported; you may RUN a test there to compare, never edit a file there):
  G7 `C:/CODING/pd71_g7/game` (3a66ffc: no A5), HEAD `C:/CODING/g71_head/game` (fda25f9: A5 in, no wave 1).
  Godot: `/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe`;
  one file: `"$G" --headless --path <tree> -s tests/run_tests.gd -- --only=<test>` (in the live tree `bash tests/run.sh --only=<test>`
  is the same). Wrap any run > 60 s in `bash .plan/hb.sh <ID> <calls> <est> "<label>" -- <cmd>`.
- **Never touch** `C:/CODING/g71_clean` (ORCH's frozen copy) or anything under D:.

## Tests are frozen (Done-when frozen; the owner rule "never weaken a test")
- Never edit any file under `tests/` (expectations, setup, tolerances, helpers) and never edit a golden.
- When the sim behaviour is wrong, fix the sim (or art / UI) at the cause.
- When you conclude a test hard-codes a speed-coupled number, or has a setup bug that A5 exposed, post
  `change_request` to `orch`, topic `testfix.<test>`, data: `{"file":"tests/<f>.gd","line":N,"old":"<exact text>",
  "new":"<exact text>","why":"<one paragraph>","evidence":"<log paths: G7 vs HEAD vs live>"}`. ORCH asks the owner
  before any expectation change. Then go on with your next file; don't wait.

## Files you may edit
Every wave-1 agent has finished, so you may edit the sim / presentation / content / art files your fix needs, EXCEPT the
ORCH files (`sim/world.gd`, `sim/content.gd`, `tools/ui_playtest.gd`, goldens, README / PROGRESS / DECISIONS / docs): for
those post `change_request` to orch with the exact function and change. **Before your first edit of any tracked file**, post
`fact claim.file '{"file":"<path>","by":"<ID>","why":"<short>"}'` and read the board (`read.mjs --topic claim.file`): if
another fixer already claimed it, send them a `change_request` instead of editing. Fellow fixers: ARTFIX71, UIFIX71,
SPEEDFIX71, SPEEDCN71. Never edit a wave-2 file (`*71.gd` files of DAMAGE71 / FIRES71 / ARMY71 / BASTION71 / CNOPS71 /
SWARMNAT71, `content/g71/*` except the FARP / air entries ARTFIX71 needs). A5 stays: never undo or re-apply the x1.2
speed rule (`rules.g71_speed_mult`, `Content._apply_g71_speed`).

## Determinism after any sim change
- `test_hot_state` must stay 17/0 on the current goldens.
- The 3 bench hashes must stay at `fact w2.bench_ref` on board_g71 (2k fight 8fd794b3, 2k mixed a1e5af17, 10k
  valley_conquest_l 200t 41b5f765; harness `.plan/perfsim71/sim_ab4.gd`, every run under `orch.timing_lock`, seq 440).
- If a correct fix moves a hash on purpose, say which and why, with two identical runs of the new value. ORCH re-baselines.
- Parse-check every edited `.gd`; LF line endings; no background script left running when you hand off or finish.

## Board
`AGENT_BOARD="C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board_g71.jsonl"` on every
`post.mjs` / `read.mjs` call. Status every 5 tool calls (`calls_used`, `tokens_used_est`, `next_action`, `done_so_far`).
Budget: **MAX_TOKENS 750000, MAX_TOOL_CALLS 140**. Hand off at 70%: `max(est + 90k, 312k + 2.3k x calls) >= 525k` or
calls >= 98, or at once on `budget.handoff_now`: write `.plan/handoff/<ID>-<gen>.json` (per test: state, cause found, fix,
files touched, exact next step), post `handoff {"file":...}`, end with status "recycled". No git writes, no commits.
No GENESIS / postflight offer.

## Done for each test file
A fresh run of that file in the live tree: `RESULT ... fail=0` and `script_errors=0`, OR a posted `testfix.<test>` change
request with the evidence. Then run the other test files that cover the code you changed (name them).

## Final report
Per test file: cause (one or two sentences, with evidence), fix (files + functions) or change-request seq, RESULT line
before / after with log paths. Then: hashes / test_hot_state after your last sim change, files touched, anything left.
