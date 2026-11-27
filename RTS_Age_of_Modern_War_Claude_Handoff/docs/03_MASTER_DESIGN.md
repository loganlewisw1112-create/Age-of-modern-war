# Consolidated master game design

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [GDD_v1.0](../source_text/GDD_v1.0.md)

# Master_GDD_v1.3

Source: reference/RTS_Age_of_Modern_War_Four_Documents_v1.3(1)/Master_GDD_v1.3.docx

RTS - Age of Modern War
Master Game Design Document v1.3
Status: Consolidated approved vision plus implementable design specifications | Date: 22 October 2026 | Platform: Offline single-player | Title: Working title
Authority. Approved direction records the user's locked creative choices. The implementation specification provides concrete mechanics to implement that intent, but numbers, map/faction names and balance values are provisional. v1.3 supersedes the old v1.2 survival-first development sequence; survivor gameplay remains in the full-game vision.
1. Vision and Product Identity
1.1 High concept
A post-nuclear persistent strategy world where independent civilizations construct, research, compete, negotiate and wage war without waiting for the player. Launch directly into accessible Classic RTS Custom Skirmish or, in the full experience, inhabit a physical survivor, build communities, command military organizations and govern continents. All use related authoritative simulation systems. The skirmish is a separately instantiated bounded session, not a second combat engine.
1.2 Core pillars
Classic RTS readability first. Building, producing, selecting and fighting must feel responsive before deeper systems add complexity.
Military agency at every scale. Individual units, squads, officers and future theater commands share consistent orders.
Autonomous competitors. AI nations pursue goals and fight one another with realistic knowledge and resources.
Consequential persistence. Inventory, damage, captured facilities, military casualties, territory, technology, and events matter.
Optional depth. Economy, military command, construction and diplomacy are delegable, not mandatory micromanagement.
Exactly 13 civilization stages. Stable stage IDs across every mode; stage signifies real capabilities rather than a combat buff.
Grounded cinematic identity. Detailed atmospheric 2D/2.5D pixel art while preserving clear unit silhouettes and functional proportions.
1.3 Hard boundaries and non-goals
Offline single-player; no multiplayer, cloud requirement, pay-to-win, or mandatory AI model runtime. Sci-fi requires internally consistent costs/vulnerabilities, not magical warfare. No claim that thousands of detailed soldiers can be rendered in real time before measured profiling. First playable is not the full survivor / naval / politics / continent renderer.
2. Modes and Core Loops
Custom Skirmish | Player loop: Configure continent, map, factions, stage, credits and victory; build, research, produce, scout, fight | Availability: First playable priority
Living World | Player loop: Survive, scavenge, befriend, settle, expand, pass on legacy | Availability: Full-game expansion
Tactical RTS | Player loop: Select units, build, defend, delegate to commanders and attack | Availability: First playable
Continental Strategy | Player loop: Govern territory, diplomacy, production, infrastructure and armies | Availability: Full-game expansion
Map and Scenario Editor | Player loop: Create landforms, bases, starting positions, special objectives | Availability: Full-game expansion
Core RTS loop: Configure → survey → acquire resources → construct → recruit/manufacture → explore/recon → engage → repair/replenish → expand/research → resolve victory or continue endlessly. World time runs unless paused; save slots isolate Skirmish from Living World.
3. First Playable Scope: What Is Actually Approved
The first substantial classic-RTS slice targets three asymmetric faction archetypes, content for Stages 7–9, three handcrafted maps in one Industrial River Valley, procedural/seeded variants, a fixed isometric camera, a hybrid HUD, autonomous economic/military AI, hybrid credits and physical inventories, sensible construction, unit templates, officer orders, casualties, key persistent destruction, and customizable victory rules. Stage 8: Modern Nations is the primary content emphasis. The initial engineering prototype may temporarily use one map/fewer factions and small combat counts, but that is a milestone rather than a downgrade to the final slice.
Scale target: stress-test toward 500–2,000 soldiers; the final achieved active count depends on profiling on specified hardware. The long-term full simulation can manage far larger distributed totals with fidelity tiers, without promising equivalent on-screen fidelity.
4. Custom Skirmish Setup
4.1 Geographic selection
Choose fictional continent → select map from that continent's collection → choose compatible size/seed variation → choose playable sides and match rules. Each continent must contain multiple genuinely distinct maps, not cosmetic variations of one terrain file. The first approved region is a diverse continent's Industrial River Valley. Initial handcrafted map working titles: River Crossing (small), Industrial Heartland (medium), and Valley Conquest (large). Their macro geography is authored: bridges, riverbanks, ridgelines, roads, industrial centers, vegetation and vital resources. Seeded variants alter foliage, resource quantities/position within safe masks, ruins, minor barriers and legal spawn alternatives without ruining navigation or spawn fairness.
4.2 Per-civilization controls
Every human and AI player can have separately configured faction, team/alliance, start location, Stage 1–13, starting treasury credits, stockpiled physical resources, population and workforce, existing structures/utilities, trained troops, vehicles/aircraft, starting territory, unlocked tech, actual research, industrial tooling, logistics, commander competence and doctrinal profile. AI skill and starting handicap must remain separate. The UI shows what is actually granted, estimated match load, any scenario incoherencies and the practical consequences of unequal stages.
Content availability: show all 13 stage names in the selector, but only Stages 7, 8 and 9 are match-start enabled in the first slice. Unavailable stages are clearly marked, never silently converted. Starting at Stage 9 does not conjure an unconfigured inventory of Stage 9 weapons or production assets.
4.3 Economy profile
Arcade: fast credits, simplified material pools, abstracted logistics and forgiving refill rules.
Standard: currency plus explicit physical resources, production, power/storage, basic supply transport and consumables.
Simulation: detailed materials, inventories, transport, manufacturing recipes, labor, markets, servicing and shortages.
Custom: independently tune individual supply/economy rules; all profiles use the same legal resources and command interface.
Realism and economic complexity are separate from AI difficulty. The player may select full simulation and easy AI, or Arcade economy with very intelligent AI.
4.4 Victory expression
Military elimination/HQ capture; territorial percentage or hold objectives; economy/score thresholds; stage/research race; diplomacy/unification; defense survival; timed scenarios; linked AND/OR requirements; allied/individual victory; Endless Mode. Each condition is evaluated against authoritative state. Display clear progress and failure feedback. Prevent conflicting configurations (e.g., endless and mandatory timer termination) or explain priority. A scenario author may apply custom starting asymmetric objectives in the full editor.
4.5 Presets
Quick setup provides Balanced Build-Up, Immediate Battle, Survival Frontier and Last Stand (working preset names). Advanced setup preserves every supported knob. Local versioned config import/export and reproducible seeds are design targets; the first slice must save and reuse preset configurations.
5. The Universal 13-Stage Civilization System
Exactly thirteen stable stage IDs are shared by human and machine factions, skirmish, survivor settlement, AI and continental play: Scattered Survivors; Organized Camps; Frontier Settlements; Reclamation Townships; Workshop Confederacies; Industrial Revival; Mechanized States; Modern Nations; Networked Powers; Automated Technocracies; Synthetic Civilizations; Distributed Civilizations; Apex Civilizations. All are working names, approved stage count/sequence is fixed.
Progress depends on scientific knowledge, operational infrastructure, sufficient institutions, workforce skill, resource production, equipment tooling and demonstrated industrial capabilities. Players can manually formalize a transition when requirements are met. Skirmish uses readable advancement prerequisites/costs and custom pace/maximum stage; Living World reflects organic growth and possible regression. Scavenged advanced gear may be used if operable but does not grant a manufacturing industry. Civilizations within the same stage specialize in different pathways (energy, medical, logistics, armor, aerospace, digital command, machine design, ecology). Stage progression never changes unit damage merely because a number increased. See Civilization Bible.
6. Three Distinct Faction Archetypes
Human A - Modern Military Power | Structural advantage: Professional flexible combined arms, communications and training | Constraint: Higher precision-equipment and fuel/maintenance costs | RTS playstyle: Balanced maneuver with high coordination
Human B - Industrial Power | Structural advantage: Robust recycling, factories, defensive industry, cost-effective mechanization | Constraint: Less immediate network integration | RTS playstyle: Build hard, defend, sustain, counterattack
Machine - Autonomous Network | Structural advantage: Nonhuman fabrication, drones, sensor links, modular repair and recycling | Constraint: Requires power/components and functioning network paths | RTS playstyle: Distributed pressure, recon, recovery and redundancy
Machine Stage 8 should not be an identical human Stage 8 with robot skins. Factions use stage-equivalent overall industrial maturity with different production dependencies and vulnerabilities. Canon names, emblems, final roster and balance values remain open.
7. Construction and Physical Economy
Construction interaction: choose template → transparent placement/footprint/connection preview → optional rotation and grid snap → commit validated build order → workers and trucks acquire real stockpiles → phased construction, repair or cancellation. Roads/walls/fences use drag paths. Player can save layouts later; customizable modular compounds and underground rooms are full-game systems.
Credits reside in treasury, and physical materials reside in named inventories with location and owner. Production facilities process input lots, power and labor to output lots; factories and depots can become bottlenecks. Material transit supports Standard/Simulation fidelity, while Arcade may group movements into transfers without violating finite-inventory conservation. Building damage changes production, connectivity and local pathfinding. Repaired bridges/roads reroute units and supplies. Workers may be assigned priorities and automatically restock production queues.
8. Military Production and Organization
Players recruit individual soldiers or complete squads, train specialties and manufacture vehicles/equipment with explicit queues. Soldiers can be composed into squads, platoons and companies with customizable weapon roles and doctrine. Officers receive formation membership and bounded order authority. Equipment templates, group rally points and replacement policies reduce clicks. Full-game expansion includes battalions, brigades, divisions, procurement programs and cross-region support structures; distinct military branch structures need not be identical for machines.
8.1 Layered orders
Direct: move, attack, attack-move, hold, stop, patrol, guard, repair, reload or retreat. Tactical: multi-waypoint movement, formations, sectors, priority targets, recon, overwatch/suppression. Delegated: assign officer objective, zone, assets, priority, risk limit and authority; they respond autonomously and report status. Strategic (full): operational phases, reserves, front lines, supply limits, conditional objectives and theater coordination. Players can override their own officers at any time.
9. Realistic Combat and Recovery
First playable includes range and dispersion, visible projectiles where useful, directional armor, cover, suppression/morale, fatigue, ammunition and fuel, threat detection, drones/scouting, vehicle component states (mobility, main weapon, sensors, communication), basic casualty/injury outcomes and a limited but real persistent destruction set. Weather and stage-9 electronic warfare affect sensors/target quality. Commanders can seek cover, defend, withdraw, request resupply and coordinate formations within competence constraints.
No soldier should just stand exposed while automatically trading health. No weapon or vehicle bypasses supplies or meaningful counterplay. Advanced physics, medical trauma detail, expansive terrain cratering and complex acoustic/ballistic modelling are full-game aspirations and must be benchmarked. Disabled vehicles may remain salvageable; bridges, industrial buildings and routes may be ruined and must be repaired. Mature graphic presentation is optional; mechanics are independent of gore.
10. Autonomous Enemy Civilizations
AI exists at individual, squad, officer, faction economy and civilization-strategy tiers. In first playable, all three factions can construct, mine/gather, produce, research, scout, defend, attack, replace losses and pursue victory without scripted player triggers. Competitors may fight one another when configured as opposing teams. AI uses the same command validator, inventories, research permissions, fog and decision costs as a player. Plans have traceable reasons and finite computational budgets; uncertainty and outdated intel persist. Full game adds durable institutional memory, adaptive doctrine, treaties, internal politics, leaders and generational change.
11. World and Atmosphere
The setting is an original fictional post-nuclear planet with temperate landscapes, highlands, arid regions, wetlands, coastlines, metropolitan ruins, industrial corridors and cavernous underground networks. The deeper post-collapse scientific mystery is optional, not a mandatory quest gate. Civilizations keep operating when ignored. The full world supports day/night, seasons, families, succession and political upheaval. The first playable focuses on one industrial river-valley military region and its three RTS maps, followed by a larger combined-biome showcase.
Approved artistic baseline: grounded gritty high-detail pixel art with layered 2.5D depth, dramatic overcast light, weather and readable military silhouettes. Six approved mockup PNGs are retained byte-for-byte as design references; they are concept frames, not promised screenshots or strict UI layout blueprints.
12. Camera, Interface and Accessibility
First playable camera is fixed-angle isometric. Enable scrolling/keyboard and edge pan, scroll zoom without arbitrary rotation, selection drag, control groups, unit follow hotkeys and smooth bounded travel. HUD uses familiar resource bar and minimap, bottom/context unit actions, construction/production panes, alert severity and readable overlays. Responsive UI scaling, remappable inputs, color-safe team indicators and reduced-flash modes are required design goals.
The complete game adds adaptive close/tactical/operational/strategic zoom, survivor control, modular movable dashboards, layered intel and saved layouts. These expansions must not compromise the first-playable traditional RTS control loop.
13. Completion Bar and Non-Goals
Substantial slice: launch configured three-faction skirmish on each of three maps; vary credits/stage per AI side; recruit infantry and build armored units; demonstrate real economy and construction, research/transition 7→8→9, basic autonomous officer orders, combat and casualties, constrained rival AI, configurable victory rules, save/load and seed-repeatability. Profile toward target battle sizes. Do not claim full 13-stage playability, comprehensive naval/underground war, direct-character Survivor control, finished editor or continent-wide simulations yet.
Every numerical stat and every working map/faction/technology name is provisional pending actual implementation and playtests. Locking the design intention does not imply the feature exists in running software.

