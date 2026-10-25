# G6-ELEV-VIEW: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §7. **Plan:** PLAN_G6 §2 A1 (render).
**Board / bus id:** `ELEV-VIEW`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_elev_view.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ELEV-VIEW: drawing the terrain height
- **Role:** terrain-height rendering, cliff/ramp/slope and rail terrain art in every style, fog on raised tiles, and picking on raised tiles.
- **Owns:** see CONTRACTS_G6 §1 row ELEV-VIEW (`terrain_layer`, `fog_layer`, `camera_rig`, `view_util`, `tools/art/g6_terrain*.gd`, `assets/art/g6_terrain/**`, test_elev_view).
- **Inputs:** ELEV's height data (`w.map.height` / `ramps`) and `elev.api_ready`; the G4 terrain art modules (`tools/art/g4_terrain*.gd`) as the model.
- **Tasks (in order):**
  1. Terrain art: cliff faces, ramps and slopes per terrain style + RAIL tiles (`tools/art/g6_terrain*.gd` → `assets/art/g6_terrain/`).
  2. `terrain_layer`: tiles drawn with a height offset (16 px per level, tunable), correct draw order across levels, cliff faces on level edges.
  3. `fog_layer` on raised tiles; `view_util` / `camera_rig` picking that accounts for height. Post `fact view.elev_ready` and FOUND-line the offset rule for VIEW6.
  4. Make test_elev_view green; windowed probe screenshots under `.plan/shots/ELEV-VIEW/`.
- **Publishes:** `view.elev_ready`.
- **Done-when:**
  - test_elev_view green
  - probe screenshots of every terrain style with height
  - full suite green
- **Never:** edit entity rendering (VIEW6).
