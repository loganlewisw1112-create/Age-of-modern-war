# XENOGENESIS — intelligent extraterrestrial species and civilization director
Owner-approved design 2026-11-27; implementation pending. Fifth coordinated director, DLC 2 only; no independent heavyweight engine or competing authoritative world state. Read [master DLC GDD](BEYOND_CIVILIZATION_GDD.md) and [existing directors](NEXTGEN_SIMULATION_GDD.md).

## Responsibilities
| ID | Logical subsystem | Inputs → bounded outputs |
|---|---|---|
| XG-01 | Species Genesis | Authored anatomy, ecology, origin, needs, capabilities → validated species profiles and starting populations; no uncontrolled species creation |
| XG-02 | Biological Evolution | Heritable variation, environment, generations → bounded adaptation; never arbitrary combat buffs |
| XG-03 | Ecological Intelligence | Climate, biome, food web, populations → migration, reproduction, predation, invasive species, collapse/recovery and research opportunities |
| XG-04 | Population Dynamics | Cohorts, births/deaths, habitat capacity, migration → conserved population transitions, workforce and refugee intents |
| XG-05 | Civilization Evolution | Capability evidence, institutions, resources → development priorities; existing 13-stage model remains intact |
| XG-06 | Cultural Intelligence | History, beliefs, isolation, exchange → evolving cultural profiles and Forge events |
| XG-07 | Political Intelligence | Legitimacy, grievances, leadership, territory → reform, rebellion, succession, fragmentation proposals |
| XG-08 | Colonization Intelligence | Habitability, tech, supplies, known geography → survey, settle, expand and evacuate intents |
| XG-09 | Military Evolution | Observed outcomes, doctrine, biology, industry → validated roster modules, doctrine and operational priorities; biological/synthetic/conventional/exotic arms races |
| XG-10 | Technological Evolution | Research, discoveries, tooling, scientific evidence → tech priorities, prerequisite-constrained unlock proposals, reverse engineering |
| XG-11 | Economic Intelligence | Stocks, industry, demand, shortages, trade → economic priorities, bids, investment and recovery |
| XG-12 | Diplomatic Intelligence | Beliefs, trust, historical claims and power → treaties, trade, alliances, sanctions, rivalries and war proposals |
| XG-13 | Engineering Intelligence | Design templates, engineering tech, material/energy budgets → construction/repair/repurpose projects including megastructures |
| XG-14 | Ancient Civilization Intelligence | Authored precursor history, dormant state, artifacts → discoveries, recoveries, activation within narrative and tech guards |
| XG-15 | First Contact Intelligence | Sensor observations, known signals, translation knowledge → investigate, identify, negotiate, warn; species-dependent progression |
| XG-16 | Interstellar Expansion | Range, routes, supplies, beliefs, strategic aims → fleets, colonies, system-level campaigns |
| XG-17 | Historical Memory | Committed events, timestamps, provenance → durable summaries, inherited grievances and records |
| XG-18 | Behavioral Adaptation | Observed successes/failures and costs → bounded doctrine/policy adjustments, decay of stale beliefs |
| XG-19 | Strategic Forecasting | Belief state, resource limits, goals → bounded threat/opportunity estimates, uncertainty and alternative plans |
| XG-20 | Civilization Decision Core | Subsystem proposals and shared policies → prioritized legal intents and delegation, budget arbitration and conflict handling |

## Shared authority and interfaces
Existing Dynamic World Director owns causal event pacing; Geopolitical Director owns global relationship/territory policy; Historical & Generational Director owns canonical timeline; Faction Evolution Director owns shared civilization capability progression. XG owns extraterrestrial-specific profiles, needs, behaviors and proposals. All consume same event ledger; existing economy/logistics/research/construction/combat/command systems execute legal actions. No double simulation, direct inventory edits or duplicate history. Myrieme Forge owns linguistic generation and versioned language state, not diplomacy. Campaign narrative guard wins where authored milestones require; campaign battles played personally, delegated battles in Living World. Skirmish AI uses compatible modules without mandatory civil administration.

