# G7-CIWS7-5: finish CIWS7-4 + make the drawn barrel match the stream (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action, also
before/after every long run; no git, no D:). Spec: docs/G7_REFERENCE.md 13.9c-32a (owner verbatim: "CIWS turrets need to
have that signatture phlanx BBRRRRTTTTTTTTTT shooting sound + shooting in a strait line wherever the barrel is point w
realistic bullet spread the further they shoot"), 13.9c-32, 13.9c-30, 13.9c-28. Handoff: .plan/handoff/CIWS7-4.json
(read all of it: sound, spread rule, stream are written; its "remaining" list is yours).
## Jobs
A. CIWS7-4's remaining steps, in its order: extend + run test_ciws7 (hit share falls with range at the 3 ranges in the
   handoff, ShotFired brg == the mount bearing, same inputs -> same hash twice); test_muzzle7; pt7_ciws7 close + far
   bursts with frame-exact shots and straight-line / wider-far checks (windowed, timeout 900, 0 fail); `--import` so the
   6 new wavs get .import files (the editor segfaults on exit AFTER "DONE reimport": judge by 0 ERROR lines, not exit).
B. NEW (owner's "wherever the barrel is pointed"): the mount art has only 8 yaw frames x 3 elevations
   (tools/art/g7_ciws7.gd build(): `for k in 8: for el in 3`), so the straight stream can leave up to 22.5 deg off the
   drawn barrels. Raise the resolution so the drawn barrels and the stream agree: at least 16 yaws (<= 11.25 deg), 32 if
   the art byte budget (entry g7.bytes vs C.BUDGET.turret) allows; at least 5 elevation steps, chosen from the real
   elevation to the target. Update everything keyed on 8/3: the state picker presentation/art/g5_art.gd (cw<k> from tb,
   el), Traverse7.snap_bearing use for this def if any, tools/art/muzzle7.gd _state_dir cw case + the cw5_0 derived
   point logic (now per hidden-barrel state, derived from neighbours), muzzle7_gen regen, the rot_/fire aliases at the
   end of build(). Then the stream (fx_layer CIWS branch) leaves the drawn tip of the frame actually shown. Report the
   max angle between drawn barrels and stream after the change (measure it, e.g. from muzzle tips vs bearing).
   Keep the art at the approved look (same design, more frames); test_art7f / any art budget test green.
C. Shots for the owner (fact shots.best, read them first, plain caption): a close burst and a far burst showing the
   straight stream from the barrels and the wider spread far. Say the sound cannot be shown in a still.
Files: tools/art/g7_ciws7.gd (+ its generated assets), presentation/art/g5_art.gd (CIWS branch only), tools/art/muzzle7.gd
(+ assets/art/muzzle7.json), presentation/view/fx_layer.gd (CIWS branch), sim/systems/ciws7.gd (only if needed),
tests/test_ciws7.gd, tools/pt7_ciws7.gd. Post a claim fact first; BAL7, PERF7G, DFEED7 are live.
