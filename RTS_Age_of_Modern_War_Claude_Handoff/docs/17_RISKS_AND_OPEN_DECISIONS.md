# Risk register and next planning actions

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Development_Roadmap_v1.3](../source_text/Development_Roadmap_v1.3.md), [Technical_Architecture_v1.0](../source_text/Technical_Architecture_v1.0.md), [Civilization_Bible_v1.3](../source_text/Civilization_Bible_v1.3.md)

| Risk | Impact | Mitigation / required evidence |
|---|---|---|
| Scope explosion across survivor, RTS and continental simulation | No finished playable loop | Follow G0–G4; preserve future design in backlog |
| Art fidelity vs actor count | Poor readability or frame time | Small in-engine art proof, batching/LOD, measured dense scenes |
| Pathfinding congestion and bridge destruction | Stalls, unreachable supply | Movement-class graph validation, bounded replanning and bridge tests |
| Economy/AI deadlock | Unplayable factions | Self-sufficient opening tests, shortage reasons, autonomy soak |
| AI hidden knowledge/resources | Unfair opponents | Observer views, shared validators and inspectable ledgers |
| Resource duplication/save drift | Broken economy and persistence | Atomic commands, conservation properties, repeated save tests |
| Stage prerequisite contradiction | Incorrect advancement | Preserve CON-04 and resolve operational gates before implementing |
| Missing historical files/catalogs | False canon or incomplete transfer | Gap register, source manifests and labelled reconstruction |
| Unspecified hardware/platform | Unsupported capacity claims | Agree environment and record real profiles |
| Asset provenance unknown | Distribution uncertainty | Track origins/rights before shipping assets |

## Recommended next planning deliverable

Claude should return a bounded G0 implementation plan after reading this package: file/module layout, chosen engine/version proposal, smallest runnable interaction, 64-actor profile scenario, seed/save strategy, exact acceptance evidence, art proof and unresolved material decisions. Mark assumptions clearly. The current request builds the handoff; beginning the game requires a subsequent user instruction. No full-game dates, staffing, budget or promised performance are derivable from the supplied sources.


## Approved DLC addendum — 2026-11-27
[DLC risks and production backlog](../../game/docs/DLC_DELIVERY_PLAN.md): final names, species/rosters, system catalog and coordinates, planet inventories, performance budgets, software and release contracts remain pending; no implementation claims.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Provisional names, numerical orbital modeling, material properties, individual model definitions, canonical narrative revelations, performance budgets and commercial entitlement details pending production.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## G18 risk and production decisions

G18 includes all online multiplayer, independently owned open-source platform, DEAD SECTOR/PATHOGEN and SUBTERRANEAN WARFARE/DEEPWAR. G17 acceptance precedes it, G19 and G20 only after full G18 acceptance. Inheritance/Living World remain offline solo. Risks: relay cost, NAT reachability, host trust and fog secrecy, migration split-brain, data privacy, dependency licensing, platform reliability, infection and underground simulation performance, horror accessibility, scope duplication. Mitigate with shared authority, direct hosting, bounded fixtures, measured budgets and signed releases; no guaranteed free hosting or perfect anti-cheat. Platform name/license, providers, transport, exact budget, content balance and dedicated hosting policy remain production choices. See [G18 delivery](../../game/docs/G18_DELIVERY_PLAN.md) and [platform](../../game/docs/G18_OPEN_GAMING_PLATFORM.md). No code changes or tests claimed.
