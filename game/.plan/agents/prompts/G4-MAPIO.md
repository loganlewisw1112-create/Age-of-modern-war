# MAPIO: map files, file-map loading, triggers, new victory presets, save at scale
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §2.3 (hooks), **§5** (yours).
**Owns:** `sim/map_io.gd`, `sim/systems/triggers.gd`, `sim/systems/victory.gd`, `sim/map_gen.gd` (export function only; never change generator output), `tests/test_map_io.gd`, `tests/test_triggers.gd`, `tests/test_save_scale.gd`.
**Others wait on you:** ED1/ED2 (file API + validate), AI5 (file maps). Post `fact mapio.api_ready` early with exact signatures, even before everything is implemented.

Tasks:
1. `MapIO.save/read/validate`, plus `load_map(w,cfg)` and `place_entities(w,cfg)` (the hooks already called by world.gd), all in the §5 JSON format.
   - terrain/biome base64; decor; resources; bridges; players and starts → `map.spawns` + `spawn_sets`; `start_packages` flag; placed entities with tags; regions; triggers.
   - Deterministic: file order, ascending.
2. `MapGen.to_file(seed, id, path)`: export any built-in map. Round trip: the exported file loads to the same terrain/resources/spawns. Saving and loading a match on a file map gives an equal hash.
3. Triggers runtime: every when/then type in §5; state in `w.sys_state.triggers` (saved); `once`.
4. Victory presets in victory.gd: `survive`, `destroy_target`, `reach_stage`, `hold_point`, combinable with AND/OR. `validate_rules` knows them. Keep every test_victory test green.
5. `MapIO.validate`:
   - start positions reachable pairwise (foot + vehicle);
   - resources reachable;
   - illegal placements;
   - player count matches starts;
   - each issue reported as `{code, msg, cell}`.
6. **Save at scale** (`tests/test_save_scale.gd`): a 10,000-unit valley world mid-fight saves and loads with an equal hash. Report time and size.
7. Seed-repeat check: every built-in map, 2 seeds, same hash twice.
Done when: tasks 1-7 are green and the full suite is green. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `MAPIO`.
