# SPACE EXPANSION GDD

Owner-approved direction, 2026-11-27. PLANNED / NOT IMPLEMENTED. All examples are non-executable documentation guidance. No runtime changes or gate changes authorized.

## Design authority
DLC 1 = Space Expansion (G19); DLC 2 = Beyond Civilization (G20); UNDERSTRIKE is base game. True Dynasty is the primary earned path: Inheritance → Living World → DLC 1 → DLC 2, preserving consequential history and requiring prior progression. Separate new saves may independently start either owned DLC with preset or customized coherent historical state, never modifying Dynasty saves; standalone DLC 1 may continue to DLC 2. New DLC factions playable only in Skirmish; campaign/Living World retain inherited civilization and AI opponents. Campaign personally played battle requirements unchanged. Offline, classic RTS controls, no mandatory micromanagement. Existing gate statuses, six aerospace hull rosters, arrival war and campaign endings protected.

## Decision register
1. B+ Original fictional star system; protect homeworld canon
2. C Twelve planets, 48 moons, five belts
3. D+ Diverse worlds and exotic resources
4. A+C, some B Specialized moons, selective colonization
5. D Dynamic asteroids and finite extraction
6. D Modular orbital cities and megastructures
7. D+ Causal hazards, opportunities, automated routine responses
8. D Research and reverse engineering
9. D+ Player-founded bases, then autonomous development
10. D+ Realistic commanders with limited knowledge and competence
11. D Physical automated logistics
12. D Persistent exploration and competing discoveries
13. D+ Persistent multi-domain warfare
14. D Interactive 3D stellar view and hierarchical RTS navigation
15. D+ Autonomous civilization evolution
Final decisions: Hidden History D+; physical realism D; revolutionary technology D+; continuity A primary plus B/C independent saves. Stellar design: individual physical profiles and realistic dimensions; solid surfaces only where appropriate; individually authored moons and dynamic belts. Names and exact numerical specifications provisional.

## Seven nonlinear gameplay phases
1. Race to Orbit — aerospace recovery, launches and sustainable orbital footholds
2. Orbital Supremacy — stations, defense, shipyards, orbital factories
3. Lunar and Asteroid Expansion — personally establish extraction, research and military bases, delegate
4. Age of Discovery — exotic resources, ancient technology and optional mysteries
5. Interplanetary Civilization — autonomous colonies, cities and physical trade
6. War for the Star System — multi-domain warfare and preserved arrival war
7. Beyond the System — advanced propulsion, megastructures and interstellar readiness
Not new numbered civilization stages, mandatory quests or separate releases. DLC 1 remains indefinitely playable alone. Player selects, builds, researches, produces, moves, attacks, delegates and intervenes. System/planet/orbit/region/tactical/local views share authoritative state. Godot presentation and Rust simulation reused after actual interface audit.

## Continuity contract
Proposed save header: {schema_version, save_id, lineage_id, start_kind: Dynasty|Preset|Custom, parent_snapshot_id, progression_flags, content_entitlements, world_seed, tick, catalog_version}. Persist population, factions, commanders, territory, tech, resources, infrastructure, fleets, diplomacy, discoveries, history and pending conflicts. Ownership grants access, not free advancement. Independent saves have fresh IDs and validated historical initialization. Missing DLC retains compatible bounded history without full unowned simulation. Transactional migration and rollback fixtures required. Signals propagate with delays. Preserve thirteen stages and campaign endings.

[SPACE EXPANSION GDD](SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](SPACE_EXPANSION_DELIVERY_PLAN.md)


## Corrected owner-approved execution sequence

G11–G17 full XENOGENESIS and Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization (DLC 2). Both systems must be fully implemented, integrated, tested and accepted by G17 exit (before G18 and G19): all 20 XENOGENESIS subsystems; all 15 Myrieme Forge engines and eight integration adapters, including offline runtime. Earlier development is permitted. G20 interstellar gameplay/content production happens after G19; G11–G17 testing uses representative fixtures without requiring full G20 content or exposing unowned DLC. No implementation or gate completion is claimed.


## G11–G17 integrated system development — current owner authority

G11–G17 integrated development of XENOGENESIS and full Myrieme Forge; both fully implemented, integrated, tested and accepted as mandatory G17 exit criteria. G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization. No separate integration checkpoint; G20 gameplay and full universe content production remain after G19. All 20 XENOGENESIS subsystems, 15 Forge engines and eight integration modules, offline runtime and shared director interoperability required by G17. Representative validation fixtures, not premature DLC gameplay; ownership boundaries remain. See the current ROADMAP and DLC delivery plan for per-gate assignments. No implementation or gate completion claimed.


**Current gate authority:** G17 Living World and full XENOGENESIS/Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion (DLC 1) → G20 Beyond Civilization (DLC 2). Both DLCs begin only after the base game is complete. No runtime changes or gate completion claimed.


## G18 current approved design authority

G18 is final base-game completion: internet multiplayer, independently owned open-source gaming platform, Last Protocol co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN), and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE is an integrated Human A gameplay branch, not a separate expansion; dedicated warfare scenarios reuse it. New modes preserve existing faction rights, use traditional RTS controls and have no individual soldier-follow cameras. XENOGENESIS and Myrieme Forge must be fully accepted by G17. G19 Space Expansion and G20 Beyond Civilization follow G18 acceptance; civilization continuations remain offline, compatible owned expansion content extends Skirmish only for new playable DLC factions. No mandatory platform login offline, no Steam dependency. All G18 additions planned, not implemented.

[G18 MASTER GDD](G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](G18_DELIVERY_PLAN.md)


## Expanded gameplay design integration — 2026-11-27

DLC 1 follows full expanded G18 acceptance. Compatible templates, scenario/world generation, replays, creator and operational systems may extend into owned space content at G19. No new official DLC playable factions outside Skirmish, no online Dynasty, home system and arrival canon unchanged.

[Expanded master](EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Integrated delivery](EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Shared scenario engine](DYNAMIC_SCENARIO_ENGINE.md). No implementation or gate completion claimed.
