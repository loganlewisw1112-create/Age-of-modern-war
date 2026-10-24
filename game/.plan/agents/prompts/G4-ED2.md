# ED2: editor scenario tools + custom maps in skirmish
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §5 (file shape, triggers, victory presets), **§9**. Plan: PLAN_G4 §3.1 tabs 6-8, Validate, Test Play, §3.2.
**Owns:** `presentation/editor/ed2_*.gd`, `presentation/menu/skirmish_setup.gd`, `tools/editor_playtest.gd`, `tests/test_editor_scenario.gd`.
**Depends on:** ED1's framework (`fact ed1.framework_ready` gives the tab registration and undo API; build on it, never edit ED1's files; send CRs) and MAPIO's API (`fact mapio.api_ready`).

Tasks:
1. **Units & buildings tab:**
   - choose a player (colour chip) and a faction filter; the palette fills automatically from Content for that faction, including new G4 units, walls and later air/naval defs;
   - place, rotate facing (Q/E), built/foundation toggle, drag-box formation placement;
   - load troops into a carrier (a cargo list in the entity entry);
   - set `tag` in the properties panel; delete/move.
2. **Players tab:** 2-4 slots (human/AI/closed, faction, team, colour, start stage, credits, start stock, AI difficulty), a start-position marker per player, and a "start packages on/off" toggle.
3. **Victory & triggers tab:**
   - victory presets (§5) with AND/OR;
   - a trigger list editor (when / then / once);
   - regions drawn as rectangles and named.
4. **Validate** (top bar, uses `MapIO.validate`): an issue list with jump-to.
5. **Test Play:** save to a temp file, start a match with `cfg.map_file` plus sides built from the scenario players, and return to the editor when the match ends or on Esc → "Back to editor".
6. **Skirmish setup:**
   - a map list with "Built-in" and "Custom" groups (`user://maps/*.rtsmap`), thumbnail (minimap render), size and players;
   - custom scenario rules vs "skirmish rules only";
   - sides are prefilled from the file's players.
7. `tools/editor_playtest.gd` (synthetic input, like `tools/ui_playtest.gd`), entirely by clicks:
   - open the editor; new 128 map; paint terrain; draw a river; fill a lake; scatter trees; symmetry mirror;
   - place an HQ + units for 2 players; set the players; validate (0 issues); save;
   - back to the menu → skirmish → pick the custom map → start → the match runs 30 s.
   - Report `PLAYTEST RESULT pass=N fail=0`.
8. Tests (`tests/test_editor_scenario.gd`): palette from content, player/start mapping to cfg, trigger editor → JSON exactness, test-play cfg build.

Done when: tasks 1-8 are done and green. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `ED2`.
