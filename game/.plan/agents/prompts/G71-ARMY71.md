# G71-ARMY71: a real army: discipline, infantry weapons, ammo tiers (D4, B3, B5, G1 NVG, I2 hand-to-hand, G2 flame tank)

> **ORCH 2026-11-09:** every roster question is answered in `.plan/orch71/wave2_roster.md` section 5A. Read it before your first step; it overrides any "if" in this brief. Q1: Last Protocol only.


You are ARMY71. Read `G71_COMMON.md` first (and through it G7_COMMON.md) and follow it. Budget: MAX_TOKENS 750000,
MAX_TOOL_CALLS 140 (hand off at 70%: `max(est + 90k, 312k + 2.3k x calls) >= 525k` or calls >= 98). Scope:
`docs/G71_SCOPE.md` parts **D4, B3, B5**, the **NVG / thermal** bullet of G1, the **hand-to-hand on the walls** bullet
of I2 and the **flame / thermite tank** bullet of G2, the Pre-start decisions (incl. the 2026-11-09 sim-gate amendment)
and Done-when 1, 3, 4, 7, in full. Roster: `.plan/orch71/wave2_roster.md`.

## The owner's words
- D4 "DISCIPLINE — a real army": "Formation keeping, no drifting; real cover use (hug, peek, bound cover to cover);
  threat-based target choice and focus fire; sectors of fire, overlapping fields, staggered reloads." "NCO leadership:
  sergeants keep squads tight, call targets and shifts; lose the NCO and the squad gets sloppy." "Radio callouts:
  'Contact front!', 'Reloading!', 'Man down!', 'Sector 3 is breaking!', tied to real events." "Hand signals + stacking:
  visible signals, stacking on doors, buddy-covered cover-to-cover moves."
- B3: "Crew-served MGs: belt-fed nests, sustained / rapid / cyclic rates, barrel overheat + swaps, beaten zones,
  traversing and searching fire." "AT teams for real: gunner + loader, reload cycles, backblast danger zone, top-attack
  vs brutes." "Anti-materiel snipers: .50 cal teams with a spotter who calls weak spots and cores at long range."
  "Grenadiers: airburst over swarms; frag / smoke / thermite types."
- B5: "AP / HE / HEAT / airburst / top-attack / incendiary / rail slugs, unlocked and upgraded through the match so
  firepower keeps pace with harder waves. Ammo use and supply drops (D2) make tier choice matter."
- G1: "Night vision / thermal gear: a real NVG / thermal edge at night; Glass stalkers (C4) show on thermal."
- I2: "Hand-to-hand on the walls: when crawlers reach the wall-walk: close combat, bayonets, shotguns, flamers."
- G2: "Flame / thermite tank: heavy flamer that burns swarms and stops nanite regrowth (B2)."

## Before you start (ORCH fills these in)
- **ANSWERED, see roster section 5A (Q1)** (D4 / B3 / B5 in every mode or LP only?). If every mode: D4 runs on the
  2k bench (human_a vs human_b), moving its hash and cost against the ~0.45 ms headroom, and off-LP target choice is
  mirrored natively (roster Q2: **ANSWERED, see roster section 5A (Q2)**). LP is on the GDScript path today (`WallFire7.any`).
- **ORCH: confirm roster Q3** (PERFSIM71-7 ended; its cut7 edits kept or reverted) before you edit combat.gd /
  morale.gd / accuracy8.gd / stray8.gd, and post `fact w2.bench_ref`.
- **ANSWERED, see roster section 5A (Q5)** (B5 unlock path before H7), **Q12** (MG crews / AT teams new defs or reworks), **Q13**
  (radio callouts voiced now or text now), **Q4** (snapshot fields for signals / stacking poses).
- Glass stalkers (C4) and brutes (C3) are wave 3: thermal seeing and top-attack are built and tested on today's units,
  with the hooks wave 3 uses. Art: functional at the G7 detail level (roster Q16).

