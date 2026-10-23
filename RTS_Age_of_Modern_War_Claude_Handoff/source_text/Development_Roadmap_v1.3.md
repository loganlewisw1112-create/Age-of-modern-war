# Development_Roadmap_v1.3

Source: reference/RTS_Age_of_Modern_War_Four_Documents_v1.3(1)/Development_Roadmap_v1.3.pdf


## Page 1
RTS  /  AGE OF MODERN WAR                                      DEVELOPMENT PACKAGE   v1.3
DESIGN SPECIFICATION  •  22 OCT 2026                  PAGE 1
RTS - Age of Modern War
Parallel Design + Development Roadmap v1.3
Strategy approved: develop a classic RTS playable slice while expanding the 13-stage and hybrid-world design. 
Milestones are gate-based; calendar estimates and staffing are intentionally not invented.
1. Delivery Logic
Two continuous tracks: (A) actual Godot development and instrumented playtests, and (B) living game design / data 
catalogs / visual production. Neither waits for every full-game system to be documented. A running minimal prototype 
is NOT the same thing as the agreed first playable skirmish target.
G0 - Engine Spike | Deliverable: Camera, selection, command bus, unit movement, one terrain | Required proof: Godot 
launched; repeatable selection/move; 64-unit baseline profiled | Stage of project: Small technical demo
G1 - Core RTS | Deliverable: Gathering, treasury, material ledger, power, HQ, barracks, production, basic combat | 
Required proof: Build → recruit → fight → HQ win; no duplicate money/material | Stage of project: Minimum playable 
loop
G2 - Smart Warfare | Deliverable: Groups, officer mission, suppression/cover, armor/component damage, supply, 
smarter AI | Required proof: Orders persist and AI attacks without scripted trigger | Stage of project: Tactical proof
G3 - Approved Slice Content | Deliverable: 3 distinct factions, 3 distinct maps, Stage 7/8/9, asymmetrical skirmish 
setup, victories | Required proof: Target user journeys S1–S3 and slice QA pass | Stage of project: Substantial first 
playable
G4 - Harden + Scale | Deliverable: Save/load, seed repeat, bridge reroute, perf suite, onboarding and polish | Required 
proof: Reports for benchmarks toward 500–2,000 participants; measured supported cap | Stage of project: Quality gate 
before broader testing
G5 - Full-world Foundation | Deliverable: Simulation tier transition, persistent regional aggregates, fuller 
economy/diplomacy, survivor prototype | Required proof: No conservation drift, playable continuity across modes | 
Stage of project: Future expansion
G6 - Full Experience | Deliverable: All 13 deeply implemented, editor, multiple continents, survivor+strategic cameras 
and institutions | Required proof: Extensive independent system testing | Stage of project: Long-term ambition
Ordering note: Save/load should be built as a vertical feature early (G0/G1) and hardened by G4, not postponed until 
hundreds of systems rely on volatile in-memory state. AI faction planning evolves concurrently with economy. The 
camera remains fixed angle until the full-game expansion.
2. Prioritized Product Backlog
F-001 | Priority: P0 | Item: Godot project, display modes, fixed isometric camera | Completion rule: Smooth 
panning/zoom with deterministic world-to-screen picking | Dependency: None
F-002 | Priority: P0 | Item: Stable world IDs and command/event bus | Completion rule: Same command rules for 
player and AI; testable logs | Dependency: F-001
F-003 | Priority: P0 | Item: RTS selection/movement/formation | Completion rule: Click, marquee, group assignment, 
path following | Dependency: F-001, F-002
F-004 | Priority: P0 | Item: Resource and credits ledger | Completion rule: Extraction/purchase/production balance 
with no negatives | Dependency: F-002
F-005 | Priority: P0 | Item: Building placement and construction | Completion rule: Placement preview, footprint 
rejection, worker completion | Dependency: F-003, F-004

