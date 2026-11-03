# G7-CIWS7-6: CIWS realistic depression limit (~-25 deg) (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls, never 10 min silent: heartbeat .plan/hb.sh around
long runs; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-32b** (owner choice "Realistic: ~25 deg limit"), with
13.9c-32 / -32a. Handoff: .plan/handoff/CIWS7-5.json (32 yaws x 6 bands [-60,-47,-34,-21,+8,+32], el_band in
sim/systems/ciws7.gd, defs_g7_ciws.json "elev" block, art tools/art/g7_ciws7.gd, muzzle7, fx_layer CIWS branch).
## Build
1. Sim: the mount cannot depress below DEPRESS_MIN (PROVISIONAL -25 deg, in defs). A ground target whose line from the
   muzzle needs more depression than that is NOT engageable (can_target / ground pick skip it; deterministic, pure);
   the blind ring is therefore ~8-9 tiles round the command centre (report the measured radius per mount). Air / intercept
   engagement unchanged. Report how the ground engagement count changes in pt7_ciws7's crawler step (move the flow's
   crawlers outside the blind ring so ground fire is still shown; add a check that a crawler INSIDE the ring is never
   fired on).
2. Art bands: no drawn barrel below the limit. Re-pick the bands inside the real span (e.g. -25, -18, -11, -4 aim, +8
   rest, +32 high; your call) within the 3 MB turret budget; regen art + muzzle7; el_band unchanged in spirit.
   Re-measure the barrel-vs-stream max angle (test_ciws7 sweep; ground cases now only outside the blind ring) and keep
   the regression bounds honest (if the new max is lower, tighten; never loosen without saying why).
3. Tests: test_ciws7 (new: inside-ring crawler never engaged; outside-ring engaged; depression never below the limit),
   test_muzzle7, test_art7f, test_audio7, test_sent7 + test_cnfac7 (balance fights must stay as BAL7 left them:
   sent7 12/0), windowed pt7_ciws7 0 fail; post fact shots.best: a burst at the edge of the ring showing the barrels at
   their lowest, plus one showing a crawler close to the building NOT fired on by the CIWS (read them first).
4. Then run the editor import once: "$G" --headless --path . --import (it segfaults on exit AFTER "DONE reimport":
   judge by 0 ERROR lines) so the regenerated PNGs and the 6 CIWS wavs get .import files.
Files: sim/systems/ciws7.gd, content/g7/defs_g7_ciws.json (elev block + new limit key), tools/art/g7_ciws7.gd (+ assets),
tools/art/muzzle7.gd (+ muzzle7.json), presentation/view/fx_layer.gd (CIWS branch), tests/test_ciws7.gd,
tools/pt7_ciws7.gd. Post a claim first (LPRES7, FACINT7 and a PERF successor are live).
