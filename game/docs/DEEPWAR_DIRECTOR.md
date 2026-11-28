# DEEPWAR DIRECTOR

Owner-approved G18 design direction; implementation pending. Engineering contracts, candidate algorithms and schemas below are documentation-only proposals, not runtime code. Existing source, assets, saves and gate completion statuses are untouched.

## Mode-only authority
Exclusive to SUBTERRANEAN WARFARE's five scenarios. Does not become the base game's underground AI or activate in Inheritance/Living World/DEAD SECTOR; reuse existing ordinary underground AI and shared simulation. Candidate logical components:
| ID | Responsibility |
|---|---|
| DW-01 | Fog-limited reconnaissance, belief map, concealed facilities and intelligence provenance |
| DW-02 | Hierarchical rival commanders, doctrine/personality, authority and objectives |
| DW-03 | Strategic territorial development, autonomous settlement/industry |
| DW-04 | Faction-legal excavation, support, construction, route planning and fortification |
| DW-05 | Tactical assaults, breaches, defense, reserves and counteroffensive scheduling |
| DW-06 | Physical logistics, power/air/water, transport capacity and resupply priorities |
| DW-07 | Geology, damage, collapse, flooding, repair and persistent route changes via existing systems |
| DW-08 | Adaptive doctrine/countermeasures based on observed history; bounded learning |
| DW-09 | Surface/underground combined operations, multiple-floor conflict coordination |
| DW-10 | Alliances, rivalries, dynamic objectives and military crises |
| DW-11 | Delegation, direct takeover and multiplayer AI substitution |
| DW-12 | Hierarchical fidelity, deterministic intent arbitration, save/replay and performance |

Operation {id, issuer, scope, objective, observed_tick, force_ids, reserved_supplies, route_refs, constraints, phase, contingency}; Belief {faction, region, evidence, confidence, last_observed_tick}; Sector {id, floor, links, controller, structure_ref, logistics_state}; EngineeringIntent {id, faction, site, legal_capability, material_budget, work, stability_check, dependency_ids}; DoctrineMemory {faction, observations, counter_preferences, limits, history_cursor}. No simulated knowledge of undiscovered facilities. Existing geometry/physics/economy are authoritative. Use route/stability validation and cost reservation before engineering; other factions may not construct protected assets. No free reinforcements or instant breakthroughs. Preserve original UNDERSTRIKE constraints and existing battle rules. Director evaluates opportunities from true constraints and observed state, with bounded randomized alternatives. Actual command latency, supply and route viability; player may surprise AI. Player takeover cancels/reconciles conflicting queued intents without rollback of completed work.

```text
# illustrative, not executable
for commander in stable_order(due_commanders):
    belief = read_observed_state(commander)
    plans = bounded_candidates(belief, doctrine, objectives)
    for plan in ranked(plans):
        if conflicts_with_manual_control(plan): continue
        if legal_faction_capability(plan) and viable_route(plan):
            propose_intent_with_budget(plan)
validate_reserve_commit_via_shared_authority()
```
Active engagements fine detail, adjacent networks bounded operational state, distant forces cohorts with conserved supplies, wounds, casualties, route time, territorial and structural state. Camera changes never affect outcomes. Deterministic seeds, event IDs, authority epochs and saved plans; host only decides in online match; per-team fog and visible presentation events. No separate underlying engine. Test illegal bunker/borer requests incl capture, route destruction, delayed breakthrough, fog, competing commanders, logistics conservation, collapse/repair persistence, player override, cross-floor replay, AI replacement, host migration, no off-mode work, stress and accessibility. Exact budgets and doctrine tuning pending.
