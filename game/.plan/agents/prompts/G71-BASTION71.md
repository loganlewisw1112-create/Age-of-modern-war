# G71-BASTION71: the walls fight back: new turrets, wall tech, turret and gate fights, engineers (B1, G3, I2, G1 engineers+, G2 dozer)

> **ORCH 2026-11-09:** every roster question is answered in `.plan/orch71/wave2_roster.md` section 5A. Read it before your first step; it overrides any "if" in this brief. Q1: Last Protocol only.


You are BASTION71. Read `G71_COMMON.md` first (and through it G7_COMMON.md) and follow it. Budget: MAX_TOKENS 750000,
MAX_TOOL_CALLS 140 (hand off at 70%: `max(est + 90k, 312k + 2.3k x calls) >= 525k` or calls >= 98). Scope:
`docs/G71_SCOPE.md` the **rotary railgun** and **directed energy** bullets of B1, part **G3**, part **I2** except
"hand-to-hand on the walls" (ARMY71), the **combat engineers+** bullet of G1 and the **breacher / bulldozer tank**
bullet of G2, the Pre-start decisions (incl. the 2026-11-09 sim-gate amendment) and Done-when 1, 3, 4, 7, in full.
Roster: `.plan/orch71/wave2_roster.md`.

## The owner's words
- B1: "Rotary railgun turret: wall turret firing hypervelocity slugs at minigun rate; shreds swarms and over-penetrates
  through lines; spin-up, heat build-up, forced cooldown, glowing barrels, power draw from the grid." "Directed
  energy: laser CIWS that burns drones out of the sky (beam dwell time, heat, weather and smoke cut range); high-power
  microwave (HPM) emitter that fries a swarm's electronics in a cone (short range, long recharge)."
- G3: "Flak cannon tower: proximity-fused flak bursting inside drone clouds; the main answer to aerial flocks (C5)."
  "Sonic / seismic sensors: ground sensors detecting burrowers and Glass stalkers, shown on the minimap and in the
  threat forecast (D6)." "Wall tech: armour tiers (steel -> composite -> nanite-resistant coating); anti-climb
  (overhangs, electrified tops, fire-pour points against body-piles); hidden firing ports and pop-out gun slits along
  the wall face; fast wall lifts moving troops and robots onto the wall-walk." [PROPOSED, approved] obstacle belts are
  kept "to what engineers (G1) and dozers (G2) already build".
- I2: "Disabled, not dead: heavy hits jam or disable turrets; engineers revive them fast." "Drone repairs:
  maintenance drones repair turrets in the middle of a wave." "Gate defence: gates are focal points with murder holes,
  pop-up guns and gate reinforcement." "Wall-walk choke points: doors and towers that seal to stop crawlers running
  along the wall." "Turret firing look: barrel recoil, ejected casings that pile up, heat glow and steam during
  cooldown, visible tracking lasers / IR at night before firing." [PROPOSED, approved] no turret ammo feeds, heat wear,
  target priority or modules: "the kill-zone tool (D5) carries target sectors; nothing else is added".
- G1: "Combat engineers+: lay wire, rebuild walls under fire, place demo charges, build bunkers / firing steps
  mid-siege; work with the auto repair crews (G4)." G2: "Breacher / bulldozer tank: armoured dozer that clears wreck
  piles (C6), pushes sapper trenches in, builds earth berms."

## Before you start (ORCH fills these in)
- **ANSWERED, see roster section 5A (Q12)** (rotary railgun / laser CIWS / HPM / flak tower: new defs beside
  a_t7_railgun, the G6 Laser CIWS, a_t7_microwave and the G6 flak defs, or reworks of them?).
- **ANSWERED, see roster section 5A (Q11)** (B1 per-weapon heat stays; no general turret heat-wear system?), **Q5** (wall armour
  tiers unlocked during the run before H7?), **Q14** (minimap.gd for sensor contacts: grant or CR), **Q15** (how many of
  each new defence in the LP starting base, and who places them), **Q4** (snapshot fields for heat / disabled / casings).
