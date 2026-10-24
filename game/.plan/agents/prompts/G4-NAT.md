# NAT: engine foundations (terrain semantics, movement classes, gate nav, native threads)
Read G4_COMMON.md first. Contract sections: CONTRACTS_G4 §0, §1, §2.2, **§3** (yours), §4 (thread needs from you).
**Owns:** `sim/terrain.gd`, `sim/systems/movement.gd`, `sim/native_core.gd`, `native/**`, `bin/**`, `tools/build_native.sh`, `sim/systems/damage.gd` (only the LOS terrain set), `tests/test_terrain_classes.gd`, `tests/test_native.gd`.
**Others wait on you:**
- THREAD (threads DLL);
- FORT (`Movement.set_gate`);
- ED1/ART-T (terrain semantics);
- UNITS (LOS through cliffs).
Post `fact nat.<milestone>` as each piece lands.

Tasks (in this order):
1. **Threads build first** (THREAD is blocked on it):
   - add `experimental-threads` to the godot dependency in `native/rts_core/Cargo.toml`;
   - rebuild with `tools/build_native.sh --stage/--swap`;
   - prove `world.step()` on a WorkerThreadPool task does not abort, native on, 2k units, 500 ticks, hash equal to a main-thread run;
   - post `fact nat.threads_ready`.
2. **Terrain semantics for codes 8-13** (§3 table): `Terrain.passable(code, mc)`, `speed_mult`, `buildable`, `blocks_los(code)`, and `sight_bonus(code)` (HILL +2). WATER keeps its current semantics for foot/vehicle, so **River Crossing stays byte-identical in behaviour** (test_maps and the hashes must stay green).
3. **Movement classes** `amphibious`, `naval_small`, `naval`, `air_low`, `air_high`, with `air` an alias of air_low:
   - the native nav builds a grid per class lazily;
   - the GDScript fallback works too;
   - `naval` needs ≥3-wide channels (precompute a channel mask).
4. **Gates:**
   - `Movement.set_gate(w, cells, owner_team, locked)`;
   - a per-team blocked overlay (native + fallback), so path queries take the entity's team automatically and flow fields are keyed by team;
   - post `fact nat.gates_ready` with the exact API.
5. **LOS:** `Damage.line_clear` plus native `RtsCombat.line_clear` treat CLIFF/RIDGE/BUILDING as blocking. Add a parity test.
6. **Tests** (`tests/test_terrain_classes.gd`):
   - passability per class per code;
   - a naval channel rule;
   - a gate blocking an enemy team while letting the owner through (native + fallback);
   - LOS blocked by a cliff;
   - same hash threaded vs main on a 2k scenario.
7. Rebuild the DLL safely (stage/swap; retry if locked), then re-prove the packaged load (recipe in `.plan/handoff/N1-core-3.json`).
After task 7, if budget remains, start on PERF10K's native-held positions only if PERF10K has not started (check the board); otherwise stop.
Done when: tasks 1-7 are green, the full suite is green, and nat.* facts are posted. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `NAT`.
