# G71-CONTROL71: clicking and camera (A4)

You are CONTROL71. Read `G71_COMMON.md` first and follow it. Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140.
Scope: `docs/G71_SCOPE.md` part A4 in full. Presentation-only work: the view-on/off hash must stay identical.

## Build
1. **Bigger hitboxes** for units, vehicles, buildings and wall-walk troops: pick by a generous screen-space radius that
   scales with zoom (small units stay clickable zoomed out), nearest-to-cursor wins, wall-walk troops pickable over the
   wall sprite. Measure before / after: a scripted cursor sweep over a crowded LP wall section, % of clicks that hit
   the intended entity.
2. **Hover outline** (presentation/view/hover_outline.gd): crisp outline on whatever the cursor would select, team
   colour; must not cost fps at 2k on screen.
3. **Unit roster panel** (presentation/ui71/roster.gd): selected units grouped by type with counts, health, click to
   narrow selection, double-click to centre. Passes tools/ui_fit_test.gd.
4. **AoE-style edge scroll** (cursor at the screen edge pans; on by default; a toggle in settings), **faster pan**
   (keys + edge + drag), **zoom-to-cursor** (the point under the cursor stays put while zooming).
5. **Bigger minimap** with incoming waves shown (read existing threat / wave data from the render snapshot; request
   new snapshot fields from PERFDRAW71 by change_request), **click and click-drag** to move the camera.
- Difficulty unchanged.

## Files
camera_rig.gd, minimap.gd, view_util.gd (picking), the selection / hover / picking functions in match_view.gd (claim
them by name on the board before editing: `fact control71.claims {"match_view.gd":["_func_a","_func_b"]}`).
Tests `tests/test_control71.gd` (pick accuracy oracle, zoom-to-cursor oracle, edge-scroll oracle), flow
`tools/pt71_control71.gd` (windowed; screenshots of hover outline, roster, minimap; post `fact shots.best`).
Hotkeys / settings toggles: change_request to ORCH.
