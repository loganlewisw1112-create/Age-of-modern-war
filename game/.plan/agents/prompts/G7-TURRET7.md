# G7-TURRET7: 8 new Human A turrets (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: turret7. Spec: G7_REFERENCE master scope sections 0 and 7 (all 8 turrets exactly),
plus 10 (the Last Protocol outer ring is stocked with them).

## Deliver
1. **Content** (`content/g7/defs_g7_turrets.json`, numbers PROVISIONAL; Human A; stage gating set by you, sensible):
   1. Heavy MG nest (twin .50 behind sandbagged armour; infantry, swarms, light walkers);
   2. Autocannon turret (rotating 30 mm; light vehicles, drones, packhunters);
   3. Hull-down tank turret (120 mm in a buried armoured casemate; main anti-armour wall gun);
   4. Auto-mortar pit (automated 120 mm over the walls; needs spotting from towers or drones);
   5. EMP projector (stuns Machine units, drops drones at the wall; long recharge; use CREEP7's `MachineEW7.stun`);
   6. Thermite flame turret (burns creep, seeds and small Machine units on the approach: `Creep.burn`);
   7. Microwave anti-swarm turret (soft-kill cone vs swarms, micro-drones, leeches; complements the Laser CIWS);
   8. Rail cannon (late game; extreme range and penetration vs the biggest Machine units and the walking core; slow fire,
      heavy power draw).
   Any behaviour the existing defence/combat code can't express goes into a new helper `sim/systems/turrets7.gd` (no
   system slot needed if you call it from existing hooks; if you need a slot, change_request ORCH).
2. **Art**: the owner rejected the first art samples and an art rework (ARTCN7-2) is running now with a bigger, more
   detailed, grounded military style (watch `fact art.detail_level` on the board). Draw the 8 turrets in a new generator
   `tools/art/g7_turrets2.gd` (ARTCN7-2 owns g7_turrets.gd for its 2 samples) following ARTCN7-2's latest detail level:
   every facing, build stages, damaged state, traverse, recoil or beam, muzzle and impact frames; menu icons; register the
   art group by change_request to ORCH. If ARTCN7-2's level isn't posted yet, build the sim first and draw last.
3. **AI**: AI builders can place them (Human A AI defence logic) and the Last Protocol base uses them (LPMODE7 places).

## Tests (tests/test_turret7.gd)
each turret builds, targets its intended class, and applies its special effect (EMP stun, creep burn, soft-kill cone,
rail penetration, mortar needs spotting); stage gating; same seed twice = same hash; a match without them is
hash-identical. Playtest flow tools/pt7_turret7.gd: a wall line of all 8 vs a Machine assault; shots.
