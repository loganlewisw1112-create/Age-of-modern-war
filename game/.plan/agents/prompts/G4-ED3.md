# ED3: finish the editor (successor to ED1 + ED2)
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §5, §9. Plan: PLAN_G4 §3.
**Owns (everything editor and menu):** `presentation/editor/**` (ED1 + ED2 files), `presentation/main.gd`, `presentation/menu/main_menu.gd`, `presentation/menu/pause_menu.gd`, `presentation/menu/skirmish_setup.gd`, `tools/editor_playtest.gd`, `tests/test_editor_core.gd`, `tests/test_editor_scenario.gd`.
**Read:** `.plan/handoff/ED1-1.json` and `.plan/handoff/ED2-1.json` (both: done / remaining / gotchas / API). ED1's work is committed; ED2's work is in the tree, and ORCH commits it once verified.

Tasks (in this order):
1. **Units not drawn in the editor (CR from ED2):** THREAD's entity_layer now reads `mv.snap`, `mv.world_readable()` and `mv._world`. In `editor_view.gd` add `var snap`, `var _world` (= world), `func world_readable() -> bool: return true` and `func sim_busy() -> bool: return false`, and end `_sync_world()` with `RenderSnap.build(world); snap = RenderSnap.latest(world)` (check RenderSnap's real API in `sim/render_snap.gd`). The editor must log no SCRIPT ERROR per frame.
2. `editor_doc.gd`: the default scenario victory is "hq_elimination" (not "hq").
3. `main_menu.gd` build_config: after `victory.apply(cfg)`, call `if setup.has_method("finalize"): setup.finalize(cfg)`.
4. `pause_menu.gd`: during an editor test-play (main's editor-test flag), show "Back to editor" instead of "Main menu", returning to the editor.
5. **ED2 remaining 1-3:**
   - fix the playtest click offsets: viewport→window transform via `root.get_final_transform()`; verify by printing `view.mouse_cell()`;
   - fix the save-overwrite confirm (pre-delete `user://maps/ed_2_playtest.rtsmap`);
   - re-run `tools/editor_playtest.gd` until `PLAYTEST RESULT pass=N fail=0`.
6. **ED1 remaining 3-5:**
   - run `--editor-demo` screenshots and view them; fix any layout issues;
   - measure EDITOR_FPS_256 (target 60) and fix if low;
   - verify the MapIO save/read round trip from the editor (MAPIO is committed).
7. View the ED2 tabs' screenshots and fix layout.
8. **Tests:** test_editor_core + test_editor_scenario green; the full suite once at the end (hb.sh). Quote any failures in other agents' files.

Done when: tasks 1-8 are done, the editor playtest is all-pass, and screenshots are in `.plan/shots/ED3/`. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `ED3`.
