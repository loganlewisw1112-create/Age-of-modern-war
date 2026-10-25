# Common brief: G4 builders (G4a + G4e + G4b in parallel)

You are one builder on a Godot 4.7.2 RTS ("RTS: Age of Modern War"). G1–G3b shipped:
- 3 factions, 3 maps, Stage 7–9;
- a Rust native core (`native/rts_core`, built DLL in `bin/`);
- fidelity tiers and a batched renderer.

The owner loves it and asked for three sub-slices at once:
- **G4a:** engine foundations (sim off the main thread, 10k units, new terrain/water/movement classes, map files);
- **G4e:** an AoE/Stronghold-style map and scenario editor;
- **G4b:** walls/gates/towers, troop transports, 8 new human units.

Many builders work in the same checkout at the same time. **Your role and file list are fixed in your own brief. Do only that.**

Project root: `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`. Quote paths; they contain spaces.

## Read first (in order)
1. `.plan/AGENT_RULES.md`: budget protocol, tests, final report format, GDScript gotchas. **Binding.**
2. `docs/CONTRACTS_G4.md`: **binding**. Read §0 hard rules, §1 ownership, §2 scaffold, then the sections your brief names.
3. `docs/PLAN_G4.md`: the owner-facing plan, for intent and nuance.
4. Your own brief, then the current code you own or call (headers and public functions first).

## Non-negotiables
- **Touch only files you own (CONTRACTS_G4 §1).** For anything else, post a CHANGE_REQUEST to the owner on the board and list it in your report.
- **Content:** only your own `content/g4/<file>.json` fragment. Never edit the base `content/*.json`.
- **Determinism and saves:** same seed + same commands = same hash, threaded or not, native or fallback. Save/load round trips must hold for your new state.
- **Keep the tree compiling after every write.** When a big file is written in chunks, add empty stub functions FIRST, so no write ever calls a function that does not exist yet. Check with `godot --headless --path . --quit-after 60 2>&1 | grep -A1 "SCRIPT ERROR"` (must print nothing). Write complete, compilable chunks of ≤250 lines. If you break compile for others, fix it immediately.
- **Tests:** iterate with `bash tests/run.sh --only=<file>`; run the full suite once at the end inside `.plan/hb.sh`. If a peer's in-progress file breaks the full run, quote the error and keep your own runs green.
- **Budget:**
  - status every 5 calls or 4 minutes, with `calls_used`, `tokens_used_est` (≈60k + 5k per call) and `next_action`;
  - heartbeat (`.plan/hb.sh`) around every godot/cargo run over ~60 s;
  - at 70% of the projection, write `.plan/handoff/<your-id>-<n>.json` (done / remaining exact steps / files / test state / gotchas) and stop.
- **Kill your own leftover godot processes** before your final report.
- **Final report** in the AGENT_RULES format. Do not commit. No GENESIS/postflight offer.
