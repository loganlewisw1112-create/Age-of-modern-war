# E2-art: detail pass on vehicles + buildings, new G2 sprites
MAX_TOKENS 500000 | MAX_TOOL_CALLS 130 | model opus (visual judgement)

You own `tools/gen_art.gd`, `tools/art/**`, `assets/generated/**`, `presentation/art/**`, `tests/test_art.gd`.

**Owner feedback (2026-10-23):** "the animation and visual art is pretty close to what I want, just a little more detail for the vehicles and buildings would be nice." So keep the style, palette, proportions, pivots and silhouettes. Add detail; do not restyle.

1. **Vehicle detail pass** (ifv, mbt, plus the new logistics_truck, in all 8 facings, idle/move/fire, with wrecks):
   - Visible road wheels/track links with shading.
   - Hatches, a commander cupola, vision blocks, an antenna whip, stowage boxes/jerrycans on the hull sides.
   - Exhaust grille, tow hooks, a mantlet and a barrel bore evacuator (MBT), smoke-launcher clusters.
   - Weathering: mud on the lower hull, chipped edges.
   - Stronger ambient occlusion under turrets and between the hull and the tracks.
   - Team colour stays on the mask regions.
2. **Building detail pass** (hq, generator, depot, barracks, motor_pool, guard_tower and the new refinery, built plus 3 construction stages):
   - Window rows with frames and some lit windows, doors and roll-up gates.
   - Rooftop clutter (HVAC boxes, vents, pipes, antenna/dish on the HQ), sandbags and barriers at entrances.
   - Crates/fuel drums near the depot, a transformer with cables on the generator, lights on the guard tower.
   - Refinery: tanks, pipes, a stack with a faint plume.
   - Edge highlights and AO at wall bases.
   - Keep the footprint diamond and pivot identical.
3. **New sprites:**
   - `officer` (cap, radio pack, map case; 8 facings × idle/walk_a/walk_b/fire) and `logistics_truck` (8 facings, cargo bed with crates).
   - `refinery` (3x3).
   - `bridge_span` overlays: intact, damaged (broken planks, scorch) and ruined (collapsed girders sticking out of the water), positioned over the bridge cells. Expose `ArtCatalog.bridge_overlay(state:String, cell:Vector2i) -> Dictionary {texture, offset}` per cell.
   - Effects: `disabled_smoke` (6-frame loop), `pinned` marker (small, 2 frames), `cover` pip, `retreat` chevron.
   - Icons: officer, logistics_truck, refinery, repair, patrol, guard, formation_line/wedge/column, mission_secure/hold/attack/patrol, assign_officer.
4. Keep generation deterministic (the manifest md5 is stable across runs) and keep the ArtCatalog API backward compatible (D2 is integrating concurrently). Add the new functions only.

Verification: regenerate the contact sheet (`.plan/shots/E2-art/contact.png`) with a side-by-side "before vs after" crop of the MBT, IFV, HQ and barracks at 1x and 2x (render "before" from git HEAD's art before your edits, e.g. copy the old PNGs to `.plan/shots/E2-art/before/` first). View it with Read and iterate until the detail reads clearly at 1x without becoming noisy. Update `tests/test_art.gd` so every new def/effect/icon is covered. Done when `--only=test_art` and the full suite are green.