## Page 2
RTS  /  AGE OF MODERN WAR                                      DEVELOPMENT PACKAGE   v1.3
DESIGN SPECIFICATION  •  22 OCT 2026                  PAGE 2
F-006 | Priority: P0 | Item: Production queues and rally | Completion rule: Barracks, factory, material consumption, 
repeat queue | Dependency: F-004, F-005
F-007 | Priority: P0 | Item: Basic infantry/vehicle combat | Completion rule: Resolve LOS/range/ammo/damage and 
death or component disable | Dependency: F-003, F-002
F-008 | Priority: P0 | Item: AI strategic baseline | Completion rule: AI collects, builds, produces, attacks on its own | 
Dependency: F-004 through F-007
F-009 | Priority: P0 | Item: Match setup/validation | Completion rule: Stage 7–9 & credits independently per side; 
invalid reason visible | Dependency: F-002, F-004
F-010 | Priority: P0 | Item: Victory tree and results | Completion rule: Military, control, AND/OR, endless work | 
Dependency: F-002, F-009
F-011 | Priority: P0 | Item: Save/load + seed restart | Completion rule: Exact durable state, no duplicate assets, 
deterministic opening | Dependency: F-002, F-004
F-012 | Priority: P1 | Item: Distinct three-faction roster | Completion rule: 3 different production chains and 7/8/9 
options | Dependency: F-006, F-008
F-013 | Priority: P1 | Item: Three river-valley maps | Completion rule: All maps validated; seeded legal variants | 
Dependency: F-001, F-009
F-014 | Priority: P1 | Item: Stage registry + transitions | Completion rule: Exactly 13 stable IDs; legal Stage 7→8→9 path 
| Dependency: F-004, F-009
F-015 | Priority: P1 | Item: Officers and delegated operations | Completion rule: Formation can complete multi-step 
bounded task, report status | Dependency: F-003, F-008
F-016 | Priority: P1 | Item: Cover/morale/supply/component damage | Completion rule: Readable tactical impact and 
no invalid stocks | Dependency: F-007
F-017 | Priority: P1 | Item: Destructible bridge and repair | Completion rule: Route invalidated, repaired and persisted 
| Dependency: F-013, F-011
F-018 | Priority: P1 | Item: Adaptive but classic HUD | Completion rule: Core actions discoverable, inspect alerts and 
era | Dependency: F-003 onward
F-019 | Priority: P1 | Item: Procedural map seeds | Completion rule: Repeatable, spawn-valid variation of authored 
macro map | Dependency: F-013
F-020 | Priority: P1 | Item: Battle stress suite | Completion rule: Automated actor-count, tick-time, memory, fps 
reporting | Dependency: F-007 onward
F-021 | Priority: P2 | Item: Deep markets, human politics, generations | Completion rule: Persistent external 
settlements and authority | Dependency: G5/G6
F-022 | Priority: P2 | Item: Direct survivor controls and seamless multi-scale | Completion rule: Same authoritative 
world survives camera switch | Dependency: G5/G6
F-023 | Priority: P2 | Item: Full continent + underground/naval warfare | Completion rule: Durable region streaming, AI 
operations and terrain | Dependency: G5/G6
F-024 | Priority: P2 | Item: Advanced map/scenario editor | Completion rule: Save/export authored geometry and start 
packages | Dependency: G6
F-025 | Priority: P2 | Item: Complete Stage 1–6 and 10–13 content | Completion rule: Each stage distinct playable 
mechanics for all 3 core factions | Dependency: G6
3. Parallel Design Track Deliverables
D-001 Design authority: Keep the decision register updated and separate approved choices from test fixtures; prevent 
reintroduction of survival-first priority.

## Page 3
RTS  /  AGE OF MODERN WAR                                      DEVELOPMENT PACKAGE   v1.3
DESIGN SPECIFICATION  •  22 OCT 2026                  PAGE 3
D-002 First three faction content: unique architecture silhouettes, stage-bound research, production dependency 
graph, base kits, voice/visual identities.
D-003 Stage Bible expansion: for every one of 13 stages deepen culture/government, civil infrastructure, environment, 
technology, warfare and machine parallels without making all stages immediate implementation blockers.
D-004 Visual bible: define pixel unit proportions, camera angle, tile scale, map-layer language, color coding and VFX 
budgets with actual small-size sprite tests.
D-005 UX wireflows: skirmish setup, building/production, unit inspector, stage advancement, victory/status, enemy 
intel and notifications.
D-006 Data validation and balance: prototype recipes, unit role costs, performance tiers, fail-state warnings, 
configurable difficulty without cheating.
D-007 Playtest evidence: measured match duration, player clarity, AI autonomy, navigation failures, FPS profile and bug 
recurrence.
4. Dependency-Critical Sprint Bundles (No Calendar Assumption)
Bundle A - Engine boundary & interaction
Demonstrate selected units, pathfinding on fixed-angle river-valley test map, a validated click-to-command path, and 
repeatable seed. Build HUD prototype and record footage/perf; keep art basic but silhouettes proportional.
Bundle B - A functioning economy
Resource nodes, worker jobs, treasury, production recipes, storage, power, auto construction and barracks/motor pool. 
Validate resource conservation using property tests. Include an AI side that builds without pre-seeded events.
Bundle C - Combat credibility
Cover, basic LOS, ammo, morale, mobility vs weapon component disable, officer delegated objective and limited 
wreck/destructible bridge. Show AI combatants that retreat/regroup. Combat fidelity should scale without complex 
visual physics on every entity.
Bundle D - Match breadth
Data-drive 3 factions, their different production graphs, research and Stage 7–9 progress; 3 distinct maps; configure 
independent sides and all victory rules. Stage 8 gets best content fidelity, with Stage 7/9 meaningful differences.
Bundle E - Quality + expansion compatibility
Save/replay, fog fairness, deterministic stress tests, content audits, map-validation pass, measured scale toward 500–
2,000 soldiers, maintainable clean data contracts and extensible camera projection.
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
8. Package Deliverable Checklist
 Master design, architecture, precise slice specification, 13-stage bible, milestone plan, visual references.☒
 Design decision register showing all locked choices and contradictions resolved.☒
 Machine-readable stage/faction/unit/building/map / skirmish starter contracts and validator.☒
 Original v1.0–v1.2 editable design/architecture documents preserved unchanged.☒
 Original six approved visual mockups preserved unchanged.☒
 Actual Godot gameplay code compiled and tested — ☐ not included; this package specifies what to build.
 Measured target-hardware benchmarks — must be generated during actual implementation.☐
 Final canon faction/continent/game names and balancing — intentionally not invented.☐