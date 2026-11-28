# Next-generation Campaign & Living World — approved GDD extension

Owner approved all 25 decisions on 2026-11-27. This is the canonical additive design for Inheritance and Living World, not a claim of implementation or a frozen gate contract. Existing tactical RTS, Last Protocol, Skirmish, authored campaign secrets and expansion contracts remain intact. Read with [campaign vision](CAMPAIGN_VISION.md) (internal spoilers) and [roadmap](ROADMAP.md).

## Product rule: deep simulation, classic RTS simplicity

Build → discover → expand → fight → upgrade → adapt. Every addition must create a meaningful decision, visible consequence, interesting opportunity or believable activity. Automate routine work; expose optional detail progressively. Preserve selection, right-click orders, control groups, familiar build/train/research menus and pause/speed. Player commands take precedence over delegated authority; resume automation explicitly or under a clear standing policy. No mandatory individual needs, component orders, timetables, taxation, administrative chores, daily tasks or grind. No external AI or connectivity. Preserve the low-detail isometric art identity. Remove or simplify features failing playability tests.

## Approved decisions (25/25)

| ID | Choice | Design and player-facing contract |
|---|---|---|
| 01 | D | Persistent individual civilian/soldier/officer identities and essential state; households/cohorts for distant simulation, detailed relevant entities. No identity loss on promotion to detail. |
| 02 | C | Autonomous births, aging, deaths, families, jobs, housing, education, healthcare, migration, routines and recruitment; player supplies infrastructure, not personal needs. No detailed psychology/hygiene. |
| 03 | D | Organic residential/commercial development and assisted utilities/roads; optional zoning, manual construction, industrial and military design; automatic construction crews and repairs constrained by materials/access. |
| 04 | D | Physical extraction, refining, components, assembly, regional inventories, warehousing, trade, transport, military supply, maintenance, salvage/recycling and shortage routing. One familiar production order drives the chain; no component micromanagement. |
| 05 | D | Military institutions recruit, train, assign personnel/equipment, patrol, deploy, resupply, maintain, evacuate casualties, rotate reserves and develop careers. Direct orders and hierarchy coexist. Campaign battles still personally played; Living World allows delegated battles. |
| 06 | D | Weather, seasons, day/night, water/flooding, vegetation, wildlife, fires, persistent ruins and ecological recovery; only consequential/visible detail, automatic response. |
| 07 | D | Rival civilizations independently build, trade, research, fight, ally, split, retreat, recover or collapse. Same meaningful resource and information constraints; distinct leadership and history. |
| 08 | D | Era-dependent exploration, ruins, survivors, recoverable technology, infrastructure, hidden sites and optional expeditions; manual or delegated reconnaissance, actionable notices. |
| 09 | D+ | Dynamic World Director: brutally realistic, unpredictable causal events, opportunities, crises and pacing; no artificial punishment/protection or armies spawned because player succeeds. |
| 10 | D | Component damage, structural impairment/collapse, debris, fire, infrastructure disruption, persistent scars; automatic recovery, salvage and reconstruction within available resources; direct intervention. |
| 11 | D | Adaptive command across squad, battlefield, settlement, region and continent, later underground/orbit; contextual HUD, delegation, direct takeover, pause/speed, background continuity; seamless where feasible, loading boundaries allowed when necessary. |
| 12 | D | Believable facility dimensions, vehicle clearances, meaningful interiors, actual personnel and equipment operations, production, maintenance, training, security, hospitals and depots; adaptive detail, no routine facility management. |
| 13 | D | Roads, rail, ports, airfields, public transport, convoys and underground links; physical local movement, distant aggregated journeys, automatic routing/repair; no schedules required. |
| 14 | D+ | Geopolitical Director: independent government stability, succession disputes, diplomacy, treaties, alliances, trade, tribute, vassals, territorial claims, fragmentation and shifting power. Major choices only; no legislation/tax micromanagement. |
| 15 | D/A | Familiar research tree and 13 stages; autonomous institutions, rediscovery, prototypes, captured technology, transfer, specialization, modernization and regression. One research priority/order, no laboratory management. |
| 16 | D+ | Historical & Generational Director: persistent timeline, people, rulers, institutions, battles, memorials, inherited knowledge, grievances, settlement evolution and consequences; optional archive. |
| 17 | D | Autonomous reconnaissance, surveillance, uncertain/stale intelligence, counterintelligence, deception, intelligence sharing and covert operations; simple reports and fog-of-war controls. |
| 18 | D | Automatic firefighting, evacuation, shelters, hospitals, utility recovery, rescue, refugees and reconstruction with finite personnel/resources; no separate director or required interface. |
| 19 | D+ | Faction Evolution Director: independent civilization specialization/adaptation within faction identity and prerequisites; familiar controls across factions. |
| 20 | D | Cinematic campaign with authored milestones, optional dynamic operations, persistent settlements/people, played years-pass interludes, returning locations and unique circumstances; protect secrets and authored beats. |
| 21 | D | Endless Living World with emergent nations, fragmentation, crises, ambitions, recovery/regression, exploration, successive rulers and optional expansion content; no predetermined end or grind. |
| 22 | D | Contextual animation, lighting, traffic, facility activity, wildlife, distance audio, dynamic music and optional cinematic observation; visual activity reflects actual state where practical; no forced camera interruptions. |
| 23 | D/A | Classic RTS controls, contextual HUD, smart orders, autonomous/assisted/manual modes, low/normal/high priorities, consolidated alerts, optional inspection and pause/speed. |
| 24 | D | Adaptive persistent Godot/Rust engine, spatial partitioning, event scheduling, deterministic commits, simulation LOD, save/load and performance budgets; targets validated rather than promised. |
| 25 | D | RTS-first fun, simplicity, autonomy, player authority, causality, fairness, offline operation, visual identity and incremental measurable acceptance gates. |

