# G7.1 wave 2 roster (DRAFT for ORCH review; W2PLAN71-1, 2026-11-09)

Covers wave 2 of `docs/G71_SCOPE.md` "Build order": **B (B1-B7), G1-G3, I2, D4-D5, D7 + H8, J1-J3, J6, J10**.
Inputs read: G71_SCOPE.md (header, Pre-start decisions incl. the 2026-11-09 sim-gate amendment, Done-when, every wave-2
part in full), PLAN_G71.md, G71_COMMON.md, G7_COMMON.md, AGENT_RULES.md, the 5 wave-1 briefs, ROADMAP.md (G8+ only, to
keep it out), board_g71.jsonl (state to seq ~772), docs/NATIVE_COMBAT71.md, and a code survey (files named below exist
on C: today unless marked "new"). Nothing in the code was edited.

**Open questions for ORCH are in section 5 (Q1-Q20). Briefs mark the places that wait on an answer as
`ORCH: answer Qn here before launch`. Nothing in this roster resolves them.**

## 1. Slots and start order
- Cap 6 live. Live now: SWARMNAT71-1 (native/, entity_layer.gd, motion.gd, render_snap.gd snapshot fields) and
  RAMP71-1 (cn_facility.gd ramp / lineup / bay_seq code; its status says the ramp code also lives in transport.gd).
  PERFSIM71-7 posted its handoff (seq 744) but still posted a status at seq 767 ("waiting: cut7.sh lean_vis oracles"):
  see Q3. W2PLAN71 ends with this roster.
- So **4 wave-2 slots now, 5 once RAMP71 ends**. Five agents, all with successors (-2, -3 ...) from handoffs.

| Start | Agent | Model (suggested) | Parts | Est. generations |
|---|---|---|---|---|
| now | DAMAGE71 | Opus | B2, J1, J2, J3, G1 combat medics+ | ~6-7 |
| now | FIRES71 | Opus | B4, D5, B1 thermobaric + incendiary, B6, G1 forward observers / JTAC, G2 MLRS | ~6-7 |
| now | ARMY71 | Opus | D4, B3, B5, G1 NVG / thermal gear, I2 hand-to-hand on the walls, G2 flame tank | ~6-7 |
| now | BASTION71 | Sonnet (Opus if its survey finds design questions) | B1 rotary railgun turret + laser CIWS + HPM, G3, I2 (all but hand-to-hand), G1 combat engineers+, G2 breacher / dozer tank | ~5 |
| when RAMP71 posts done + test_cnfac7 green | CNOPS71 | Opus | D7, H8, J6, J10, B7 | ~6-7 |

- Within "now": DAMAGE71 and FIRES71 post their consumed APIs first (`fact parts71.api` incl. `ignite`, `fact
  killzone71.api`) as compiling stubs within 15 tool calls; ARMY71 / BASTION71 call them through guards until complete.
