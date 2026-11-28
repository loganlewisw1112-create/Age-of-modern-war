# CONQUEST GDD

Owner-approved expanded design direction, 2026-11-27. All features planned; implementation and acceptance pending. Working names, proposed interfaces and test IDs are not source code or frozen gate contracts. Existing G10.1 regression remains open.

## Purpose
Meaningful territory rather than painted map or mandatory HQ elimination; traditional build, train, research and fight with a compelling capture -> consolidate -> fortify -> exploit -> expand -> adapt loop. Territory should confer actual infrastructure, resource and military opportunities, not magical income. Reuse existing control, logistics, trade, territorial victory and geopolitical rules.

| ID / scenario | Strategic emphasis | Win options |
|---|---|---|
| CQ-01 Territorial Supremacy | Hold connected strategic regions | Weighted control/hold duration, dominance or elimination |
| CQ-02 Industrial Dominance | Secure factories, depots, resource/transport hubs | Sustained productive capacity, resource throughput or economic objective |
| CQ-03 Regional Warfare | Multiple linked military sectors and fronts | Capture designated regions or defeat enemy command |
| CQ-04 Coalition War | Team competition and optional shifting alliances | Team control, negotiated objectives or agreed dominance; betrayal only opt-in |
| CQ-05 Technological Supremacy | Secure research facilities, materials and tooling | Legal research milestones/production or strategic site control |
| CQ-06 Total Conquest | Combined economic, territorial, political and military contest | Custom linked conditions, persistent war or endless |

Sector {stable_id, boundary, neighbor_links, control, contested_state, infrastructure_ids, resource_access, supply_access, capture_progress, objective_weight}; control derived from existing legal presence, objectives and security, not color alone. Capture changes access/ownership via ledger; occupation does not conjure resources or technology. Damaged assets require repair and eligible personnel/tooling. A surrounded region may be held but cannot receive unmodeled supply. Isolated formations may retreat, request support or surrender where existing mechanics permit. Frontlines calculated from control, movement and logistical graph; command AI uses observed info. Recon, flanking, alternate supply and defense offer options. Major breakthroughs reward real captured capabilities; no rubber-band spawns, artificial punishment or arbitrary health multipliers. Stalemate prevention through map diversity, meaningful objectives, legal time/score rules and actual alternative opportunities, not forced win.
 
Quick balanced starts, asymmetric scenarios, varied map sizes, one-click presets or advanced customization (resources, stage, terrain, control criteria, diplomacy, fog, economy, time, teams). Generated maps validate access to critical infrastructure, multiple plausible paths and legal spawn/industry; equal opportunity for ranked presets, asymmetric starts labeled. Short matches or persistent regional wars, all scenario families offline, online co-op/PvP compatible. Score and control state clear, readable frontline overlay optional. Victory evaluation reuses shared AND/OR/time/hold framework, no silent incompatible rules. Capture events drive strategic objectives and historical records. No civilian paperwork. Preserve DLC faction and Human A construction restrictions.

## Acceptance
Six scenarios with distinct win strategies, no duplicate ownership/resources, no fake supply, meaningful disconnected territory, AI can consolidate/recover without micro, validated varied maps, clear contested/control UI, replay/save consistency and online fog/score authority. Playtest for momentum, counterplay, multiple viable doctrines and no endless compulsory mop-up. [Scenario engine](DYNAMIC_SCENARIO_ENGINE.md) · [Operations](OPERATIONAL_INTELLIGENCE.md).
