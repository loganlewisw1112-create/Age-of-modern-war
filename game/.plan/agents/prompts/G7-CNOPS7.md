# G7-CNOPS7: counter-nanite operation support + progression (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: docs/G7_REFERENCE.md master scope 6.9 (the support bullets: overwatch drone, fire
support on call, relief convoy), 6.10 (progression), 13.4 (operators who feel alive: personalities, bonds, signature
skills; the voice barks themselves are AUDIO7's, you provide the personality data and the events), plus sections 6.3-6.8
for context and the brainstorm entries about named operators and teams. Read the CNSIM7-*, CNFAC7 and DRONE7 handoffs.

Note: this workstream was planned in wave 3 but never launched; it starts late. The counter-nanite units, APCs, facility
and drones already exist. Build in new files and plug in through small, marked hooks.

## Files you own
New sim/systems/cn_ops7.gd (overwatch drone, fire support calls, relief convoy) and sim/systems/cn_progress7.gd (named
operators + teams, call signs, records, scars, team XP levels, bonds, personalities, signature skills, specialist
upgrade paths through the lab and workshop), content/g7/defs_g7_cnops.json (PROVISIONAL), tests/test_cnops7.gd,
tools/pt7_cnops7.gd (flow "cnops7" is registered). System slots / world.gd COMMANDS / research.json entries / HUD cards:
change_request to ORCH with exact lines. counter_nanite.gd / apc7.gd (CNSIM7), cn_facility.gd (CNFAC7), drone_pilot.gd
(DRONE7): change_request with exact lines; never edit them.

## Deliver
1. Overwatch drone: circles the convoy and the site, shares what it sees with the team (use SENSE7's knowledge API if
   posted, else intel.gd), warns of threats (events), can be flown with the existing drone piloting; has its own bay.
2. Fire support on call: the team leader calls artillery, rocket or air strikes from base on targets the team can see;
   limited calls per mission; uses the existing strikes / callins systems.
3. Relief convoy: fresh operator squads or a reload APC sent from the facility to a team in the field.
4. Progression: named operators (name, call sign like "Reaper 2-1", kill and purge record, wounds/scars) and named
   teams ("Team Halcyon"); team XP from missions and drills (faster arming, tighter convoys, quicker dismounts); losing
   veterans costs levels; personalities (calm veteran, nervous rookie, joker, hardliner) and bonds (buddy wound
   call-outs, dragging specific friends, morale hit when a close teammate dies); one signature skill per named
   operator; specialist upgrade paths. Emit events AUDIO7 / OPSUI7 can use (post `fact cnops.api`).

## Tests (tests/test_cnops7.gd)
overwatch drone shares a sighting; a fire-support call hits only a target the team can see and respects the call limit;
relief convoy arrives; names/call signs stable per seed; XP gains and veteran loss; a bond reaction; signature skill
effect; same seed twice = same hash; a match without counter-nanite units is hash-identical; save/load round trip.
Playtest flow tools/pt7_cnops7.gd: an overwatch warning, a fire-support call, a relief convoy, a team card with
names and skills; shots (look at every one).
