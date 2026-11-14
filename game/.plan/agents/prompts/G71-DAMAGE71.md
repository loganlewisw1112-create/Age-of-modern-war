# G71-DAMAGE71: what a hit does to men and machines, the wounded, and the gore (B2, J1, J2, J3, G1 medics+)

> **ORCH 2026-11-09:** every roster question is answered in `.plan/orch71/wave2_roster.md` section 5A. Read it before your first step; it overrides any "if" in this brief. Q1: Last Protocol only.


You are DAMAGE71. Read `G71_COMMON.md` first (and through it G7_COMMON.md) and follow it. Budget: MAX_TOKENS 750000,
MAX_TOOL_CALLS 140 (hand off at 70%: `max(est + 90k, 312k + 2.3k x calls) >= 525k` or calls >= 98). Scope:
`docs/G71_SCOPE.md` parts **B2, J1, J2, J3** and the **"Combat medics+"** bullet of G1, the Pre-start decisions
(incl. the 2026-11-09 sim-gate amendment) and Done-when 1, 3, 7, 9, in full. Roster: `.plan/orch71/wave2_roster.md`.

## The owner's words
- B2: "Component damage: legs (limp / stop), weapons (go silent), sensors (blind, wild fire), armour (core exposed).
  Each machine type has its own part layout and weak spots" ... "armour plates shear off visibly; shallow-angle hits
  ricochet with sparks; armour thickness and angle vs round class (extends ballistics8's 27 round classes)" ...
  "Nanite self-repair: damaged machines regrow unless burned, EMP'd or finished ... Forces commitment over chipping" ...
  "Heavy death physics: brutes topple and crush what's under them; walkers collapse into walls; wrecks keep momentum".
- J1: "Full graphic gore, no slider": one wound outcome per ballistics8 round class (rifle bleeding / knock-downs, MG
  heavier, .50 / anti-materiel severed limbs + bodies thrown, cannon body destroyed, railgun clean through-holes often
  several soldiers in a line, airburst shredded, thermobaric charred and thrown). "Bodies and broken machines stay all
  match unless dragged away"; blood soaks the ground; burn + char; crush + trample. "The sim records the outcome (limb
  lost, death); gore is drawn from those events, so results are hash-identical. Settled bodies become batched static
  images and count in the E2 perf gates."
- J2: crawling wounded (missing limbs crawl, scream, clutch wounds, call for medics); "medics tag green / yellow / red
  / black, save who can be saved first; black-tagged soldiers get morphine and are made comfortable".
- J3: "silver nanite fluid, sparks, cable entrails, pulsing cores"; "half-dead machines keep crawling, twitching and
  dragging their torso; a threat until finished".
- G1: "Combat medics+: triage, drag wounded, stabilise, run casualties to the aid station; a field surgery tent near
  the walls (extends G7 casualty care)".

## Before you start (ORCH fills these in)
- **ANSWERED, see roster section 5A (Q1)** (B2 on Machines outside LP, or LP only? J is LP by its header).
- **ANSWERED, see roster section 5A (Q10)** (does a walker collapsing into a wall hurt the wall? No breach holes either way).
- **ANSWERED, see roster section 5A (Q4)** (how you get snapshot fields + the motion.gd corpse hand-off).
- Gore ART (severed-limb / charred / viscera sprites at full depth) is wave 5 (Build order; roster Q16). You build the
  outcomes, events, persistence and a functional drawing path at the G7 detail level (`fact art.detail_level`).

## Step 1: survey and measure before building (mandatory)
1. Trace the hit pipeline today: `Damage.apply_hit` -> `Ballistics8` (round, v(d), pen, wound value) -> `Wounds.apply_hit`
   (zones, bleeding, out of action, crawl) / `Blast8.on_burst` (throw, concussion) / `Shrapnel.burst`, and
   `Medical.on_zero_hp` (wounded state, evac, hospitals). List every Machine def on the LP map (lp_setup + waves) with
   hp / armour / size, and which ballistics8 round classes hit our soldiers in LP (Machine weapons + stray8 friendly fire).
2. Measure the "before": on `fact bench.lp_peak` and a 20-min LP run, bodies on screen over time against motion.gd's
   CORPSE_CAP 240 / CORPSE_LIFE 45 s, fps p10, and the profiled share of damage / wounds / blast8 / medical.
3. Post `fact damage71.survey` (findings + numbers) and compiling stubs `fact parts71.api`
   (`Parts71.ignite(w, e, secs)`, `burning(e)`, `part_state(e, part)`, `can_fire(e)`, `acc_mult(e)`, `speed_mult(e)`),
   `fact gore71.api` (`Gore71.bodies_near(w, pos, r)`, `drag(w, body_id, to)`, `remove(w, body_id)`) and
   `fact care71.api` (`Care71.tag_of(e)`, `casualties(w, fid)`) within your first 15 tool calls. FIRES71 / ARMY71 /
   BASTION71 call `ignite`; BASTION71's dozer and wave-3 harvesters call `drag` / `remove`; CNOPS71's hospital reads tags.

## Step 2: build
1. **B2 parts** (new sim/systems/parts71.gd, content/g71/defs_g71_parts.json keyed by Machine def id): per type a part
   layout (legs, weapons, sensors, armour plates, core, cells) with weak spots; hits pick a part (one w.rng draw, same
   style as Wounds zones); effects: legs limp / stop, weapons silent, sensors blind + wild fire, armour gone = core
   exposed. Effects reach other systems through hooks: speed / accuracy / damage via `G6Hooks` (ORCH owns g6_hooks.gd:
   one change_request with the exact lines), "weapon silent" via one guarded `Parts71.can_fire` call in combat.gd
   (ARMY71 owns combat.gd: change_request). Expose a registration API so wave-3 units (brute, walker, burrower ...)
   add their layouts as data only.
2. **Plates + ricochets** (ballistics8.gd): plate thickness and impact angle vs round class (pen vs effective
   thickness); shallow angle -> ricochet event (sparks); plate shear event when a plate's hp is gone. Also place
   ARMY71's ammo-tier hook (`Ammo71.round_for`, guarded) where ballistics8 picks the round, on its change_request.
3. **Nanite self-repair**: damaged Machine parts regrow at a PROVISIONAL rate unless burning (`ignite`), EMP'd
   (MachineEW7 stun state) or finished; "silver flow over wounds" as an event / snapshot state for the view.
4. **Heavy death physics**: heavy Machines topple along their momentum, crush what is under them (deterministic, ids
   ascending), collapse against walls per the Q10 answer; the wreck keeps momentum then settles (wrecks as cover are
   wave 3: store settled wrecks in Gore71 with position / size so C6 can use them).
5. **J1 outcomes** (wounds.gd / blast8.gd / shrapnel.gd + new gore71.gd, rules_g71_gore.json): one outcome per round
   class (table in rules, PROVISIONAL numbers), railgun line-through using the shot line, burn + char (burning soldiers
   run a few steps then fall), crush + trample by tanks / heavy Machines / swarms. Every outcome is a saved + hashed
   record and an event; the view never decides an outcome. Bodies persist until dragged (medics recover ours; Gore71
   `drag` / `remove` for harvesters / dozers later). LP only (section J header).
6. **J1 drawing**: new presentation/view/gore71_layer.gd (+ .gdshader): settled bodies and wrecks baked into chunked
   static images or one instanced batch, so 60 min of bodies costs ~0 per frame; blood soak and drag trails in
   decal_layer.gd; burning / smoking bodies through the public fx61 API. The live corpse -> settled hand-off in
   motion.gd is SWARMNAT71's (change_request, or per the Q4 answer).
7. **J3**: viscera / sparks / cable "entrails" / pulsing cores as fx61 particles + decals (silver fluid); half-dead
   machines: at 0 hp a Machine with B2 parts and legs or torso left enters a crawling "half-dead" state (slow,
   still fights in reach) until finished. Its numbers PROVISIONAL.
8. **J2 + G1 medics+** (wounds.gd, medical.gd, new care71.gd, defs_g71_care.json): crawling wounded with limb loss
   (extends WOUND7 crawl), call-for-medic events; triage tags green / yellow / red / black (medics tag, save in tag
   order, ties by id); black tag -> morphine, made comfortable (outcome timer PROVISIONAL); medics drag, stabilise and
   run casualties to the aid station (CNOPS71's hospital replaces it later: route through Medical's def-driven hospital
   lookup, not a hard-coded building); a buildable field surgery tent near the walls. Player overrides as commands
   (`triage_tag`, `give_morphine`; ORCH registers: change_request with exact names and SYSTEM_ORDER slot).

## Files (write; everything else by change_request to its owner, see the roster)
sim/systems/damage.gd, ballistics8.gd, wounds.gd, medical.gd, blast8.gd, shrapnel.gd; new parts71.gd, gore71.gd,
care71.gd; presentation/view/fx_layer.gd, fx61_core.gd, fx61_engine.gd, fx61_tex.gd, decal_layer.gd (other agents call
the public fx61 API from their own files and ask you for new fx / decal kinds, e.g. BASTION71's casing piles); new
presentation/view/gore71_layer.gd (+ .gdshader), new presentation/ui71/triage_tags.gd; new content/g71/rules_g71_damage.json,
defs_g71_parts.json, rules_g71_gore.json, rules_g71_care.json, defs_g71_care.json; new tools/art/g71_damage.gd (+
assets/art/g71_damage/); tests/test_damage71.gd, test_gore71.gd, test_care71.gd; tools/pt71_damage71.gd, pt71_gore71.gd,
pt71_care71.gd. Not yours: combat.gd / accuracy8.gd (ARMY71), g6_hooks.gd + world.gd (ORCH), motion.gd / entity_layer.gd /
render_snap.gd (SWARMNAT71), machine_g6.gd / threats7.gd (unowned: ORCH).

## Rules
- **Sim cost** (amended bar: final build <= 1.7x G6 on 2k; every later wave ~0): with your code in, the 2k fight, 2k
  mixed and 10k 200t hashes equal `fact w2.bench_ref`, and your systems' profiled share there is <= 0.05 ms/tick
  (PROVISIONAL, roster Q18; `tools/perf71_prof.gd`). Per-hit work must early-exit on a precomputed per-def flag (no
  dictionary walks per shot). When used: event-driven, tiers.gd budgets it, measured on bench.lp_peak (ms/tick share).
  Timing runs follow `orch.timing_lock` (seq 440).
- **Native combat**: rules inside `Combat._fire` / Damage are safe (every shot is handed back to GDScript). Anything
  that changes WHO a unit targets (blind sensors) runs off LP only after the Q2 answer.
- **Determinism**: gore outcomes hash-identical between two runs (Done-when 9: write that test); save / load mid-fight
  keeps the same future (bodies, parts, tags saved).
- **Perf (Done-when 3 + 9)**: fps p10 on bench.lp_peak and 2k before / after your presentation work, and a 60-min
  body-accumulation run (sim-skipped is fine) showing the fps gates still hold. No visible quality trades.
- **Screenshots** as each visible thing lands (plates shearing, ricochet sparks, silver repair flow, bodies + blood,
  crawling wounded, triage tags, half-dead machine): look at them, then post `fact shots.best`.
- Tests: tests/test_damage71.gd (parts, plates / ricochet angles, repair blocked by fire / EMP, death physics crush),
  tests/test_gore71.gd (one outcome per round class, railgun line, persistence, two-run hash, save / load),
  tests/test_care71.gd (triage order, morphine, medic drag + stabilise, surgery tent). Flows (ORCH registers):
  `tools/pt71_damage71.gd`, `pt71_gore71.gd`, `pt71_care71.gd` (windowed, screenshots).
- Report: AGENT_RULES final report format. No commits. No GENESIS/postflight offer.
