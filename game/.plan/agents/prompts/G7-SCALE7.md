# G7-SCALE7: 512×512+ map support (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: scale7. Spec: G7_REFERENCE master scope sections 0, 10 (map size LOCKED by the
owner: **Last Protocol map minimum 512×512 tiles**), 12 (risks). Risk #1 of the whole slice: prove the engine holds up.

Today: `sim/map_io.gd` has `MAX_DIM := 512`; maps run 96–256; fog_layer and minimap were sized for up to 256. The
Last Protocol map (LPMAP7, later) will be at least 512 and may be larger.

## Deliver
1. **Size cap:** raise the map size cap so 512 and up to 768 load, save and validate (map_io, map_gen, terrain, editor
   limits if they assert). Save/load round-trip at 512 and 768.
2. **Blank test map** `sim/maps/lp_test512.gd`: a 512×512 generated test map (two sides far apart, mixed terrain,
   elevation, a river, roads, some towns) used by bench/tests and by later agents until LPMAP7's real map exists.
   Register it with ORCH by change_request if maps.json must list it.
3. **Sim at 512+:** pathing (movement.gd outside formation_slots; native path if used), spatial index (sim_index),
   fog/sight grid (fog.gd sim) all correct and fast at 512 and 768. Measure memory and ms/tick with 2k units spread
   over the map and 2k units in one fight. No per-tick cost that scales with map area when nothing happens there.
4. **View at 512+:** terrain_layer, minimap and camera limits/zoom work on 512 and 768 (no seams, no huge texture
   uploads per frame, minimap readable). Ask LOOK7 by change_request for anything needed in fog_layer.
5. **Bench:** `tools/bench.gd` gets a `--map=lp_test512` option (and 768). Report: 2k on screen p10 fps, 10k zoomed
   out p10 fps, 2k sim ms/tick at 512 vs the same load on a 256 map, CPU load and Godot process count.
6. **Hash safety:** existing maps hash identical (test_hot_state 17/17 GOLD untouched). New hashes on lp_test512 stable
   over two runs.

## Tests (tests/test_scale7.gd)
512 and 768 load/save/validate round-trip; path from corner to corner on lp_test512 found within a time budget; fog
grid dimensions and a sight query at the far corner; sim_index queries correct at the far corner; same seed twice =
same hash on lp_test512 (200 ticks, 500 units); existing map hashes unchanged.
Playtest flow tools/pt7_scale7.gd: load lp_test512, pan to all four corners and the centre, zoom fully out and in,
shots of each, minimap shot.

## Stop-if
If 2k-unit fps or sim cost on lp_test512 can't come within the G7 gates after reasonable work, post `BLOCK` with the
numbers and the cause and stop: ORCH asks the owner. Do not shrink the map yourself.