## Step 1: reproduce the "before" (mandatory)
1. Read SquadAI (`leader_of`, bounding, cover), Formations7 (`formation_slots`, the G6.1 chunks-of-12 fix), Morale
   (cover flags, suppression, leader candidate cache), Companies (leader defs / chain of command), Combat (`_pick`,
   `_engage`, `_fire`, reload / cooldown, melee), Accuracy8 (visibility, thermal / NVG def flags), Senses7 (light / night,
   spot gate), AmmoBearer, and the native find / act hand-back rules in docs/NATIVE_COMBAT71.md s3-s8.
2. Headless probe (tools/army71_probe.gd + tests/test_army71.gd) on (a) an LP wall section under a Machine wave and (b)
   a field fight: log per squad every N ticks the drift from formation slots, % of soldiers in cover, target choice vs
   threat (did they shoot the biggest danger?), how many reload at once, what happens when the leader dies.
3. Post `fact army71.baseline` (numbers + method), then compiling stubs `fact discipline71.api`, `fact crew71.api`,
   `fact ammo71.api` (`Ammo71.round_for(w, e, weapon) -> String|null`) and `fact radio71.api` (line fragments:
   `presentation/audio/lines71_<agent>.json` + `Radio71.say(w_or_view, key, pos, team)`) within your first 15 tool calls.

## Step 2: build
1. **D4 discipline** (new sim/systems/discipline71.gd; squad_ai.gd, formations7.gd, morale.gd, combat.gd): formation
   keeping without drift (tighter slot error, catch-up rule); cover use: hug, peek, bound cover to cover with a buddy
   covering; threat-based target choice + focus fire (a squad target picked by threat score, deterministic ties);
   sectors of fire + overlapping fields from `KillZone71.sector_of` (FIRES71 API, guarded); staggered reloads (never
   the whole fire team at once). Show the before / after numbers from Step 1.
2. **NCOs**: sergeants keep squads tight, call targets and shifts; when the NCO falls the squad gets measurably
   sloppier (slot error, slower target switch, worse reload stagger: PROVISIONAL mults) until a new leader steps up
   (reuse the Morale leader map; never a full scan per tick).
3. **Radio callouts** (presentation/audio/radio_queue.gd + the fragment loader, new presentation/audio/lines71_army.json,
   new presentation/ui71/radio_feed.gd): "Contact front!", "Reloading!", "Man down!", "Sector N is breaking!" driven by
   sim events, rate-limited, one voice per event cluster (voiced per the Q13 answer through tools/audio). Other agents
   drop their own `lines71_<agent>.json`; you own the loader.
4. **Hand signals + stacking** (new presentation/view/signals71_layer.gd; sim state for stack positions): visible
   signals on leader orders, stacking on doors before entering a building, buddy-covered moves.
5. **B3 crews** (new sim/systems/crew71.gd, defs_g71_army.json): MG nests with sustained / rapid / cyclic rates,
   barrel heat + swaps, beaten zones (ground strike pattern at range), traversing and searching fire; AT teams (gunner
   + loader, reload cycle, backblast danger zone that hurts our own behind the tube, top-attack mode); .50 anti-
   materiel teams with a spotter who marks weak spots / cores (`Parts71.part_state`, DAMAGE71 API) at long range;
   grenadiers with airburst / frag / smoke / thermite (thermite calls `Parts71.ignite`). MG crews obey FPF (`Fires71.fpf_aim`).
6. **B5 ammo tiers** (new sim/systems/ammo71.gd, rules_g71_ammo.json, new presentation/ui71/ammo_panel.gd): per weapon
   class the allowed tiers (AP / HE / HEAT / airburst / top-attack / incendiary / rail slugs) mapped to ballistics8
   round classes; per-side unlock + upgrade levels "through the match" per the Q5 answer; tier choice per unit / squad
   / global; ammo use draws the side's stock. DAMAGE71 places your `Ammo71.round_for` hook in ballistics8 (send the CR
   with the exact line).
7. **G1 NVG / thermal** (accuracy8.gd, senses7.gd): soldier gear flags that remove the night penalty (NVG) or see heat
   (thermal) per rules; a hook for wave-3 Glass stalkers (`thermal_reveals`).
