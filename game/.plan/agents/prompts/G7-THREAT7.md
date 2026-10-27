# G7-THREAT7: Machine threat units (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: threat7. Spec: G7_REFERENCE master scope section 8 ("Threat units" and "Living
cores"), plus brainstorm record B13–B15 and B17 (Weavers). The Machine keeps its CURRENT art style; ARTCN7-2 is reworking
the packhunter, Weaver and living core samples; draw the others in the same Machine style (new generator
`tools/art/g7_threats2.gd`).

Pre-registered stub (ORCH): `sim/systems/threats7.gd` (after Creep, Cores).

## Deliver (content `content/g7/defs_g7_threats.json`, numbers PROVISIONAL)
1. **Burrowers**: tunnel under creep and erupt beneath convoys or inside deployment rings.
2. **Nanite spitters**: ranged slugs built to puncture suits (call `Wounds.puncture`; main source of suit breaches).
3. **Mimic infiltrators**: look like friendly soldiers/vehicles to the enemy until scanner technicians (CNSIM7) or the
   facility decontamination walkway (CNFAC7 sets `e.mimic_exposed`) expose them; then they fight.
4. **Packhunter walkers**: move like wolves/spiders with clawed talons, packs of 4–6, flank convoys from several sides,
   go for APC mounts and gunners, close-combat attacks that puncture suits.
5. **Leeches**: latch onto APCs (`e.leech_on` on the vehicle, as CREEP7 expects) and physically wreck the gun mounts,
   side panels and dome emitter part by part (Apc7 state); pried or shot off by crew/other squads; the APC EMP pulse and
   `Creep.detach_leeches` knock them off.
6. **Weavers**: huge spider-mothers; webbing slows vehicles and cocoons soldiers (cocooned = suit breached), hauls the
   cocoon toward the creep; any soldier can cut a cocoon slowly, the purge specialist and medic-engineers fast; a soldier
   dragged fully into creep is lost. Spawning is gated by an API LPMODE7 calls (Weavers only from 60–75% into a Last
   Protocol run).
7. **Walking last core polish**: CREEP7's walker moves straight with no pathing; give it real pathfinding around
   obstacles while barrier lines still stop it (coordinate the API with `Cores`).
8. The Machine AI fields these units (via CREEP7's `machine_react7.gd` learned reactions: hunt strike teams, defend sites,
   raid the facility); post `fact threats.api`.

## Tests (tests/test_threat7.gd)
each unit's signature behaviour; leeches wreck parts and come off by pry/shot/EMP; cocoon cut-free vs lost; mimic
exposure; walker pathing; same seed twice = same hash; a match without them is hash-identical.
Playtest flow tools/pt7_threat7.gd: packhunters flanking a convoy, a leech on an APC, a Weaver cocooning; shots.
