# G7-SEQ7: facility mission sequences on screen (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh SEQ7 <calls> <tokens> "<label>" -- <cmd>`, status
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
Tests: tests/test_seq7.gd (new). Playtest tools/pt7_seq7.gd (ORCH registered "seq7"): windowed, shots at zoom
1 / 1.75 / 2.5 of each feature, LOOK at every shot yourself (Read the PNG) and fix what falls short; list the best shots
in your report (the owner wants to see them). "More depth": add further touches of your own and list them.

## Deliver (choreography driven by the real CnFacility / CounterNanite phases and events, display only)
1. Launch: alarm, crews run to the APCs, garages open, APCs roll up the dropship ramp, ramp closes, rotor spool-up
   with dust, take-off. Where the sim already moves the units, dress it (crew runners, door / ramp timing, dust,
   spool-up); never move sim units yourself.
2. Return + decon: dropship lands, APCs through the wash with spray animation, crews walk the decon hall and come out
   clean (dirty -> clean look).
3. Casualty flow: medics carrying stretchers from the pad to the aid station for wounded team members; quarantine-bay
   lights for exposed soldiers (read the wound / exposure state from the snapshot).
4. Resupply flow: ammo carts loading the APC rocket pods and the teams' special rounds before each launch.
5. Camera-friendly: each sequence readable at zoom 1-2.5; an optional "follow the launch" camera hint is fine.
Files you own: new presentation/view/fac_seq7.gd (+ helpers), tools/art/g7_seq7.gd + its art, tests/test_seq7.gd,
tools/pt7_seq7.gd. The dropship / APC sprites are ARTCN7's (don't redraw them); add overlays (dust, ramp lights,
spray) in your layer.
