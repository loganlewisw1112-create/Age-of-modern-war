# DLC delivery pipeline and release gates
Owner-approved direction 2026-11-27. No implementation started or tests run. Existing [roadmap](ROADMAP.md) and frozen gate contracts take precedence for current development; G10.1 wider regression remains open. G11–G17 base game, G18 Space Expansion and G19 Last Protocol Combined Arms retain order and scope. DLC 3 gate numbers and dates not assigned. [Master design](BEYOND_CIVILIZATION_GDD.md).

| Workstream | Dependencies | Deliverable / exit criteria |
|---|---|---|
| P0 Base game | Current roadmap | Existing regression and milestone acceptance; UNDERSTRIKE integrated base-game work, campaign and Living World |
| P1 Shared foundations | Existing contracts and owner-reviewed future scope | Stable IDs, event ledger, versioned saves, deterministic scheduling, conservation, entitlement registry, hierarchical simulation, interfaces; no premature implementation |
| P2 Myrieme Forge | Approved independent tool design | 15 engines, versioned canonical packages, 8 adapters, offline runtime; golden tests and content approval; parallel independent development permitted |
| P3 DLC 2 (G18) | G17, relevant P1/P2 | Home system, existing aerospace milestones/arrival war/six hull rosters, planet/orbit/ground interoperability, colony naming and language, outcome import, ownership/skirmish tests |
| P4 XENOGENESIS | P1, existing four directors, P2 interfaces | XG-01..20 bounded deterministic prototypes, cross-director arbitration and soak |
| P5 DLC 3 content | P2/P4 contracts | Seven regions, 50-system baseline, five major/four minor/one precursor concepts, canon-reviewed species/languages, complete playable rosters and authored locations |
| P6 Exploration slice | P3–P5 | Home-to-neighbor route, landing and RTS control, first contact, ancient discovery, save/load and delegation |
| P7 Civilization slice | P4–P6 | Autonomous ecology, diplomacy, economy, migration, research, engineering; distinct civilizations with credible evolution and constraints |
| P8 Warfare slice | P6–P7 | Interstellar/orbital/air/surface/underground battles; logistics, adaptive fleets and invasion/takeover |
| P9 Skirmish | Validated rosters and combat | Entitlement-aware full faction playability, presets, optional custom scenarios, legal starts, balance |
| P10 Integration/release | All applicable streams | Scale, offline, compatibility, content quality, gameplay simplicity and full polished release. No unfinished public DLC. |

Work in small dependency-driven vertical slices. Each implementation slice requires owner-reviewed GOAL, scope, acceptance contract, budget and tests before coding. Parallel tasks only with independent ownership and shared typed contracts; use existing agent rules/coordination board where applicable. Commit validated increments and preserve evidence; no claim of a shipped game build from documentation commits.

## Acceptance matrix (NOT RUN)
| ID | Test |
|---|---|
| DLC-01 | Base-only, DLC 2 only, DLC 3 entitlement/prerequisite combinations; no unowned runtime work, no unauthorized access; exact commercial dependency policy to be contracted |
| DLC-02 | Import each existing campaign ending, preserve assets/tech/territory/factions/relationships and arrival consequences; no forced restart; no arbitrary reset |
| DLC-03 | Preserve 13 stage IDs, authored campaign story and personally played battles; Living World delegation and takeover |
| DLC-04 | 50-system baseline and seven regions validated; one home system in DLC 2, remaining systems in DLC 3; fixed topology, finite boundary, varied meaningful content |
| DLC-05 | Landing/building/combat and persistent changes on suitable surfaces; hazard constraints and authored POIs |
| DLC-06 | Travel, supply, repair, route constraints, encounters and time acceleration; no duplication or bypass of critical events |
| DLC-07 | Every XG subsystem validated with isolated fixtures and cross-director integration; independent AI civilizations, imperfect intel and no default cheats |
| DLC-08 | Every Forge engine/adapter functional, deterministic, canon-locked, offline and accessible; no manual language requirement |
| DLC-09 | Ecosystems, populations, cultural evolution and diplomacy respect constraints; no runaway generation |
| DLC-10 | Economy, research, trade, engineering, capture and salvage obey prerequisites and conservation |
| DLC-11 | Multi-domain warfare and command handoff; losses, cargo, units and ownership conserved across fidelity transitions |
| DLC-12 | Owned new DLC factions fully playable in Skirmish only; no illegal Campaign/Living World switching; full roster parity and meaningful counters |
| DLC-13 | Quick-start and optional advanced customizer, legal environments, victory and independent difficulty |
| DLC-14 | Versioned saves/migrations, deterministic replay, RNG/event persistence and failure recovery; existing saves and modes regress |
| DLC-15 | Offline packaging and no required external AI/API/subscription; safe fallback for missing assets |
| DLC-16 | Profile active and distributed loads separately: tick latency, frame percentiles, CPU, RAM, save size/load, queue sizes, long soaks; budgets established on documented hardware before implementation lock |
| DLC-17 | Representative playtests: build/train/fight/explore/colonize using familiar RTS controls, delegate routine tasks, meaningful rewards and choices, no admin chores; simplify features failing fun/readability |
| DLC-18 | Canon and asset review: species, names, maps, tech, language, audio and licenses; no borrowed IP; no placeholders presented as finalized |
| DLC-19 | Complete release qualification, regression of existing modes, packaged build and reproducible evidence; no tests marked pass without evidence |

## Risks and open production work
Scope and performance: prototype one star-system transition and two independent alien powers before scaling. Content cost: modular validated roster/terrain/asset pipelines, not generic reskins. Save migration: stable IDs, transactional snapshots and regression fixtures. Director conflicts: one authoritative ledger and deterministic intent validation. Linguistic authenticity: independent tool implementation, non-acoustic adapter R&D, canon approval and fallback. Final species names, unit/building rosters, stellar catalog/coordinates/planet inventories and exact budgets remain production work; no fake completion. No new gate assigned and no DLC 1 invented. Protect base-game delivery above all.
