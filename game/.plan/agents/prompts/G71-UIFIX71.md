# G71-UIFIX71: the 1 px BottomPanel / GroupBar overlap (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)

You are UIFIX71 (generation 1). Read `G71-FIX71_COMMON.md` first and follow it.

## Your 2 red files (wave-1 regressions: HEAD fda25f9 passes both)
- `test_ui_fit` 2/4 (~18 min per run): every case reports `OVERLAP Root/BottomPanel with=Root/GroupBar/Button"[.] Idle 5"
  area=61x1` (46x1 at 75%), at every resolution and UI scale, incl. the drone corner feed cases.
- `test_ui6a` 7/1 (~100 s per run): same overlap, 42 issues at 100%, 46 at 75 / 150%.

## What ORCH already knows
- It is NOT the minimap size: the same failure with `_minimap.SIZE` 205 and 192 (hud.gd is back to 206, byte-identical
  to the frozen copy). FLOW71-2 once saw issues=0 only with minimap DEFAULT_SIZE 192, so something else changed too.
- Wave-1 candidates: `presentation/ui7/cardbar8.gd`, `presentation/ui5/panels/g5_unit_cmds.gd`, `presentation/ui5/panels/
  hotkeys.gd`, `presentation/ui71/roster.gd`, `presentation/ui71/flow_bar.gd`, the minimap frame in `presentation/hud/
  minimap.gd`, `presentation/hud/hud.gd`. Diff each against HEAD (`git diff fda25f9 -- <path>` is read-only and allowed).
- Old notes / logs: `.plan/orch71/test_ui_fit.log`, `.plan/orch71/test_ui6b.log`, `.plan/orch71/test_ui_panels.log`.

## What to do
Find what really sets BottomPanel's height / top edge and the GroupBar's bottom edge, and which wave-1 change moved
one of them by 1 px. Bisect by swapping single wave-1 files back to HEAD in a scratch copy if needed (never in the live
tree for longer than one run; restore byte-exact). Fix it at the cause **without moving the cargo strip** and without
shrinking any control's content. Use `test_ui6a` to iterate (fast), then run `test_ui_fit` once at the end.

## Check
`test_ui6a` and `test_ui_fit` green in the live tree, plus `test_control71`, `test_flow71`, `test_ui_panels` (and any
other test file that covers what you changed). Post `fact shots.best` with a before / after crop of the bottom HUD at
1280x720.
