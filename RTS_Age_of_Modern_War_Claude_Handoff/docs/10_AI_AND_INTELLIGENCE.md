# Autonomous AI, fairness and intelligence

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [Technical_Architecture_v1.0](../source_text/Technical_Architecture_v1.0.md), [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md)

10. Autonomous Enemy Civilizations
AI exists at individual, squad, officer, faction economy and civilization-strategy tiers. In first playable, all three factions can construct, mine/gather, produce, research, scout, defend, attack, replace losses and pursue victory without scripted player triggers. Competitors may fight one another when configured as opposing teams. AI uses the same command validator, inventories, research permissions, fog and decision costs as a player. Plans have traceable reasons and finite computational budgets; uncertainty and outdated intel persist. Full game adds durable institutional memory, adaptive doctrine, treaties, internal politics, leaders and generational change.

05 / AI Architecture
Decision hierarchy
Civilization planner (strategic cadence) → institution and operational planners (medium cadence) → squads, workers and characters (local cadence). All planning has explicit CPU/time budgets and graceful fallbacks.
Algorithms to prototype
Utility AI + GOAP for characters; behavior trees/state machines for tactical behavior; hierarchical task networks for organizations; influence maps and cost-aware graph search for strategy; bounded Monte Carlo/lookahead only where profiling justifies it.
Memory and adaptation
Event summaries, persistent rival models, tactic outcome statistics and relationship changes. Explanations exposed to player and developer through inspectable decision traces.
Dialogue
Finite/stateful dialogue and authored templates initially. Optional local language-model adapter behind validated intent/action boundary, not part of core simulation or required hardware.

## Proposed implementation behavior

Strategic loop: evaluate known resource security/threat/objectives → allocate economy and military budgets → schedule scouting, construction, research and production → issue bounded operations → assess outcomes. Tactical loop responds to threats, cover, supplies and retreat conditions. Separate machine energy/network bottlenecks from human workforce/fuel needs.

Difficulty modifies decision cadence, candidate quality, risk and coordination within budgets. Any configurable starting handicap is visible in setup. Hidden resource grants or omniscient target access violate the baseline. Known contact age/confidence and observation source must be inspectable. Remembered intelligence must follow explicit target-location and expiry rules.

AI autonomy test starts with finite opening assets and no player-triggered events: log gathering, legal construction, production, research, scouting, defense, enemy-AI engagement and recovery. Record rejected commands, planner time, stalled goals, next action and observer-filtered contacts. A stationary enemy firing on a timer does not prove autonomous civilization behavior.


## Approved DLC addendum — 2026-11-27
Four existing directors remain; DLC 2 adds [XENOGENESIS](../../game/docs/XENOGENESIS.md), with 20 logical subsystems and shared authority, imperfect information, bounded plans, and no default AI cheats. [Forge integration](../../game/docs/MYRIEME_FORGE_INTEGRATION.md) supports communication and evolution.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Four base directors, XENOGENESIS fifth in DLC 2, Chronicle shared framework; no duplicate world state. Nine commander directives; competence and knowledge limits.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## G18 current approved design authority

G18 final base game: internet multiplayer, independently owned open-source gaming platform, Last Protocol online co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN) and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE remains integrated, Human A-exclusive construction rights unchanged, not a standalone expansion. Neither new mode has individual soldier-follow. All XENOGENESIS and Myrieme Forge accepted by G17. G19 Space Expansion (DLC 1), G20 Beyond Civilization (DLC 2) only after G18; civilization continuations offline, compatible owned content in Skirmish. No mandatory platform login offline. Planned only.

Four general directors, fifth XENOGENESIS (accepted by G17), PATHOGEN and DEEPWAR mode-exclusive G18 directors; all share validator, ledger and simulation, no omniscience or duplicate state.

[G18 MASTER GDD](../../game/docs/G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](../../game/docs/G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](../../game/docs/G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](../../game/docs/DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](../../game/docs/PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](../../game/docs/SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](../../game/docs/DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](../../game/docs/G18_DELIVERY_PLAN.md)


## Expanded gameplay authority — 2026-11-27

Current owner-approved expanded design: G11–G18 integrates 33 additions and five additional modes (34 scenario families), three shared systems, procedural world/fortresses, creator/SDK/Workshop/Store, replay/spectators/records, player experience, independent platform and release qualification. G18 finalizes eleven base-game experiences. Inheritance/Living World offline solo only; no additional global directors or new official DLC playable factions outside Skirmish; Human A-only bunker/borer construction. G17 full XENOGENESIS/Myrieme Forge acceptance unchanged; G19 then G20 after G18. Planned only; no source changes or milestone acceptance.

Seven directors unchanged; 13 doctrine presets, bounded commander profiles, operation templates, causal strategic objectives, simple recovery and reorganization/modernization. No omniscience or duplicate authority.

[Expanded master](../../game/docs/EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Delivery and acceptance](../../game/docs/EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Scenario engine](../../game/docs/DYNAMIC_SCENARIO_ENGINE.md) · [Operations](../../game/docs/OPERATIONAL_INTELLIGENCE.md) · [Archive](../../game/docs/WORLD_ARCHIVE.md) · [Creator toolkit](../../game/docs/CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Platform](../../game/docs/PLATFORM_PRODUCT_ROADMAP.md).