Proposed data contracts (names illustrative): SpeciesProfile{id, version, anatomy, environmentLimits, modalityIds, adaptationBounds}; CivilizationProfile{id, speciesId, canonVersion, culturalTraits, doctrine, capabilities, languageFamilyId}; SystemRecord{id, regionId, fixedCoordinates, bodies, routes}; PopulationCohort{id, speciesId, siteId, count, ageBands}; CivilizationState{id, government, beliefs, goals, capabilityEvidence, knownTech, territoryRefs, relationships, memoryRefs}; Intent{id, actorId, type, targetId, costs, prerequisites, observedTick, confidence, causalEventIds, priority}; Event{id,tick,type,actorId,subjectId,payload,causalParents}; LanguageEvent{civilizationId, languageId, eventId, type, timeDelta, contactIds}. Use stable references, schema versions and deterministic serialization. Store authoritative and belief data separately.

## Execution and fidelity
Read committed snapshot → update beliefs → evaluate event-driven subsystem proposals → budget and rank via XG-20 → shared validator checks authority, tech, cost, accessibility, narrative and conflicts → deterministic commit (tick, priority, stable actor ID, sequence) → ledger event → feedback to directors and Forge. Deduplicate event IDs, rate-limit cascades, serialize RNG streams and pending work. Read-only parallel evaluation permitted; deterministic commit, no wall-clock-authoritative effects. No omniscience; intel confidence, age and source. Player command priority within legal constraints; safe takeover/resume policy. No forced disasters or resource cheats by default.

Active battle full units; relevant adjacent regions detailed; distant planets aggregate cohorts, inventories, conserved manifests, infrastructure and scheduled operations; distant systems strategic summaries. Fidelity transitions preserve IDs, casualties, wounds, cargo, resources, production, positions/assignments, ownership, history and pending intents. Relevance not just camera visibility. Bounded ecology, bounded adaptation, credible generations; time acceleration never skips unresolved critical encounters without policy. No simulation while game closed required. Pause stops authoritative progression. Fully offline, native Rust authority + Godot presentation; profile before setting budgets, no performance promises.

## Player commands and safeguards
Explore, investigate, contact, trade, ally, defend, colonize, invade, research, build, delegate, take control. Existing RTS selection and menus. Autonomous AI uses same prerequisites, resources and fog as player. Difficulty controls competence/tempo and explicit optional handicaps, not invisible cheats. Alert only actionable events, batch routine results; optional causal history. Minor civilizations can rise, merge, split or collapse within bounded content templates; generated variants use validated modules. Biological changes on believable timescales. Ancient discoveries preserve canon and narrative secrecy. Full roster and simulation tests required before release.

## Acceptance
XG-01..20 each require deterministic fixture, negative validation, integration and soak tests. Cross-director duplicate event/conflict tests; resource and population conservation; same seed+commands reproducibility including save/load and LOD; multiple independent AI powers with no player input; belief-limited decisions; no illegal campaign faction switch or auto-resolved mandatory battle; interrupted manual takeover; ecology and evolution bounds; no uncapped queue/faction proliferation; measurable CPU/memory/save budgets; offline operation; player can play traditional RTS without administration. All tests NOT RUN.


## 2026-11-27 — Authoritative expansion integration

DLC 1 = Space Expansion (G19); DLC 2 = Beyond Civilization (G20). UNDERSTRIKE is integrated base game. True Dynasty is the primary earned progression from Inheritance through Living World and both expansions, preserving the same civilization history. Independent preset/custom starts in either owned DLC are separate saves, never modifying Dynasty; DLC 1 standalone can continue to DLC 2. New DLC factions playable only in Skirmish. Existing campaign battle rules, endings, arrival war, rosters and current gate statuses are protected. All new work is planned, not implemented.

