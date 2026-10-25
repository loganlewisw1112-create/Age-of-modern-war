# G6-ELEV: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §7, §5.2 (elev.*). **Plan:** PLAN_G6 §2 A1.
**Board / bus id:** `ELEV`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_elevation.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ELEV: terrain height (sim side)
- **Role:** the per-cell height layer and every sim rule that uses it (D23, D24), the new move classes, and authored height for the built-in maps.
- **Owns:** see CONTRACTS_G6 §1 row ELEV (`sim/terrain.gd`, `sim/systems/elevation.gd`, `sim/map_io.gd`, `sim/map_gen.gd`, the built-in map scripts, `content/g6/rules_elevation.json`, their tests).
- **Inputs:** the PLAN_G6 D23/D24 numbers; `sim/terrain.gd` (codes 0-13, move-class table); `sim/map_gen.gd`, `sim/map_io.gd`; `sim/maps/*.gd` + `map_check.gd`.
- **Tasks (in order):**
  1. Implement `w.map.height` / `w.map.ramps` (PackedByteArray, default plain = 1) created by MapGen and every map script. Make `height_at`, `ramp_at` and `edge_ok` real. **A map with no height keeps `w.map.height` absent (absent = all plain)**, so every existing state hash stays equal until `elev.maps_ready`. Post `fact elev.api_ready` (partial) within your first hour.
  2. Add `Terrain.RAIL = 14` and the `rail` / `hover` move classes to the class table (§7 4a). FOUND-line the exact passability so PERF6 / NAVAL6 / MECH6a can rely on it.
  3. Implement `adv`, `los` (cells along the segment vs the higher endpoint level), `range_mult`, `defence_mult`, `sight_bonus`, `slope_mult` from `rules_elevation.json`. Air units and indirect fire ignore LOS (indirect keeps the range bonus). Re-post `elev.api_ready` (complete).
  4. Map file format: add height + ramps with a version bump. Old files load as plain with HILL→2 and CLIFF kept. Save/load round-trips height (the map dict is saved by SaveSystem; check it, CR ORCH if not).
  5. Author real height for River Crossing (map_gen), Industrial Heartland, Valley Conquest (real valleys and ridges, ramps between) and Coastal Front. Extend `map_check` to validate every spawn is reachable by foot and vehicle through ramps. Post `fact elev.maps_ready`; ORCH re-baselines the hash fixtures.
  6. `map_gen` gains height noise + ramp placement + validation for generated / editor maps (an API ED6's brushes can call: `MapGen.validate_height(w) -> Array` of issues).
- **Publishes:** `elev.api_ready`, `elev.maps_ready`; FOUND lines with the move-class table.
- **Done-when:**
  - test_elevation green (every skeleton test with real checks)
  - test_maps, test_map_io, test_coastal_front, test_terrain_classes green
  - full suite green at the end (hb.sh)
- **Never:** edit movement / combat / fog / native code (PERF6 wires your API there), rendering (ELEV-VIEW), or editor UI (ED6).
