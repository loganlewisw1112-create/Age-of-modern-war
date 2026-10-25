# Common brief for every G5 agent ("Full Spectrum", one wave, up to 8 agents live)

You are one builder on a Godot 4.7.2 RTS ("RTS: Age of Modern War"). G1-G4 shipped. The owner approved G5: air, naval, 17 new human ground units, auto resupply + medical evac, a UI facelift with a custom typeface, G4 gap fixes and a tutorial. **Your role, files and tasks are fixed in your own brief (`G5-<ID>.md`). Do only that.**

**Project root:** `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`. Quote paths; they contain spaces.
**Godot console exe:** `/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe`.

## 1. Read first (in order)
1. `.plan/AGENT_RULES.md`: budget protocol, tests, report format, GDScript gotchas. **Binding.**
2. `docs/CONTRACTS_G5.md`: **binding**. §0 hard rules, §1 ownership, §2 scaffold, §11-§12, plus the sections your brief names.
3. `docs/PLAN_G5.md`: intent and nuance (your workstream section).
4. Your brief, then the code you own or call (headers and public functions first).

## 2. Message board: structured record (`.plan/board.jsonl`)
Post with:
`AGENT_BOARD="D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board.jsonl" node "D:/CODING/SKILLS/tools/agent-board/post.mjs" <ID> orch <type> <topic> '<json>'`

**What to post:**
- `status progress` as your FIRST tool call and then every 5 tool calls (reading files counts), with `{"calls_used":N,"tokens_used_est":N,"next_action":"..."}`. Estimate tokens as about 95k + 2.3k per call.
- A `claim files` with your owned files at the start.
- A `fact <name>` when an API in CONTRACTS_G5 §5 is callable (compiling stub first, within your first hour), then again when it is complete.
- A `change_request <topic>` to another file's owner (`to` = their ID) for anything outside your files.
- `handoff` and `done` at the end.

**Long runs:** wrap any command that may run over 60 s in `bash .plan/hb.sh <ID> <calls> <tokens> "<label>" -- <command>`. It posts heartbeats. An agent silent for 12 minutes is stopped.

## 3. Semantic layer: live meaning stream (`.plan/bus.log`)
At every finding, decision, dead end or milestone, append ONE short line:
`echo "$(date +%H:%M:%S) <ID> NOTE|FOUND|BLOCK|DONE <short message>" >> "D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/bus.log"`
- **NOTE** = progress / a decision; **FOUND** = a fact others may need; **BLOCK** = you need something (name who); **DONE** = finished.
- Never paste file contents or logs into the bus.
- If you break the shared tree: `<ID> BLOCK tree.broken <file>`, then fix it immediately.

## 4. Non-negotiables
- **Touch only files you own** (CONTRACTS_G5 §1). Everything else goes through a `change_request`.
- **Content:** only your own `content/g5/<file>.json`. New IDs only (CONTRACTS_G5 §3 fixes them).
- **Determinism and saves:** same seed + commands = same hash, threaded or not, native or fallback. New state is saved and hashed. Existing G4 results must not change unless your contract section says so.
- **Keep the tree compiling after every write:**
  - stub functions first, chunks of ≤250 lines;
  - then `"$G" --headless --path . --quit-after 60 2>&1 | grep -A1 "SCRIPT ERROR"` must print nothing.
- **Tests:**
  1. At start, `git mv` your skeleton(s) from `tests/pending_g5/` into `tests/`.
  2. Make every test pass with real checks. Iterate with `bash tests/run.sh --only=<file>`.
  3. Run the full suite once at the end inside hb.sh. If a failure is in another agent's in-progress file, quote it and keep yours green.
- **Machine sharing:**
  - never kill a godot process you didn't start;
  - at most 3 soaks and 2 windowed playtests machine-wide (check the board);
  - record the CPU load with any timing. Final perf numbers are taken by ORCH on a quiet PC.
- **Native DLL:** only `bash tools/build_native.sh --stage`, then `--swap`.
- **Budget:** at 70% of the projection, or on `budget.handoff_now`, write `.plan/handoff/<ID>-<n>.json` (done / exact remaining steps / files / test state / gotchas), post `handoff`, and stop. Never ask for a bigger cap.
- **Finish:**
  - kill your own processes;
  - post `done` and a bus `DONE` line;
  - send the AGENT_RULES final report: STATUS, FILES, TESTS (raw lines), EVIDENCE, CONTRACT_DEVIATIONS, CHANGE_REQUESTS, KNOWN_GAPS.

  **Do not commit** (ORCH commits). **No GENESIS/postflight offer.**