## Retained full-game reference

# GDD_v1.0

Source: reference/Game_Project_GDD_Architecture_Approved_Mockups/Documents/GDD_v1.0.docx

GAME DESIGN DOCUMENT
Version 1.0  |  Living World Survival • Civilization • Warfare
STATUS  •  Design baseline / proposed engineering decisions  •  21 October 2026
This document distinguishes confirmed creative decisions from proposed implementation details. Targets are aspirations until validated by profiling and playtests.
01 / Creative North Star
High concept
A fully offline, single-player, persistent post-nuclear world combining intimate survival RPG, intuitive settlement construction, tactical real-time strategy, and continent-scale civilization simulation. The player can remain an explorer or build a civilization over generations. Autonomous rivals continue their own histories regardless of player attention.
Experience pillars
1. Deep simulation, effortless controls. 2. Meaningful agency at personal, tactical and strategic scales. 3. Autonomous civilizations with observable goals and consequences. 4. Persistent history, damage, knowledge and legacy. 5. Visually stunning yet readable cinematic 2D/2.5D pixel art. 6. Genuine freedom to ignore the central mystery.
Non-goals and hard boundaries
No multiplayer, mandatory online services, cloud inference, or pay-to-win systems. Orbital warfare is a distant optional expansion, not initial scope. No claim that every inhabitant is fully simulated at maximum fidelity or every soldier rendered simultaneously.
02 / World, Setting & Story
World framework
Original fictional planet with handcrafted macro-geography, ruined surface cities, vast underground complexes, ecological regions and multiple historically distinct civilizations. Procedural systems fill local detail, settlement variation, resources, events and campaign evolution. Nuclear/geopolitical collapse and pre-collapse infrastructure secrets underpin the world; final lore, names and chronology remain open.
Machine civilization
An autonomous industrial civilization with its own nonhuman organizational logic, distributed control, manufacturing and strategic ambitions. It must be materially and behaviorally different from human factions; not a reskinned human army.
Three narrative layers
Handcrafted optional mystery; emergent geopolitical and economic history; individual character stories and generational legacy. No mandatory quest gate for core sandbox play. Knowledge can be partial, false, stale or politically contested.
World lifecycle
Time advances continuously through day/night, seasons and generations. Settlements rise and fall; borders, roads, ecological hazards, technologies and social institutions evolve. Manual pause and optional acceleration exist; switching camera modes does not auto-pause.
03 / Player Experience & Core Loops
Primary loop
Observe needs and opportunities → explore or gather intelligence → plan → acquire labor, knowledge and resources → build, trade, negotiate or fight → experience persistent consequences → adapt.
Survivor loop
Move, interact, investigate, scavenge, craft, maintain health, establish relationships, survive combat and environmental hazards. Player remains physically vulnerable while issuing orders.
Settlement loop
Place structures with smart snapping and previews → assign or delegate jobs → route supplies and utilities → grow population and services → establish defense, trade and research → expand.
Military loop
Recruit and equip → establish officers, doctrine and formations → reconnoiter → plan operations and logistics → execute real-time combined-arms engagements → recover casualties, equipment and territory.
Civilization loop
Set broad priorities and laws → develop economy, infrastructure and diplomacy → monitor institutions and threats → delegate execution → respond to emergent crises and opportunities.
Player origins and legacy
Multiple configurable backgrounds with lone survivor default. Death can lead to successor play, political succession or new character in same world; customizable mortality/legacy rules.
04 / Camera, Controls & Interface
Three seamless perspectives
Close isometric survivor view with WASD/mouse aiming and contextual interaction; overhead tactical RTS with unit selection, queues, formations and command groups; continental strategic map with diplomacy, infrastructure, borders and military theaters. Zoom transitions preserve shared world state.
Intuitive construction
Quick Build (single action), City Plan (drag roads/walls, districts and blueprints), Architect (optional fine-grained modular construction). Preview costs, prerequisites, routes and consequences before commitment. Undo/redo for uncommitted plans; live-world demolition remains consequential.
Information architecture
Contextual radial/action menu, search and filters, layered maps, alerts by urgency, inspector panels, optional automation policies, readable hotkeys, controller consideration. Show outcomes first and expose underlying mechanics on demand.
Exploration and fog
Maps distinguish verified, historical, reported, suspected and unknown knowledge. Information ages; drones, scouts, spies, surveys, documents and expeditions update records. Surface and underground layers use independent exploration state.
05 / People, Society & Survival
Characters
Persistent identity, needs, abilities, relationships, memory of consequential events, loyalty, role, health, injuries, morale and ambitions. Family, aging, leadership and succession matter. Offscreen individuals use lower-frequency or cohort simulation with identity records retained where important.
Societal systems
Food, water, housing, sanitation, health, education, security, leisure, culture, inequality, migration, demographics and social mobility influence settlement outcomes. Granular mechanics should be delegable.
Combat consequences
Grounded lethal combat with wounds, trauma, medical treatment, equipment damage, morale and lasting battlefield scars. Mature gore is configurable in presentation; mechanics do not require gore to communicate damage.
06 / Construction, Environment & Infrastructure
Building system
Modular housing, industry, defense, transport, utilities and civic buildings; customizable compounds, fortifications, underground chambers and megaprojects. Structural rules, construction stages, materials, workforce and maintenance apply.
Terrain and persistence
Excavation, trenches, tunnels, fires, flooding, collapses, destroyed structures, wrecks and reconstruction alter navigation, cover, resources and ownership. High-fidelity local destruction is translated into persistent regional state.
Networks
Road, rail, power, water, communication, storage and supply networks connect settlements. Smart connection suggestions prevent busywork; advanced routing remains available.
07 / Economy, Technology & Politics
Economy
Physical resource extraction, inventories, transport, factories, markets, households, labor, trade, prices, taxation, banking, debt, smuggling, shortages and crises. Aggregate faraway production while preserving quantities and constraints.
Research and engineering
Separate scientific knowledge, practical design, prototypes, production tooling and industrial scale. Scientists experiment; reverse engineering, espionage and knowledge loss create alternate development paths.
Politics
Distinct governmental structures, laws, legitimacy, institutions, parties, factions, elections, coups, succession, diplomacy, sanctions, rebellions and negotiated treaties. New states can emerge, split, merge and collapse autonomously.
08 / Warfare and Military Organizations
Force structure
Units form squads, platoons, companies, battalions, brigades and larger commands as relevant to doctrine. Player can customize ranks, equipment, training, uniforms, organizations and procurement. Officers hold delegated objectives and operational authority.
Domains and scale
Infantry, armor, artillery, drones, aircraft, helicopters, naval and underground operations. Theater-level engagements may involve very large force totals; nearby actors receive detailed simulation, distant formations are abstracted. A large roster is not a promise of simultaneous on-screen sprites.
Operational factors
Recon, fog, terrain, weather, supply, fatigue, morale, communications, casualties, experience, doctrine, fortification and civilian effects change outcomes. Armies should retreat, regroup and exploit opportunities rather than mindlessly attack.
09 / Autonomous Intelligence
AI hierarchy
Individuals: behavior trees, utility selection, memory and needs. Organizations: work allocation, inventories, policies and commanders. Civilizations: strategic goals, diplomacy, economic priorities and threat assessment. A bounded planner coordinates levels through orders and reports.
Adaptation
Commanders and institutions record outcomes and revise tactics, doctrine, trade, research and political posture using transparent rule-based/statistical adaptation. No required per-NPC LLM or runtime model training.
Player observability
Explainable decisions through reports, rumors, officer briefings, timelines and inspection tools. Rival civilizations should show preparatory behaviors before war, not appear to cheat. Knowledge and resource constraints also apply to AI.
Dialogue
Offline structured dialogue is the reliable baseline; richer local-model conversations may be optional later. NPC speech must never silently mutate authoritative world state outside validated action interfaces.
10 / Art, Audio & Atmosphere
Visual direction
Premium cinematic high-detail pixel art with grounded, gritty post-apocalyptic art direction. Layered 2.5D depth, physically inspired lighting, atmospheric fog, dust, rain, smoke, fire, weather, interior glow and massive underground vistas.
Scale-aware rendering
Close zoom emphasizes sprite detail and animation; tactical zoom prioritizes silhouettes, cover, formations and projectiles; strategic zoom shifts to symbolic readable infrastructure and territorial information. LOD, instancing, impostors and aggregated effects preserve frame rate.
Audio
Reactive soundscape: distant industrial ambience, weather, localized weapons, underground reverberation, civilian bustle, layered battle sound, contextual music. Accessibility options include subtitle and visual-alert equivalents.
Presentation constraints
Pixel density, sprite proportions, camera tilt, lighting model, UI palette and animation frame budgets need a visual bible and early proof-of-concept. Cinematic fidelity must not conceal gameplay information.
11 / Progression, Challenge & Accessibility
Progression
Growth emerges from knowledge, production, relationships, territory, institutions and experience rather than a single universal tech tree. No mandatory victory state; optional achievements, scenario goals and world-history milestones.
Difficulty
Separate controls for survival pressure, economic complexity, aggression, mortality, automation, pacing and presentation. Avoid punitive complexity spikes; teach advanced mechanics through optional contextual prompts.
Accessibility
Remappable inputs, adjustable UI scale, color-safe overlays, subtitle controls, reduced flashing, gore toggles, pause and simulation speed, readable alerts and input assistance.
12 / Vertical Slice & Acceptance Tests
Playable region
One handcrafted region with surface and limited underground layer, two competing autonomous factions, one player origin, one small settlement, a modest economy and a bounded battlefield.
Must demonstrate
Direct character movement and interaction; fog and exploration; intuitive building; needs and logistics; independent rival construction; recruitment and command; switching camera scales; persistent combat damage; save/load; useful debug overlays.
Acceptance tests
A player can found a functioning settlement without reading a manual; rival AI expands without scripted player triggers; soldiers obey orders and consume supplies; a destroyed bridge changes travel routes; save/reload preserves entities, inventories, knowledge and damage; performance stays within measured prototype budgets.
Explicitly deferred
Global continent streaming, full naval/air fleets, elaborate electoral politics, thousands of high-detail simultaneous units, extensive procedural diplomacy, deep local dialogue models and orbital warfare.
13 / Risks, Scope & Open Decisions
Primary risks
System interactions may overwhelm testing; distant simulation may diverge from local reality; seamless zoom is costly; persistent destructible worlds inflate save size; AI may feel arbitrary; high-detail art content production may dominate schedule.
Mitigations
Vertical slices, deterministic replay, simulation invariants, authoritative world-state model, data-driven content, simulation dashboards, automated soak tests, profiled budgets and progressive fidelity.
Still undecided
Final game title; canon factions and history; exact world dimensions; target OS/hardware; pixel scale and camera geometry; final art pipeline; specific combat ballistics; economy formulas; narrative cast; modding policy; monetization/distribution; team size and production schedule. Do not treat these as finalized.


## Approved DLC addendum — 2026-11-27
Full approved expansion design is incorporated by reference: [master DLC GDD](../../game/docs/BEYOND_CIVILIZATION_GDD.md). UNDERSTRIKE is base-game content, DLC 2 is one home system and DLC 3 the finite interstellar frontier. Campaign outcomes directly affect starting conditions; classic RTS controls and automation remain mandatory.
