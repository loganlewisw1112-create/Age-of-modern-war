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
