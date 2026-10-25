# Common brief for every G6 agent ("Command & Terrain", one wave, up to 8 agents live)

You are one builder on a Godot 4.7.2 RTS ("RTS: Age of Modern War"). G1-G5 shipped. The owner approved G6:
- real terrain height;
- companies and armies with a chain of command;
- AI that fights with real military doctrine, plus player-side AI Commanders;
- 89 new assets and the systems they need;
- exo-suits and loadouts, Stage 10, a marketplace, a new airfield, survival mode, editor Live mode;
- fixes for the G5 gaps.

**Your role, files and tasks are fixed in your own brief (`G6-<ID>.md`). Do only that.**

**Project root:** `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`. Quote paths; they contain spaces. **Branch:** `g6`. Never switch branches.
**Godot console exe** (`$G`): `/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe`.

## 1. Read first (in order)
1. `.plan/AGENT_RULES.md`: budget protocol, tests, report format, GDScript gotchas. **Binding.**
2. `docs/CONTRACTS_G6.md`: **binding**. §0 hard rules, §1 ownership, §2 scaffold, §5 APIs, §6 state, §17-§18, plus the sections your brief names.
3. `docs/PLAN_G6.md`: intent and nuance (your workstream section).
4. Your brief, then the code you own or call. Read headers and public functions first; don't read whole 1000-line files.

## 2. Message board: structured record (`.plan/board.jsonl`)
Post with:
`AGENT_BOARD="D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board.jsonl" node "D:/CODING/SKILLS/tools/agent-board/post.mjs" <ID> orch <type> <topic> '<json>'`

**What to post:**
- **`status progress`:** as your FIRST tool call, then every 5 tool calls (reading files counts) and after every write or test run. Body: `{"calls_used":N,"tokens_used_est":N,"next_action":"...","done_so_far":"..."}`. Estimate tokens as about 95k + 2.3k per call.
- **`claim files`:** your owned files, at the start.
- **`fact <name>`:** when an API in CONTRACTS_G6 §5 is callable. Post it for a compiling stub first, within your first hour, then again when it is complete.
- **`change_request <topic>`:** to another file's owner (`to` = their ID), for anything outside your files.
- **`handoff` and `done`:** at the end.
- **After each status,** read directives for you: `... node "D:/CODING/SKILLS/tools/agent-board/read.mjs" --for <ID> --type directive`.

**Long runs:** wrap any command that may run over 60 s as `bash .plan/hb.sh <ID> <calls> <tokens> "<label>" -- timeout <secs> <command>`. It posts heartbeats. **An agent silent for 12 minutes is stopped.**

## 3. Semantic layer: live meaning stream (`.plan/bus.log`)
At every finding, decision, dead end or milestone, append ONE short line:
`echo "$(date +%H:%M:%S) <ID> NOTE|FOUND|BLOCK|DONE <short message>" >> "D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/bus.log"`
- **NOTE** = progress or a decision; **FOUND** = a fact others may need; **BLOCK** = you need something (name who); **DONE** = finished.
- Never paste file contents or logs into the bus.
- If you break the shared tree: `<ID> BLOCK tree.broken <file>`, then fix it immediately.

## 4. Non-negotiables (lessons from G4, G5 and the G6 art pass)
- **Touch only files you own** (CONTRACTS_G6 §1). Everything else goes through a `change_request`. Never run `git add/commit/stash/reset/checkout/switch` (ORCH commits).
- **Write in chunks.** A compiling skeleton first, edits ≤250 lines, then a compile check and a status after each:
  - compile check: `timeout 240 "$G" --headless --path . --quit-after 60 2>&1 | grep -E -A2 "SCRIPT ERROR|Parse Error"` must print nothing.
  - In the G6 art pass, an agent writing one 60 KB file in a single call went silent for 12 minutes and was stopped with nothing saved.
  - **Every intermediate state must compile** (ORCH rule, 2026-10-25): three agents broke the whole tree for every other agent by appending a call before the function it calls (machine_g6.gd, mobility.gd `_pack`, ops_missions.gd `_eval_doc`). Write callees before callers, keep public functions present in every chunk, and use the Write/Edit tools for code: a shell heredoc append that fails silently caused one of the three.
  - **Never capture a fixture from a broken tree** (ORCH rule, 2026-10-25): before trusting any hash, golden, soak RESULT or perf number, grep its log for `SCRIPT ERROR`; it must be 0. A test_hot_state GOLD captured at 09:16 came from a tree where sonar.gd lacked tick() (1520 errors, every step aborted) and cost two agents an hour.
