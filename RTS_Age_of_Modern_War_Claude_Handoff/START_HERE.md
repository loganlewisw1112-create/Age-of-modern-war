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

DLC 1 is Space Expansion (G18); DLC 2 is Beyond Civilization (future unnumbered). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Use current expansion specifications as design authority, not authorization to implement ahead of gates. Documentation-only proposals.

[SPACE EXPANSION GDD](../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)
