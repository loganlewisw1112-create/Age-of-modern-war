# G7-LIFE7: facility life: activity, moving parts, ops room (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh LIFE7 <calls> <tokens> "<label>" -- <cmd>`, status
every 5 tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-7**
(the owner's choices, quoted: read every word) and 13.9c..13.9c-6 (the facility: layout, two-layer entry, towers,
sentries, walkable walls, the new buildings FACB7 is adding now), 6.2 / 6.9 (facility, dropships), every "Look
checkpoint" decision (the owner's quality bar: "no flaws", depth that makes sense from every angle). Look at the current
facility shots: C:/CODING/integ7_fast/pt_art7f/*.png and pt_wallwalk7/*.png.
Live at the same time: **FACB7** (owns the facility layout, defs json, cn_facility.gd, tools/art/g7_fac7f.gd,
entity_layer.gd / baseprops_layer.gd facility drawing: never edit those; ask it on the board), and sister agents
(LIFE7 activity + moving parts + ops room, ATMO7 atmosphere + wear + signage + damage, SEQ7 mission sequences). Agree on
the board who draws what so nothing is drawn twice. Read the facility through CnFacility.render_entries / the render
snapshot / events only, never mv.world per frame (the G7 fps lesson: per-frame mv.world reads join the sim thread).
**Display only:** state hash identical with your layer on / off (test it); fps gates hold (2k p10 >= 60: measure with
the bench before / after, report as shared-PC numbers); a match without a facility costs nothing. Wiring into
match_view: send ORCH a change_request (exact lines). Art: your own generator under tools/art/, registered via
presentation/art/art_catalog.gd (register only), at the approved detail level; never delete art you don't own.
Tests: tests/test_life7.gd (new). Playtest tools/pt7_life7.gd (ORCH registered "life7"): windowed, shots at zoom
1 / 1.75 / 2.5 of each feature, LOOK at every shot yourself (Read the PNG) and fix what falls short; list the best shots
in your report (the owner wants to see them). "More depth": add further touches of your own and list them.

## Deliver
1. Staff on real routes (technicians between workshop / garages / pads / ops, guards at the checkpoint checking
   arrivals, a guard dog on the inner wall route), deterministic from tick + facility state.
2. Vehicles at work: forklifts carrying ammo crates magazine -> APCs / pads, a fuel truck servicing the pads, a tow
   tractor moving dropships (display actors; they never block sim units: when a sim unit is near, they wait).
3. Range training: drills, pop-up targets rising / falling, kill-house lights during live fire.
4. A perimeter drone circling overhead; drone-bay and garage doors rolling open / shut when used.
5. Moving parts: radar dish turning, blinking comms-mast lights, glowing ops screens, tower cupolas tracking the
   nearest enemy (from the snapshot).
6. Ops-room activity: staff at screens and a map table showing live strike-team positions (an inset / cut-away or
   window glow; your call, make it read).
Files you own: new presentation/view/fac_life7.gd (+ helpers), tools/art/g7_life7.gd + its art, tests/test_life7.gd,
tools/pt7_life7.gd.