## Four coordinated directors

One authoritative world state and event ledger; four modules, not four heavyweight engines. Each consumes committed events and proposes bounded decisions. No director independently changes inventory, casualties, ownership or history. Shared command validator checks authority, resources, tech, information, narrative guard and conflicts; deterministic commit order (tick, priority, stable actor ID, sequence). Seeded random streams and pending decisions serialized. Async read-only evaluation allowed; deterministic scheduling/commit, no wall-clock dependent authoritative outcomes. Deduplicate events by stable ID; record causal parents; rate-limit cascades; support debugging/replay. No omniscience for faction decisions. Player decisions override delegated orders within legal game constraints.

| Director | Owns | Does not own |
|---|---|---|
| Dynamic World | Contextual encounters, environment, disasters, exploration, crisis pacing, opportunities | Free armies/resources, forced difficulty scaling, political/tech mutations |
| Geopolitical | Relationships, political stability, treaties, claims, trade agreements, fragmentation, strategic reactions | Physical execution, history rewrites, authored story overrides |
| Historical & Generational | Succession/aging coordination, history ledger, institutional legacy, memory and long-term effects | Duplicate casualties/births, invented past events, forced story changes |
| Faction Evolution | Doctrine, specialization, research/modernization priorities, faction-specific adaptation | Bypassing costs/prerequisites, replacing explicit player orders |

Example: destroyed factory is committed once by combat; World coordinates response, Geopolitical evaluates changed leverage, Historical records consequences, Evolution proposes alternative production/research. Logistics and construction systems execute validated orders. World events have causal prerequisites and bounded stochasticity, not guaranteed safety or punishment; periods of peace are legitimate.

Faction profiles: Modern Human professional combined arms, advanced engineering and automation; Scavenger Human salvage, industrial resilience and rugged mechanization; Machine energy/hive/replication and synthetic adaptation; Shadow Coalition covert networks, contracts, asymmetric capabilities and technology acquisition. Multiple civilizations of a faction may diverge within authored constraints. Hidden identities stay internal.

## Campaign and Living World mode boundaries