- When SWARMNAT71 ends (6th slot): successors only, or (ORCH's choice) split B6 CONDUCTOR out of FIRES71 into its own
  agent if FIRES71 is behind. Not planned by default.
- Before launch ORCH should: answer Q1, Q3, Q4, Q18 (they change scope or files for 3+ agents); post `fact
  w2.bench_ref` (2k fight / 2k mixed / 10k 200t hashes + G6 and G7.1 ms/tick on the same PC) used by every brief's
  "unused = hash-identical" check; register the flow names in section 4; post `orch.grants` for the files below.

## 2. Ownership (write) — no overlap between agents, SWARMNAT71 or ORCH
| Agent | Owns (write) |
|---|---|
| DAMAGE71 | sim/systems/damage.gd, ballistics8.gd, wounds.gd, medical.gd, blast8.gd, shrapnel.gd; new sim/systems/parts71.gd (component damage, plates, ricochets, nanite self-repair, heavy death physics, burning state + `ignite` API), new gore71.gd (sim gore outcome records, persistent bodies list), new care71.gd (triage tags, morphine, medic+ jobs, field surgery tent); presentation/view/fx_layer.gd, fx61_core.gd, fx61_engine.gd, fx61_tex.gd, decal_layer.gd; new presentation/view/gore71_layer.gd (+ .gdshader: settled bodies / wrecks as batched static images); new presentation/ui71/triage_tags.gd; new content/g71/rules_g71_damage.json, defs_g71_parts.json, rules_g71_gore.json, rules_g71_care.json, defs_g71_care.json; new tools/art/g71_damage.gd (+ assets/art/g71_damage/); tests/test_damage71.gd, test_gore71.gd, test_care71.gd; tools/pt71_damage71.gd, pt71_gore71.gd, pt71_care71.gd |
| FIRES71 | sim/systems/strikes.gd, callins.gd; new sim/systems/fires71.gd (radial missions, strike shapes, FPF, counter-battery, observed fire, thermobaric + incendiary munitions and belts), new killzone71.gd (fire sectors, auto zones, FPF strips, `allow` API), new conductor71.gd (gunship orbit + wingmen); new presentation/ui71/fire_radial.gd, strike_shape.gd, killzone_paint.gd, conductor_orbit.gd; new presentation/view/fires71_view.gd (strike / FPF / sector markers; calls the public fx61 API); new content/g71/defs_g71_fires.json, rules_g71_fires.json; new tools/art/g71_fires.gd (+ assets/art/g71_fires/); tests/test_fires71.gd, test_killzone71.gd, test_conductor71.gd; tools/pt71_fires71.gd, pt71_killzone71.gd, pt71_conductor71.gd |
| ARMY71 | sim/systems/combat.gd (the only wave-2 owner: places other agents' hook calls by change_request), accuracy8.gd, stray8.gd, spread8.gd, morale.gd, fatigue.gd, squad_ai.gd, formations7.gd, orders.gd, companies.gd, senses7.gd, `formation_slots` + the helpers right below it in movement.gd; new sim/systems/discipline71.gd, crew71.gd, ammo71.gd; presentation/audio/radio_queue.gd (+ a loader for per-agent line fragments `presentation/audio/lines71_<agent>.json`), new presentation/audio/lines71_army.json; new presentation/ui71/radio_feed.gd, ammo_panel.gd; new presentation/view/signals71_layer.gd; new content/g71/defs_g71_army.json, rules_g71_discipline.json, rules_g71_ammo.json; new tools/art/g71_army.gd (+ assets/art/g71_army/); tests/test_army71.gd, test_crew71.gd, test_ammo71.gd; tools/pt71_army71.gd, pt71_crew71.gd, pt71_ammo71.gd |
| BASTION71 | sim/systems/turrets7.gd, wallturret7.gd, traverse7.gd, counterdrone.gd, ciws7.gd, airdef.gd, fortify.gd, wallwalk7.gd, wallfire7.gd (never change what `WallFire7.any` returns: the native combat guard reads it), engineer7.gd, engineering.gd, fieldworks.gd, repair.gd; new sim/systems/turrets71.gd (rotary railgun, laser CIWS, HPM, flak, disabled / jammed state, drone repairs), new walls71.gd (wall tiers, anti-climb, firing ports, lifts, choke doors, gate defence), new sensors71.gd (sonic / seismic contacts API); new presentation/view/turret71_look.gd (recoil, casings, heat glow, steam, tracking lasers / IR); new content/g71/defs_g71_defences.json, rules_g71_defences.json; new tools/art/g71_defences.gd (+ assets/art/g71_defences/); tests/test_bastion71.gd, test_walls71.gd; tools/pt71_bastion71.gd, pt71_walls71.gd |
| CNOPS71 | sim/systems/cn_mission8.gd, specops8.gd, counter_nanite.gd, apc7.gd, cn_progress7.gd, cn_ops7.gd, cn_role7.gd, base_state7.gd, vanta7.gd, cards8b.gd, cards8c.gd, ammo_bearer.gd (mask spares only), and after RAMP71 ends cn_facility.gd + transport.gd; new sim/systems/cnmission71.gd (D7 area search, chaining, re-plan, stuck watchdog, ROE, abort), new hospital71.gd, new gas71.gd; presentation/ui7/team_card.gd, team_cam.gd, ops_panel.gd, armory_card8.gd, building_card8c.gd (aid station -> hospital card); new presentation/ui71/cn_mission71.gd, hospital_card.gd; new presentation/view/gas71_layer.gd; new presentation/audio/lines71_cn.json; new content/g71/defs_g71_cn.json, rules_g71_cn.json, rules_g71_hospital.json, rules_g71_gas.json; new tools/art/g71_cn.gd (+ assets/art/g71_cn/); tests/test_cnops71.gd, test_facility71.gd, test_hospital71.gd, test_gas71.gd; tools/pt71_cnops71.gd, pt71_facility71.gd, pt71_hospital71.gd, pt71_gas71.gd, pt71_vanta71.gd |
| SWARMNAT71 (live) | native/ (build_native.sh stage / swap), presentation/view/entity_layer.gd, motion.gd, sim/render_snap.gd snapshot fields: every wave-2 agent sends change_requests (see Q4) |
| ORCH | sim/world.gd (systems, commands), sim/content.gd, sim/systems/g6_hooks.gd (hook dispatcher: agents ask for one line each), tools/ui_playtest.gd, registries outside own fragment, research.json / factions.json, test_hot_state goldens, hotkeys.gd, hud.gd, attach lines for new panels, README / PROGRESS / PLAY_ME, packaging, commits |

**Files nobody in wave 2 owns (change_request to ORCH; Q14 asks ORCH to confirm or grant):** movement.gd (except
formation_slots), fog.gd, sim_index.gd, tiers.gd (read-only API use is fine), air.gd (Conductor and Vanta2 steer through
Air's public order API; any air.gd edit is a CR), minimap.gd, match_view.gd (new tools attach as their own nodes with
their own input handling, as PatrolDraw71 did: CR 161), supply8.gd, drone_bay7.gd, machine_g6.gd, threats7.gd, cores.gd,
creep.gd, machine_react7.gd, last_protocol.gd, lp_setup.gd, lp_defence.gd, lp_garrison7.gd (placing new units /
defences / the hospital in the LP starting base: Q15), sentinels7.gd, pads71.gd (register through its API only),
flow71.gd, existing tools/art generators.

## 3. Per agent: inputs, Done-when fed, sim cost, riskiest question, ambiguities
Sim-cost rule (every agent; from the 2026-11-09 amendment: final build <= 1.7x G6 on 2k, every later wave ~0):
(a) **unused = hash-identical**: with your code in, the 2k fight, 2k mixed (river_crossing_s, human_a vs human_b) and
10k 200-tick hashes equal `fact w2.bench_ref`, and your systems' profiled share there is <= 0.05 ms/tick
(`tools/perf71_prof.gd`; PROVISIONAL per-agent figure, Q18); (b) **used**: event-driven or staggered
(`(w.tick + id) % N`), budgeted by `sim/systems/tiers.gd` (REDUCED in huge fights), measured on the LP-peak case
(`fact bench.lp_peak`) and reported as ms/tick; (c) **render**: LP-peak and 2k fps p10 before/after your presentation
work, no measurable loss; (d) every timing run follows `orch.timing_lock` (seq 440).

### DAMAGE71 (B2, J1, J2, J3, G1 medics+)
- Inputs: none blocking. Consumers: FIRES71 / ARMY71 / BASTION71 call `Parts71.ignite` (fire stops nanite repair);
  CNOPS71's hospital reads triage tags + casualties; ARMY71's ammo71 picks rounds that ballistics8 resolves (one hook
  line in ballistics8 placed by DAMAGE71 on ARMY71's CR). SWARMNAT71: motion.gd corpse hand-off (CORPSE_CAP 240,
  CORPSE_LIFE 45 s today) and snapshot fields by CR.
- Done-when: 9 (gore hash-identical; fps holds while bodies accumulate 60 min), 1, 3, 4 (machines fight with parts), 7
  (all new state saved + hashed).
- Riskiest: bodies "stay all match" while LP peak is already ~22 fps p10 vs the 60 gate (PERFDRAW71-8, seq 698):
  settled bodies must cost ~0 per frame (baked / instanced), or J1 breaks Done-when 3 + 9.
- Ambiguities: Q1 (B2 on Machines in skirmish?), Q10 (walkers collapse into walls vs "wall damage not picked"),
  Q16 (gore ART is wave 5: wave 2 builds outcomes + functional drawing), J2 black tag outcome (death timer number
  PROVISIONAL).

### FIRES71 (B4, D5, B1 thermobaric + incendiary, B6, G1 FO / JTAC, G2 MLRS)
- Inputs: pads71 + hot-pit (AIRFIX71 done) for the Conductor; `Parts71.ignite` (DAMAGE71). Consumers: BASTION71
  (turret sectors, FPF laying of wall turrets) and ARMY71 (squad sectors, MG crews in FPF) call `KillZone71.allow` /
  `Fires71.fpf_aim` in their own files. Counter-battery needs an enemy indirect shooter: today's Machine artillery
  stand-in; the siege walker is wave 3.
- Done-when: 1, 3, 4 (fires + FPF used in the LP soak), 5 (Conductor is a look-checkpoint sample later; functional art
  now), 2 (Conductor must not break the AIRFIX matrix: run test_airfix71 after air work).
- Riskiest: FPF "every assigned weapon fires its max rate" for 30-60 s on all faces at LP peak = a per-tick burst;
  and D5's "never step 16" across any selection size (company / army) plus auto zones for everything.
- Ambiguities: Q1 (fire support / kill zones in skirmish? Off-LP turret / unit sector filtering touches native
  find/act: Q2), Q6 (illumination in B4 vs I5), Q7 (does gas belong in the radial?), Q19 (B4 "gunship" entry =
  the Conductor orbit?).

### ARMY71 (D4, B3, B5, G1 NVG / thermal, I2 hand-to-hand, G2 flame tank)
- Inputs: ORCH grant of combat.gd / morale.gd / accuracy8.gd / stray8.gd after PERFSIM71-7 is confirmed ended (Q3);
  `fact killzone71.api` (FIRES71) for sectors of fire; `Parts71.ignite` for the flame tank. Consumers: every other
  agent's combat / accuracy hook lines (CRs to ARMY71); radio line fragments (lines71_<agent>.json) from all agents.
- Done-when: 1, 3, 4 (discipline + crews in the LP soak), 7.
- Riskiest: D4 touches every soldier. If it runs outside LP it moves the 2k bench hash and cost (headroom to 1.7x is
  ~0.45 ms) and off-LP target choice is mirrored by native find / act (WallFire7.any keeps LP on GDScript).
- Ambiguities: Q1, Q2, Q5 (B5 "researched during the match" vs LP research_all + H7), Q13 (radio voice now or text),
  Q12 (B3 crews = new units vs reworked MG units: brief reads new team units; confirm).

### BASTION71 (B1 rail / laser / HPM, G3, I2 minus hand-to-hand, G1 engineers+, G2 dozer)
- Inputs: `fact killzone71.api` + `Fires71.fpf_aim` (FIRES71) in turret retarget; DAMAGE71's decal API for casing
  piles (new decal kind by CR); `Parts71.ignite` for fire-pour points. Wrecks-as-cover (C6), sappers / body-piles
  (C3 / C5) and Glass stalkers (C4) are wave 3: dozer clear / fill, fire-pour and sensors are built against today's
  stand-ins (threats7 burrower exists) with the API wave 3 plugs into.
- Done-when: 1, 3, 4 (turrets + walls in the LP soak), 7.
- Riskiest: "disabled, not dead" turrets + engineer / drone revives change LP balance (brutal-but-winnable, Pre-start
  decisions) and the rotary railgun's over-penetration at minigun rate is a per-shot pierce cost at 1,000+ machines.
- Ambiguities: Q11 (I2 "no heat wear / modules / target priority added" vs B1 per-weapon heat), Q12 (rotary railgun /
  HPM / laser CIWS new vs reworks of a_t7_railgun / a_t7_microwave / G6 Laser CIWS), Q14 (minimap.gd for sensor
  contacts), Q15 (LP base placement).

### CNOPS71 (D7, H8, J6, J10, B7)
- Inputs: RAMP71 done (cn_facility.gd + transport.gd free, test_cnfac7 green); DAMAGE71 triage / casualty API (into the
  hospital); ARMY71 places the mask accuracy / vision factor in accuracy8 (CR) and the radio fragment loader; FIRES71
  API for "call support"; pads71 for medevac helicopters and Vanta2. Wave-3 J5 (infection) will call the quarantine
  lockdown API this agent builds; wave-3 C2 will trigger "facility under siege".
- Done-when: 4 (CN missions purge nodes with 0 stuck states), 8 (airlock cycle <= 70 s; the core raid half is wave 4),
  10 (gas + masks + filter wear; the quarantine lockdown machinery, with a test stand-in until J5), 1, 2 (medevac helis
  and Vanta2 keep the AIRFIX matrix green), 3, 7.
- Riskiest: Done-when 8: G7 measured 83.5 s for the hardened 8-APC exit against a ~70 s target (G7_REFERENCE 13.9c-50)
  and Done-when 8 adds heal + rearm inside the same 70 s.
- Ambiguities: Q8 (which 70 s), Q7 (gas source + wind before I3), Q9 (hospital footprint in the fixed facility),
  Q5 (H8 "facility upgrades during the run" vs H7), Q1 (D7 / B7 in skirmish), Q20 (facility under siege trigger).

## 4. Names ORCH registers (tests run with `bash tests/run.sh --only=<file>`; flows `tools/pt71_<flow>.gd`)
| Agent | Tests | Playtest flows | Commands / systems (sent as change_request with exact SYSTEM_ORDER slot) |
|---|---|---|---|
| DAMAGE71 | test_damage71, test_gore71, test_care71 | damage71, gore71, care71 | Parts71 + Gore71 + Care71 ticks (after Wounds); `triage_tag`, `give_morphine` (player overrides) |
| FIRES71 | test_fires71, test_killzone71, test_conductor71 | fires71, killzone71, conductor71 | Fires71, KillZone71, Conductor71 ticks; `fire_mission`, `fpf_fire`, `fpf_paint`, `kz_paint`, `kz_clear`, `belt_lay`, `belt_ignite`, `conductor_orbit` |
| ARMY71 | test_army71, test_crew71, test_ammo71 | army71, crew71, ammo71 | Discipline71 + Crew71 ticks (after SquadAI), Ammo71; `ammo_select`, `ammo_research`, `crew_rate`, `barrel_swap` |
| BASTION71 | test_bastion71, test_walls71 | bastion71, walls71 | Turrets71, Walls71, Sensors71 ticks; `wall_tier`, `gate_reinforce`, `choke_seal`, `lift_use`, `turret_revive`, `berm_build`, `doze_clear` |
| CNOPS71 | test_cnops71, test_facility71, test_hospital71, test_gas71 | cnops71, facility71, hospital71, gas71, vanta71 | CnMission71, Hospital71, Gas71 ticks; `cn_search`, `cn_abort`, `cn_roe`, `fac_upgrade`, `hosp_*`, `gas_release`, `mask_on` |

Command names are PROVISIONAL: each agent sends its exact list in its first 10-15 tool calls, as FLOW71 did (seq 16).

## 5. Open questions for ORCH (not resolved here)
- **Q1 (changes scope for 4 agents). LP-only or every mode?** Scope headers C, F, G, H, I, J say Last Protocol; A, B,
  D, E do not, and G71_COMMON says "Last Protocol only where the scope says so". So B (B1-B7), D4, D5 and D7 read as
  every mode. But ROADMAP G9 lists "armour and ballistics (facing, angle, weak spots, ammo types) for every match type"
  and G12 lists "combined arms ... recon and sniper teams" for every mode, which suggests G7.1's versions are LP; and
  the 2k bench is a skirmish fight (human_a vs human_b), so D4 / B3 / B5 / D5 running in skirmish moves its hash and
  cost against the amended bar (headroom ~0.45 ms) and changes target choice that native find / act mirror off LP (Q2).
  Machines are not on the 2k bench, so B2 off LP is a skirmish balance question, not a bench one. Needed: per part,
  LP-only or every mode.
- **Q2. Native combat off LP.** If any targeting rule (D4 threat choice / focus fire, D5 sectors, I2 disabled towers
  with def.weapon, B2 sensor blindness) runs off LP, native find / act need a port or a hand-back bit (native/ is
  SWARMNAT71's). Rules inside `_fire` (accuracy, damage, rounds) are safe: shots are handed back to GDScript. LP is safe
  today: `WallFire7.any(w)` keeps combat on GDScript there. Who ports, and when? (Only if Q1 says every mode.)
- **Q3. Live agents and their files.** PERFSIM71-7: handoff at seq 744 but a status at seq 767 ("waiting: cut7.sh
  lean_vis oracles"). Is it ended, and do its cut7 edits stay? ARMY71 takes combat.gd / morale.gd / accuracy8.gd /
  stray8.gd after that. RAMP71's grant names cn_facility.gd, but its status says the ramp code lives in transport.gd:
  confirm its file set (CNOPS71 takes both after it). Post `fact w2.bench_ref` (hashes + G6 / G7.1 ms).
- **Q4. Snapshot fields and draw hooks.** render_snap.gd, entity_layer.gd, motion.gd are SWARMNAT71's. All 5 agents
  need snapshot fields (parts / plates, gore records, turret heat / disabled, sectors / FPF, NCO signals, masks, gas,
  CN mission steps, Conductor / Vanta2 banking + trail); DAMAGE71 also needs motion.gd's corpse hand-off. Options: one
  generic hook added once (e.g. a `g71` dict in the snapshot filled by per-system providers, each in its owner's file),
  or CRs batched through SWARMNAT71 / ORCH. Briefs say "snapshot fields by change_request" until ORCH decides.
- **Q5. "Researched / upgraded during the run" before H7.** B5 ammo tiers ("unlocked and upgraded through the match"),
  G3 wall armour tiers and H8 "facility upgrades during the run" are wave 2; H7 (wave 4) is the LP siege tech tree and
  lists ammo tiers B5 and wall tiers G3 as items; LP starts with `LpSetup.research_all`. Does wave 2 build an interim
  unlock path (cost + time, PROVISIONAL) that H7 later absorbs, or only the mechanic + an unlock API?
- **Q6. Illumination.** B4's radial lists illumination; I5 (wave 5) says illumination rounds are "added to B4's radial
  menu". Does FIRES71 build the entry + lit-area state now (I5 adds the darkness penalty), or leave the slot for I5?
- **Q7. Gas source and wind.** J10 says what the gas does, not how it is released (a radial fire mission, a CN weapon /
  grenade, facility vents, a turret?). It says "wind carries it (I3)", but I3 wind is wave 5. Does CNOPS71 build a
  minimal deterministic wind field now (I3 later shows it on the HUD and drives smoke / fire with it)?
- **Q8. Which 70 s.** Done-when 8: "a CN team cycle through the airlock (return -> heal -> rearm -> redeploy) in <= 70 s".
  H8 calls it "the 13.9c-50 ~70 s exit target that G7 missed", which was 8 APCs out under pressure (83.5 s hardened).
  The Done-when cycle only, or both? Does a soldier kept in a hospital ward count inside the 70 s?
- **Q9. Hospital footprint.** J6 "replaces the aid station" and is "bigger"; the aid station is a zone of the fixed CN
  facility (cn_facility.gd zones, defs_g7_facility.json) on the fixed LP map. Inside the facility, a new building
  beside it, or a base layout change? CNOPS71 surveys and proposes; ORCH / owner approves.
- **Q10. Walkers collapsing into walls** (B2) vs Settled "Not picked: wall damage / breach holes". Does the collapse
  hurt the wall, or only lie against it as a wreck? (No breach holes either way.)
- **Q11. Heat.** I2 [PROPOSED]: "no turret ammo feeds, heat wear, target priority or modules ... nothing else is
  added"; B1 gives the rotary railgun and laser CIWS heat build-up / forced cooldown. Reading: B1's per-weapon heat
  stays, no general turret heat-wear system. Confirm.
- **Q12. New or rework.** G7 ships a_t7_railgun (rail cannon, pierce), a_t7_microwave (soft-kill cone), a_t7_thermite
  and the G6 Laser CIWS (counterdrone.gd); G6 has a_mlrs and flak defs; MG units exist. Are B1's rotary railgun / laser
  CIWS / HPM, G3's flak tower, G2's MLRS and B3's MG crews new defs beside these, or reworks of them?
- **Q13. Radio voice now or text.** D4 callouts and D7 team-leader reports: voice now through the in-house pipeline
  (tools/audio/render_voice_g7.py, sapi_render.ps1, presentation/audio/radio_queue.gd), or a text feed now and voice
  with the wave-5 sound pass (H10 / E1)?
- **Q14. Unowned files** (section 2 list): change_request to ORCH, or grants (e.g. minimap.gd to BASTION71 for sensor
  contacts, the Vanta flight functions of air.gd to CNOPS71)?
- **Q15. LP starting base.** Who places the new units / defences / hospital in the LP base (lp_setup.gd,
  lp_garrison7.gd, lp_defence.gd are unowned) and how many of each (PROVISIONAL counts per agent, or ORCH sets them)?
- **Q16. Art depth now.** Build order puts the gore art and the full art roll-out (after the look checkpoint) in
  wave 5. Briefs say: wave 2 builds outcomes + functional art at the G7 detail level (`fact art.detail_level`) through
  new tools/art generators, no full art roll-out. Confirm.
- **Q17. Stale budget fact.** `perf71.budget` (seq 110) was written for the retired <= G6 bar. Re-post for 1.7x.
- **Q18. Per-agent unused budget.** 1.7x G6 = ~27.1 ms vs 26.67 today: ~0.45 ms for waves 2-6. Briefs use
  hash-identical on the bench + <= 0.05 ms/tick profiled share per agent (PROVISIONAL). Confirm or set.
- **Q19. B4 "gunship" radial entry** = calling the CONDUCTOR orbit (B6), or a separate gunship call (e.g. Vanta)?
- **Q20. H8 "late in the run the hive targets the facility itself"**: the hive side is C1 / C2 (wave 3). Briefs say
  CNOPS71 builds the facility's response (defences, staged lockdown, evacuation) with a test trigger and an API for
  the director. Confirm.

## 5A. ORCH answers (2026-11-09, binding for wave 2; PROVISIONAL marks a call the owner may change)
- **Q1: Last Protocol only.** The frozen GOAL block's Out-of-scope line says "skirmish changes beyond what A1-A5 touch".
  So every wave-2 feature (B1-B7, D4, D5, D7, G, I2, J) is gated on the LP mode; skirmish and the 2k/10k benches stay
  hash-identical to `fact w2.bench_ref`. ROADMAP G9/G12 carry the every-mode versions.
- **Q2: moot** (Q1). LP stays on the GDScript combat path (`WallFire7.any`); target-choice rules live there. No native
  port in wave 2.
- **Q3:** PERFSIM71-7 has ENDED (its seq-767 line was a background heartbeat). Its lean_vis cut was NOT installed
  (sim/systems/fog.gd == .plan/perfsim71/chk/fog.gd.orig7). RAMP71's file is sim/systems/transport.gd
  `_tick_bay_boarder` (CR 778 granted); CNOPS71 takes transport.gd + cn_facility.gd after RAMP71 reports.
  `fact w2.bench_ref` is posted on the board.
- **Q4: one generic snapshot hook.** SWARMNAT71 adds, as a small first change, a `g71` dictionary in render_snap filled
  by per-system providers (`RenderSnap.register_g71(key, callable)`); each wave-2 agent writes its provider in its OWN
  file and draws its new visuals in its OWN new layer under presentation/view/*71*.gd or presentation/ui71/. Edits to
  entity_layer.gd / motion.gd (incl. DAMAGE71's corpse hand-off) go by change_request to SWARMNAT71. Until the hook
  lands, build sim + tests first.
- **Q5: mechanic + unlock API now, no progression.** Each tiered item (B5 ammo, G3 wall armour, H8 upgrades) gets its
  tiers, effects and an `unlock(tier)` / `upgrade(tier)` API with PROVISIONAL cost/time in content JSON; LP keeps
  `research_all` (all unlocked) until H7 (wave 4) builds the run progression on top of the API. Tests drive the API.
- **Q6: leave the slot.** FIRES71 builds the radial with an empty illumination slot; I5 (wave 5) adds the rounds, the
  lit-area state and the darkness penalty, as the scope says.
- **Q7 (PROVISIONAL): gas comes from CN gas munitions** (CN team grenades / canister launchers) **and facility gas
  vents during a breach lockdown.** CNOPS71 builds a minimal deterministic wind field now (direction + strength,
  seeded, slowly changing); I3 (wave 5) shows it on the HUD and drives smoke / fire with it.
- **Q8 (PROVISIONAL): the gate is Done-when 8's team cycle** (return -> heal -> rearm -> redeploy <= 70 s, timed from
  the team's first unit entering the airlock to the last unit leaving it, redeployed). A soldier kept in a hospital
  ward is replaced or left out and does not count in the 70 s; report how many. Also measure and report the 13.9c-50
  8-APC exit, but it is not the gate.
- **Q9:** CNOPS71 surveys and proposes the hospital site (inside the facility vs a new building beside it) with a
  screenshot; ORCH approves before building. A change to the fixed LP base layout goes to the owner.
- **Q10: no wall damage.** A collapsing walker lies against the wall as a wreck (the Settled list rules out wall damage
  and breach holes).
- **Q11: confirmed.** B1's rotary railgun and laser CIWS keep their own heat build-up / forced cooldown; no general
  turret heat-wear system (I2).
- **Q12: new defs, old ones untouched.** B1, G3 flak, G2 MLRS / flame tank / dozer and B3 MG crews are new LP defs in
  content/g71 (new ids only), reusing existing code paths and art bases where that is exact; G6/G7 units are unchanged.
- **Q13: text now, voice in wave 5.** Callouts and team-leader reports go through presentation/audio/radio_queue.gd as
  text (subtitle) entries with line ids in `lines71_<agent>.json`; the wave-5 sound pass (H10 / E1) voices them with
  the in-house pipeline.
- **Q14: grants.** minimap.gd sensor-contact drawing -> BASTION71; air.gd Vanta flight functions -> CNOPS71 (AIRFIX71
  is done); every other unowned file: change_request to ORCH.
- **Q15: ORCH adds one LP-base hook** in lp_setup.gd that reads `content/g71_lp/lp_base_<agent>.json` (NOT content/g71/: the content merger would load it as a unit fragment; caught by FIRES71-1) (placements +
  counts, PROVISIONAL, proposed by each agent); ORCH owns the hook and approves the counts.
- **Q16: confirmed.** Wave 2 builds outcomes + functional art at the G7 detail level; gore art and the full art
  roll-out wait for the wave-5 look checkpoint.
- **Q17:** `perf71.budget` re-posted for the 1.7x bar.
- **Q18: confirmed.** Unused: hash-identical on the 2k fight / 2k mixed / 10k and <= 0.05 ms/tick profiled share per
  agent. Used: budgeted by tiers.gd, measured on bench.lp_peak and reported.
- **Q19: yes,** the radial "gunship" entry calls the CONDUCTOR orbit (B6).
- **Q20: confirmed.** CNOPS71 builds the facility's response (defences, staged lockdown, evacuation) with a test
  trigger and an API; the hive director (C1/C2, wave 3) calls it.

## 6. Kept out of wave 2
- G8+: view rotation and the art detail upgrade (G8), Machine overhaul and armour / ballistics for every match type
  (G9), human depth for every mode (G12), co-op (parked).
- Later G7.1 waves: C (hive units, director, Hollow King, Glass stalkers, wrecks as cover), F (robots, drone bay rework,
  mules), H4-H6, I6-I7, J4 harvesters, J5 infection, J8 Lazarus walker (wave 3); D1-D3, D6, H1-H3, H7, H9, H11, I1,
  G4-G6, J9, J11-J15 (wave 4); E1, E3, H10, H12, I3-I5, I8, J7, gore art (wave 5); E4 (wave 6). Where a wave-2 part
  names one of these (B2 brutes, B4 siege walker, G1 UCAV, G3 burrowers / stalkers / body-piles, J1 harvesters), the
  brief builds against today's stand-ins and exposes the API the later wave plugs into.
