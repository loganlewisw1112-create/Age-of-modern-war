# THREAD: sim off the main thread + render snapshot + presentation integration owner
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, **§4** (yours). Background: `.plan/handoff/R4-render-3.json` and the R5-thread findings in `PROGRESS.md` (G3b evidence, "Parked"). A gdext abort happens off the main thread unless the DLL is built with experimental-threads (NAT is doing it; wait for `fact nat.threads_ready`). A world deep copy costs 22 ms at 2k, so use a compact snapshot instead.
**Owns:** `presentation/match_view.gd`, `presentation/view/**` except `terrain_layer.gd` and `g4b_*.gd`, `presentation/hud/**` except `g4b_*.gd`, `sim/render_snap.gd`, `tests/test_thread.gd`. You are also the **integration owner**: UI4B and ED agents send CHANGE_REQUESTs to wire their new files into hud.gd/match_view. Apply them promptly; watch the board.

Tasks:
1. `sim/render_snap.gd`: build `w.render_snap` at the end of `world.step()`. ORCH will add the call in world.gd on your request; post the CR with the exact line.
   - Packed per-unit arrays (ids, pos, prev_pos, facing, def index, owner, hp fraction, flag bits: moving/firing/selected-relevant/air/cargo-count);
   - buildings (state, progress, `conn`, `status`);
   - this tick's events;
   - per-faction top-bar numbers;
   - `detail` dict copies for `w.snap_request` ids;
   - fog visibility arrays (copy or double buffer).
   - Must be cheap (<2 ms at 2k).
2. Convert entity_layer/batch_art/overlays/fx/HUD/minimap to read ONLY the snapshot, plus immutable content and map terrain. The map terrain only changes through bridge/fire events, which come via snapshot events.
3. `match_view`:
   - step the world on a WorkerThreadPool task;
   - the main thread renders the last snapshot and interpolates;
   - commands queue on the main thread and hand over between steps;
   - if a step runs long, render on and don't start another until it joins; the game slows gracefully;
   - add the `--sim-thread=off` flag.
4. Wall art hook: buildings with `conn` pick art state `conn_<mask>` (ART-F supplies those states).
5. Tests and measurement:
   - `tests/test_thread.gd`: a recorded command stream gives the same hash threaded vs off; 2,000 ticks at 2k with no crash; the snapshot matches world state for sampled ids.
   - The 4 UI playtests pass with the thread on: human 33, human_b 37, machine 37, stages 53. Commands are in `.plan/handoff/UI4-3.json`.
   - fps table (quiet machine noted) for 2k fighting at normal zoom and 10k on valley at zoom 0.3. Targets: 60+ and 30+.
Done when: tasks 1-5 are done and the full suite is green. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `THREAD`.
