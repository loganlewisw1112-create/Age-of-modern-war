# OPERATIONAL INTELLIGENCE

Owner-approved expanded design direction; implementation pending. Proposed IDs, interfaces and pseudocode are design artifacts only. Reuse the Godot/Rust simulation, current director scheduler, validators and event ledger.

## Shared military service, not a new director
One interface for existing military AI, player-delegated commands and directors to propose legal operations. Player manual control has precedence over delegated scope; no mandatory micro. Doctrines bias priorities, never bypass faction/stage, budgets, fog, command jurisdiction or actual forces. No global omniscient planner. Four general directors and two mode-specific directors use existing authority; XENOGENESIS adapters only in relevant content.

## Advanced doctrine catalogue
| Doctrine | Policy emphasis |
|---|---|
| Armored Warfare | Mechanized formations, armor, maintenance |
| Mobile Warfare | Maneuver, mobility, flexible reserves |
| Defensive Warfare | Fortification, defense, security |
| Attrition Warfare | Sustainable pressure, endurance, reserve planning |
| Air Dominance | Aviation, reconnaissance and legal airfield capacity |
| Naval Dominance | Maritime operations, ports, transport |
| Asymmetric Warfare | Faction-legal intelligence, covert and disruption roles |
| Autonomous Warfare | Robotics, drones and network support where available |
| Combined Arms | Complementary service branches |
| Expeditionary Warfare | Long-distance staging and supply |
| Underground Warfare | Existing legal underground roles, no new construction rights |
| Adaptive Doctrine | Adjust within authorized bounded priorities based on observed history |
| Custom Doctrine | Player-selected low/normal/high priorities, optional detailed overrides |

Existing faction-specific doctrine unlock/lock rules remain, including any DLC doctrines; generic policy selection does not grant prohibited tech or change locked doctrinal choices. Era/faction availability and capability warnings before applying. Candidate DoctrineProfile {id, faction_scope, stage_range, weight_vector, eligible_roles, research_bias, logistics_bias, reserve_policy, adaptation_bounds, version}. AI commander personality {id, profile, competence, caution, flexibility, observed_history, authority_scope}; strategy varies with doctrine, competence and real intelligence, not health multipliers or hidden map information. Learning bounded and reproducible; no external model runtime. Player chooses one preset or a few priorities, commanders optimize routine decisions. Display short reason for recommendations.

## Operation templates
| Order | Automated work |
|---|---|
| Secure Region | Recon, deploy, hold/patrol and support |
| Assault Stronghold | Organize eligible forces, coordinate staging, supply and attack |
| Establish Military Base | Validate template/site, construction, logistics, security |
| Reinforce Frontline | Reserve personnel/equipment, travel, deliver and assign |
| Conduct Expedition | Explore, support, recover and return |
| Recover Forces | Withdrawal, evacuation, medical and repairs |
| Maintain Defense | Patrol, reserves, resupply and repair |
| Launch Counteroffensive | Counter current threat with available forces |

Operation {id, issuer, faction, scope, objective_ref, priority, ruleset, force_ids, reserve_ids, approved_budget, phase, dependencies, observed_tick, contingencies, last_report}. Phase: proposed -> validated -> assigned -> staging -> executing -> sustain -> completed/failed/withdrawn; pause/cancel/replan at safe transaction boundary. Conflict resolution by manual claims, explicit authority scopes, standing priorities, stable deterministic order. Reserve resources/units atomically; release unused reservations on cancel/failure. Reassign operations when legitimate conditions change; do not endlessly loop on impossible routes. Report blocking reason and one meaningful action. Delegate commander, target, priority; manual intervention on any authorized force, then explicitly or by policy resume delegation. Compatible online shared roles and host authority, no double claims. Use current command bus; no mutation from HUD, archive or planner.

## Strategic objectives, recovery and modernization
Objective proposals generated from observable conditions (isolated forces, research discoveries, failing allied infrastructure, changing territory); cause event IDs, valid location, eligible owners, objective options, expiry/conditions, consequence refs, visibility. Deduplicate and cap concurrent offers; optional objectives may be ignored, actual simulation continues, no artificial punishment or reward conjuring. Authored story beats protected. Major choices only; tactical reports concise.

Recovery priority: Minimal (essential), Standard, Military Priority, Full Reconstruction. Existing medical, engineering, civilian, transport, supply and salvage execute automatically with finite access/personnel/materials. Stabilize -> recover -> repair -> rebuild; persistent scars and missing assets remain until repaired. No free material or resurrection. Report blocked work; preserve player veto. Do not auto-rebuild deliberately demolished or forbidden structures without policy/approval.

Reorganization: split/merge surviving formations, transfer to armies/reserves, change commander/HQ, refit equipment, preserve personnel/equipment/IDs and lineage via archive; never duplicate or erase casualties. Modernization: choose formation/facility and target legal upgrade; existing tech/tooling, cost, downtime, delivery, refit, replacements and redistribution/salvage/export as appropriate. Keep usable legacy equipment if supply unavailable. Preview tradeoff, one order and progress summary. Optional loadout/configuration templates only for supported equipment categories, default standard units unchanged; no mandatory part design.

## Candidate flow
```text
read observer-scoped state and manual claims
collect eligible director/commander/player intents
rank bounded plans by doctrine, objective, legal resources
validate faction rights, route, scope, reservations
commit through shared ledger in stable order
publish progress and observable outcomes to archive/UI
```
Budget planning per active region/commander, coarse distant aggregate state, unchanged deterministic outcomes across camera views. Save operation cursor, reservations, doctrine/profile, contingency and authority epoch; reconcile on load and migration. Test legal/illegal orders, doctrine constraints, fog, conflicting claims, takeover, reorg and modernization conservation, recovery, objectives and bounded scheduling. Foundations G12–G13; campaign/world integration G15–G17; online G18. [Archive](WORLD_ARCHIVE.md) · [Scenario engine](DYNAMIC_SCENARIO_ENGINE.md).
