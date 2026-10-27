# G7-CNFAC7: Counter-Nanite facility, dropships, base secure state (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: cnfac7. Spec: G7_REFERENCE master scope sections 0, 6.2, 6.9 (the dropships part),
9, plus the brainstorm record entries B2, B4, B9, B11, B18 that concern the facility and dropships. Size reference
(planning estimate): the facility is about 32×32 tiles.

Pre-registered stubs (ORCH): `sim/systems/cn_facility.gd` (after Production), `sim/systems/base_state7.gd` (before
Victory). CNSIM7 builds the strike team, operators and APCs in parallel: agree the spawn and loading interface early.

## Deliver
1. **The facility building** (`content/g7/defs_g7_facility.json`, numbers PROVISIONAL; Human A and Human B only; unlocked
   by CNSIM7's research item): a massive compound **built already gated and fortified**: perimeter walls, armoured gate
   and checkpoint, a hardened tower on each side (remote weapon station, counter-drone emitter, interceptors), blast
   walls, a short-range EMP field, unhackable electronics, entrance/staging ground with anti-vehicle barriers and smoke
   cover; everything completes with the building, no separate orders. Inside, from the gate inward: decontamination zone,
   central concrete loading area, garages for 5–8 APCs, helipad for the stealth dropship, overwatch drone bay, mission
   planning room, simulation range, package lab, workshop and drone bay. Use ARTCN7's sample sheets for the areas it drew
   (assets/art/g7_cn: gate, decon, garage, helipad); others get placeholders until the full art roll-out.
2. **Flows** (`cn_facility.gd`): trains the strike team and tactical squads (they spawn inside their APCs in the garages,
   pull onto the loading pad, load, roll out through the gate; all visible); APC repair/upgrade and restock of packages and
   interceptor drones; package lab production queue and tier upgrades; simulation range drills that build team XP (only
   while secure); decontamination: APCs rinsed before parking, soldiers through the walkway, punctured suits cleared and
   repaired, exposure cleared, mimic infiltrators exposed (hook for THREAT7). **If breached:** lockdown (blast doors seal
   garages/lab/helipad, pop-up turrets, counter-nanite mist that hurts Machine units), emergency evacuation of APCs and the
   dropship, backup power and self-repair.
3. **Dropships** (transport.gd is yours): an **internal cargo bay** on both the regular Human A VTOL Dropship
   (`a_vtol_dropship`, enlarged; override in your g7 fragment) and a new **stealth strike dropship** (no rotors, stealth
   engines, VTOL; Human A and B; lives on the facility helipad): one vehicle up to strike-APC size + its occupants + one
   extra squad, all inside (never slung). Stealth dropship: 20–25 soldiers without a vehicle; launches 5 defence drones
   (3 kamikaze, 2 machine-gun) while extracting; long cooldown. Art: ARTCN7's samples (g7_cn_stealth_dropship,
   g7_a_vtol_dropship_xl).
4. **Base secure state** (`base_state7.gd`): each base is secure / contested / under fire / breached from threats inside
   its perimeter and incoming fire; API `BaseState7.state(w, side, pos)` and a training-speed multiplier the facility (and
   LPMODE7 later) read; the facility's own defences count toward "secure". Post `fact base_state.api`.

## Tests (tests/test_cnfac7.gd)
facility builds with all its defences in one order; training spawns inside APCs in the garages; loading and roll-out;
decon clears exposure and repairs suits; lab production; range XP only while secure; lockdown and evacuation on a
breach; both dropships carry one APC + occupants + a squad inside; stealth dropship drones on extraction; secure state
transitions; same seed twice = same hash; a match without the facility is hash-identical to before.
Playtest flow tools/pt7_cnfac7.gd: build the facility, train a strike team, watch the APCs load and roll out, a
dropship loading an APC, a breach and lockdown; shots of each.
