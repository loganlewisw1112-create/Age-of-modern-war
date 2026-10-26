# G61-REAL61: suppression, fatigue, veterancy and traits (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: real61.

The human factors every level of the chain reads. Morale (sim/systems/morale.gd) already has cover flags, suppression
decay, morale, break/rally: deepen it, don't fork it.

## 1. Suppression (morale.gd)
- Incoming fire (hits AND near misses within a radius, scaled by weapon calibre/explosive) builds suppression.
- States: alert > suppressed (accuracy and speed down) > pinned (prone, won't advance, returns fire weakly) > broken
  (existing break/rally). Cover, height, veterancy, leaders nearby and traits resist it.
- MGs and artillery suppress strongly (content fields per weapon, e.g. `suppress`, defaulted by weapon class).
- Effects go through the existing G6Hooks multipliers (accuracy_mult / speed_mult; ORCH owns g6_hooks.gd: post a
  change_request with the exact one-line calls you need, or expose `Morale.acc_mult(w, e)` / `Morale.speed_mult(w, e)`
  for ORCH to wire). Prone state readable for SQUAD61 (`Morale.is_pinned(w, e)`).

## 2. Fatigue (new sim/systems/fatigue.gd)
- Infantry tire from marching (distance), running/assaults, carrying heavy weapons, combat time; vehicles' crews tire
  slowly. Rest (idle/out of combat, faster in a garrison/near HQ/medic) restores it.
- Effects: speed, accuracy, suppression resistance down at high fatigue; exhausted units won't assault.
- AI reads it (`Fatigue.level(w, e)`, 0..1) to rotate tired units and pace marches.

## 3. Veterancy (new sim/systems/veterancy.gd)
- XP from damage dealt, kills, surviving combat, objectives (officers gain from their unit's success).
- Ranks green > regular > veteran > elite > hero with modest bonuses (accuracy, suppression resistance, reload, morale);
  a small chevron in the inspector and on the unit (presentation hook data; ORCH places it).
- Companies keep a reputation (average veterancy); replacements arrive green and dilute it.

## 4. Traits
- Leaders (captain, lieutenant, commander, AI general slots) get 1-2 traits at spawn, deterministic from the seed:
  cautious, bold, tactician, aggressive, stubborn (holds longer), logistician, inspiring (morale aura), recon-minded.
  Soldiers may get one minor trait at veteran+ (marksman, steady, fast, medic-trained).
- Expose `Veterancy.traits(w, uid)` and `Veterancy.trait_weight(w, uid, key)` (numbers GEN61/OFF61 read to shape
  decisions); post `fact realism.api` as a stub within 15 calls.

## Content and UI
new content/g6/rules_g61_realism.json (all numbers PROVISIONAL); new presentation/ui6/realism_info.gd returning inspector
lines (suppression state, fatigue bar, rank, traits) that ORCH wires into the inspector.

## Tests (tests/test_real61.gd)
MG fire pins a squad in the open but not one in heavy cover; pinned units don't advance; suppression decays; fatigue
grows with a long march and recovers at rest; exhausted units refuse to assault; XP accrues and rank changes at the
thresholds with the stated bonus; traits deterministic from seed; save/load + determinism.
Keep test_morale* / test_combat* / test_perf_g6 green; report 2k-unit ms/tick before/after.
Playtest flow tools/pt61_real61.gd: MG pins a squad (shot), a veteran's inspector lines (shot).