- **Never break callers mid-rewrite** (G6 wave, day 1: three agents broke the whole tree within an hour):
  - every CONTRACTS_G6 §5 function in your files stays present with its exact static signature at all times (keep the stub until the real one replaces it);
  - create a new file as a compiling stub BEFORE you add a `preload` of it anywhere;
  - static script functions are called directly (`G6Hooks.speed_mult(w, e)`), never through `.call()` on the script.
- **Every Godot run gets a `timeout`, and you never filter away `SCRIPT ERROR` / `Parse Error`.** Godot hangs at exit after a GDScript parse error and prints nothing, which looks like a silent agent.
- **Determinism and saves:**
  - same seed + commands = same hash, threaded or not, native or fallback;
  - new state is saved and hashed;
  - existing results don't change unless your contract section allows it.
- **Tests:**
  1. At start, `git mv` your skeleton(s) from `tests/pending_g6/` into `tests/` (`git mv` is the one git command you may run, for your own skeletons only).
  2. Make every test pass with real checks. Iterate with `bash tests/run.sh --only=<file>`.
  2b. **One heavy Godot job at a time per agent** (ORCH rule, 2026-10-25 11:20: about 22 Godot processes made every run 10x slower). Heavy = soak config, 10k bench, test_ui_fit, test_hot_state, windowed capture. Soak lanes: at most 2 configs in parallel. On Windows `timeout` may not kill the Godot child: if a run hangs, Stop-Process your own PIDs.
  3. **Do NOT run the full suite** (ORCH rule, 2026-10-25: concurrent full runs share user:// and broke test_save; 13 Godot runs at once slowed everyone). At the end, run `--only=` for every test file you own **plus** each test file covering a file whose callers you touched (e.g. production, world, damage, movement, airfield). ORCH runs the full suite at heartbeats and sends you any failure in your files. If a targeted run fails in another agent's in-progress file, quote it and keep yours green.
- **Height-aware:** after `elev.api_ready`, range, sight and LOS code goes through the `Elevation` API.
- **Machine sharing:**
  - never kill a godot process you didn't start;
  - at most 3 soaks and 2 windowed playtests machine-wide (check the board);
  - record the CPU load with any timing. Final perf numbers are ORCH's, on a quiet PC.
- **Native DLL:** only `bash tools/build_native.sh --stage`, then `--swap` (PERF6 only).
- **Network drop:** if your run is cut by a connection error, you are resumed from your own transcript. Post a status first.
- **Budget:** MAX_TOKENS 750000, MAX_TOOL_CALLS 140 unless your brief says otherwise. The guard projects `max(est + 90k, 303k + 2.3k x calls)` and nudges at 70% (about 96 calls).
  - At 70%, or on `budget.handoff_now`: write `.plan/handoff/<ID>-<n>.json` (done / exact remaining steps / files / test state / gotchas), post `handoff`, and stop.
  - Never ask for a bigger cap.
- **Finish:**
  - kill your own processes;
  - post `done` and a bus `DONE` line;
  - send the AGENT_RULES final report: STATUS, FILES, TESTS (raw lines), EVIDENCE, CONTRACT_DEVIATIONS, CHANGE_REQUESTS, KNOWN_GAPS.

  **Do not commit. No GENESIS/postflight offer.**
