# ART-U: 8 new human units + editor tool icons
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §1, **§8** (IDs). Style: Human A modern military (`tools/art/vehicles.gd`, `units.gd`, `g3b_human_a.gd`); Human B industrial (`faction_b_*.gd`, `g3b_human_b.gd`). The owner likes the current detail level.
**Owns:** `tools/art/g4_units*.gd` (`g4_units.gd` is a registered stub), `tools/art/g4_editor*.gd` (called from g4_units.gd's build), entries in `assets/generated/**`, `tests/test_art_g4_units.gd`.
Tasks:
1. Sprites for `a_apc`, `a_sniper` (ghillie/prone look), `a_mortar` (packed + deployed frames), `a_combat_engineer`, `b_flamer` (flame jet fire frame), `b_halftrack`, `b_scrap_mech` (legged walk), `b_rocket_truck` (salvo frame).
   - Facings, anims, team masks, wrecks for vehicles, build/train icons, LOD class mapping.
2. Effect sprites: fire on forest (3-frame loop), burnt ground, mine (own-side view), charge (blinking), flame jet.
3. Editor tool icons (32×32): brush, line, rect, fill, river, lake, bridge, tree, rock, resource, eraser, symmetry modes, undo/redo, validate, test play, player start, region, trigger.
4. Generator lock protocol; existing files byte-identical.
5. Tests: all defs have art, sizes sane, deterministic.
6. Contact sheets in `.plan/shots/ART-U/`, self-checked.
Done when: tasks 1-6 are done. MAX_TOKENS 500000, MAX_TOOL_CALLS 130, board id `ART-U`.