- Wave-3 things you build against stand-ins, with the API wave 3 plugs into: wrecks as cover (C6) and sappers (C3) for
  the dozer, body-piles (C5) for fire-pour points, Glass stalkers (C4) for sensors (today's threats7 burrower exists),
  aerial flocks (C5) for flak. Auto repair crews (G4) are wave 4: engineers expose a job hook they will use.
- Art: functional at the G7 detail level (`fact art.detail_level`), no full art roll-out (roster Q16).

## Step 1: survey and reproduce before building (mandatory)
1. Read Turrets7 (kinds gun / mortar / emp / flame / cone / rail, shared bucket grid, SCAN), WallTurret7 (face mounts,
   arc), Traverse7, Counterdrone (G6 Laser CIWS), Ciws7, Airdef (radar, flak), Fortify (walls, gates, towers), WallWalk7,
   WallFire7 (the owner's "no shooting out through the walls unless ..." rule; `WallFire7.any` is also the native combat
   guard: never change what it returns), Engineer7 + Sentinels7 job board, Engineering, Fieldworks, Repair, and find the
   existing maintenance-swarm def for drone repairs.
2. Headless repro on the LP map under a Machine wave (bench.lp_peak or a smaller LP wave): turret deaths, seconds each
   turret is dead, crawlers reaching / running along the wall-walk, gate hits, per-turret shots and pierce counts.
3. Post `fact bastion71.survey` (numbers + method) and compiling stubs `fact turrets71.api` (`Turrets71.disabled(e)`,
   `revive(w, e, by)`), `fact walls71.api` (`Walls71.tier(w, b)`, `choke_sealed(w, cell)`, `lift_of(w, cell)`) and
   `fact sensors71.api` (`Sensors71.contacts(w, fid) -> Array`) within your first 15 tool calls. Send ORCH your commands
   + SYSTEM_ORDER slots.

## Step 2: build
1. **Rotary railgun wall turret** (new sim/systems/turrets71.gd plugged into the Turrets7 kinds; defs_g71_defences.json):
   spin-up, minigun rate, heat build-up + forced cooldown, over-penetration through lines (reuse the rail pierce lane
   maths), power draw (def power). **Laser CIWS**: beam dwell to kill, heat, range cut by smoke (Senses7 clouds) and by
   weather that exists (rain was not picked; fog mornings are I3, wave 5). **HPM emitter**: cone, short range, long
   recharge, fries swarm electronics (MachineEW7 stun / drone drop, like the EMP kind).
2. **Flak tower**: proximity-fused bursts inside drone clouds (burst when a cloud is within the fuse radius;
   deterministic), Airdef radar cueing.
3. **Disabled, not dead** (turrets71.gd + repair.gd): heavy hits jam or disable a turret (PROVISIONAL thresholds) instead
   of killing it outright; engineers revive fast (`turret_revive`); the maintenance swarm repairs turrets mid-wave.
   Report how this changes turret uptime vs the Step-1 numbers (difficulty must stay brutal-but-winnable: say so if it
   swings a lot).
4. **Wall tech** (new walls71.gd, fortify.gd, wallwalk7.gd, wallfire7.gd): armour tiers steel -> composite -> nanite-
   resistant (unlock per Q5); anti-climb: overhangs, electrified tops, fire-pour points (`Parts71.ignite`, DAMAGE71 API);
   hidden firing ports + pop-out gun slits as explicit allowed cases of the WallFire7 rule; fast wall lifts to the wall-
   walk; choke doors / towers on the wall-walk that seal against crawlers (pathing stays valid for our own troops).
5. **Gate defence**: murder holes, pop-up guns, gate reinforcement (`gate_reinforce`).
6. **Sensors** (new sensors71.gd): sonic / seismic ground sensors that detect burrowers (and later stalkers) in range;
   a contacts list for the minimap (per Q14) and for D6 (wave 4).
7. **Engineers+ and the dozer** (engineer7.gd, engineering.gd, fieldworks.gd): lay wire, rebuild walls under fire,
   demo charges, bunkers / firing steps mid-siege; the breacher dozer builds earth berms and offers clear-wreck /
   fill-trench actions against Gore71 wrecks (`Gore71.remove` / `drag`, DAMAGE71 API) and a trench stub for C3.
8. **Turret firing look** (new presentation/view/turret71_look.gd): barrel recoil, casings that pile up (a decal kind:
   ask DAMAGE71, owner of decal_layer.gd), heat glow + steam during cooldown, tracking lasers / IR at night before
   firing; effects through the public fx61 API. Turret / wall state reaches the view through snapshot fields (Q4).
9. **Kill zones + FPF in turret targeting**: call `KillZone71.allow` and `Fires71.fpf_aim` (FIRES71 APIs, guarded) in
   Turrets7 / WallTurret7 / Turrets71 retarget. That is the only target-priority change (I2 [PROPOSED]).

## Files (write; everything else by change_request to its owner, see the roster)
sim/systems/turrets7.gd, wallturret7.gd, traverse7.gd, counterdrone.gd, ciws7.gd, airdef.gd, fortify.gd, wallwalk7.gd,
wallfire7.gd, engineer7.gd, engineering.gd, fieldworks.gd, repair.gd; new turrets71.gd, walls71.gd, sensors71.gd; new
presentation/view/turret71_look.gd; new content/g71/defs_g71_defences.json, rules_g71_defences.json; new
tools/art/g71_defences.gd (+ assets/art/g71_defences/); tests/test_bastion71.gd, test_walls71.gd; tools/pt71_bastion71.gd,
pt71_walls71.gd. Not yours: combat.gd (ARMY71: towers with a def.weapon fire through Combat; any change there is a CR),
movement.gd / minimap.gd / lp_setup.gd (unowned: ORCH), drone_bay7.gd (unowned; F7 is wave 3).

## Rules
- **Sim cost** (final build <= 1.7x G6 on 2k; every later wave ~0): with your code in, 2k fight / 2k mixed / 10k 200t
  hashes equal `fact w2.bench_ref` and your systems' profiled share there is <= 0.05 ms/tick (PROVISIONAL, roster Q18).
  Turret thinking stays on the shared bucket grid + SCAN cadence; the rotary railgun's pierce must not scan all
  Machines per shot (lane query on the index); measure an LP-peak wave (ms/tick share). tiers.gd budgets used cost.
  Timing runs follow `orch.timing_lock` (seq 440).
- **Determinism**: two-run hash identical; save / load mid-wave keeps the same future (heat, disabled state, tiers,
  seals, sensors saved + hashed).
- **Perf**: fps p10 on bench.lp_peak and 2k before / after turret71_look.gd; casings piles capped (batched / baked);
  no visible quality trades.
- **Screenshots** as each visible thing lands (rotary railgun spun up + glowing, laser CIWS beam, HPM cone, flak
  bursts, a disabled turret being revived, wall tiers, firing ports, a sealed choke door, gate murder holes, berms, the
  dozer): look at them, then post `fact shots.best`.
- Tests: tests/test_bastion71.gd (spin-up / heat / cooldown, pierce count, laser dwell + smoke cut, HPM cone + recharge,
  flak fuse, disable + revive, drone repair, sector / FPF calls), tests/test_walls71.gd (tiers, anti-climb, ports vs the
  WallFire7 rule, lifts, choke seal pathing, gate defence, sensors, berms / dozer actions). Flows (ORCH registers):
  `tools/pt71_bastion71.gd`, `pt71_walls71.gd` (windowed LP walls under a wave, screenshots).
- Report: AGENT_RULES final report format. No commits. No GENESIS/postflight offer.
