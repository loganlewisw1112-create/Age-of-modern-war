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
- Task 17 CG10: 3f046cf6 — Counter-Ghost corps + Shade Dart; test_g10_counterghost 5/0; FACT ship.cg10 seq 209/210; addendum 171 folded; pushed
- Task 19 MODE10: fdb8282f — Coalition Protocol LP + Stages 3/8/12; test_g10_modes 8/0; NEED 183 world stage gate → E3; FACT ship.mode10 seq 205/208; pushed

## Complete (VERIFY E2)
- VERIFY10 E2 closeout: FACT `verify.e2` seq **212**; STATUS `e2-ready-for-e3` seq **213**; report `.superpowers/sdd/task-verify-e2-report.md`
- Suite (Godot 4.7.2 headless): all present `test_g10_*` + `test_exo` + `test_lpmode7` → **116/0**; ART look open gate (not system fail)

## Complete (E3)
- ORCH E3 world.gd seams: CLAIM `orch.e3.world` **217**; NEED **164**/**183** closed; FACT `ship.e3`; smoke **91/0**; report `.superpowers/sdd/task-e3-world-report.md`
- Wires: validate_config `playable_stages_for`; SYSTEM_ORDER tech/buildings/mech/dark/GhostConductor; glue Progression/Production/Construction/Market + AiController CoalitionAi10; GhostConductor no double GhostExo tick
- ExoArmory10 API-only (no tick); CounterGhost via Exo; ART left unstaged

## Complete (E4 batch A — pre-lock)
- ORCH/VERIFY10 E4 batch A: CLAIM `orch.e4.batch_a` **224**; FACT `verify.e4.batch_a` **225**; STATUS `e4-awaiting-art-for-lock` **226**; RELEASE **227**
- Expanded smoke **118/0** (all `test_g10_*` + `test_exo` + `test_lpmode7` + `test_lp_save71`); report `.superpowers/sdd/task-e4-batch-a-report.md`
- Two-run hashes Stages 3/8/12 MATCH + LP profiles PASS; closest AI/100-squad probes green; peak SKIP (no G10 tool)
- **No** `g10.lock`; ART unstaged; lock waits owner look + package/docs
- Note: AI soak invariants OK but 7× `ai_air.gd:113` SCRIPT ERROR under Coalition `ai:true`

## Complete (ART look samples — partial)
- Cycle 8 **partial lock**: CELL/DEATH/WALKER/SAFEHOUSE/CLOSE AIR locked; TECHNICAL Humvee **excepted** (owner reject after approve)
- FACT `art.look.approved.except_technical` seq **246** (supersedes full `art.look.approved` **241**); NEED **240** closed **242**; RELEASE **155** **243**; CLAIM **248** TECHNICAL open; NEED **249** `g10.look.technical`; STATUS partial lock **250**; bulk **blocked** **251**
- Approve note: `.superpowers/sdd/task-8-art-samples-owner-approve-cycle8.md` · revise8: `.superpowers/sdd/task-8-art-samples-revise8-report.md`

## Live E2 (≤6)
- ART10 CLAIM **248** TECHNICAL revise9 Humvee (paths on samples.gd + x_technical_rocket*)

## Free slots
~5 of ≤6 usable. E3 world + E4 batch A released; TECHNICAL CLAIM held.

## Queued / next dispatch
1. ART10 revise9 TECHNICAL Humvee → owner re-approve NEED 249 → then unlock bulk
2. ART10 bulk catalog (Task 8 Steps 3–9) — **blocked** until TECHNICAL locked
3. E4 Task 23 — package `g10.lock` (**after** bulk + final catalog look gate)
4. Optional: harden `ai_air.gd` aircraft String coerce; full Task 21–22 soak/peak tools if required beyond closest probes

## OWNER ADDENDUM 171 — FOLDED
Board FACT `g10.owner.addendum.counterghost` seq **171**. CG10 Task17 shipped (loadouts Interceptor/Bulwark/Seeker/Ward, Shade Dart, 13 vehicle homes, weaker-than-Death, no CN/Blackglass). See FACT g10.cg.task17 seq 202 + FACT ship.cg10 seq **209**.

## Closed E3 NEEDs
- NEED 164: CoalitionTech10 wired into Progression/Production/Construction/Market (command path)
- NEED 183: SimWorld.validate_config Coalition `playable_stages_for`

## Still deferred (non-blocking E3)
- NEED 175: company templates in rules_g10_coalition (IDENT/ORCH) — E4 content if needed
