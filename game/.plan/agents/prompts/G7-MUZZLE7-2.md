# G7-MUZZLE7-2: APC rear gun animation + finish barrel-tip muzzle flashes (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action; post
`fact shots.best` as soon as something is visible; no git, no D:). Read the predecessor handoff .plan/handoff/MUZZLE7.json
and its board posts (audit seq 5435). Spec: docs/G7_REFERENCE.md **13.9c-28a** (owner: "donte forget the mounted gun on the
back of the apc -- thats needs to be animated correctly when shooting too"), 13.9c-28, 13.9c-13, 13.9c-18.
ORCH has applied CR 5592 (entity_layer.drawn7). Note: at the time of writing test_muzzle7 showed 5/1 with
"every shot used a measured barrel tip {tip 0 ...}" while another agent's cn_facility.gd edit broke compilation; recheck
once the tree compiles.
## Build (in this order)
1. 13.9c-28a: the CN strike / tactical APCs' rear roof gun (all 4 defs): its own traverse to the target independent of
   the hull (a separate rear-gun sprite layer with 8 aim rows, or the existing anim61 turret mechanism used for mbt / ifv:
   see presentation/art/muzzle_g61.gd, VehAnim61 and entity_layer's turret_src path), recoil frames, flash / tracer /
   casings from its barrel tip per aim row, front and rear guns flashing at their own barrels, idle gun back to travel
   position. Art: the APC generator (find it via the art manifest of g7_cn_strike_apc; regenerate only those sheets) or
   a new small rear-gun sheet. Test it (tests/test_muzzle7.gd) and shoot it in game at zoom 2.5, frame-exact on a flash.
2. Finish MUZZLE7's not-done list: playtest zoom re-applied after center_camera_on (real zoom-2.5 shots), air group in
   range / attack order, Sentinels on a wall (wallwalk7 facility setup), crouch / prone shots, laser beams from the barrel
   tip (G6Fx.from_event path), hill lift on building anchors, re-run muzzle7_gen.gd after any art regeneration.
3. test_muzzle7, test_vfx61, test_view5, test_look7 green (never weaken); post fact shots.best (Read every PNG first).
Files you own: MUZZLE7's files (tools/art/muzzle7*.gd, assets/art/muzzle7.json, presentation/art/muzzle_g61.gd,
fx_layer.gd muzzle parts, fx61_core.gd muzzle parts, tests/test_muzzle7.gd, tools/pt7_muzzle7.gd) + the CN APC art
generator section for the rear gun. entity_layer.gd lines: change_request to ORCH (exact lines).