Inheritance retains the authored 13 chapters and existing founder/heir structure, 60–80 hour target, Story retry and Dynasty ironman, existing settlement emphasis I–IX and full RTS base-building X–XIII. The public proposed chronology (years after collapse) is 0, 1, 4, 9, 17, 30, 45, 60, 80, 105, 130, 160, 200; production timing still requires validation. New systems introduced progressively: I survival/identity; II community/construction; III exploration/transport; IV infrastructure; V institutions; VI industry; VII mechanized logistics; VIII national military; IX intelligence; X multi-front robotics; XI synthetic research; XII distributed governance; XIII mature simulation. Directors respect authored milestones, secrets, chapter endings and explicit story diplomacy. Existing rule to personally play every campaign battle remains; autonomous routine military management and tactical assistance are permitted, not strategic auto-resolution. Optional operations and years-pass policy interludes carry state forward. Regional intel restriction in older vision is superseded: add optional stale/uncertain intel, retain tactical belief fog; no mandatory spy-management layer.

Living World continues same save or new legacy in that world; autonomous battles may be delegated, with player takeover and consistent outcomes across scales. Systemic geopolitics, independent civilizations, evolving ambitions, crises and technological regression; no arbitrary endgame. Campaign director restrictions lifted only where compatible with post-campaign state. UNDERSTRIKE and Space Expansion reuse identities, inventories, logistics, command and persistence; no premature new stage numbering, no changes to their separately approved scope. Skirmish and Last Protocol stay separate; do not add compulsory civilization systems there.

## Engine design and interface

Keep existing Godot presentation and Rust simulation; extend rather than rewrite. Stable entity IDs, compact essential individual records, household/cohort aggregates, spatial chunks and persistent site/facility records. Active combat uses existing fixed ticks; local movement/animation interpolates; civilian routines and industry use lower-frequency/event-driven updates; distant transportation/armies use conserved manifests and scheduled outcomes; civilization strategy periodic; historical interludes accelerated. Promotion/demotion preserves personnel, equipment, inventories, positions/assignments, wounds, ownership, event history and production progress. Avoid camera-dependent advantage: relevance includes contested operations, not just visibility. Background simulation runs unless paused; time controls and manual takeover defined at safe tick boundaries. One canonical ledger for material transfers, casualties and ownership. Versioned save schema includes director queues, seeds and pending operations; migration/compatibility plan before implementation.

HUD: select entities/organizations with familiar controls; show only relevant commands. Optional strategic panels for settlement, army, economy, logistics, diplomacy, research, succession, ambitions and historical archive. Alerts grouped by actionable priority with cooldowns; routine activity silent. Automation presets autonomous/assisted/manual; explicit takeover/resume; broad priority controls. No per-person routine commands required. Physical activity should correspond to real simulation events; illustrative visuals cannot create resources or state.

## Validation and delivery

Research targets (not shipped guarantees): 1M+ persistent inhabitants, 10K+ distributed military entities; only subset high fidelity. Benchmark active vs distributed counts separately, tick latency, frame percentiles, memory, save size/load time, director CPU budgets and long-running worlds on documented hardware. Establish baseline and budgets before feature contracts; regress existing modes. Test identical seed/commands/save-load, LOD round trips and conservation, director conflict/deduplication, fairness, authored story invariants, interrupted manual takeover, autonomous recovery with shortages, multiple independent AI civilizations, multi-generation transitions, UI comprehensibility and optional automation. Test representative players can build/train/fight and advance with classic controls and no administrative micromanagement. Remove or simplify systems that fail gameplay value or performance.

Dependency sequence (not new gate numbers): 1 persistent IDs/state/ledger/minimal director framework; 2 civilian/settlement foundation; 3 industry/transport; 4 military institutions/facilities; 5 environment/damage/immersion; 6 mature director behavior incrementally with underlying systems; 7 G15 campaign integration; 8 G17 Living World integration; 9 expansion interoperability (G11–13/G16/G19 as applicable); 10 scale/balance/polish continuously. Preserve existing roadmap order and G10.1 open regression. Freeze each implementation slice with owner-reviewed scope and acceptance before coding. No automatic widening of current gates. Research developer publications for comparable simulation techniques; reference games are inspiration, not claims about proprietary internals.

