# RTS: Age of Modern War — Claude handoff

Prepared 22 October 2026, America/Los_Angeles. Documentation handoff revision 1; underlying design remains v1.3. This ZIP consolidates every locally available upload, all six source documents, six approved mockups, one additional military reference image, and the readable referenced conversation. No playable Godot project was supplied or built.

## Read in this order

1. [Claude entry prompt](CLAUDE_ENTRY_PROMPT.md).
2. [Authority and decisions](docs/01_AUTHORITY_AND_DECISIONS.md).
3. [Inconsistencies and missing sources](docs/02_INCONSISTENCIES_AND_GAPS.md).
4. [Master design](docs/03_MASTER_DESIGN.md) and [first playable](docs/04_FIRST_PLAYABLE.md).
5. [Architecture](docs/05_ARCHITECTURE.md), [civilizations](docs/06_CIVILIZATIONS_13_STAGES.md), [skirmish](docs/07_SKIRMISH.md).
6. Economy, military, AI, world, art, UI, roadmap, tests, requirements, risk and traceability documents in `docs/`.

## Package layout

- `originals/`: byte-identical copies of both uploaded ZIPs and the JPEG.
- `reference/`: extracted source DOCX/PDF documents and six approved PNGs, with original archive paths retained.
- `source_text/`: complete paragraph-order DOCX text, page-labelled PDF text, and retrieved conversation. Text extraction does not preserve visual document formatting; the originals remain authoritative evidence.
- `docs/`: consolidated topic documents and proposed integration contracts, each labelled by status.
- `data/`: newly reconstructed stage registry and requirements index. These are handoff aids, not recovered v1.3 implementation data.
- `audit/`: source inventory, hashes and package verification report.

## Completeness boundary

One ChatGPT project source failed to sync; its identity and content are unknown. v1.3 refers to JSON catalogs, a validator, a decision register, and v1.1/v1.2 originals absent from the available archives. The earlier final assistant response is only a content-reference marker. This is comprehensive for the available evidence, not a claim to recover inaccessible material. See the gap register before treating any missing detail as approved.

## Development direction

Classic RTS first. G0 is a 64-unit engineering demonstration; the substantial slice requires three distinct factions, three maps, Stages 7–9 with Stage 8 emphasis, configurable skirmish, fair autonomous AI, real economy/combat and persistence. Exactly 13 stages remain the full-game design. Deep survivor, continental, naval, underground and political systems follow later. All performance claims require measurements on identified hardware.


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Use current expansion specifications as design authority, not authorization to implement ahead of gates. Documentation-only proposals.

[SPACE EXPANSION GDD](../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## Corrected owner-approved execution sequence

G11–G17 full XENOGENESIS and Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization (DLC 2). Both systems must be fully implemented, integrated, tested and accepted by G17 exit (before G18 and G19): all 20 XENOGENESIS subsystems; all 15 Myrieme Forge engines and eight integration adapters, including offline runtime. Earlier development is permitted. G20 interstellar gameplay/content production happens after G19; G11–G17 testing uses representative fixtures without requiring full G20 content or exposing unowned DLC. No implementation or gate completion is claimed.


## G11–G17 integrated system development — current owner authority

G11–G17 integrated development of XENOGENESIS and full Myrieme Forge; both fully implemented, integrated, tested and accepted as mandatory G17 exit criteria. G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization. No separate integration checkpoint; G20 gameplay and full universe content production remain after G19. All 20 XENOGENESIS subsystems, 15 Forge engines and eight integration modules, offline runtime and shared director interoperability required by G17. Representative validation fixtures, not premature DLC gameplay; ownership boundaries remain. See the current ROADMAP and DLC delivery plan for per-gate assignments. No implementation or gate completion claimed.


**Current gate authority:** G17 Living World and full XENOGENESIS/Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion (DLC 1) → G20 Beyond Civilization (DLC 2). Both DLCs begin only after the base game is complete. No runtime changes or gate completion claimed.


## G18 current approved design authority

G18 final base game: internet multiplayer, independently owned open-source gaming platform, Last Protocol online co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN) and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE remains integrated, Human A-exclusive construction rights unchanged, not a standalone expansion. Neither new mode has individual soldier-follow. All XENOGENESIS and Myrieme Forge accepted by G17. G19 Space Expansion (DLC 1), G20 Beyond Civilization (DLC 2) only after G18; civilization continuations offline, compatible owned content in Skirmish. No mandatory platform login offline. Planned only.

Read G18 master and delivery plan before G18; no premature implementation during earlier gates.

[G18 MASTER GDD](../game/docs/G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](../game/docs/G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](../game/docs/G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](../game/docs/DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](../game/docs/PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](../game/docs/SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](../game/docs/DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](../game/docs/G18_DELIVERY_PLAN.md)


## Expanded gameplay authority — 2026-11-27

Current owner-approved expanded design: G11–G18 integrates 33 additions and five additional modes (34 scenario families), three shared systems, procedural world/fortresses, creator/SDK/Workshop/Store, replay/spectators/records, player experience, independent platform and release qualification. G18 finalizes eleven base-game experiences. Inheritance/Living World offline solo only; no additional global directors or new official DLC playable factions outside Skirmish; Human A-only bunker/borer construction. G17 full XENOGENESIS/Myrieme Forge acceptance unchanged; G19 then G20 after G18. Planned only; no source changes or milestone acceptance.

Current active scope: close G10.1 regression; G11–G18 implement shared foundations and expanded systems according to owner-reviewed gate contracts; G19/G20 only after G18.

[Expanded master](../game/docs/EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Delivery and acceptance](../game/docs/EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Scenario engine](../game/docs/DYNAMIC_SCENARIO_ENGINE.md) · [Operations](../game/docs/OPERATIONAL_INTELLIGENCE.md) · [Archive](../game/docs/WORLD_ARCHIVE.md) · [Creator toolkit](../game/docs/CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Platform](../game/docs/PLATFORM_PRODUCT_ROADMAP.md).
