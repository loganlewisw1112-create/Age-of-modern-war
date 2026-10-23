# C-art: generated pixel-art + ArtCatalog
MAX_TOKENS 500000 | MAX_TOOL_CALLS 130 | model opus (visual judgement)

You own `tools/gen_art.gd`, `assets/generated/**`, `presentation/art/art_catalog.gd`, `tests/test_art.gd`.
Implement the ArtCatalog API in CONTRACTS.md section 7 exactly, keeping every static function signature of the stub.

Direction (owner-approved for this slice, "readable pixel-art pass"): grounded, gritty, muted military palette;
realistic, proportional silhouettes; a post-collapse industrial river valley. Look at 2-3 of the concept mockups
first for palette and mood. Use the Read tool on the PNGs; they are large, so view at most 3:
`../RTS_Age_of_Modern_War_Claude_Handoff/reference/Game_Project_GDD_Architecture_Approved_Mockups/Approved_Mockups/03_Massive_Tactical_Battle.png`,
`02_Settlement_Construction.png`, `06_Mountain_Valley_Warfare.png`. They are concept references: match their mood and
readability, not their detail level.

Requirements:
- `tools/gen_art.gd` is a SceneTree script run headless (`"$G" --headless --path . -s tools/gen_art.gd`). It draws
  everything procedurally with Image pixel ops and its own deterministic seeded RNG. It saves PNGs plus
  `assets/generated/manifest.json` (frame sizes, pivots/offsets). Re-running it must reproduce byte-identical files.
- Terrain:
  - Iso tiles are 64x32 diamonds. The top vertex sits at the cell's world_to_screen point (see CONTRACTS section 7).
  - 3+ variants each for grass and dirt, plus road, bridge (planks/girders over water), ford (shallow, lighter water with stones), water (2-4 animated frames), forest floor and ridge rock.
  - Decor: 3+ tree sprites (conifer/deciduous mix, darker, with shadows) for forest cells, and rock outcrops for ridges. The choice per cell is deterministic.
- Units:
  - 8 facings from e.facing in WORLD radians. Remember the iso projection when mapping facing to screen direction.
  - Infantry, each ~14-18 px tall with a 2-frame walk and a firing frame: engineer (hard hat, tool), rifleman, at_gunner (launcher tube), recon (lighter kit).
  - Vehicles: ifv (wheeled 8x8, small turret) ~44x30, mbt (tracked, long barrel) ~52x34.
  - Team colour via a mask: tint an armband/helmet band and a vehicle hull stripe/panels at load time from a greyscale mask layer. The team must read clearly at 1x zoom.
  - Add drop shadows.
- Buildings, sized to their footprint (size 3 means a 192x96 base diamond plus height): hq, generator, depot, barracks, motor_pool,
  guard_tower. Each needs an under-construction look (scaffold/foundation, chosen by e.built and e.progress) and a team-colour
  flag or marking.
- Resources: a salvage pile (rusty scrap metal) and an ore deposit (rocky, with mineral glints). Wrecks: burnt-out
  vehicle hulks and building rubble.
- Effects: muzzle flash (2-3 frames), small and large explosions (5-6 frames), smoke puff.
- UI art: 32x32 icons for every production item and buildable building. A selection ring (iso ellipse). Fog tiles:
  "unexplored" near-black, "explored" translucent dark blue-grey.
- ArtCatalog loads PNGs at runtime via `Image.load_from_file(ProjectSettings.globalize_path("res://assets/generated/..."))`
  and turns them into ImageTextures. It caches everything and builds tinted team variants lazily per (def, colour). Missing files fall back
  to magenta and never crash.
- **Order of work:** within your first ~30 tool calls, land a complete, simple version of EVERY API function, with all
  assets generated (even if basic), so agent D (rendering, working concurrently) can integrate. Then iterate on quality.
- Verification: write a contact-sheet mode (`-- --contact`) that composes a sample scene (terrain patch,
  river + bridge, trees, both teams' units in several facings, vehicles, all buildings, effects) into
  `.plan/shots/C-art/contact.png` at 1x and 2x. View it with the Read tool and iterate until the silhouettes read clearly.
  tests/test_art.gd: every API returns non-null for every def in content, and generator determinism holds (hash of the manifest).
