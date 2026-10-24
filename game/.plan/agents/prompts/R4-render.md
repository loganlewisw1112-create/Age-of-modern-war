# R4-render: batched rendering, LOD, smooth frames (CONTRACTS_G3b §6)
Read G3B_COMMON.md first.

Measured baseline: with the sim paused (`--spawn-test=1000 --sim-paused --no-vsync --fps-log`), 1,000 units render at 33-43 fps with view at about 450 ms/s (about 12 ms of CPU per frame). Each entity is a Sprite2D updated from GDScript every frame (`presentation/view/entity_layer.gd`). Targets: **60+ fps with 2,000 fighting on screen; 30+ fps zoomed out with 10,000 on a 256×256 map.**

Order:
1. Profile entity_layer, fx_layer, overlay_layer and fog_layer at 1,000/2,000 with the sim paused. Find where the per-frame cost goes.
2. Replace per-entity Sprite2D with batched drawing:
   - MultiMesh per texture/atlas, or one CanvasItem per layer drawing visible entities with batched `draw_texture_rect_region`;
   - viewport culling;
   - update only entities that changed or moved.
   - Keep everything that exists: team colour masks, facings, anim frames, selection rings, health bars on hover/selection, wrecks, ghosts of remembered buildings, damage states, G2 overlays.
3. Zoom LOD: far zoom draws team-coloured icons/dots (ART4 will deliver icons; use a placeholder rect/dot until then) and drops small FX.
4. Interpolate positions between 20 Hz sim ticks.
5. Terrain: pre-bake chunks so a 256×256 map costs nothing per frame. MAP4 is building `industrial_heartland_m` 160×160 and `valley_conquest_l` 256×256; until those land, test with a stretched River Crossing or a debug flag.
6. After N1's native movement lands (watch the board), measure with the sim running. If sim ticks still cause hitches, put `world.step()` on a worker thread with a snapshot handoff. Note that the HUD reads world state, so do it safely: snapshot or step between frames.
7. Add `--map=<id>` and `--zoom=<f>` debug flags. Screenshot evidence in `.plan/shots/R4-render/`; fps tables in your report.

Visual parity matters: the owner loves the current look. Compare before/after screenshots at normal zoom. MAX_TOKENS 600000, MAX_TOOL_CALLS 150, board id `R4-render`.
