# Design authority and decision register

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [Technical_Architecture_v1.0](../source_text/Technical_Architecture_v1.0.md), [Game_Next_Steps_Conversation](../source_text/Game_Next_Steps_Conversation.md)

## Evidence hierarchy

Current user instructions control this handoff. The v1.3 documents explicitly distinguish approved creative direction from provisional implementation values. Treat their approval statements as source-reported approval; the complete original approval conversation was not supplied. The retrieved assistant's recommendations alone do not establish new approval. v1.3 supersedes older survival-first sequencing while retaining the full-game vision. v1.0 architecture remains useful where compatible, but describes proposed engineering decisions.

| ID | Direction | Status and evidence |
|---|---|---|
| DEC-01 | Offline solo; optional online modes at G18; no required cloud or runtime language model | v1.3 Master §§1,10 |
| DEC-02 | Classic RTS Custom Skirmish first; survivor expansion later | v1.3 Master §§2–3,13; Roadmap G0–G6 |
| DEC-03 | Exactly 13 stable stages for humans and machines | v1.3 Master §5; Bible §§1–2,6 |
| DEC-04 | Slice playable stages 7–9, Stage 8 focus; others visible and disabled | Master §§3–5; First Playable §§1,9 |
| DEC-05 | Three structurally distinct factions, two human and one machine | Master §6; First Playable §§4–5 |
| DEC-06 | Three authored maps in Industrial River Valley; bounded seeded variations | Master §4; First Playable §3 |
| DEC-07 | Fixed-angle isometric slice camera; no free rotation | Master §12; First Playable §8 |
| DEC-08 | Credits plus physical inventories; configurable economic depth | Master §§4,7; First Playable §6 |
| DEC-09 | Player and AI share command, resource and knowledge constraints | Master §10; Architecture §§1,4–5 |
| DEC-10 | Officers, supply, casualties, component damage and selected persistent destruction | Master §§8–9; First Playable §7 |
| DEC-11 | Configurable victories, AND/OR composition and Endless | Master §4; First Playable §§2,9 |
| DEC-12 | Grounded atmospheric pixel-art/2.5D identity; mockups are concept references | Master §11; original Approved_Mockups |
| DEC-13 | Start with 64 actors, profile toward 500–2,000 soldiers | Roadmap §§1,7; no achieved capacity asserted |
| DEC-14 | Names, exact costs, rates, hardware and art geometry remain provisional | Master §13; Architecture §10 |

## Change control

Preserve original evidence. Assign a decision ID, source, affected feature/test IDs and explicit status to any change. Never silently turn a fixture, assistant suggestion or reconstructed catalog into a user-approved fact. Request a decision only when a material choice cannot be resolved from sources; complete bounded planning work first. This handoff request authorizes documentation packaging, not game implementation.


## Approved DLC addendum — 2026-11-27
Owner-approved 2026-11-27 addendum: all 26 DLC decisions and five finalization components are approved design, not implemented or frozen gate scope. The current owner-approved addendum controls conflicts; archived source text remains unchanged. See [decision register](../../game/docs/BEYOND_CIVILIZATION_GDD.md).


## 2026-11-27 — Current expansion design authority

DLC 1 is Space Expansion (G19); DLC 2 is Beyond Civilization (G20). UNDERSTRIKE is base game. True Dynasty is the primary earned continuous campaign → Living World → DLC 1 → DLC 2 path; preset/custom independent starts are separate new saves. Existing game code, gate statuses, campaign canon and rosters are unchanged. All additions are planned, not implemented.

Approved 15 space decisions, stellar design and four final decisions: Hidden History D+, validated physics D, original technology D+, Dynasty A with independent B/C.

[SPACE EXPANSION GDD](../../game/docs/SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](../../game/docs/STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](../../game/docs/EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](../../game/docs/SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](../../game/docs/DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](../../game/docs/HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](../../game/docs/AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](../../game/docs/SPACE_EXPANSION_DELIVERY_PLAN.md)


## Corrected owner-approved execution sequence

G11–G17 full XENOGENESIS and Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization (DLC 2). Both systems must be fully implemented, integrated, tested and accepted by G17 exit (before G18 and G19): all 20 XENOGENESIS subsystems; all 15 Myrieme Forge engines and eight integration adapters, including offline runtime. Earlier development is permitted. G20 interstellar gameplay/content production happens after G19; G11–G17 testing uses representative fixtures without requiring full G20 content or exposing unowned DLC. No implementation or gate completion is claimed.


## G11–G17 integrated system development — current owner authority

G11–G17 integrated development of XENOGENESIS and full Myrieme Forge; both fully implemented, integrated, tested and accepted as mandatory G17 exit criteria. G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization. No separate integration checkpoint; G20 gameplay and full universe content production remain after G19. All 20 XENOGENESIS subsystems, 15 Forge engines and eight integration modules, offline runtime and shared director interoperability required by G17. Representative validation fixtures, not premature DLC gameplay; ownership boundaries remain. See the current ROADMAP and DLC delivery plan for per-gate assignments. No implementation or gate completion claimed.


**Current gate authority:** G17 Living World and full XENOGENESIS/Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion (DLC 1) → G20 Beyond Civilization (DLC 2). Both DLCs begin only after the base game is complete. No runtime changes or gate completion claimed.


## G18 current approved design authority

G18 final base game: internet multiplayer, independently owned open-source gaming platform, Last Protocol online co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN) and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE remains integrated, Human A-exclusive construction rights unchanged, not a standalone expansion. Neither new mode has individual soldier-follow. All XENOGENESIS and Myrieme Forge accepted by G17. G19 Space Expansion (DLC 1), G20 Beyond Civilization (DLC 2) only after G18; civilization continuations offline, compatible owned content in Skirmish. No mandatory platform login offline. Planned only.

All eleven DEAD SECTOR and nine SUBTERRANEAN WARFARE decisions approved; G18 four tracks, no Steam requirement, indie costs, no online campaign.

[G18 MASTER GDD](../../game/docs/G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](../../game/docs/G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](../../game/docs/G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](../../game/docs/DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](../../game/docs/PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](../../game/docs/SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](../../game/docs/DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](../../game/docs/G18_DELIVERY_PLAN.md)


## Expanded gameplay authority — 2026-11-27

Current owner-approved expanded design: G11–G18 integrates 33 additions and five additional modes (34 scenario families), three shared systems, procedural world/fortresses, creator/SDK/Workshop/Store, replay/spectators/records, player experience, independent platform and release qualification. G18 finalizes eleven base-game experiences. Inheritance/Living World offline solo only; no additional global directors or new official DLC playable factions outside Skirmish; Human A-only bunker/borer construction. G17 full XENOGENESIS/Myrieme Forge acceptance unchanged; G19 then G20 after G18. Planned only; no source changes or milestone acceptance.

EX-01–33 owner-approved design direction; 34 new scenario families and 40 expanded acceptance criteria. Working names, exact matchmaking/scale and production choices remain subject to gate sign-off.

[Expanded master](../../game/docs/EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Delivery and acceptance](../../game/docs/EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Scenario engine](../../game/docs/DYNAMIC_SCENARIO_ENGINE.md) · [Operations](../../game/docs/OPERATIONAL_INTELLIGENCE.md) · [Archive](../../game/docs/WORLD_ARCHIVE.md) · [Creator toolkit](../../game/docs/CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Platform](../../game/docs/PLATFORM_PRODUCT_ROADMAP.md).