Consume bounded DLC 1 historical state and Chronicle effects exactly once. Respect knowledge propagation and stable IDs; no omniscience or competing authoritative state.

[SPACE EXPANSION GDD](SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](SPACE_EXPANSION_DELIVERY_PLAN.md)


## Corrected owner-approved execution sequence

Owner-approved sequence: G11–G17 full XENOGENESIS and Myrieme Forge integration and acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization (DLC 2). All 20 XENOGENESIS subsystems and full Myrieme Forge production/runtime integration (15 engines, eight adapters) must be implemented, integrated, tested and accepted by G17 exit (before G18 and G19), not merely prototyped. G20's actual interstellar gameplay and content development follows G19. G11–G17 validation may use bounded representative fixtures; it does not require the full G20 universe to be produced or exposed. DLC 2 runtime entitlement boundaries remain intact. No implementation or gate completion claimed.


## G11–G17 integrated system development — current owner authority

Owner-approved execution: distribute XENOGENESIS and full Myrieme Forge implementation/integration across G11–G17, with full acceptance required to close G17. G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization follow in order. Pre-G18 prerequisite remains mandatory but is satisfied at G17; no standalone checkpoint after G19. G20 actual interstellar gameplay and production universe content remain after G19; representative fixtures validate all systems beforehand. Entitlement boundaries and existing gate scopes remain protected; no implementation or completion claimed.

| Gate | Assigned system work |
|---|---|
| G11 | Shared stable IDs, versioned persistence, event ledger, bounded scheduler interfaces, Forge package/schema and independent tool foundation; reuse existing contracts. |
| G12 | Forge language generation and communication foundations; XENOGENESIS species, ecology, population and environment contracts; representative offline fixtures. |
| G13 | Integrate resource, settlement, ecology and archaeology interfaces with underground discoveries; Forge ancient scripts, naming and historical language data; preserve UNDERSTRIKE faction restrictions. |
| G14 | Complete remaining Forge production engines and adapters against faction/stage content; develop XENOGENESIS civilization, economic, political, military, research and engineering capabilities using representative species and factions. |
| G15 | Integrate campaign history, generational state, linguistic evolution, communication, first-contact and archaeological interpretation; protect campaign secrets and personally played battle rules. |
| G16 | Complete outstanding XENOGENESIS subsystems and Forge integration; harden deterministic cross-director arbitration, persistence, performance, offline packages and representative stress tests. |
| G17 | Mandatory full completion and acceptance: all XG-01–20 subsystems, all 15 Forge production engines, all eight integration adapters, lightweight offline runtime, full interoperability with the four existing directors, save/load, entitlement, determinism, performance and regression evidence. No deferral of system capabilities to G18/G19/G20. |


**Current gate authority:** G17 Living World and full XENOGENESIS/Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion (DLC 1) → G20 Beyond Civilization (DLC 2). Both DLCs begin only after the base game is complete. No runtime changes or gate completion claimed.


## G18 design integration

G18 final base-game completion includes online Last Protocol co-op, Skirmish co-op/PvP, owned open-source gaming platform, DEAD SECTOR/PATHOGEN and SUBTERRANEAN WARFARE/DEEPWAR. Inheritance and Living World offline solo only; UNDERSTRIKE integrated Human A branch. No soldier-follow in new modes. G17 full XENOGENESIS and Myrieme Forge acceptance precedes G18, then G19 Space Expansion and G20 Beyond Civilization. No new DLC, code changes or completion claims.

XENOGENESIS is fifth director, mandatory full G17 acceptance; no cross-activation of PATHOGEN or DEEPWAR in its content. Use shared validated ledger.

[Master GDD](G18_MASTER_GDD.md) · [G18 delivery](G18_DELIVERY_PLAN.md) · [PATHOGEN](PATHOGEN_DIRECTOR.md) · [DEEPWAR](DEEPWAR_DIRECTOR.md).
