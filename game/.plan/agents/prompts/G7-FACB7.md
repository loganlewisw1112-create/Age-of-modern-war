# G7-FACB7: the missing facility buildings (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh FACB7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-6** (the
owner's choice; read every word) and 13.9c..13.9c-5 (the layout rules: no overlap, two-layer APC entry, towers, walls,
sentries, walkable walls, cleared site), 6.2 (facility), 6.3-6.9 (the counter-nanite teams, their weapons, suits, APCs,
dropships). Read the handoffs / commits of BASE7-2, BASE7-3 (e8877bb), ART7F / ART7F-2 (b9b05f0), WALL7 (e8877bb): the
facility layout is content/g7/defs_g7_facility.json `_g7_facility` + sim/systems/cn_facility.gd; the art generator is
tools/art/g7_fac7f.gd (BASE7-3 left slack at x10..11 y21..24, x16..19 y15, x22..25 y25).

## Files you own (nobody else is live on them)
content/g7/defs_g7_facility.json, sim/systems/cn_facility.gd (zones, zone purposes), tools/art/g7_fac7f.gd + the art it
writes, presentation/view/entity_layer.gd + baseprops_layer.gd (facility drawing only), tests/test_cnfac7.gd +
tests/test_art7f.gd (extend; never weaken), tools/pt7_art7f.gd / pt7_cnfac7.gd. Systems the purposes touch (resupply,
suit repair, medical, refuel): call their existing APIs (sim/systems/supply.gd, medical.gd, wounds.gd, counter_nanite.gd,
airfield.gd); if you need a change in one, post a change_request to orch. Keep wall-walk access (a free inside cell at
every tower) and the WALL7 tests green.

## Deliver
1. The buildings of 13.9c-6 placed with the no-overlap / clearance / lane rules, compound about the same size.
2. Each with a cheap, real purpose in the sim (see 13.9c-6); deterministic, saved, hashed; a match without a facility
   costs nothing extra.
3. Finished art for each at the approved detail level (the owner's bar: "no flaws", "dont make sense or arent fully
   ... given true art" is what we fixed before); the folded-in pieces (runoff tank, quarantine bay, comms/EW mast).
4. Tests: no overlap incl. the new buildings; each purpose works (e.g. a team resupplies its special ammo at the
   magazine; a breached suit is repaired at the suit bay; an exposed soldier is treated at the aid station; a dropship
   refuels at the fuel point); test_cnfac7, test_art7f, test_wallwalk7, test_lpmap7, test_lpmode7 green.
5. Playtests pt7_art7f and pt7_cnfac7 windowed, with a shot of the whole compound and of each new building at zoom
   1 / 1.75 / 2.5. Look at every shot yourself (Read the PNG) and fix what falls short. List the best shots in your
   report (the owner wants to see them).
