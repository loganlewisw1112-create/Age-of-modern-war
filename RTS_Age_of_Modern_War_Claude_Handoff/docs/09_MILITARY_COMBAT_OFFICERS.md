# Military roles, combat and delegated command

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md)

8. Military Production and Organization
Players recruit individual soldiers or complete squads, train specialties and manufacture vehicles/equipment with explicit queues. Soldiers can be composed into squads, platoons and companies with customizable weapon roles and doctrine. Officers receive formation membership and bounded order authority. Equipment templates, group rally points and replacement policies reduce clicks. Full-game expansion includes battalions, brigades, divisions, procurement programs and cross-region support structures; distinct military branch structures need not be identical for machines.
8.1 Layered orders
Direct: move, attack, attack-move, hold, stop, patrol, guard, repair, reload or retreat. Tactical: multi-waypoint movement, formations, sectors, priority targets, recon, overwatch/suppression. Delegated: assign officer objective, zone, assets, priority, risk limit and authority; they respond autonomously and report status. Strategic (full): operational phases, reserves, front lines, supply limits, conditional objectives and theater coordination. Players can override their own officers at any time.
9. Realistic Combat and Recovery
First playable includes range and dispersion, visible projectiles where useful, directional armor, cover, suppression/morale, fatigue, ammunition and fuel, threat detection, drones/scouting, vehicle component states (mobility, main weapon, sensors, communication), basic casualty/injury outcomes and a limited but real persistent destruction set. Weather and stage-9 electronic warfare affect sensors/target quality. Commanders can seek cover, defend, withdraw, request resupply and coordinate formations within competence constraints.
No soldier should just stand exposed while automatically trading health. No weapon or vehicle bypasses supplies or meaningful counterplay. Advanced physics, medical trauma detail, expansive terrain cratering and complex acoustic/ballistic modelling are full-game aspirations and must be benchmarked. Disabled vehicles may remain salvageable; bridges, industrial buildings and routes may be ruined and must be repaired. Mature graphic presentation is optional; mechanics are independent of gore.

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

## Proposed combat integration checklist

Resolve observation/target eligibility before firing; check range, line of sight, ammunition, weapon/component state and orders. Record attack cause and damage result for debugging. Separate health/destruction, mobility, weapon, sensors and communications; a mobility kill may leave a functioning turret. Cover, armor facing, dispersion and suppression need explainable feedback and tunable formulas.

Model wounded, dead, disabled and salvageable outcomes distinctly where implemented. Remove killed actors from control groups and future orders while preserving casualty/equipment accounting. Repairs and replacements consume resources. Projectile and area-effect behavior, friendly fire and aircraft flight rules remain design decisions.

Officer mission proposal: objective, zone, assigned assets, priority, risk bound, authority, supply limit and status. Phases could include assess, move, secure, hold, resupply and withdraw. Manual player override cancels or supersedes delegated intent under a documented policy. Persist membership, mission, progress and reason for replanning.

JPEG taxonomy is a broad military concept sheet: infantry specialties; light vehicle/APC/IFV/MBT/AA/artillery/rocket/recon/engineering/logistics; helicopters/jets/drones/VTOL; naval classes; emplacements; mobile HQ/comms/recovery. It is not a final roster or balanced production catalog. First slice minimum roles remain builders, infantry equivalent, recon/specialists, mobile/heavy combat, artillery and logistics for each faction.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Shared multi-domain warfare and physical supply; preserve six space hull rosters and arrival-war outcomes; commander scopes and manual takeover.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## G18 design integration

Current G18 design: offline solo remains; Inheritance/Living World strictly offline single-player; internet Last Protocol co-op, Skirmish co-op/PvP, DEAD SECTOR and SUBTERRANEAN WARFARE. Independently controlled open-source gaming platform; indie-cost direct hosting and relay fallback; mode-exclusive PATHOGEN and DEEPWAR. UNDERSTRIKE is an integrated Human A branch, not DLC. G17 full XENOGENESIS/Myrieme Forge acceptance; G18 final base game; G19 Space Expansion; G20 Beyond Civilization. No code changes or implementation claimed.

Retain command scope, logistics, faction restrictions and takeovers; G18 co-op claims and autonomous replacement, DEEPWAR limited to its dedicated scenarios.

[Master GDD](../../game/docs/G18_MASTER_GDD.md) · [G18 delivery](../../game/docs/G18_DELIVERY_PLAN.md) · [Networking](../../game/docs/G18_ONLINE_MULTIPLAYER.md) · [Platform](../../game/docs/G18_OPEN_GAMING_PLATFORM.md) · [New mode designs](../../game/docs/DEAD_SECTOR_GDD.md), [SUBTERRANEAN WARFARE](../../game/docs/SUBTERRANEAN_WARFARE_GDD.md).
