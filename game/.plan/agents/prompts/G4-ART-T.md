# ART-T: terrain art + terrain rendering for the new codes
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §2.2. Art style: see `tools/art/terrain.gd` (existing), the G3b art modules, and `docs/vision/README.md` (view at most 2 images). The owner loves the current pixel-art look; match it.
**Owns:** `tools/art/g4_terrain*.gd` (`g4_terrain.gd` is a registered stub; fill it in), `presentation/view/terrain_layer.gd`, terrain entries in `assets/generated/**`, `tests/test_art_g4_terrain.gd`.
**Downstream:** ED1 (the editor shows your terrain), THREAD (renderer). Post `fact art_t.ready` when done.

Tasks:
1. Tiles for BUILDING (concrete/foundation ground under decor), SHALLOW (light water, ripples), DEEP (dark water, animated shimmer frames), BEACH (sand), CLIFF (rock face reading as a wall), HILL (raised grass with shading).
   - Each in the 4 biome looks where it makes sense (temperate/desert/snow/wasteland), and biome variants of grass/dirt/forest.
2. **Automatic transitions:** shoreline (land↔SHALLOW↔DEEP), beach edges, cliff edges, by a 4- or 8-neighbour bitmask, in the same isometric tile size as the existing terrain.
3. `terrain_layer.gd`:
   - render the new codes plus biome plus transitions in the existing pre-baked chunk system (keep the lazy chunking for big maps);
   - support `rebake_cells(cells)` for the editor (fast partial rebake) and for fire/bridge changes;
   - keep River Crossing pixel-identical (compare a screenshot before and after).
4. Generator lock protocol (`art.gen_lock`). Regenerated assets must leave existing files byte-identical.
5. `tests/test_art_g4_terrain.gd`: every code and biome has a tile; transition sets complete; sizes sane; deterministic regen.
6. Contact sheet `.plan/shots/ART-T/terrain.png`, viewed with Read to self-check quality.
Done when: tasks 1-6 are done and the art tests are green. MAX_TOKENS 600000, MAX_TOOL_CALLS 150, board id `ART-T`.
