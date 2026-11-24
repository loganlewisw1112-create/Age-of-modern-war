# G10 SDD Progress Ledger

Branch: g71 (pushed github/g71)
Plan: docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md
Scope: FROZEN — implementation open
Mode: Subagent-Driven + max safe parallelism ≤6
Subagents: Auto (owner usage limit)

## Complete
- Task 0: 45f3fbc9 — Stage E roster + CLAIM map (incl. ARMORY10, DOG10)
- Task 1: a3278b6d — shadow_coalition + 61-core seed
- Task 2: f2f0e511 — Coalition-only Stages 1–13
- Task 3: a889fb9a — doctrine facade + Coalition Command

## Complete (E2)
- Task 7C DOG10: 4fb11cc6 — Human A dog redesign; fleet71 4/0, anim61 10/0; pushed
- Task 13 TECH10: 6cb7c0e0 — buy/steal/unseal; test_g10_tech 6/0; NEED 164 wire deferred to E3
- Task 7 BLD10: 5432a16e — buildings/hidden/Ghost campus/Armory shell; test_g10_buildings 8/0
- Task 7B ARMORY10: c07d6dc3 — Exo Armory outfit/bay sim; test_g10_exo_armory 7/0; FACT ship.armory10; pushed
- Task 5 RAID10: 940b020d — Stage 1–6 raiders; test_g10_stage; FACT ship.raid10; pushed (with LATE)
- Task 6 LATE10: 940b020d — Stage 11–13 late syndicate; test_g10_stage 14/0; FACT ship.late10; pushed
- Task 18 AI10: Coalition AI + doctrine; test_g10_ai; HANDOFF/RELEASE; world wire E3
- Task 20 DARK10: four dark picks; test_g10_dark 6/0; FACT ship.dark10; world wire E3
- Task 14–16 GHOST10: Ghost vertical + vehicles; exo.gd RELEASED; ship.ghost16
- Task 17 CG10: 3f046cf6 — Counter-Ghost corps + Shade Dart; test_g10_counterghost 5/0; FACT ship.cg10 seq 209; addendum 171 folded; pushed
- Task 19 MODE10: HANDOFF 184 / RELEASE 185; test_g10_modes 8/0 (+ LP suites); NEED 183 world stage gate → E3; ORCH commit pending; FACT ship.mode10

## Live E2 (≤6)
- ART10 Task 8 samples — CLAIM 155 held; NEED 201 cycle2 pause_for_owner (do NOT regenerate; owner look gate)

## Free slots
~5 of ≤6 usable (only ART10 holds a live path CLAIM). No CG10 dispatch — Task17 shipped.

## Queued / next dispatch
1. ORCH commit wave: MODE10 (+ any unpushed HANDOFF leftovers) — no world.gd
2. VERIFY10 — independent smoke/hash once commit wave lands (or read-only evidence prep)
3. E3 ORCH — world.gd wires (BLOCKED until E3 wave): NEED 164 tech, NEED 183 stage gate, armory/dark/ai/buildings/mechanics/cg ticks
4. ART bulk catalog — only after owner FACT approve/revise on NEED 201

## OWNER ADDENDUM 171 — FOLDED
Board FACT `g10.owner.addendum.counterghost` seq **171**. CG10 Task17 shipped (loadouts Interceptor/Bulwark/Seeker/Ward, Shade Dart, 13 vehicle homes, weaker-than-Death, no CN/Blackglass). See FACT g10.cg.task17 seq 202 + FACT ship.cg10 seq **209**.

## Deferred ORCH (E3 — do not touch world.gd until E3 wave)
- NEED 164: wire CoalitionTech10 into Progression/Production/Market
- NEED 183: SimWorld.validate_config Coalition playable_stages_for
- NEED 175: company templates in rules_g10_coalition (IDENT/ORCH)
- world.gd seams: ExoArmory10, CoalitionDark10, CoalitionAi10, buildings, mechanics, CounterGhost tick if needed
