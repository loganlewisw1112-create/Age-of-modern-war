# Requirements, scope and traceability

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [First_Playable_Spec_v1.3](../source_text/First_Playable_Spec_v1.3.md), [Development_Roadmap_v1.3](../source_text/Development_Roadmap_v1.3.md), [Technical_Architecture_v1.0](../source_text/Technical_Architecture_v1.0.md)

## Functional coverage

The machine-readable `data/requirements.csv` indexes source F-001..025, first-playable acceptance IDs and QA-001..015 without claiming implementation. Each row retains its source wording, source document and NOT RUN status. The canonical detailed definitions remain in the complete Markdown sources.

| Domain | Authoritative source | Consolidated document | Gate |
|---|---|---|---|
| Vision/modes | Master §§1–3,13 | 03 / 04 | G0–G6 |
| Setup/victory | Master §4; Spec §§1–3,9 | 07 | G1–G3 |
| Stages | Bible §§1–6; Master §5 | 06 | Registry G0; playable G3; all G6 |
| Faction roles | Master §6; Spec §§4–5 | 09 | G3 |
| Economy/building | Master §7; Spec §6 | 08 | G1–G3 |
| Combat/officers | Master §§8–9; Spec §§5,7 | 09 | G1–G3 |
| AI/intel | Master §10; Architecture §5 | 10 | G1–G3 |
| Maps/world | Master §11; Spec §3 | 11 | G0–G3; full world G5–G6 |
| Art/audio | Master §11; GDD §10 | 12 | Early proof then staged content |
| Controls/accessibility | Master §12; Spec §8 | 13 | G0–G4 |
| State/save/performance | Architecture §§1–8; Roadmap §§1,7 | 05 / 15 | Early foundation; G4 hardening |

## Nonfunctional requirements and unresolved platform inputs

Offline operation; one authoritative state; bounded AI work; no unmeasured capacity claims; finite resource conservation; observer-specific knowledge; reproducible seeds; versioned saves and content; readable tactical presentation; recoverable failure feedback; extensibility across future modes. Target OS/hardware, supported rendering API, install footprint, minimum FPS and save-time limit remain unset. The older 60 FPS /1080p target is a hypothesis, not a shipping guarantee.

## Delivery requirements

A future gameplay delivery must include an actual launchable project/build, versioned source and content, setup/run instructions, required licenses, evidence for claimed gates, known issues and supported hardware. This handoff includes design/reference material and integrity evidence only. New generated JSON is not tested Godot data and no original starter validator was recovered.


## Approved DLC addendum — 2026-11-27
[Master DLC decision register 01–26](../../../game/docs/BEYOND_CIVILIZATION_GDD.md) traces approved design; [XG-01..20](../../../game/docs/XENOGENESIS.md), [Forge engines and MF-A01..08](../../../game/docs/MYRIEME_FORGE_INTEGRATION.md), [DLC-01..19](../../../game/docs/DLC_DELIVERY_PLAN.md) trace proposed implementation and acceptance. Existing archived requirements remain intact.
