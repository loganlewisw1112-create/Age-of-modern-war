# 08 — Release phases, risk gates and acceptance criteria

## Strategy
All 32 decisions define the long-term UNDERSTRIKE target; **not all must ship in the first playable phase**. Build one shared canonical simulation and progressively deepen it. Every phase must be independently playable with complete basic controls, stable saves and understandable results. No release is considered done because a menu, mockup or empty UI panel exists.

## Phase 1 — Bunker foundation (minimum meaningful player slice)
**Includes:** Modern-Human-only bunker unlock; one constructible bunker object with architecture for 15 floors; initial floor and incremental expansion; basic geology clearance; modular rooms (security/barracks/workshop/storage/power/air); power and resource connections; initial autonomous policies and smart templates; surface/vertical cutaway/floor camera; one concealed multi-vehicle service elevator with real loading/animation/closure; basic save/load, attackable bunker entrance and operations linked to surface economy.

**Explicitly defer:** 12 complete borers, full population city simulation, full rail, catastrophic multi-floor cascade, advanced exotic tech and faction-wide subterranean wars. However, foundation models must already preserve 3D topology, resource flow, sector identity, geometry state, automation authority and future save schema.

**Phase 1 playable scenario:** A Stage 8 Modern Human commander places a bunker near the headquarters, excavates a second floor, builds an automated vehicle storage/workshop, sends two compatible vehicles down and back through the concealed elevator, inspects cutaway/floor without disrupting surface battle, saves and reloads in mid-operation.

## Phase 2 — Military UNDERSTRIKE
**Includes:** basic underground exploration/fog of war; core borer/infantry combined-arms subset from the approved 12-class roadmap; underground commanders; sector capture and security barriers; alternate entrances; vehicle surface breakthroughs; enemy temporary assault tunnels/raids; local geometry damage and selected structural disasters; tactical AI; maintenance/counter-recon.

**Phase 2 scenario:** Modern Human assaults surface through dynamically excavated point; Machine or Scavenger faction detects/raids a bunker through legal means but cannot build a bunker; human commander defends two sectors with no civilian micromanagement.

## Phase 3 — Networked civilization
**Includes:** multiple bunkers; connected roads/rail, transportation hubs, and automated cross-bunker shipments; resident cohorts and locally visible people; self-sufficiency loops; civilian districts; specialized research, discoveries and resource processing; remaining boring-class production and upgrade branches by incremental content batches; meaningful enemy attacks on logistics and research. High-speed maglev and sophisticated power unlock by stage.

**Phase 3 scenario:** Two disconnected bunkers become joined by tunnel+freight links, automatically transfer a produced vehicle and supplies, then recover when one route is disabled. A civilian bunker supports isolated residents at defined utility/food targets without player worker assignment.

## Phase 4 — High-fidelity advanced simulation
**Includes:** mature chunk-based geological simulation, complex groundwater and support behavior; cascading multilevel destruction with physically coherent persistent ruins, surface subsidence and advanced VFX; experimental hybrid-material fabrication and programmable tunneling; advanced vehicle variants, substantial region-scale underground command and optimized LOD; large simultaneous operation profiling and hardening.

**Phase 4 scenario:** Several distant bunkers continue economic operation while player observes complex collapse involving multiple floors, active underground war, autonomous rescue, a dynamic surface breakthrough and material processing. After save/reload all strategic consequences persist regardless of particle settings.

