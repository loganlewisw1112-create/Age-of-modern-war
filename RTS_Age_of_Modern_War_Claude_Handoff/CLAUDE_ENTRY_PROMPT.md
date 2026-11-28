# Claude entry prompt

You are taking over RTS: Age of Modern War from this evidence-preserving handoff. Read START_HERE.md, docs/01_AUTHORITY_AND_DECISIONS.md and docs/02_INCONSISTENCIES_AND_GAPS.md first, then the complete master, playable, architecture, civilization, skirmish, art, roadmap and testing documents. Consult source_text/ for exact extracted wording and reference/ for original formatting and images.

Your first response should establish what exists (design documents and reference images), what is not verified (any playable Godot implementation), the current RTS-first scope, and the gaps affecting execution. This handoff alone authorizes analysis/planning, not starting the game build. If the user subsequently authorizes development, proceed within that instruction and do not repeatedly ask for already granted permission.

Respect these constraints:

- Offline solo and optional G18 online modes, shared authoritative simulation, Godot 4 baseline with exact engine/version choices still proposed.
- Classic RTS first. G0: one map, camera, selection, validated commands, movement and measured 64-actor baseline. G1: build–produce–fight loop. G2: tactical systems. G3: three distinct factions, three authored maps, Stage 7–9 content and configurable skirmish. G4: hardening and honest measured scale. Survivor/continental/full 13-stage implementation is later.
- Exactly 13 stable stages; names are provisional. Only 7–9 playable in the substantial slice. Advanced loot or starting stage is not automatic industrial capability or equipment.
- Fixed-angle isometric camera; no free rotation in slice. Preserve grounded pixel-art direction and readable realistic silhouettes; mockups are concept references.
- AI uses the same commands, resources and legal intelligence as the player. Distinguish starting handicaps from difficulty.
- Credits and finite inventories, power, production, supply, component damage, officers, persistent wrecks/bridges and save/reload follow staged gates.
- Keep originals immutable. Do not treat older survivor-first phases as current priority. Do not claim absent catalogs, original validators, v1.1/v1.2 files or unsynced material were recovered.
- docs/02 records conflicting advancement prerequisites. Do not silently pick final gates. Use the dedicated 7→8→9 section for planning while exposing unresolved thresholds.
- New data/ files are reconstructed handoff aids, not recovered approved production catalogs.
- Every implementation claim needs runnable evidence. Every performance claim needs named hardware, build/config and measured scenario. 500–2,000 soldiers is a stress-test ambition, not an achieved on-screen count.

Initial requested output: a concise source-grounded handoff assessment, prioritized unresolved decisions, and a concrete G0 plan with dependencies, proposed architecture, smallest content set, acceptance scenarios and verification steps. Maintain feature/test IDs. Preserve the broader full-game vision without expanding G0 to implement it. Clearly distinguish source-reported approved direction, provisional values, new recommendations and tested results. Ask only decisions that materially block the next authorized work.


## Future expansion authority (2026-11-27)

[Space Expansion master design](../game/docs/SPACE_EXPANSION_GDD.md) records the approved DLC 1 / DLC 2 numbering, True Dynasty and independent starts, stellar catalog, Hidden Chronicle and engineering guidance. These are future planning specifications only; do not implement ahead of existing gates. No change to current source, build, save format or completion status.


## Corrected owner-approved execution sequence

G11–G17 full XENOGENESIS and Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization (DLC 2). Both systems must be fully implemented, integrated, tested and accepted by G17 exit (before G18 and G19): all 20 XENOGENESIS subsystems; all 15 Myrieme Forge engines and eight integration adapters, including offline runtime. Earlier development is permitted. G20 interstellar gameplay/content production happens after G19; G11–G17 testing uses representative fixtures without requiring full G20 content or exposing unowned DLC. No implementation or gate completion is claimed.


## G11–G17 integrated system development — current owner authority

G11–G17 integrated development of XENOGENESIS and full Myrieme Forge; both fully implemented, integrated, tested and accepted as mandatory G17 exit criteria. G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization. No separate integration checkpoint; G20 gameplay and full universe content production remain after G19. All 20 XENOGENESIS subsystems, 15 Forge engines and eight integration modules, offline runtime and shared director interoperability required by G17. Representative validation fixtures, not premature DLC gameplay; ownership boundaries remain. See the current ROADMAP and DLC delivery plan for per-gate assignments. No implementation or gate completion claimed.


**Current gate authority:** G17 Living World and full XENOGENESIS/Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion (DLC 1) → G20 Beyond Civilization (DLC 2). Both DLCs begin only after the base game is complete. No runtime changes or gate completion claimed.


## G18 current approved design authority

G18 final base game: internet multiplayer, independently owned open-source gaming platform, Last Protocol online co-op, Skirmish co-op/PvP, DEAD SECTOR (PATHOGEN) and SUBTERRANEAN WARFARE (DEEPWAR). Inheritance and Living World remain strictly offline solo. UNDERSTRIKE remains integrated, Human A-exclusive construction rights unchanged, not a standalone expansion. Neither new mode has individual soldier-follow. All XENOGENESIS and Myrieme Forge accepted by G17. G19 Space Expansion (DLC 1), G20 Beyond Civilization (DLC 2) only after G18; civilization continuations offline, compatible owned content in Skirmish. No mandatory platform login offline. Planned only.

Agents must preserve offline solo; internet networking and the two exclusive directors are future G18 implementation, never authorization to change source in a documentation pass.

[G18 MASTER GDD](../game/docs/G18_MASTER_GDD.md) · [G18 ONLINE MULTIPLAYER](../game/docs/G18_ONLINE_MULTIPLAYER.md) · [G18 OPEN GAMING PLATFORM](../game/docs/G18_OPEN_GAMING_PLATFORM.md) · [DEAD SECTOR GDD](../game/docs/DEAD_SECTOR_GDD.md) · [PATHOGEN DIRECTOR](../game/docs/PATHOGEN_DIRECTOR.md) · [SUBTERRANEAN WARFARE GDD](../game/docs/SUBTERRANEAN_WARFARE_GDD.md) · [DEEPWAR DIRECTOR](../game/docs/DEEPWAR_DIRECTOR.md) · [G18 DELIVERY PLAN](../game/docs/G18_DELIVERY_PLAN.md)
