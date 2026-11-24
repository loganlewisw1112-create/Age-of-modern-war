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

## Complete (ART look samples — approved-core)
- Owner **2026-11-24**: remove TECHNICAL + SAFEHOUSE mockups; continue with approved
- **LOCKED:** CELL / DEATH / WALKER / CLOSE AIR — FACT `art.look.approved.core` seq **268**
- **DEFERRED:** TECHNICAL + SAFEHOUSE/HATCH — FACT **269**/**270**; CLAIM **248** RELEASED **271**
- Look package regenerated (2×2 approved strips); safehouse states strip omitted
- Bulk wave1: `g10_coalition.gd` → 30 approved clones + 31 deferred ids; catalog group wired
- Lock exception: `.superpowers/sdd/g10-lock-deferred-exception.md` (Done-when #13a)
- Reports: `task-8-art-approved-core-defer-report.md` · `dispatch-art-bulk-approved.md`

## Complete (ART bulk wave2 — runtime unblock)
- Fleet/army role marks on 26/30 approved clones; facings + kit strips
- Step 4 tests: `test_g10_content` **13/0**; orphan_art = deferred-only (31)
- FACT `ship.art.bulk.approved.wave` — report `.superpowers/sdd/task-8-art-bulk-wave2-report.md`

## Complete (ART bulk wave3 — Ghost + camo + CLOSE AIR)
- Ghost Wing 17 ids (Judge/Warden/Shade/Sergeant + Mk/ace) from Death kit; no purple
- Camo states (7) per Ghost id; CLOSE AIR Silent Rotor gunship + drone/transport active frames
- Tests: `test_g10_content` **15/0**; FACT `ship.art.bulk.wave3`
- Report: `.superpowers/sdd/task-8-art-bulk-wave3-report.md`
- Leftover for g10.lock: Step 9 final contact + owner look gate (deferred exception OK)

## Complete (docs — G10 close / deferred art)
- Parallel docs track (Auto): owner-deferred TECHNICAL / SAFEHOUSE / HATCH recorded for lock
- Note: `.superpowers/sdd/g10-deferred-art-note.md`
- SCOPE addendum: `game/docs/G10_SCOPE.md` — deferred subjects only; **no** weaken of other Done-when
- PLAY_ME: `game/docs/PLAY_ME_G71_2026-11-22.txt` — G10 near-lock + deferred-art ship note
- Lock exception (prior): `.superpowers/sdd/g10-lock-deferred-exception.md` (Done-when #13a)

## Complete (E4 lock — Task 23)
- ORCH/VERIFY10: CLAIM `orch.e4.lock` → FACT `ship.g10.lock` / `g10.lock` CLOSED
- Fresh smoke **122/0** (all `test_g10_*` + `test_exo` + `test_lpmode7` + `test_lp_save71`)
- Stage hashes 3/8/12 MATCH; AI soak + 100-squad stress green; peak SKIP (no G10 tool)
- Lock file: `.superpowers/sdd/g10.lock` · report: `.superpowers/sdd/task-e4-lock-report.md`
- Deferred exception: TECHNICAL / SAFEHOUSE / HATCH (owner) — lock proceeded
- Package `package_g71.ps1 -Note g10.lock` + README/PLAY_ME/SCOPE/ROADMAP closed
- Optional leftover: Ghost strip owner look only (non-blocking)

## Complete (post-lock ART amend — anim + air)
- ART10: `5354846f` / board note `84a94012` — real Human A anim boards + unique Coalition air fleet
- Board FACT `ship.art.g10.anim_air_overhaul` seq **294–295**; lock amend FACT `g10.lock.amend.anim_air`
- Report: `.superpowers/sdd/task-art-g10-anim-air-overhaul-report.md`
- `g10.lock` AMENDED (remains CLOSED); TECHNICAL / SAFEHOUSE / HATCH still deferred
- Tests: `test_g10_content` **15/0**

## Complete (post-lock ART polish — exo NVG + laser + transport)
- ART10: exo NVG UP/DOWN + green laser + fire hold; `x_stealth_transport` tilt-rotor redesign
- Board FACT `ship.art.g10.exo_nvg_transport` seq **297**; **g10.lock amend still needed**
- Report: `.superpowers/sdd/task-art-g10-exo-nvg-transport-report.md`
- Tests: `test_g10_content` **15/0**

## Live (≤6)
- (none for G10 lock — CLOSED / amended; lock amend for exo/nvg/transport pending ORCH)

## Free slots
≤6 free (G10 closed).

## Queued / next dispatch
1. Optional: Ghost strips owner look (non-blocking)
2. TECHNICAL / SAFEHOUSE / HATCH redesign — **later** (design-blueprint)
3. G11+ per ROADMAP

## OWNER ADDENDUM 171 — FOLDED
Board FACT `g10.owner.addendum.counterghost` seq **171**. CG10 Task17 shipped (loadouts Interceptor/Bulwark/Seeker/Ward, Shade Dart, 13 vehicle homes, weaker-than-Death, no CN/Blackglass). See FACT g10.cg.task17 seq 202 + FACT ship.cg10 seq **209**.

## Closed E3 NEEDs
- NEED 164: CoalitionTech10 wired into Progression/Production/Construction/Market (command path)
- NEED 183: SimWorld.validate_config Coalition `playable_stages_for`

## Still deferred (non-blocking E3)
- NEED 175: company templates in rules_g10_coalition (IDENT/ORCH) — E4 content if needed