## Acceptance suite (must be executable, not only reviewed)
| ID | Test | Pass condition |
| --- | --- | --- |
| UX-01 | New player constructs first bunker | Contextual workflow, no manual logistics/staff/power wiring required |
| UX-02 | Switch surface/cutaway/floor/unit | Same units and inventories, continuous time, consistent selection, no duplicates |
| UX-03 | Smart build a multi-module factory | Legal preview, cost/prereqs transparent, no unauthorized major demolition |
| LIFE-01 | Automate a civilian bunker for a long test run | Housing/food/air/workers handled without per-person commands; shortages explained |
| ELEV-01 | Multi-vehicle lift round trip | Physically boards/travels/exits, ground slides open/closed, clearance/queue honored |
| ELEV-02 | Disrupt elevator mid-trip | Safe failure/recovery, no cargo teleportation or missing units |
| GEO-01 | Excavate distinct rock and fault areas | Different work/risk/cost; deposits not exposed before permitted exploration |
| GEO-02 | Dig through connected floors and large chambers | 15-floor cap upheld, shafts align, structural constraints checked |
| GEO-03 | Save mid-excavation | Identical progress/geometry and material amounts after reload |
| MIL-01 | Borer geometry and route | Cannot pass through undersized tunnel or invalid geology |
| MIL-02 | Dynamic emergence | Correct surface opening, persistent topology, rally route, enemy response window |
| MIL-03 | Capture a bunker sector | Only lawful sector changes control; isolated others retain states |
| FCT-01 | Scavenger/Machine attempt bunker build | Hard reject; no tech leakage or exploit by capture |
| FCT-02 | Enemy raids existing Human bunker | Infiltration/occupation/looting/destruction work within allowed rules |
| LOG-01 | Supply from another bunker | Physical shipment, capacity limit, ownership and correct stock conservation |
| LOG-02 | Cut logistics link during shipment | AI reroute/fail with clear cause; no duplicate/vanished goods |
| DES-01 | Collapse one loaded floor sector | Structural cause, local cascade, valid resulting topology, visible animation |
| DES-02 | High- and low-VFX collapse | Identical authoritative damage/casualties/salvage outcomes |
| INT-01 | Hidden bunker with weak enemy intelligence | AI cannot target exact undiscovered location; contacts decay properly |
| PER-01 | Save with multiple simultaneous crises | Accurate restoration of occupation, lift, rail, fires, damage, queues |
| PERF-01 | Repeat stress scene on defined hardware | Recorded sim p95/p99, frame/render budgets, memory, stutter, entity counts |
| AI-01 | Full military objective delegated | Commander attempts recon/logistics/offense under player-specified restrictions |
| A11Y-01 | Reduce shake/flash, scale UI | Threat cues remain legible and all primary actions usable |

## Defining “complete”
- Feature demonstrates all 32 agreed design outcomes through live gameplay and regression tests, not just text/spec mockups.
- Enemy-only exclusivity survives map editor, skirmish setup, captured units, old saves and difficulty overrides.
- Persistent world invariants (matter, units, structures, ownership, technology, sensing and geometry) hold across view switches, chunk load/unload and save/load.
- Scale targets are accompanied by reproducible measured profiles on specified hardware; no untested promises of infinite bunkers or thousands of full-detail entities.
- A novice can complete construction, deployment, emergency response and a military objective **without micromanaging routine production, workers or transport**.
- A power user can inspect data and manually intervene with clear authority boundaries.
- Art/animation validation checks engineering silhouettes, collision, vehicle capacity, debris readability, camera safety and surface camouflage states.

## Recommended first coding backlog (engine-neutral)
1. Establish unique underground world coordinate space and identity/capability checks.
2. Implement `Bunker`, `Floor`, `Sector`, `Facility`, `Elevator`, `Policy` state with serialization.
3. Use one simple known terrain chunk and implement safe excavation transaction + nav dirty rebuild.
4. Build one modular facility with budgeted/automated construction intent.
5. Render interactive floor view and cutaway as views of shared world IDs.
6. Implement concealed vehicle elevator state machine and two-vehicle transfer.
7. Add save/load mid-elevator, mid-construction, and mid-camera-switch regression tests.
8. Add enemy attack on entrance, security state and faction restriction tests.
9. Instrument simulation time, geometry updates, path recalculation and render costs.
10. Ship Phase 1 scenario; only then expand into military/rail/civilization/collapse depth.

## Suggested risk register
- **3D topology vs legacy surface nav:** plan shared movement and surface transitions first.
- **Synchronized cutaway VFX:** render only; maintain one authoritative state.
- **Structural cascades cost:** local support graphs and event budgets, not unrestricted whole-map physics.
- **Automation deadlocks:** job reservation, resource leases, priority inheritance, safe cancellation, observable failures.
- **Civilians vs RTS scale:** aggregate offscreen cohorts; keep individual identity stable.
- **AI information cheats:** per-faction observable-intel boundary on all commander planners.
- **Too many room knobs:** curated modules, defaults and high-level policies; make advanced controls optional.
- **Graphics ambition vs performance:** include quality tiers, profiling gates and gameplay-critical indications independent of effects.
