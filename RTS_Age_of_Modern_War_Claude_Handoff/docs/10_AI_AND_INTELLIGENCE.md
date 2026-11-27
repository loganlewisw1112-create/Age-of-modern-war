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
Four existing directors remain; DLC 3 adds [XENOGENESIS](../../../game/docs/XENOGENESIS.md), with 20 logical subsystems and shared authority, imperfect information, bounded plans, and no default AI cheats. [Forge integration](../../../game/docs/MYRIEME_FORGE_INTEGRATION.md) supports communication and evolution.
