# DYNAMIC SCENARIO ENGINE

Owner-approved expanded design direction; implementation pending. Proposed IDs, interfaces and pseudocode are design artifacts only. Reuse the Godot/Rust simulation, current director scheduler, validators and event ledger.

## Shared scenario service
One reusable scenario lifecycle for authored, procedural, user-created and mode-specific scenarios. Does not add an eighth director or replace existing PATHOGEN/DEEPWAR. Scenario generation occurs before start or at safe campaign boundaries; dynamic objectives during play consume actual simulation events, no arbitrary state injection. Game modes use existing simulation, legal factions/stages, map topology, resources, command interface and victory evaluator. Inheritance authored story, personally played battles and secret boundaries remain; Living World remains offline; no automatic new-mode activation.

Quick create: choose scenario family, factions, environment, scale, starting conditions, difficulty -> generate valid preview -> play. Advanced controls: seed, map, era, roster, resource/economy, infrastructure, objectives, technology, fog, teams/roles, environment, director config, time/hold/AND/OR, optional events and persistent links. Default presets viable and balanced for intended mode. Exact scenario count and matchmaking rules per mode spec.

ScenarioDefinition {stable_id, schema, mode_family, seed, generator_version, content_manifest, legal_factions, stage, map_ref, starting_assets, role_assignments, economy_rules, difficulty_profile, objective_graph, event_rules, enabled_services, director_permissions, persistence_policy, author_provenance}. ScenarioInstance {id, definition_hash, world_id, seed_streams, objective_states, event_cursor, active_regions, authority_epoch}. Objective graph {id, conditions, owner, visibility, progress, success/failure, consequence_policy, dependencies}; reject cycles unless bounded explicit repeat, invalid contradictory win/endless constraints, unreachable location, nonexistent asset. Event conditions declarative, bounded and validated, no unrestricted executable scripts. Generation steps:
1. Resolve mode/faction/ownership/stage, supported feature manifest and seed substreams.
2. Select/generate terrain, routes, settlement/fortress/site layout with [world generator](PROCEDURAL_WORLD_AND_ENGINEERING.md).
3. Populate actual legal assets and viable logistics, resource starts, opposing roles and commanders.
4. Generate objective graph and eligible causal opportunities; no hidden unsupported reinforcements.
5. Validate movement classes, resource reachability, construction/faction restrictions, performance estimate, scenario completion, fog and role balance.
6. Try bounded alternate generation or report reason and offer valid preset; never silently convert rules.
7. Preview and freeze versioned manifest/rules hash; start with stable IDs. Track authored vs generated provenance.

## Adaptive challenge
| Dimension | Independent setting |
|---|---|
| Intelligence | Planning quality |
| Coordination | Combined-arms and command quality |
| Adaptability | Response to observed strategies |
| Economic pressure | Scarcity and starting resources |
| Environmental pressure | Hazards and conditions |
| Military pressure | Starting force/opposition |
| Assistance | Player support, explanations and automation |
Choose readable presets or advanced custom. Difficulty by competence, actual constraints and explicitly labeled starting handicap; no secret health buffs or rubber-band attacks. Fair ranked seeds and rules frozen; asymmetric presets may deliberately differ but transparent. Dynamic objectives proposed from actual observable conditions through existing directors and Operational Intelligence. Cap and dedupe events, support calm periods, failure/partial success/optional withdrawal; no forced repetitive quests or fabricated resources. PATHOGEN/DEEPWAR run exclusively in their respective modes; community configs cannot silently mix them or alter authority.

## Validation and runtime
Generate stable seed/version/hash; validate deterministic replay and generator budgets, actual pathing and economic viability using bounded fixtures/AI soaks. Use actual terrain/structure graph. No promise of every possible combination; reject invalid configuration with useful reason and safe preset. Linked campaigns use explicit state transfer rules (WAR THEATRE) and separate session save IDs; cannot merge into Dynasty. Mod/content manifest, role/faction rights and version compatibility checked on import and online host. UI preview estimated load and warnings. Replay captures exact scenario config; creator packages include reproducible fixtures. G12 prototype/editor foundations, G13 procedural layouts, G14 content interfaces, G15/G17 objectives and full integration, G18 all scenario families and authoring acceptance. [Creator toolkit](CREATOR_TOOLKIT_AND_WORKSHOP.md).
