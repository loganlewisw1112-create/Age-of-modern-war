# G7-FACB7-6: the Suit Foundry (armory + suit bay) resized and redesigned (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh FACB7-6 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-20c** (the owner's note: read every word),
13.9c-20 / -20a / -20b (the suits), 13.9c-6 (armory + suit bay), 13.9c-13 (realism), 13.9c-18 (no transparency),
13.9c-2/-8/-9/-14/-18 (layout rules: no overlap, >= 1 tile clearance, doors onto lanes, lanes never cross a footprint),
and the predecessor handoffs .plan/handoff/FACB7-5*.json (if present) for how the layout and art are built.
## Build
1. Layout (content/g7/defs_g7_facility.json `_g7_facility`, sim/systems/cn_facility.gd): grow the armory zone [16,17,4,3]
   (and its armory_part, EXO7's cn_armory 2x2) to fit ~4 m suits: big bay doors facing a lane the suits use (vehicle
   routes, not the infantry path), a test apron; re-plan neighbours if needed but keep the wall ring the same size; keep
   every layout rule and every test in tests/test_cnfac7.gd / test_lpmode7.gd green (never weaken a check). Agree cells
   with APCMOV7-2 (fac_drive7 lanes) and POLISH7-5 (fuel bay) on the board.
2. Art: redesign the building as the Suit Foundry in tools/art/g7_fac7f.gd `armory()` (+ its height in fac_life7 /
   fac_atmo7 / fac_seq7 ZONE_H tables via change_request to their owners or ORCH): tall armoured hangar bay with
   gantry crane, suit cradles with charging / arming racks, pilot entry gantry, hardened walls, signage "SUIT FOUNDRY";
   approved detail level; opaque. WALL7-2 is editing g7_fac7f.gd's wall / tower parts at the same time: edit ONLY the
   armory section, re-read the file right before every edit, and tell WALL7-2 on the board before you regenerate.
3. Name: the building shows as "Suit Foundry" in the UI (defs name of cn_armory) and the plaques.
4. Tests: test_cnfac7 / test_lpmode7 / test_cnsuits7 stay green; add checks: the foundry footprint fits a suit at the
   new radius in and out of its doors along a lane. Playtest: the facility playtest that frames the armory (find it:
   pt7_cnfac7 / pt7_art7f) at zoom 1 / 1.75 / 2.5; Read every PNG; post fact shots.best.
Files you own: content/g7/defs_g7_facility.json, sim/systems/cn_facility.gd (layout parts only), tools/art/g7_fac7f.gd
armory() only, tests/test_cnfac7.gd. EXO7-2 owns the suits (defs_g7_cnsuits.json, g7_cnsuits.gd): agree the suit radius
with it. Anything else: change_request (exact lines).
