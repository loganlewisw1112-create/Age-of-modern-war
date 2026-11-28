# WAR THEATRE GDD

Owner-approved expanded design direction, 2026-11-27. All features planned; implementation and acceptance pending. Working names, proposed interfaces and test IDs are not source code or frozen gate contracts. Existing G10.1 regression remains open.

## Purpose
Persistent military-focused campaigns bridging Skirmish and Living World; command armed forces across connected battlefields without mandatory civilian civilization management. Not a second Inheritance campaign, not an online Living World, no new director. Uses existing regional view, operational command, military institutions, logistics, persistent formations and territorial state.

| ID / family | Operational scope | Objectives |
|---|---|---|
| WT-01 Regional Campaign | Linked battlefields and strategic hubs | Secure/defend region and military infrastructure |
| WT-02 Continental War | Multiple armies and large frontlines | Defeat competing headquarters, control selected fronts or meet treaty objectives |
| WT-03 Expeditionary Campaign | Remote deployment with finite reserves | Establish staging, sustain force and complete distant objectives |
| WT-04 Defensive Campaign | Invasion pressure across several sectors | Hold critical territory, preserve forces, reverse enemy gains |
| WT-05 Coalition Campaign | Multiple allied military organizations | Coordinate objectives and shared resources by rules; allied or independent commands |
| WT-06 Liberation Campaign | Occupied cities and regions | Recover priority locations, restore essential infrastructure and secure routes |
| WT-07 Total War Theatre | Persistent dynamic campaign sandbox | Defined strategic win or endless operations with evolving rivalries |

Theatre graph nodes = regions, airfields, ports, industrial centers, bases and objective areas; edges = valid road/rail/sea/air/underground movement classes, travel time, throughput, accessibility, control. Stable formation IDs, inventory/equipment/personnel, fatigue, wounded, commander, position/route and reserves transfer between battles; losses, captured/damaged infrastructure and supply consequences persist. Deployment is a transaction: reserve force, move for actual travel time, instantiate local detail without duplication, commit outcome and demote back to strategic state. Camera never decides results. No magically resetting units or replenishing every battle. Distant AI fronts use bounded aggregate state with conservation and visible reports; player can enter eligible tactical battle at safe transition or delegate under standing policy. Existing Inheritance personally played battle rule unchanged. No compulsory civilian zoning, administration or tax. Existing military economy/industrial constraints still meaningful. Player selects theatre objective, commander and priority; operations/replenishment/rotation/medical/repair automated; manual RTS intervention available. Operations generated from actual conflicts, intel and capacity, not endless generic missions.

Offline solo, compatible online co-op/shared command or competing theatres proposed via same host-authoritative session system, saved/resumable when hosted; no continuously online campaign universe. Exact scale, lobby count, cross-battle transition sync and objective rules validated before online launch. No merge with Dynasty. Quick operation can be part of theatre history; long save supports pause/speed solo, save backup/migration, optional summary and archive. Shared map/scenario editor supports linked nodes and validated transfer conditions. Existing faction and DLC rules. [Operational intelligence](OPERATIONAL_INTELLIGENCE.md) · [Archive](WORLD_ARCHIVE.md).

## Acceptance
All seven campaign families, persistent formation/equipment/casualty/infrastructure continuity, travel/route changes, no duplicated resources on promotion, autonomous fronts and manual intervention, linked battles save/reload and replay evidence, offline no-account, compatible online sessions and reconnect, understandable strategic UI, performance measured on multi-region fixtures. No mandatory civil management or new director.
