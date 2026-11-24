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
- Task 14–15 GHOST10: 973129fb — Conductor + mission lifecycle; test_g10_ghost 11/0
- Task 16 GHOST10: (this ship) — insertion vehicles/drones/recovery kits; test_g10_ghost 15/0; exo.gd RELEASED for CG10
- CORE10 Task 4: b5999f1b — deepen core roster
- MECH10 Tasks 9–12: caadbb1e — tunnels/cells/IED/patron/weld
- AI10 Task 18: c12c7d71 — Coalition doctrine AI adapter

## Live E2 (Auto background, ≤6)
- ART10 Task 8 samples — CLAIM held; NEED owner approve before bulk
- ARMORY10 Task 7B — Exo Armory HANDOFF (ORCH commit pending)
- DARK10 Task 20 — HANDOFF (ORCH commit pending)
- RAID10 Task 5 — in progress

## Next
**CG10 Task 17** — claim exo.gd (RELEASED); honor owner addendum seq 171 (Counter-Ghost org/pads/Shade Dart)

## Queued
MODE10, RAID10/LATE10, VERIFY10, E3/E4

## OWNER ADDENDUM (2026-11-23 evening) — INFORM ORCH, DO NOT STOP LIVE
Board FACT `g10.owner.addendum.counterghost` seq **171**. Live E2 agents keep running.

**ORCH / CG10 backlog (fold into Task 17 when CG10 claims `exo.gd` after GHOST10):**
1. Counter-Ghost **full org** locked in `docs/superpowers/plans/2026-11-23-faction-depth-decisions.md` (Counter-Ghost Corps section).
2. Loadouts: **Interceptor / Bulwark / Seeker / Ward** (Ward = VIP pair that never peels).
3. Squads: **4-op / 6-op / Ward pairs / legends**; roles Lead · Sensor · Gunner · Specialist.
4. Specialties: Hound, Netman, Aegis, Seismic, Overwatch, EW Ward, Breach Medic, Suit Thief, Rooftop, Blackout Breaker, Duelist, Machine-Scarred (+ cores listed in plan).
5. Vehicles/air incl. **Shade Dart** (4-op lift-fan / no-traditional-rotor infil/exfil) + Watch Rotor, QRF Insert VTOL, CAP Knife, Medevac Hook, etc.
6. **HARD RULE:** each vehicle type has its **own** garage / bay / helipad / landing pad (plan table: Ghost-Runner Bay, Shade Dart Pad, Ward Coach House, …).
7. Keep weaker than Coalition Death; EaW intent UX; no CN/Blackglass in G10.
8. Align/extend Task 17 def IDs as needed — do not shrink scope back to thin mirror.

## Deferred ORCH
- NEED 164: wire CoalitionTech10 into Progression/Production/Market (E3)
- OWNER ADDENDUM 171: Counter-Ghost org + per-vehicle homes (queue CG10; do not preempt live E2)
