# DLC delivery pipeline and release gates
Owner-approved direction 2026-11-27. No implementation started or tests run. Existing [roadmap](ROADMAP.md) and frozen gate contracts take precedence for current development; G10.1 wider regression remains open. G11–G17 base game precedes G18 Space Expansion, then G20 Beyond Civilization, then G19 Last Protocol Combined Arms. Dates not assigned. [Master design](BEYOND_CIVILIZATION_GDD.md).

| Workstream | Dependencies | Deliverable / exit criteria |
|---|---|---|
| P0 Base game | Current roadmap | Existing regression and milestone acceptance; UNDERSTRIKE integrated base-game work, campaign and Living World |
| P1 Shared foundations | Existing contracts and owner-reviewed future scope | Stable IDs, event ledger, versioned saves, deterministic scheduling, conservation, entitlement registry, hierarchical simulation, interfaces; no premature implementation |
| P2 Myrieme Forge | Approved independent tool design | 15 engines, versioned canonical packages, 8 adapters, offline runtime; golden tests and content approval; parallel independent development permitted |
| P3 DLC 1 (G18) | G17, relevant P1/P2 | Home system, existing aerospace milestones/arrival war/six hull rosters, planet/orbit/ground interoperability, colony naming and language, outcome import, ownership/skirmish tests |
| P4 XENOGENESIS | P1, existing four directors, P2 interfaces | XG-01..20 bounded deterministic prototypes, cross-director arbitration and soak |
| P5 DLC 2 content | P2/P4 contracts | Seven regions, 50-system baseline, five major/four minor/one precursor concepts, canon-reviewed species/languages, complete playable rosters and authored locations |
| P6 Exploration slice | P3–P5 | Home-to-neighbor route, landing and RTS control, first contact, ancient discovery, save/load and delegation |
| P7 Civilization slice | P4–P6 | Autonomous ecology, diplomacy, economy, migration, research, engineering; distinct civilizations with credible evolution and constraints |
| P8 Warfare slice | P6–P7 | Interstellar/orbital/air/surface/underground battles; logistics, adaptive fleets and invasion/takeover |
| P9 Skirmish | Validated rosters and combat | Entitlement-aware full faction playability, presets, optional custom scenarios, legal starts, balance |
| P10 Integration/release | All applicable streams | Scale, offline, compatibility, content quality, gameplay simplicity and full polished release. No unfinished public DLC. |

Work in small dependency-driven vertical slices. Each implementation slice requires owner-reviewed GOAL, scope, acceptance contract, budget and tests before coding. Parallel tasks only with independent ownership and shared typed contracts; use existing agent rules/coordination board where applicable. Commit validated increments and preserve evidence; no claim of a shipped game build from documentation commits.

## Acceptance matrix (NOT RUN)
| ID | Test |
|---|---|
| DLC-01 | Base-only, DLC 1 only, DLC 2 entitlement/prerequisite combinations; no unowned runtime work, no unauthorized access; exact commercial dependency policy to be contracted |
| DLC-02 | Import each existing campaign ending, preserve assets/tech/territory/factions/relationships and arrival consequences; no forced restart; no arbitrary reset |
| DLC-03 | Preserve 13 stage IDs, authored campaign story and personally played battles; Living World delegation and takeover |
| DLC-04 | 50-system baseline and seven regions validated; one home system in DLC 1, remaining systems in DLC 2; fixed topology, finite boundary, varied meaningful content |
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
Scope and performance: prototype one star-system transition and two independent alien powers before scaling. Content cost: modular validated roster/terrain/asset pipelines, not generic reskins. Save migration: stable IDs, transactional snapshots and regression fixtures. Director conflicts: one authoritative ledger and deterministic intent validation. Linguistic authenticity: independent tool implementation, non-acoustic adapter R&D, canon approval and fallback. Final species names, unit/building rosters, stellar catalog/coordinates/planet inventories and exact budgets remain production work; no fake completion. G20 assigned before G19 and no additional DLC invented. Protect base-game delivery above all.


## 2026-11-27 — Authoritative expansion integration

DLC 1 = Space Expansion (G18); DLC 2 = Beyond Civilization (G20). UNDERSTRIKE is integrated base game. True Dynasty is the primary earned progression from Inheritance through Living World and both expansions, preserving the same civilization history. Independent preset/custom starts in either owned DLC are separate saves, never modifying Dynasty; DLC 1 standalone can continue to DLC 2. New DLC factions playable only in Skirmish. Existing campaign battle rules, endings, arrival war, rosters and current gate statuses are protected. All new work is planned, not implemented.

SP-01–15 and SP-QA-01–32 extend G18. Validate separate-save isolation and entitlement combinations, transactional import, canon compatibility and no unowned full simulation. Preserve existing pipeline and tests as planned.

[SPACE EXPANSION GDD](SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](SPACE_EXPANSION_DELIVERY_PLAN.md)


## Owner-approved execution sequence — G20 before G19

G20 — Beyond Civilization (DLC 2), including the complete finite interstellar expanse, XENOGENESIS and full Myrieme Forge integration, must be implemented and accepted in full after G18 and before any G19 Last Protocol Combined Arms development begins. Execution order: G18 → G20 → G19. Gate IDs are stable identifiers, not numerical execution order. No gate completion is claimed; release dates remain unassigned.
