# Test plan, evidence and release qualification

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md), [Development_Roadmap_v1.3](../source_text/Development_Roadmap_v1.3.md), [Technical_Architecture_v1.0](../source_text/Technical_Architecture_v1.0.md)

9. Slice Acceptance Tests — Must Pass, Not Just Exist in Documents
MATCH-01 Can start a 3-side match with independent credits, Stage 7/8/9 and different faction opening assets, all state validated.
MATCH-02 Same config+seed produces identical starting map/resources/unit IDs and eventually deterministic fixed-step outcome under fixed commands.
MAP-01 Each of three maps can load, spawn sides legally and permit a viable route to starting supplies; seed variants pass route/spawn validation.
ECON-01 One resource cannot be spent twice; production costs deduct once; money changes do not create physical materials.
ECON-02 Without power or required component, high-level production stalls with clear reason; recovery resumes without duplication.
BUILD-01 Place, rotate and finish a building; road/wall tool creates legal connected segments; destruction invalidates navigation where relevant.
MIL-01 Selected unit/group follows commands; trained squad spawns with actual equipment; formation/rally works; dead units remain dead.
MIL-02 Vehicles lose mobility/weapon capability independently; destroyed bridge changes route and does not corrupt saves.
AI-01 Each faction can independently construct, recruit, research and attack an opponent in a non-player-triggered soak test.
AI-02 AI cannot target enemy in strict hidden fog without a legal detection/remembered-intel pathway.
AGE-01 All 13 registry IDs exist; only supported playable 7-9 selectable in slice; invalid ID rejected; 7→8→9 requires gates.
VICT-01 Military, territory, combined objective and endless all produce expected outcomes; incompatible rules rejected.
SAVE-01 Save/reload preserves treasury, inventories, damage, ownership, officer orders, selected stages, unit identities and RNG state.
UI-01 New user can build HQ/depot/barracks and train a squad from contextual interface without reading a manual.
PERF-01 Benchmark runs at progressively 64→128→256→512→1024→2000 actors with combat and vehicles; record actual fps/ms/memory and clear achieved cap; no fabricated performance assertions.

5. Definition of Done Per Feature
A feature is 'done' only when (1) player action is reachable from UI, (2) actual sim state changes via validated command, 
(3) AI can use relevant action fairly, (4) save/load persists it, (5) failure states explain why, (6) automated test covers 
positive, negative and edge cases, (7) performance is measured in a representative scene, and (8) the written 
source/design registry is updated.
6. Acceptance / Smoke Test Matrix
QA-001 | Setup: Player credits 0 and no stockpile | Expected result: Valid hardship start only where opening remains 
viable; clear warning

## Page 4
RTS  /  AGE OF MODERN WAR                                      DEVELOPMENT PACKAGE   v1.3
DESIGN SPECIFICATION  •  22 OCT 2026                  PAGE 4
QA-002 | Setup: AI Stage 9, player Stage 7 | Expected result: Different tech/tooling assets and credible independent 
resource use
QA-003 | Setup: Same seed / same rules twice | Expected result: Same authored macro map and generated placement 
outcomes
QA-004 | Setup: Invalid/unplayable spawn | Expected result: Match rejects with human-readable location failure
QA-005 | Setup: 3 factions free-for-all | Expected result: Non-player AI competitors can detect/attack each other
QA-006 | Setup: Research prerequisite absent | Expected result: Stage transition blocked, reasons and missing 
capabilities displayed
QA-007 | Setup: Destroy bridge | Expected result: Ground path updates and shipment reroutes; repair restores access
QA-008 | Setup: Tank mobility disabled | Expected result: Tank weapon may still function; equipment saved faithfully
QA-009 | Setup: AI fog hides enemy | Expected result: AI has no exact target unless legal intel contact exists
QA-010 | Setup: Save during active build + attack | Expected result: Queues, inventories, orders, shots/casualties and 
RNG restore consistently
QA-011 | Setup: Endless game | Expected result: No forced ending when military rivals are defeated unless explicit 
player quit
QA-012 | Setup: Combined victory expression | Expected result: Requires all AND branches / one OR branch as 
configured
QA-013 | Setup: Arcade and Simulation economy | Expected result: Same core resource ledger, differing logistics 
abstraction, no negative balances
QA-014 | Setup: 13-stage registry | Expected result: Exactly IDs 1..13; only 7–9 active in slice; others visibly not 
available
QA-015 | Setup: Dense battle stress suite | Expected result: Report observed 1% FPS, sim ms, AI ms, memory, target 
reached/failed honestly
7. Quantitative Gates and Performance Honesty
Earlier v1.2 architecture suggested 30–100 local actors for engineering tests. The user's newly approved first-playable 
ambition is 500–2,000 participants; both are valid if correctly labeled. Begin G0 at 64 actors, profile and scale by 
doubling. Do not promise 2,000 high-detail actors visible all at once or a 60-FPS experience on unspecified hardware. 
Record number of individual simulated entities separately from drawn sprites and operational formation strength.

## Proposed verification layers

