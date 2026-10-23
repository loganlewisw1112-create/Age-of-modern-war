# Rules for every builder agent: RTS: Age of Modern War, G0+G1 slice

Project root: `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game` (bash path `/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`). Always quote paths, because they contain spaces.

## Read first
1. `docs/CONTRACTS.md`: the binding contract. Re-read §0 (hard rules) and §1 (file ownership).
2. Your own brief (`.plan/agents/prompts/<your-id>.md`).
3. The current versions of the files you own, plus the orchestrator files you call (`sim/world.gd`, `sim/content.gd`, `sim/terrain.gd`, `content/*.json`).

Five other builders work **in the same checkout at the same time**. Touch only files you own. Never run `git add`, `commit`, `stash`, `reset` or `checkout`. Never delete files you don't own.

## Engine and tests
- Godot 4.7.2 console exe: `/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe` (`$G` below). The non-console exe is in the same folder.
- Tests: `bash tests/run.sh --only=<your_test_file_basename>`, and `bash tests/run.sh` for everything. It fails on any SCRIPT ERROR / Parse Error even when assertions pass. **Your gate is green only when `bash tests/run.sh` prints `TESTS OK`.** If another agent's in-progress file breaks the full run, say so in your report, quoting the error, and make sure your own `--only` run is green.
- Do **not** run `--import` (the orchestrator does that). If you add a new `class_name`, list it in CHANGE_REQUESTS and refer to the script by `preload` meanwhile.
- GDScript strictness: values read from Dictionaries are Variant, so `var x := d.foo` fails to compile ("Cannot infer the type"). Write `var x: float = d.foo` or `var x = d.foo`.
- Windowed check (visual agents): `"$G" --path . -- --autoshot="<abs path>.png" --autoshot-delay=4 --autostart`, then view the PNG with the Read tool. Save screenshots under `.plan/shots/<your-id>/`.
- On this Windows machine each tool call takes 30-120 s. Batch work into fewer, larger edits.

## Budget protocol (mandatory, owner rule)
Board: `export AGENT_BOARD="/d/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board.jsonl"`, scripts in `/d/CODING/SKILLS/tools/agent-board/`.
- Post a status **every 5 tool calls OR every 4 minutes, whichever comes first, and before any single call that may take over 2 minutes**:
  `AGENT_BOARD=... node /d/CODING/SKILLS/tools/agent-board/post.mjs <your-id> orch status progress '{"calls_used":N,"tokens_used_est":N,"next_action":"<exact next step>","done_so_far":"<short>"}'`
  Estimate `tokens_used_est` as about 60000 + 5000 x calls_used, plus the real size of any huge reads.
- After each status, read directives for you: `AGENT_BOARD=... node /d/CODING/SKILLS/tools/agent-board/read.mjs --for <your-id> --type directive`.
- Wrap any call expected to exceed ~60 s (long godot runs, soak, bench) in the heartbeat: `bash .plan/hb.sh <your-id> <calls_used> <tokens_est> "<label>" -- <command...>`.
- Self-check at each status: if `max(est + 90000, 191000 + 2300 x calls) >= 0.7 x MAX_TOKENS` or `calls >= 0.7 x MAX_TOOL_CALLS`, or on a `budget.handoff_now` directive: stop new work and write `.plan/handoff/<your-id>-<gen>.json` (`{done, remaining (exact steps), files_touched, test_state, gotchas}`). Then post `handoff '{"file":"..."}'` and end with your final report with `status: "recycled"`.
- On finishing, post `done '{"summary":"..."}'`.

## Final report (your last message, which goes to the orchestrator, not the user)
```
STATUS: done | partial | recycled | blocked
FILES: <owned files created/changed>
TESTS: <the exact final lines of `bash tests/run.sh` (and --only) output, pasted raw>
EVIDENCE: <screenshots paths / numbers>
CONTRACT_DEVIATIONS: <anything you did differently from docs/CONTRACTS.md and why>
CHANGE_REQUESTS: <exact edits you need in orchestrator-owned files>
KNOWN_GAPS: <what is not done or not verified>
```
Never claim anything you did not run. "Not verified" is an acceptable answer, but an unverified claim is not. Do not add any GENESIS/postflight offer to your report.

## G2 additions (binding)
- Read `docs/CONTRACTS_G2.md` as well as `docs/CONTRACTS.md`.
- **Never write more than ~250 lines in one tool call.** Split big files into modules, and post a status BEFORE every large write. In G1, an agent that stayed silent for 20 minutes writing one giant file was stopped with nothing saved.
- Post a status every 5 tool calls OR every 4 minutes, whichever comes first. Wrap every godot run expected to take more than 60 s in `.plan/hb.sh`.
- Report `tokens_used_est` as about 60000 + 5000 x calls_used (self-estimates ran high in G1).
- `tests/run.sh` takes 3-6 minutes now. While iterating, use `--only=<file>`, and run the full suite once at the end (in hb.sh).
- `make_world()` in tests gives an inert side 1. Use `make_world({}, true)` for a live AI.
- Godot GDScript gotchas: a bare `randf()` inside a class resolves to the GLOBAL RNG, so use `w.rng`. `var x := dict.field` cannot infer a type. Never use var_to_str for state.
