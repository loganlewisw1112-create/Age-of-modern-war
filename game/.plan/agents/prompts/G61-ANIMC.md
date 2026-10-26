# G61-ANIMC: put the vehicle animation on screen + art memory (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: animb61 (re-run) and anim61 (must stay green).

ANIMA61(-2) wired the infantry overhaul into the renderer; ANIMB61 generated the vehicle/air/naval frames but nothing reads
them yet. Both are finished; you now own presentation/view/entity_layer.gd, batch_art.gd, batch_atlas.gd, motion.gd,
veh_anim61.gd, presentation/art/muzzle_g61.gd, tools/art/g61_anim_veh.gd, tools/art/g61_bearer.gd (+ _gen),
tests/test_anim61.gd, tests/test_animb61.gd, tools/pt61_anim61.gd, tools/pt61_animb61.gd.
Read the handoffs/reports first: .plan/handoff/ANIMA61-2.json and ANIMB61's board posts (change_request.veh_selectors,
change_request.veh_pick_helper, change_request.bearer_veh_anim, fact anim.muzzle).

1. **Wire vehicles** (ANIMB61 CRs): batch_art.veh_cols adds damaged, burner, pulse; entity_layer calls
   VehAnim61.pick(c[32], col, ...) for track phase by speed, recoil on fire (entity_layer.on_shot already exists), damaged
   below a hp fraction, banking from Motion.turn_rate for air/naval, burner for jets, pulse for Machine; mbt/ifv separate
   turret sprites rotating toward the target (VehAnim61.turret) with turret_fire/turret_recoil; suspension bob on start/stop
   and a 1 px hull rock on shots in Motion. Must respect the 700-unit motion cap and far LOD (no extra cost at 10k zoomed out).
2. **Bearer drone:** add the vehicle anim hook in tools/art/g61_bearer.gd (after ANIM.build(out)) and regenerate with
   g61_bearer_gen.gd so test_animb61 is 5/5.
3. **Memory:** decoded vehicle sheets went 87.7 -> 164.7 MB (infantry 30 -> 110 MB after ANIMA61-2's packing). Apply the
   same packed-image + mirrored-facings approach ANIMA61-2 built for infantry (batch_art split_image / frame_src / negative
   draw width) to the new vehicle anim61 columns (store 5 facings, mirror 3) where the art is left/right symmetric; keep
   the original columns. Report decoded MB before/after for infantry + vehicles and the live atlas page count/MB in a
   2k match. Target: total new-frame memory at least 35% lower than now without visible artefacts (check shots).
4. **Ship playtest:** pt61_animb61's ship case needs real water: use a map with open water (Coastal Front, coastal_front_m)
   for the naval part, and check wake/bank frames are picked at speed.
5. Tests: test_anim61, test_animb61 (5/5), test_art*, test_view5, test_view6, test_vfx61 green; view must never write the
   sim (hash identical on/off). Playtests anim61 + animb61 windowed, one at a time; save a 10-shot strip of a tank platoon
   advancing and firing (animb61_strip_*.png) and send the paths in your report.
6. FPS: the fps harness once at the end (`--fps --fps-secs=30`), record CPU load and Godot process count. PERF61 is working
   the sim side and owns the final perf report — post your numbers to the board as fact anim.fps.
