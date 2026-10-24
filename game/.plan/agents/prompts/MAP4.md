# MAP4: Industrial Heartland + Valley Conquest (CONTRACTS_G3b §4)
Read G3B_COMMON.md first. Design source: `RTS_Age_of_Modern_War_Claude_Handoff/docs/04_FIRST_PLAYABLE.md` and `11_WORLD_MAPS_AND_FUTURE_SYSTEMS.md` (map table: industrial_heartland_m, valley_conquest_l). Look at `docs/vision/2026-10-23/02_*.webp` (river crossings, dam, ridges) for mood; view at most 2 images.

Order:
1. Read `sim/map_gen.gd`, its terrain codes (`sim/terrain.gd`), and how world/fog/territory/movement/bridges/minimap use `map` (w, h, terrain, spawns, resources, bridge, fords).
2. `content/maps.json` + a generator module per map (`sim/maps/*.gd`) dispatched by id from `MapGen.generate(seed, map_id)`. River Crossing output must stay byte-identical (existing tests and hashes depend on it).
3. **Industrial Heartland (~160×160):** river basin with 2 bridges + fords, factory blocks, rail siding, refinery site (rich ore), ruined plant (salvage), towns, road loops, 6 spawns, spawn_sets for 2/3/4 sides that are fair (mirror or rotate).
4. **Valley Conquest (~256×256):** river branches, dam crossing, tunnel portal scenery, airfield flat, foothill ridges, industrial pockets, 3+ crossings, 8 spawns, spawn_sets 2/3/4, and **lots of open passable ground** (it must hold 10,000 units).
5. Multi-bridge support in `bridges.gd` + `_spawn_bridge()` (world.gd: only that function and the spawn-assignment line are yours). Hold-the-bridge uses bridge 0 or the map's `hold_bridge`. Territory works at the new sizes.
6. `tests/test_maps.gd`: all 3 maps validate for seeds 1-20 (reachability for foot and vehicle between all spawns, resources reachable, determinism: same seed gives the same terrain bytes); a 3-side and a 4-side match starts on each map; a short AI-vs-AI headless run (2,000 ticks) on each big map has no script errors.
7. Screenshots of each map (autoshot zoomed out; `--autostart` with the map once UI4/R4 add the flags, or a minimap-style PNG dump of the terrain array) in `.plan/shots/MAP4/`.
New decor art (rail, factory, dam...) is ART4's. Post CHANGE_REQUESTS with the terrain/decor ids you want; use existing codes and decor meanwhile. MAX_TOKENS 600000, MAX_TOOL_CALLS 150, board id `MAP4`.
