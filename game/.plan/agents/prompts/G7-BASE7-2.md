# G7-BASE7-2: the base and facility laid out for this fight (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh BASE7-2 <calls> <tokens> "<label>" -- <cmd>`, status
every 5 tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c**
(the owner's new note, quoted: read every word), 13.9b (first layout pass), section 10 (Last Protocol 3-ring base), 6.2
(the Counter-Nanite facility), 6.9 (helipad, C-17 loading), 7 (turrets). Read BASE7's commit (git log --grep BASE7) and
handoff (.plan/handoff/BASE7*.json), and look at the current base and facility shots (.plan/shots/BASE7/*.png).
A second agent, **ART7F**, works at the same time on the display side (flicker, joined wall art, facility interior
art, bigger pad art). Agree footprints with ART7F on the board before you change any footprint it draws.

## Research first (cite what you used in your report, opened pages only)
How real fortified bases, FOBs and military airbases are laid out for a heavy, sustained attack: perimeter layers
(obstacles, wall, standoff), entry control points (serpentine, overwatch, holding area), guard towers and interlocking
fields of fire, kill zones on approaches, artillery positions covering every approach, dispersal and revetments for
aircraft and high-value assets, ammunition storage away from barracks and the core, runway clear zones, patrol routes.
Use WebSearch / WebFetch (max 15 fetches). Turn it into concrete layout rules for our 3-ring base and the facility.

## Files you own
sim/maps/last_protocol.gd (rings, plots, roads, gates, airfield, pads, facility site), sim/systems/lp_setup.gd (what is
pre-built where; the starting garrison), the facility zone placement in sim/systems/cn_facility.gd +
content/g7/defs_g7_facility.json (footprints), patrol behaviour for the starting garrison (use the existing patrol
order / SquadAI; new code only in lp_setup.gd or a new sim/systems/lp_garrison7.gd: ask ORCH via change_request for a
system slot if you need one), tests/test_lpmap7.gd, test_lpmode7.gd, test_cnfac7.gd (extend; never weaken),
tools/pt7_lpmap7.gd, tools/pt7_cnfac7.gd.

## Deliver
1. Defences spread around the whole perimeter by threat axis: howitzers covering every approach, turrets / auto
   turrets / AA at gates, corners and approaches with interlocking fields of fire, no blind sector, nothing bunched.
2. Airfield with room for the whole runway and clear zones inside the walls (no runway under a wall), aprons,
   taxiways, revetments.
3. Dropship landing sites (regular and stealth) rebuilt bigger for the current dropship size, with an approach lane;
   C-17 ramp loading still works (test_cnfac7 and pt7_cnfac7, including the known miss
   "cnfac7_ramp_all_loaded_f6_7 1 of 2 craft hold APC + crew + 8 operators": fix its cause).
4. Starting garrison: units that patrol the outer and the inner walls on real routes along them, plus gate guards;
   more cameras with real sight; entry control at the gates.
5. A militarily sensible layout for the whole base and the facility (the facility's overall size is about right):
   defence in depth, standoff, dispersal, protected ammunition storage, every interior zone with a clear purpose.
6. Scale audit (sim side): list every footprint that no longer matches the current unit / vehicle / dropship scale
   (pads, garages, bays, gates, roads) and fix it; post the list as `fact base7_2.scale_audit`.
7. Perf: Last Protocol step stays well under 50 ms (measure before / after, .plan/lpperf7 cost harness); the garrison
   must not make it expensive (staggered thinking).
8. Tests green: test_lpmap7, test_lpmode7, test_cnfac7, test_lpperf7, test_maps; playtests pt7_lpmap7 and pt7_cnfac7
   windowed; before / after overview shots of the base and the facility at zoom 1 / 2 / 3. Look at every shot and judge
   it against the owner's words. If a decision really needs the owner, post a `need` to orch with the question and
   your default, and carry on with the default.