8. **I2 hand-to-hand on the wall-walk** (combat.gd melee path): when crawlers reach the wall-walk, close combat with
   bayonets, shotguns, flamers (defs / weapon classes); deterministic, ids ascending.
9. **G2 flame / thermite tank**: a heavy flamer vehicle (reuse the Turrets7 / Combat flame rules) that burns swarms and
   calls `Parts71.ignite` (stops nanite regrowth).
10. **Hooks you place for others** (they send the exact line by change_request; you add it guarded): `Parts71.can_fire`
   and sensor blindness (DAMAGE71), `KillZone71.allow` for units (FIRES71), the gas-mask vision / accuracy factor
   (CNOPS71, accuracy8).

## Files (write; everything else by change_request to its owner, see the roster)
sim/systems/combat.gd, accuracy8.gd, stray8.gd, spread8.gd, morale.gd, fatigue.gd, squad_ai.gd, formations7.gd,
orders.gd, companies.gd, senses7.gd, `formation_slots` + the helpers right below it in movement.gd (the rest of
movement.gd is unowned: CR to ORCH); new discipline71.gd, crew71.gd, ammo71.gd; presentation/audio/radio_queue.gd, new
presentation/audio/lines71_army.json; new presentation/ui71/radio_feed.gd, ammo_panel.gd; new presentation/view/
signals71_layer.gd; new content/g71/defs_g71_army.json, rules_g71_discipline.json, rules_g71_ammo.json; new
tools/art/g71_army.gd (+ assets/art/g71_army/); tests/test_army71.gd, test_crew71.gd, test_ammo71.gd;
tools/pt71_army71.gd, pt71_crew71.gd, pt71_ammo71.gd. Hotkeys / settings: CR to ORCH.

## Rules
- **Native combat (read docs/NATIVE_COMBAT71.md first)**: native find / act decide target choice off LP and hand every
  shot (`_fire`) back to GDScript. Changes inside `_fire` are safe. Changes to `_pick` / `_valid_target` / `_engage` /
  cooldown gating must be LP-gated or follow the Q2 answer; prove "native on == off" hash parity
  (`Combat.native_find` / `native_act` toggles, tests/test_perfsim71.gd) after every combat.gd change.
- **Sim cost** (final build <= 1.7x G6 on 2k; every later wave ~0): with your code in, 2k fight / 2k mixed / 10k 200t
  hashes equal `fact w2.bench_ref` (unless the Q1 answer puts D4 on the bench: then report the measured cost first and
  stop for ORCH) and your systems' profiled share there is <= 0.05 ms/tick (PROVISIONAL, roster Q18). Squad thinking on
  a staggered cadence; tiers.gd budgets used cost; measure on bench.lp_peak. Timing runs follow `orch.timing_lock`.
- **Determinism**: two-run hash identical; save / load mid-fight keeps the same future. **Player control first**: AI
  never overrides a fresh order and never moves a unit on Hold Position.
- **Perf**: fps p10 on bench.lp_peak and 2k before / after your presentation work; no visible quality trades.
- **Screenshots** as each visible thing lands (a squad holding formation + cover on the wall, an MG nest's beaten zone,
  an AT team's backblast, the sniper + spotter, grenadier airburst, hand signals / stacking, NVG at night, wall-walk
  melee, the flame tank): look at them, then post `fact shots.best`.
- Tests: tests/test_army71.gd (drift, cover %, threat choice, focus fire, reload stagger, NCO loss + recovery, callout
  events), tests/test_crew71.gd (MG rates / heat / swap, beaten zone, AT reload + backblast, spotter marks, grenadier
  types, melee), tests/test_ammo71.gd (tier -> round class, unlock / upgrade, stock use, save / load). Flows (ORCH
  registers): `tools/pt71_army71.gd`, `pt71_crew71.gd`, `pt71_ammo71.gd` (windowed, screenshots).
- Report: AGENT_RULES final report format. No commits. No GENESIS/postflight offer.
