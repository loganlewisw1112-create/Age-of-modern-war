# G7-ATMO7: facility atmosphere, wear, signage, damage (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh ATMO7 <calls> <tokens> "<label>" -- <cmd>`, status
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
Tests: tests/test_atmo7.gd (new). Playtest tools/pt7_atmo7.gd (ORCH registered "atmo7"): windowed, shots at zoom
1 / 1.75 / 2.5 of each feature, LOOK at every shot yourself (Read the PNG) and fix what falls short; list the best shots
in your report (the owner wants to see them). "More depth": add further touches of your own and list them.

## Deliver
1. Alarm state on attack / lockdown: red rotating beacons, flashing wall lights, tower searchlights sweeping, blast
   doors closing (from facility lockdown / attack events).
2. Night lighting: floodlight pools, blinking pad / runway edge lights, lit windows, light from open garages. There
   is no day/night cycle yet: add a display-only night look (a Settings option "Time of day: day / dusk / night",
   default day; Last Protocol may default to dusk) without touching the sim; the facility (and base) lights must read
   in it. Settings row via change_request to ORCH (presentation/menu/settings.gd).
3. Smoke, steam, mist: generator exhaust, steaming vents, drifting decon mist, windsock and flags moving with wind.
4. Wear and ground detail: tyre tracks and wet asphalt after the wash, oil stains on pads, hazard stripes around wash
   and pads, unit insignia and numbers on garages.
5. Signage and markings: building signs, lane arrows, gate numbers, warning boards.
6. Damage states for facility buildings: cracks, fires, smoke as hp drops, a ruin when destroyed (overlay in your
   own layer keyed on the building's hp from the snapshot; FACB7 keeps the base sprites).
Files you own: new presentation/view/fac_atmo7.gd (+ helpers), tools/art/g7_atmo7.gd + its art, tests/test_atmo7.gd,
tools/pt7_atmo7.gd.
