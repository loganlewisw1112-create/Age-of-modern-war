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