Approved design direction, implementation pending. No gameplay code or existing acceptance locks changed by this document.


## DLC director extension — owner-approved 2026-11-27
The four base-game directors remain authoritative. DLC 2 adds one fifth director, [XENOGENESIS](XENOGENESIS.md), with 20 logical extraterrestrial subsystems sharing the existing deterministic ledger, validator and simulation fidelity model. [Myrieme Forge](MYRIEME_FORGE_INTEGRATION.md) adds independent production tooling and lightweight offline linguistic runtime across DLC 1 and DLC 2. No additional global authority or duplicate engine; G18 adds two mode-exclusive directors PATHOGEN and DEEPWAR, inactive outside their own scenarios. Read [master expansion design](BEYOND_CIVILIZATION_GDD.md) and [delivery plan](DLC_DELIVERY_PLAN.md). No implementation claimed.


## 2026-11-27 — Authoritative expansion integration

DLC 1 = Space Expansion (G19); DLC 2 = Beyond Civilization (G20). UNDERSTRIKE is integrated base game. True Dynasty is the primary earned progression from Inheritance through Living World and both expansions, preserving the same civilization history. Independent preset/custom starts in either owned DLC are separate saves, never modifying Dynasty; DLC 1 standalone can continue to DLC 2. New DLC factions playable only in Skirmish. Existing campaign battle rules, endings, arrival war, rosters and current gate statuses are protected. All new work is planned, not implemented.

Four existing directors share one authoritative ledger; Hidden Chronicle is a framework, not a sixth director. Use hierarchical stellar/planetary/region/tactical state and automated routine responses; XENOGENESIS remains DLC 2 only.

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


## G18 current approved design authority

G18 is final base-game completion: internet multiplayer, independently owned open-source gaming platform, Last Protocol co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN), and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE is an integrated Human A gameplay branch, not a separate expansion; dedicated warfare scenarios reuse it. New modes preserve existing faction rights, use traditional RTS controls and have no individual soldier-follow cameras. XENOGENESIS and Myrieme Forge must be fully accepted by G17. G19 Space Expansion and G20 Beyond Civilization follow G18 acceptance; civilization continuations remain offline, compatible owned expansion content extends Skirmish only for new playable DLC factions. No mandatory platform login offline, no Steam dependency. All G18 additions planned, not implemented.

[G18 MASTER GDD](G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](G18_DELIVERY_PLAN.md)


## Three shared services

[OPERATIONAL INTELLIGENCE](OPERATIONAL_INTELLIGENCE.md), [WORLD ARCHIVE](WORLD_ARCHIVE.md) and [DYNAMIC SCENARIO ENGINE](DYNAMIC_SCENARIO_ENGINE.md) extend current authority, not additional directors. Reuse existing validated commands, history and mode rules; no extra always-on simulation. Classic RTS simplicity and offline private campaign preserved.


## Expanded gameplay and creator authority — 2026-11-27

Expanded owner-approved design authority: eleven base-game experiences, including BLACK OPERATIONS (7), SIEGE WARFARE (7), CONQUEST (6), COMMANDER'S CRUCIBLE (7) and WAR THEATRE (7), in addition to the six existing/planned modes. Three shared systems (OPERATIONAL INTELLIGENCE, WORLD ARCHIVE, DYNAMIC SCENARIO ENGINE), procedural world/fortress generation, engineering templates, full scenario editor/SDK, free Workshop/Creator Store, complete replays/spectators/records, player experience, reusable platform and production readiness are integrated across G11–G18. G18 finalizes all base-game scope. Seven directors unchanged, no new director; no online Inheritance/Living World, no new official playable DLC factions outside Skirmish, Human A-only protected bunker/borer construction, no individual soldier-follow in new modes. Full XENOGENESIS and Forge acceptance at G17; G19 then G20 after G18. All planned, not implemented. Existing frozen scopes and G10.1 regression unchanged.

[Master GDD](EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Delivery](EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Shared scenario engine](DYNAMIC_SCENARIO_ENGINE.md) · [Creator tools](CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Platform](PLATFORM_PRODUCT_ROADMAP.md).
