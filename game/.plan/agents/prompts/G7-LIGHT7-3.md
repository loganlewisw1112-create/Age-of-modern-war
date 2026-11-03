# G7-LIGHT7-3: lighting finish: lit windows, continuous perimeter wash, mast tips (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after every long run; post `fact shots.best` as soon as something is visible; no git, no D:). Read
.plan/handoff/LIGHT7-2.json and .plan/handoff/LIGHT7.json. Spec: docs/G7_REFERENCE.md 13.9c-24, -24a, -24b (owner:
"outer facing floodlights in facility need to be much brighter (light up the night as a real bases floodlight would be )",
"lighting and light fixtures still need upgrading and more realistic approach/placement/everything"), 13.9c-18.
ORCH applied LIGHT7-2's CRs 5926 (fac_life7 garage door quad flush with the facade, opaque, duplicate spill removed) and
5928 (fac_seq7 pad beacons flush at 1 px, translucent wedge removed). Not applied: 5927 (fac_life7 MAST_TIPS).
## Build
1. Lit window panes at night on the multi-storey buildings (command centre, barracks, workshop / drone bay, Suit
   Foundry): read each facade's window grid from its art generator (g7_fac7f.gd / g7_cn_facility.gd; do not guess), draw
   lit panes (warm / cool mix, some dark, a few flicker) aligned to the drawn windows, opaque, only on visible faces.
2. Continuous perimeter wash: the east wall at zoom 1 still shows soft patches with dark gaps; raise FLOOD_R toward 190
   or add a second flood per section so the ground outside every wall face is evenly lit at night (13.9c-24b).
3. CR 5927: re-measure the command centre's 3 comms-mast pole tips on a night zoom-2.5 shot (EW mast tip 25.6 m = 251 px
   above its foot) and fix fac_life7.gd MAST_TIPS (you own that constant and the mast-blink lines only).
4. test_light7: extend test_light_count_bounded for the new core pools + windows; run the full windowed pt7_atmo7 (day /
   dusk / night / alarm) to PLAYTEST RESULT 0 fail; lights stay under the cap. Read every key PNG; post fact shots.best.
Files you own: presentation/view/fac_atmo7.gd, tools/art/g7_atmo7.gd + assets, tests/test_light7.gd, tests/test_atmo7.gd,
tools/pt7_atmo7.gd, fac_life7.gd MAST_TIPS + mast blink lines. Anything else: change_request.
