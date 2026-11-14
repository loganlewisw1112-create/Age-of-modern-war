# G71-CNOPS71: CN teams that get the job done, the facility, the trauma hospital, gas, Vanta2 (D7, H8, J6, J10, B7)

> **ORCH 2026-11-09:** every roster question is answered in `.plan/orch71/wave2_roster.md` section 5A. Read it before your first step; it overrides any "if" in this brief. Q1: Last Protocol only.


You are CNOPS71. Read `G71_COMMON.md` first (and through it G7_COMMON.md) and follow it. Budget: MAX_TOKENS 750000,
MAX_TOOL_CALLS 140 (hand off at 70%: `max(est + 90k, 312k + 2.3k x calls) >= 525k` or calls >= 98). Scope:
`docs/G71_SCOPE.md` parts **D7, H8, J6, J10, B7**, the Pre-start decisions (incl. the 2026-11-09 sim-gate amendment)
and Done-when 1, 2, 3, 4, 7, 8, 10, in full. Roster: `.plan/orch71/wave2_roster.md`.
**Start condition:** RAMP71 has posted done and tests/test_cnfac7.gd is green (cn_facility.gd and transport.gd are
RAMP71's until then).

## The owner's words
- D7 ("very capable, smooth, efficient"): "Dispatch: click a known creep node = go purge it; paint an area = search it
  (drones up, sweep pattern), then purge what they find. One order; they handle the rest." "Smart approach: route
  around the tide, convoy spacing, stop short, scout with drones before committing." "Clean dismount + task: APCs park
  in cover; the team dismounts in formation and sets security; suits purge, operators breach / clear, engineers seal."
  "React to contact: suppress, call Vanta / support, break contact or push; casualties evacuated to the APC." "Chain +
  exfil: node done -> next node in the area -> exfil by APC or dropship when ammo / health is low; report back."
  "Feedback: mission card shows every step live (en route, scouting, dismount, purging 60%, exfil); helmet / drone cam
  view; team-leader radio reports." [PROPOSED, approved] "overwatch element left on high ground during the purge; rules
  of engagement per mission (stealth / standard / aggressive); abort-and-extract button that always works; automatic
  re-plan when the route is blocked; zero stuck states (any step that can't progress for N seconds re-plans or reports why)."
- H8: "Facility under siege: late in the run the hive targets the facility itself; its own defences, lockdown and a
  last-ditch evacuation (extends G7's breach lockdown and emergency evac)." "New CN gear: purge cannons, nanite
  grenades, shield drones." "Faster turnaround: teams return, heal, rearm and redeploy through the airlock with no
  waits (the 13.9c-50 ~70 s exit target that G7 missed becomes a G7.1 gate)." "Facility upgrades: upgrade its labs,
  bays and foundry during the run."
- J6 ("bigger, better designed, more capable"; replaces the aid station): "Triage bay (tags), surgery theatres, ICU,
  recovery ward (badly wounded return to the fight later)." "Nanite decon showers, a scan gate, a sealed quarantine ward
  that locks down if a patient turns." "Rooftop medevac pad; multiple medevac helicopters (pads in A1's registry); fast
  tracked drone ambulances pulling soldiers off the battlefield under fire." "Prosthetics bay: soldiers who lost limbs
  return with cybernetic prosthetics (feeds J9)."
- J10: "Counter-nanite gas cloud kills machines and hurts any of our troops without masks; wind carries it (I3)."
  "Masks go on visibly when gas is near; masked units lose a little vision and accuracy." "Masks from lockers, armory
  stock and storage crates near the gates; ammo bearers carry a few spares for nearby units plus their own." "Filters
  wear out during long exposure; fresh filters must be fetched from the armory, crates or lockers."
- B7 (keep rotorless): "Fast, smooth, agile and aerodynamic: higher cruise speed and acceleration, banking turns,
  strafing runs, momentum (no instant stops), twin MGs on the left and right of the front body, sharper silhouette,
  motion trail."

## Before you start (ORCH fills these in)
- **ANSWERED, see roster section 5A (Q8)** (the 70 s gate: Done-when 8's team cycle, the 13.9c-50 8-APC exit, or
  both; does a hospital ward stay count?). Done-when 8 as frozen: "a CN team cycle through the airlock (return -> heal
  -> rearm -> redeploy) in <= 70 s". Never loosen it; if it cannot be met, stop and report with numbers.
- **ANSWERED, see roster section 5A (Q7)** (where gas comes from; wind model now or with I3), **Q9** (hospital footprint), **Q5**
  (facility upgrades during the run before H7), **Q20** (facility-under-siege trigger is wave 3's), **Q1** (D7 / B7 in
  every mode?), **Q14** (air.gd Vanta flight functions: grant or CR), **Q13** (radio reports voiced now?), **Q15**
  (hospital / gear / helicopters in the LP base, how many), **Q4** (snapshot fields).
- J5 infection is wave 3: build the quarantine lockdown with a test-only "patient turns" trigger and post the API J5
  calls. Art: functional at the G7 detail level; Vanta2 is a wave-5 look-checkpoint sample (roster Q16).

## Step 1: reproduce before building (mandatory)
1. Read CnMission8 (phases, `status_line`, `step_reason`, `mission_reason`), Specops8, CounterNanite (move_team /
   remount / dismount / deploy drill / pincer), Apc7, CnOps7 fire support, CnFacility (zones incl. aid_station, garages,
   traffic controller, airlock, lockdown, `evacuate`), BaseState7, Transport ramp boarding, Medical hospitals / evac,
   Wounds care chain, Cards8b (armory + suit foundry presets), Cards8c, Vanta7 + Air flight, Pads71, AmmoBearer.
2. Measure: (a) one CN team's full cycle today: return -> heal -> rearm -> redeploy through the airlock, per phase, and
   the hardened 8-APC exit (G7 recorded 83.5 s vs ~70 s); (b) purge missions on the LP map, N seeded runs: how many end
   in a purge, how many stall, and the reason at each stall (`step_reason`); (c) Vanta speed / accel / turn today.
3. Post `fact cnops71.repro` (numbers + causes) before building, and compiling stubs `fact hospital71.api`
   (`Hospital71.admit(w, e)`, `quarantine_lock(w, on, reason)`, `ward_of(e)`) and `fact gas71.api` (`Gas71.release(w,
   pos, amount, src)`, `conc_at(w, pos)`, `masked(e)`) within your first 15 tool calls. Send ORCH your commands +
   SYSTEM_ORDER slots.

## Step 2: build
1. **D7 dispatch + approach + task + contact + chain + feedback** (cn_mission8.gd, specops8.gd, counter_nanite.gd,
   apc7.gd, new cnmission71.gd): node click = purge (exists: extend), area paint = drone search with a sweep pattern then
   purge what is found; route around the tide with convoy spacing, stop short, drone scout before committing; APCs park
   in cover, dismount in formation, security set; suits purge, operators breach / clear, engineers seal; contact:
   suppress, call Vanta / fire support (FIRES71 API, guarded), break contact or push; casualties back to the APC; chain to
   the next node; exfil by APC or dropship on low ammo / health; overwatch element; ROE stealth / standard / aggressive;
   abort-and-extract that always works; auto re-plan on a blocked route; **stuck watchdog**: any step without progress
   for N s (PROVISIONAL) re-plans or reports why. Mission card shows every step live (presentation/ui71/cn_mission71.gd,
   ui7/team_card.gd, team_cam.gd helmet / drone cam), team-leader radio reports (`presentation/audio/lines71_cn.json`
   through ARMY71's loader). Done-when 4: 0 stuck states over your seeded LP runs.
2. **H8 turnaround** (cn_facility.gd, transport.gd after RAMP71): no waits from return to redeploy: heal, rearm, re-equip
   overlapped while the team stands in the airlock / bays; measure per phase against Step 1 and the Q8 gate.
3. **H8 facility under siege**: its own defences, a staged lockdown, last-ditch evacuation (extends CnFacility
   `_lockdown` / `evacuate`); triggered by a test hook now, by the wave-3 director later (Q20). **New CN gear**: purge
   cannons, nanite grenades, shield drones (defs_g71_cn.json; armory presets in cards8b.gd). **Facility upgrades**: labs,
   bays, foundry, per the Q5 answer.
4. **J6 trauma + decon hospital** (new hospital71.gd, rules_g71_hospital.json, building_card8c.gd / new
   presentation/ui71/hospital_card.gd): triage bay reading DAMAGE71's tags (`Care71.tag_of`), surgery theatres, ICU,
   recovery ward (badly wounded return later), decon showers, scan gate, sealed quarantine ward with lockdown, rooftop
   medevac pad + several medevac helicopters (count PROVISIONAL; pads through `Pads71.register`), tracked drone
   ambulances pulling soldiers out under fire, prosthetics bay (state for J9). Wire it as a def-driven Medical hospital so
   medics / evac route to it with no hard-coded building. Footprint per Q9.
5. **J10 gas + masks** (new gas71.gd, rules_g71_gas.json, ammo_bearer.gd spares, new presentation/view/gas71_layer.gd):
   a deterministic gas field (cells, spread, decay, carried by wind per Q7), kills Machines, hurts unmasked troops;
   masks on visibly when gas is near, a small vision / accuracy cost (ARMY71 places your factor in accuracy8 on your CR);
   masks from lockers, armory stock and crates near the gates; bearers carry spares; filters wear with exposure and
   must be fetched. Done-when 10: tests for masks + filter wear, and the quarantine-lockdown machinery (J5 adds the
   infection itself in wave 3).
6. **B7 VANTA2** (vanta7.gd; Air flight changes per Q14): higher cruise + acceleration, momentum (no instant stops),
   banking turns, strafing runs, twin front MGs left / right, sharper silhouette + motion trail (art through new
   tools/art/g71_cn.gd; banking / trail in the view by snapshot field CR, Q4). Keep the AIRFIX matrix green: run
   tests/test_airfix71.gd + test_airops71.gd after every air change (Done-when 2).

## Files (write; everything else by change_request to its owner, see the roster)
sim/systems/cn_mission8.gd, specops8.gd, counter_nanite.gd, apc7.gd, cn_progress7.gd, cn_ops7.gd, cn_role7.gd,
base_state7.gd, vanta7.gd, cards8b.gd, cards8c.gd, ammo_bearer.gd (mask spares only), and after RAMP71 ends
cn_facility.gd + transport.gd; new cnmission71.gd, hospital71.gd, gas71.gd; presentation/ui7/team_card.gd, team_cam.gd,
ops_panel.gd, armory_card8.gd, building_card8c.gd; new presentation/ui71/cn_mission71.gd, hospital_card.gd; new
presentation/view/gas71_layer.gd; new presentation/audio/lines71_cn.json; new content/g71/defs_g71_cn.json,
rules_g71_cn.json, rules_g71_hospital.json, rules_g71_gas.json; new tools/art/g71_cn.gd (+ assets/art/g71_cn/);
tests/test_cnops71.gd, test_facility71.gd, test_hospital71.gd, test_gas71.gd; tools/pt71_cnops71.gd, pt71_facility71.gd,
pt71_hospital71.gd, pt71_gas71.gd, pt71_vanta71.gd. Never edit tests/test_cnfac7.gd's assertions or thresholds.

## Rules
- **Sim cost** (final build <= 1.7x G6 on 2k; every later wave ~0): with your code in, 2k fight / 2k mixed / 10k 200t
  hashes equal `fact w2.bench_ref` and your systems' profiled share there is <= 0.05 ms/tick (PROVISIONAL, roster Q18).
  Gas is a coarse cell field updated on a staggered cadence and costs nothing with no cloud; missions think on a
  cadence; measure on bench.lp_peak with missions + gas active (ms/tick share). Timing runs follow `orch.timing_lock`.
- **Determinism**: two-run hash identical; save / load mid-mission, mid-airlock, mid-gas keeps the same future.
- **Player control first**: abort always works; a player order to a team cancels or pauses the mission as today.
- **Perf**: fps p10 on bench.lp_peak and 2k before / after gas71_layer.gd and the cards; no visible quality trades.
- **Screenshots** as each visible thing lands (mission card steps live, area search sweep, dismount + security, the
  hospital wards, quarantine lockdown, drone ambulance, masks on in gas, the gas cloud, Vanta2 banking + trail): look at
  them, then post `fact shots.best`.
- Tests: tests/test_cnops71.gd (search -> purge -> chain -> exfil, re-plan, watchdog, abort, ROE), tests/test_facility71.gd
  (turnaround per phase vs the gate, siege response, gear, upgrades), tests/test_hospital71.gd (triage order, wards,
  recovery return, quarantine lock, medevac pads, ambulances), tests/test_gas71.gd (spread / decay / wind, Machine kill,
  unmasked harm, masks, filter wear + fetch, bearer spares). Flows (ORCH registers): `tools/pt71_cnops71.gd`,
  `pt71_facility71.gd`, `pt71_hospital71.gd`, `pt71_gas71.gd`, `pt71_vanta71.gd`.
- Report: AGENT_RULES final report format. No commits. No GENESIS/postflight offer.
