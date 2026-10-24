# ED1: map editor framework + land and water tools
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §2.2, **§9** (yours), §5 (file shape). Plan: PLAN_G4 §3 (layout, patterns borrowed from the AoE2 / WC3 / SC2 / Stronghold / OpenRA editors).
**Owns:** `presentation/editor/**` (core, terrain, water, nature, resources, symmetry, undo, minimap; ED2 adds `presentation/editor/ed2_*.gd`, not yours), `presentation/main.gd` (scene switching to/from the editor only), `presentation/menu/main_menu.gd` (the "Map Editor" button only), `tests/test_editor_core.gd`.
**Depends on:**
- MAPIO's `MapIO.save/read/validate` (wait for `fact mapio.api_ready`; meanwhile build against §5);
- NAT's terrain semantics (codes are fixed already);
- ART-T's terrain art (the renderer falls back to colours until it lands).
**ED2 builds on your framework.** Post `fact ed1.framework_ready` with the extension API (how a new tab registers, how tools get the map dict, the undo push API) as early as you can.

Tasks:
1. **Editor scene:**
   - a non-stepping SimWorld built from an editable `{map, scenario}` dict;
   - reuse terrain_layer/entity_layer for drawing; camera pan/zoom like the game;
   - top bar: New / Open / Save / Save As / Undo / Redo / Validate / Test Play (ED2 implements Test Play, you leave the hook) / Exit;
   - a left tab bar with a registration API;
   - right side: minimap + properties panel + layer toggles (grid, passability overlay per movement class, decor, units).
2. **Map tab:** New map (size 96/128/160/192/256, base biome, name, author, description); "Generate base" from the built-in generators by seed (via MapGen).
3. **Terrain tab:**
   - paint any code;
   - brush shape circle/square, size 1-15, strength (fill / scatter %);
   - line and rectangle tools;
   - biome paint (cosmetic layer).
4. **Water tab:**
   - **River tool**: click points, width 1-9, shallow-edge toggle, auto fords every N cells option;
   - **Lake/Ocean fill**: flood a region to SHALLOW/DEEP with an auto BEACH ring and depth falloff;
   - **Bridge tool**: a validated span across water, adds to `map.bridges`.
5. **Nature & objects tab:**
   - trees, plants, bushes, rocks, boulders, ruins, wrecks, plus all POI decor (rail, factory blocks, dam, hangar, houses...);
   - scatter brush with density and random variation (seeded), single placement, eraser;
   - impassable decor writes BUILDING/FOREST cells as the decor def requires.
6. **Resources tab:** salvage/ore piles with an amount slider; scatter or single.
7. **Symmetry:** off / mirror X / mirror Y / mirror diagonal / rotate 180 / 4-way. It applies to every tool via a cell transform.
8. **Undo/redo:** a 200-step command stack; one stroke is one step.
9. **Brushes** are pure functions `(map, cells, params) -> changed_cells` in `presentation/editor/brushes.gd`.
   - Unit tests in `tests/test_editor_core.gd`: each brush, symmetry transforms, undo/redo exactness, river/lake shapes, bridge validation.
   - Fast on 256×256: only changed chunks re-bake. The editor holds 60 fps on a 256 map.
10. Main menu "Map Editor" button; Exit returns to the menu.
Done when: tasks 1-10 are done, test_editor_core is green, and screenshots of each tab in use are in `.plan/shots/ED1/`. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `ED1`.
