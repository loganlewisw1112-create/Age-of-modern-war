# G6 art kit (proposal art for the 93 G6 assets)

This kit holds the source behind the **G6 Arsenal Concepts** page (https://claude.ai/artifact/CqtGqskcCzkoCjPrhMWkgw, made 2026-10-24).
Owner note: every asset on that page goes into the game in G6 except the 4th faction (Irregulars, `x_*` ids), which is deferred to G7 or G8. That leaves 89 assets. See PROGRESS.md, "G6 (slice after G5): owner notes", items 3 and 5.

## What is here
- `gd/g6_<module>.gd`: drawers for all 93 assets. They are written against the game's own art libraries (`res://tools/art/*`: pix, vdetail, g5_bld_lib, the G5 figure kit, faction libs, G5 aircraft mesh/raster). They produce game-schema sheets: 8 facings x frames, team masks and wrecks; buildings get rotations 0 and 1 only.
  - turrets (15), forts (13), seaair (14), vehicles (15), infantry (16), dronebld (16), horizon (4)
- `gd/g6_lib.gd` (helpers, team tint as in `art_catalog.gd`, terrain plates), `gd/g6_gen.gd` (runner), `gd/g6_now.gd` (renders the repo's G5 art), `gd/g6_scenes.gd` + `scenes.json` (battle scenes).
- `items.json`: the 93 proposals (art_id, faction, category, stage, gap, description). `assign/`: the per-module lists. `notes/`: builder notes per module. `BRIEF.md`: the builder brief. Its scratch paths are historical; the kit now runs from here.
- `page/`: the page builder (`build2.py` expects the kit layout at the scratch path; adjust `HERE` if you rebuild).

## Run
```
bash game/docs/g6_art_kit/run.sh g6_vehicles          # one module (~5-60 s); output in game/docs/g6_art_kit/art/ (git-ignored)
```
Running all 7 modules takes about 5 minutes, so run them in two or three calls (run.sh has a 300 s timeout).

## Notes
- `.gdignore` keeps Godot from importing these scripts into the project. They run only through `godot -s`.
- **This is proposal art, not integration.** Nothing here is wired into content, sim, AI or `assets/`. G6 has to move each drawer into `tools/art/` (an `assets/art/g6_*` module with its own gen script, like `g5_units_gen.gd`), add the content defs, sim mechanics, AI use and tests, and render all 4 rotations for buildings.
- Known asks for G6 integration: `b_conscripts` is a 10-man squad on a 64x44 frame (the renderer must accept per-def squad fw/fh). The ship and aircraft frames are larger than land units (carrier 140x93, lance cruiser 144x98). Aircraft use the G5 aircraft pipeline (`g5_air_mesh` / `g5_air_raster`).
