# Inconsistencies, resolution rules and unavailable evidence

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Civilization_Bible_v1.3](../source_text/Civilization_Bible_v1.3.md), [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md), [Development_Roadmap_v1.3](../source_text/Development_Roadmap_v1.3.md), [Technical_Architecture_v1.0](../source_text/Technical_Architecture_v1.0.md)

| ID | Finding | Handoff treatment / remaining action |
|---|---|---|
| GAP-01 | Project mirror reports one unsynced source | Identity unknown. Recover from project owner if needed; do not claim total historical completeness. |
| GAP-02 | First Playable §11 references `07_Implementation_Data/*.json`; no such directory in either archive | Missing original data. New `data/` files are clearly marked reconstructions and do not impersonate the absent catalogs. |
| GAP-03 | Roadmap §8 checks off a validator, decision register and original v1.0–v1.2 documents | Only v1.0 GDD/architecture and four v1.3 docs were found. Checklist is not evidence those other files were delivered. This handoff supplies a new register and audit, not the missing original validator. |
| GAP-04 | Earlier chat's final response is an unresolved content reference | Preserve marker; no final generated ZIP or hidden response content recovered. Read API returned no attachments. |
| CON-01 | v1.0 architecture phases prioritize survivor slice; v1.3 prioritizes RTS | Use v1.3 G0–G4 for current development. Retain older survival detail for G5/G6. |
| CON-02 | Earlier architecture suggests 30–100 local combatants; v1.3 targets 500–2,000 | Different scopes: early test load vs aspirational scaling. Begin 64; publish achieved counts separately from rendering and aggregated force totals. |
| CON-03 | Roadmap places save/load hardening in G4, while first-playable tests require persistence | Introduce save schema/round trips in G0/G1; harden and profile by G4. G3 content-complete does not automatically mean quality-qualified release. |
| CON-04 | Stage cards' “Evidence required for advancement” disagrees with progression matrix | Matrix 1→2 uses Stage 2 card evidence, while Stage 1 card lists safe water/food/supplies/labor. Similar offset exists across cards; Stage 13 still has advancement evidence despite no Stage 14. Preserve both. Do not generate operative stage gates from card labels. For prototype planning prefer dedicated §4 for 7→8 and 8→9; clarify final thresholds before implementing. |
| CON-05 | Initial chat lists three economy profiles; Master includes Custom | Keep Arcade/Standard/Simulation and Custom rule overrides. Custom is configuration of shared rules, not another economy engine. |
| CON-06 | Older GDD has seamless camera scales and survivor UI | Full-game references only; current slice is fixed-angle traditional RTS. |
| CON-07 | Broad victory menu includes diplomacy/stage race, but slice minimum tests focus military/control/combined/endless | Maintain full design catalog; track minimum tested subset and staged availability. Do not advertise unsupported victory types. Diplomacy victory depth remains a scope clarification. |
| CON-08 | JPEG roster contains naval and broad air fleets beyond first slice | Preserve as concept taxonomy. It does not authorize immediate naval implementation or prove asset production readiness. |
| CON-09 | Source claims approved vision but full approval provenance absent | Label source-reported approval. Current user requests consolidation; no new creative lock or build authorization inferred. |

## Open decisions requiring actual evidence

Exact Godot minor version, renderer and programming language boundary; target OS and hardware; art angle, pixels per world unit and animation directions; canonical faction/continent names; map dimensions and slots; precise recipe rates/costs; stage gate thresholds; combat formulas and fog-memory targeting policy; difficulty cadence; victory scope, tie handling and capture rules; save compatibility policy; release format, licensing and distribution. None is silently fixed by this package.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Superseded: old DLC numbering, literal Solar System geography, mandatory progression for independent saves. Campaign lore preserved; numerical parameters and canonical revelations remain open production tasks.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## G18 current approved design authority

G18 final base game: internet multiplayer, independently owned open-source gaming platform, Last Protocol online co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN) and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE remains integrated, Human A-exclusive construction rights unchanged, not a standalone expansion. Neither new mode has individual soldier-follow. All XENOGENESIS and Myrieme Forge accepted by G17. G19 Space Expansion (DLC 1), G20 Beyond Civilization (DLC 2) only after G18; civilization continuations offline, compatible owned content in Skirmish. No mandatory platform login offline. Planned only.

Earlier offline-only whole-product scope superseded for explicitly supported G18 modes. No change to initial playable contracts. Platform name/license/stack, transport selection and numerical cost/performance budgets remain production decisions.

[G18 MASTER GDD](../../game/docs/G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](../../game/docs/G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](../../game/docs/G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](../../game/docs/DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](../../game/docs/PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](../../game/docs/SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](../../game/docs/DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](../../game/docs/G18_DELIVERY_PLAN.md)


## Expanded gameplay authority — 2026-11-27

Current owner-approved expanded design: G11–G18 integrates 33 additions and five additional modes (34 scenario families), three shared systems, procedural world/fortresses, creator/SDK/Workshop/Store, replay/spectators/records, player experience, independent platform and release qualification. G18 finalizes eleven base-game experiences. Inheritance/Living World offline solo only; no additional global directors or new official DLC playable factions outside Skirmish; Human A-only bunker/borer construction. G17 full XENOGENESIS/Myrieme Forge acceptance unchanged; G19 then G20 after G18. Planned only; no source changes or milestone acceptance.

Prior six-mode and four-track G18 descriptions are original scope, not final scope; expanded 11-mode matrix and EX-A–H are additive. Tactical pause formerly parked is now planned G11; existing mode timing preserved. Free Workshop/Store launch required, paid creator content phased.

[Expanded master](../../game/docs/EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Delivery and acceptance](../../game/docs/EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Scenario engine](../../game/docs/DYNAMIC_SCENARIO_ENGINE.md) · [Operations](../../game/docs/OPERATIONAL_INTELLIGENCE.md) · [Archive](../../game/docs/WORLD_ARCHIVE.md) · [Creator toolkit](../../game/docs/CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Platform](../../game/docs/PLATFORM_PRODUCT_ROADMAP.md).
