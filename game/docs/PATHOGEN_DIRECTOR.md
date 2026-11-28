# PATHOGEN DIRECTOR

Owner-approved G18 design direction; implementation pending. Engineering contracts, candidate algorithms and schemas below are documentation-only proposals, not runtime code. Existing source, assets, saves and gate completion statuses are untouched.

## Authority and subsystem contracts
Mode-exclusive director for DEAD SECTOR only; not active in campaign, Living World, Skirmish, Last Protocol or SUBTERRANEAN WARFARE. Uses shared event ledger, combat, navigation, resources, environmental state, AI and deterministic scheduler, no parallel authoritative engine. Candidate 12 logical subsystems:
| ID | Responsibility / outputs |
|---|---|
| PA-01 | Infection transmission, exposure, incubation, conversion and population conservation; fictional game model |
| PA-02 | Strains, mutation, inheritance, environmental adaptation; bounded tradeoffs |
| PA-03 | Hordes, migration, clustering, navigation, noise/light responses |
| PA-04 | Regional outbreak growth and dormancy; causal escalation |
| PA-05 | Survivor communities, refugee flows, rivals and rescue opportunities |
| PA-06 | Environmental influence, visibility, weather, power, terrain and infrastructure |
| PA-07 | Adaptive pressure and threat selection from actual world conditions; no cheats |
| PA-08 | Persistent consequences, territory, abandoned/destroyed sites, history |
| PA-09 | Quarantine, medical/containment operations and emergency automation |
| PA-10 | Emergent encounters, discoveries and collapse/rescue objectives |
| PA-11 | Host-authoritative multiplayer intents, synchronized state and visibility |
| PA-12 | Hierarchical simulation budgets, aggregation, promotion and profiling |

InfectionState {entity_or_cohort_id, strain_id, state, exposure, transition_due_tick, origin_event_id}; StrainDef {id, fictional_traits, environment_bounds, counters, mutation_rules, cost_tradeoffs}; Horde {id, region, count_by_type, origin, route, target_belief, resource_state, tick}; OutbreakRegion {id, population_buckets, dormancy, hazard, sites, routes, ledger_cursor}; Encounter {id, cause_event_ids, location, visibility, expiry, objective_options}; AudioCue {observable_event_id, tension_band, region, priority, cooldown}. Fictional gameplay abstractions, no biological real-world engineering. Population transitions conserve headcount except explicit births/deaths/migration; synthetic units excluded from biological state. Variant changes bounded by templates, seed, environmental pressure and elapsed time; no infinite power growth. Recognizable counterplay for walkers, runners, armored/heavy, climbing/stealth, wildlife and underground variants. No arbitrary spawns behind sealed defenses; infected originate from modeled populations/entries. Dormant populations remain tracked.

```text
# illustrative, not executable
for region in stable_order(due_regions):
    state = authoritative_region_snapshot(region)
    exposure = bounded_fictional_exposure(state, environment)
    propose_validated_population_transitions(exposure)
    plan_horde_routes_from_known_stimuli(state)
    evaluate_survivor_and_containment_intents(state)
    emit_causal_encounters_if_eligible(state)
commit_via_shared_ledger()
publish_observable_horror_cues()
```
No omniscience: target beliefs use available cues, routes and sensing; player alerts limited to discovered evidence. A pressure budget controls pacing by choosing among eligible causes, never spawning unsupported enemies, forcing collapse or retaliating for player success. Recovery/calms emerge from conditions; catastrophe possible, not guaranteed. Deterministic random streams per subsystem/region, stable IDs and order. Pause halts progression; no sim while closed. Active combat individual units, nearby groups, distant cohorts with conserved counts, injury, strain, location, planned travel and pending events. Promotion/demotion transactional, no duplication or teleportation; route travel time preserved. Host authoritative in online sessions, per-team visibility, save snapshots include director state/RNG/cursors/causal history. Audio is presentation only. Test dormant activation, blocked paths, population conservation, mutations/counters, outbreak replay, independent factions, no off-mode activation, no unfair spawns, migration/reconnect, fog, scale and cue accessibility. Exact balancing and budgets measured in production.