1. Content/config validation: unique IDs, exactly 13 stages, references, unavailable content, recipe inputs/outputs, legal starts, victory trees and no cyclic unbounded prerequisites.
2. Simulation invariants: resource conservation with explicit sources/sinks, no duplicate IDs, command rejection atomicity, production exactly once, roster/casualty accounting, owner permissions and fog access.
3. Scenario runs: S1–S3, MATCH/MAP/ECON/BUILD/MIL/AI/AGE/VICT/SAVE/UI cases preserved above, plus roadmap QA-001..015.
4. Save/replay: save during queued construction/combat/bridge repair, reload repeatedly, check RNG/orders/reservations/objective timers and corrupt/unsupported save handling.
5. AI autonomy: all factions and AI-vs-AI, finite resources, no player trigger, visible planner trace, starvation/deadlock recovery and fog fairness.
6. Navigation/destruction: chokepoint congestion, blocked/unreachable destinations, bridge loss while crossing or delivering, alternate route and repair.
7. User/visual/audio checks: discoverable build-produce-fight loop, selection/picking accuracy, silhouette/occlusion, scaled HUD, input remap and reduced-flash mode.
8. Performance/soak: 64→128→256→512→1024→2000, representative combat, vehicles, effects and supply; accelerated long runs with invariant checks. A 24-hour accelerated soak is an older proposed test, not an achieved result.

Record scenario revision, content/config/seed, hardware, OS/engine/build, duration, individually simulated actors, visible sprites, formation strength, frame-time median/p95/p99 and 1% FPS, subsystem times, memory, path backlog and save latency. Report failures and achieved stable cap without extrapolation. Specify speed factor and test duration; an empty terrain benchmark does not qualify a dense battle.

## Evidence report template

Test ID; expected result; build/hash; environment; config/seed; reproduction steps; actual result; logs/video/profile path; PASS/FAIL/BLOCKED; defect ID; retest result. All game tests remain NOT RUN here. Package integrity checks are documented separately in audit/ and qualify only this handoff artifact.


## Approved DLC addendum — 2026-11-27
[DLC acceptance matrix DLC-01..19](../../game/docs/DLC_DELIVERY_PLAN.md) and detailed subsystem tests extend existing requirements. All new tests NOT RUN; budgets and evidence required before release.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

SP-QA-01–32 NOT RUN, separate saves and entitlement tests, validated orbital data, resource conservation, replay and manual handoff; no new runtime tests executed.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## Corrected owner-approved execution sequence

G11–G17 full XENOGENESIS and Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization (DLC 2). Both systems must be fully implemented, integrated, tested and accepted by G17 exit (before G18 and G19): all 20 XENOGENESIS subsystems; all 15 Myrieme Forge engines and eight integration adapters, including offline runtime. Earlier development is permitted. G20 interstellar gameplay/content production happens after G19; G11–G17 testing uses representative fixtures without requiring full G20 content or exposing unowned DLC. No implementation or gate completion is claimed.


## G11–G17 integrated system development — current owner authority

G11–G17 integrated development of XENOGENESIS and full Myrieme Forge; both fully implemented, integrated, tested and accepted as mandatory G17 exit criteria. G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization. No separate integration checkpoint; G20 gameplay and full universe content production remain after G19. All 20 XENOGENESIS subsystems, 15 Forge engines and eight integration modules, offline runtime and shared director interoperability required by G17. Representative validation fixtures, not premature DLC gameplay; ownership boundaries remain. See the current ROADMAP and DLC delivery plan for per-gate assignments. No implementation or gate completion claimed.


**Current gate authority:** G17 Living World and full XENOGENESIS/Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion (DLC 1) → G20 Beyond Civilization (DLC 2). Both DLCs begin only after the base game is complete. No runtime changes or gate completion claimed.


## G18 design integration

G18 final base-game completion includes online Last Protocol co-op, Skirmish co-op/PvP, owned open-source gaming platform, DEAD SECTOR/PATHOGEN and SUBTERRANEAN WARFARE/DEEPWAR. Inheritance and Living World offline solo only; UNDERSTRIKE integrated Human A branch. No soldier-follow in new modes. G17 full XENOGENESIS and Myrieme Forge acceptance precedes G18, then G19 Space Expansion and G20 Beyond Civilization. No new DLC, code changes or completion claims.

G18-01–34 NOT RUN; all four tracks must pass offline/online tests, security, cost, playtests and regression before G19.

[Master GDD](../../game/docs/G18_MASTER_GDD.md) · [G18 delivery](../../game/docs/G18_DELIVERY_PLAN.md) · [PATHOGEN](../../game/docs/PATHOGEN_DIRECTOR.md) · [DEEPWAR](../../game/docs/DEEPWAR_DIRECTOR.md).


## Expanded gameplay integration — 2026-11-27

Original acceptance unchanged; expanded EX-A01–40 required alongside G18-01–34. Clean G10.1 regression remains open. Hardware, durable save, creator security, platform and all mode checks NOT RUN. [Delivery](../../game/docs/EXPANDED_GAMEPLAY_DELIVERY_PLAN.md).

Eleven base-game experiences complete by G18; G17 full XENOGENESIS/Myrieme Forge acceptance and G19/G20 sequence retained. Seven directors only, Inheritance/Living World offline solo, UNDERSTRIKE Human A protected construction unchanged. Design only. [Expanded master](../../game/docs/EXPANDED_GAMEPLAY_MASTER_GDD.md).
