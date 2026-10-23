# First_Playable_Spec_v1.3

Source: reference/RTS_Age_of_Modern_War_Four_Documents_v1.3(1)/First_Playable_Spec_v1.3.docx

RTS - Age of Modern War
First Playable Classic RTS: Vertical Slice Specification v1.3
Scope: user-approved target slice, implemented in iterative gates | Working title and content labels | No playable game code is claimed in this document.
1. What a Player Will Actually Experience
From Main Menu → Custom Skirmish, the player chooses the available continent and a distinctly sized/skinned river-valley map, a world seed, one of three faction archetypes, the start Stage 7/8/9, starting credits, force/infrastructure preset, opponents and team affiliations, AI difficulty, economy profile, and victory conditions. A preview shows the initial industrial/equipment package and any unsupported requirements. After Start, the player pans a fixed isometric RTS camera, selects troops, orders workers, gathers material, builds a base, produces soldiers/vehicles, researches improvements, scouts enemies, fights and sees the result or continues Endless Mode. AI rivals concurrently expand and attack each other where relations allow.
Do not confuse: This substantial first playable target is reached after several much smaller engineering gates. The initial demo need not contain every map/faction, but these remain the approved end-of-slice targets.
2. Player Journey Acceptance Scenarios
Scenario S1 - First 15 Minutes (illustrative flow; times not guaranteed)
Select Industrial Heartland; player Human A at Stage 8, AI Human B Stage 7, AI Machine Stage 9; 50,000 opening credits; Standard economy; military elimination or 60% territorial control.
Setup preview identifies each side's independent treasury, start positions, stage-specific viable industry and asymmetry. Start succeeds with seeded layout.
Camera pans/zooms without rotation; marquee-select workers; order salvage collectors to storage.
Place a power station and barracks (ghost indicates costs/area). Workers deliver resources; build progress appears.
Queue a squad; configure rally point; trained squad appears with correct faction equipment and spends credits/materials exactly once.
Build motor pool, produce a vehicle, assign squad + vehicle to a group, issue attack-move toward a known chokepoint.
Scouts reveal enemy units; fog is observer-dependent. Officer can be assigned secure_bridge objective and gives progress updates.
Damage disables a vehicle component or destroys a bridge; pathfinding/transport reroutes or signals blocked. Game can save/reload and reproduce seeded opening.
Scenario S2 - Age Progression
Start Stage 7 with sufficient valid material chain; research/construct prerequisite packages; Stage 8 eligible indicator appears; manually trigger transition; new modern units/buildings become manufacturable once physical tooling/prerequisites exist. Continue research toward Stage 9; network systems appear without instantly spawning gear. A Stage 9 starter can be chosen independently for enemy sides.
Scenario S3 - Variable Wins
Play a territorial objective game; change to two-condition (hold bridge 5m AND 60% controlled territory), observe both checklist states; then start Endless with no termination. Invalid contradictory condition sets are rejected with explanatory errors.
3. Initial Skirmish Maps - Handcrafted + Validated Seed Variants
river_crossing_s - River Crossing | Scale and geography: Small valley: one major river, primary bridge, two secondary crossings, forests and ridges | Intended tactical lesson: Fast expansion, contesting a crossing | Distinct POIs / constraints: Fuel depot, crossing chokepoint; 2-4 initial spawn sites proposed
industrial_heartland_m - Industrial Heartland | Scale and geography: Medium river basin: factories, train yards, scattered towns, road loops | Intended tactical lesson: Build economy, defend industry, alternate attack routes | Distinct POIs / constraints: Refinery, rail siding, ruined plant, 3-6 spawn sites proposed
valley_conquest_l - Valley Conquest | Scale and geography: Large valley: multiple industrial pockets, foothills, river branches, complex roads | Intended tactical lesson: Larger formations, divided fronts and logistical vulnerability | Distinct POIs / constraints: Dam, tunnel portal as scenery, airfield, 4-8 spawn sites proposed
Number of map slots, map dimensions and kilometer scales must be performance-tested; above spawn counts are design fixtures, not fixed constraints. Procedural generation only changes legal seeded zones, never foundational crossings or core macro-geography without a verified alternate connectivity graph.
4. Faction Starter Kit — A Real Difference, Not Recolored Models
Human A: Modern Military Power
Initial practical style: combined-arms coordination. Production: HQ, barracks, motor pool, comms center and advanced vehicle works. Suggested opening combat roles: rifle squad, engineer squad, recon team, IFV, MBT, logistics truck, self-propelled artillery, rotary scout/attack craft (selected later gate). Stage 9 unlocks enhanced targeting/drone relay support.
Human B: Industrial Power
Initial practical style: durable industry and logistical redundancy. Production: reclaimed foundry, fortified barracks, heavy-vehicle plant, salvage yard, defense workshop. Suggested opening combat roles: militia/industrial infantry, combat engineers, heavy rifle squad, armored carrier, rebuilt MBT, artillery truck, maintenance/recovery truck, utility drone. Stage 9 adds hardened communications and production optimizations.
Machine: Autonomous Network
Initial practical style: decentralized fabrication + energy dependence. Production: core controller, assembler cell, materials reprocessor, charging hub, sensor relay, crawler works. Suggested opening roles: scout crawler, light combat drone, heavy ground walker, armored tracked platform, repair bot, cargo hauler, sensor mast, artillery node. Stage 9 adds distributed target sharing and remote EW/sensor countermeasures. No human barracks/food/worker reskin.
Each faction must have a plausible self-sufficient opening economy and meaningful counterplay. Machine and human stages are capacity-equivalent, not equivalent unit types. All names are working concepts.
5. Units, Formations and Production Targets
The data catalog includes initial template IDs, classes, stage eligibility and production facility refs; it is a design starter rather than final balance. Minimum functional roles per faction at Stage 8: builder/work crew, general infantry equivalent, specialist/recon, one mobile combat vehicle, one heavy vehicle, artillery/support, logistics/support. The three unique factions are essential to the substantial slice. Stage 7 supplies a narrower roster, Stage 9 adds specific advanced capabilities to demonstrate progression.
Formation controls: select individual actor or squads; Ctrl+number control groups, shift selection, rally, move, attack-move, stop, hold, patrol, guard, set formation, formation template, officer assignment, authorized replenish toggle. A production queue can assemble predefined squads even when recruit UI displays individual members. Unit panels show owner, HP/status, ammo/fuel, gear, morale, experience and current objective.
6. Buildings, Recipes, Resources and Technology
Headquarters / command | Human use: HQ | Machine counterpart: Core controller | First slice behavior: Production authority, basic territory and opponent elimination condition
Collector / salvage yard | Human use: Extraction crew yard | Machine counterpart: Reprocessor | First slice behavior: Acquires/recovers physical raw materials
Storage / depot | Human use: Logistics depot | Machine counterpart: Buffer depot | First slice behavior: Resource lots, delivery staging, supply radius
Power | Human use: Generator substation | Machine counterpart: Reactor/charging node | First slice behavior: Enables production and selected unit servicing
Refiner | Human use: Smelter/refinery | Machine counterpart: Material processor | First slice behavior: Raw material → processed input
Barracks / assembler | Human use: Troop training | Machine counterpart: Combat unit assembly | First slice behavior: Production queues, rally
Motor pool / crawler works | Human use: Ground vehicle plant | Machine counterpart: Tracked/walker assembly | First slice behavior: Vehicle queues, resource reservation
Research / comms | Human use: Research station | Machine counterpart: Pattern/compute node | First slice behavior: Research progress, capability unlock
Defense | Human use: Turret, wall, checkpoint | Machine counterpart: Sentry turret, barrier | First slice behavior: Terrain/LOS protection and destructible structure
Repair | Human use: Workshop / repair station | Machine counterpart: Repair/reconstitution bay | First slice behavior: Requires resources, recovers damaged equipment
Initial common resource fixture: credits, salvage, ore, alloys, components, fuel, ammunition, provisions and energy generation. Not every faction consumes each item identically. The ledger treats provisions for biological workers and charge/parts for machines as structurally distinct dependencies. Electricity is a produced/consumed flow, not unlimited instant stock. Recipes belong in versioned data; costs and rates are balance fixtures, not user-approved numbers.
Stage progression in first slice: Stage 7 permits mechanized baselines; Stage 8 adds modern integrated systems/training/reliable power and manufacturing; Stage 9 adds network/sensor/EW/drone improvements. The stage UI explains known designs vs available tooling vs actually produced vehicles. Manual advancement is gated by a demonstration of operating industrial capabilities and research prerequisites, and may require credits/materials depending on player-selected advancement rules.
7. Combat, AI and World Persistence
Combat requirements: directional armor & damage class, terrain cover and concealment, suppression, morale/retreat, ammo/fuel consumption, basic individual injury, tracked component disablement, select persistent wrecks and bridge/structure destruction, correct targeting under fog. One military operation can group several squads with an autonomous officer; show their mission and reason for phase change. Advanced EW prototypes for Stage 9 are optional in the earliest internal gate but part of final Stage 9 differentiation.
Rival AI: each side budgets treasury and stockpiles, grows facilities, trains squads, detects enemies, plans defenses and attacks based on knowledge, and can act against rival AIs. Show AI debug inspector: current objective, strategy score, last command, success/failure, next planning tick and known contacts. Difficulty changes reaction/quality, not hidden omniscience.
World consequences: wrecks persist; destroyed bridges re-path road vehicles; production damage lowers output; captured territory transfers ownership; repairs consume materials. No inventory or roster duplication after pause, reload, LOD change or restart.
8. User Interface and Input Contract
Left click / drag | Behavior: Select one / box-select team units (modifier for multiple)
Right click | Behavior: Smart context move / attack / harvest / repair; modifier for attack-move
Mouse wheel | Behavior: Smooth zoom while retaining fixed isometric tilt and stable target pivot
WASD/arrow/edge | Behavior: Pan camera; optional drag-pan
Ctrl+1–9 / 1–9 | Behavior: Save and recall control groups
Build | Behavior: Preview footprint, red/green legality, rotate, optional snap, cost, worker route
Production | Behavior: Queue, rally, cancel, list required components and blocked reasons
Top bar | Behavior: Credits, key stockpiles, power, population/supply alerts, stage
Lower HUD | Behavior: Unit/formation inspector, contextual orders and build/research panels
Map | Behavior: Fog, ally/enemy known contacts, objectives, camera jump
Alerts | Behavior: Classified by severity: building stalled, under attack, supply missing, tech unlocked
Menu flow: title → Skirmish → continent → map gallery → mode/preset → player/opponent slots → advanced rules → summary/validation → match. Keep options accessible via keyboard and mouse, scale the HUD and avoid hiding critical mechanics under cinematic VFX. The first playable excludes a free-rotating camera by explicit choice.
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
10. Implementation Boundaries
Engineering micro-slice (first runnable milestone): one map, single human faction, second AI test economy, four-ish unit classes, a few buildings, conventional attack-move and HQ elimination. Substantial first playable (committed content target): three factions, three maps, Stages 7–9, robust AI and configurable rules. Explicitly deferred: live survivor avatar direct-control, Stage 1–6/10–13 playable assets, full naval/underground, global politics, full continent editor, massive operational view, movable dashboard system and cinematic near-photoreal all-scale rendering.
11. Test Content Handoff
Use 07_Implementation_Data/*.json as a starter source for stage IDs, faction IDs, map refs, unit/building templates and example match config; these are deliberately versioned and balance-neutral. Refer to the roadmap for dependency order, test gates and the documentation/QA checklist. Do not mistake JSON data for a compiled or tested Godot game.