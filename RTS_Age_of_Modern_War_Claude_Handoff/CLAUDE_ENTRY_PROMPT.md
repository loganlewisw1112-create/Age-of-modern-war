# Claude entry prompt

You are taking over RTS: Age of Modern War from this evidence-preserving handoff. Read START_HERE.md, docs/01_AUTHORITY_AND_DECISIONS.md and docs/02_INCONSISTENCIES_AND_GAPS.md first, then the complete master, playable, architecture, civilization, skirmish, art, roadmap and testing documents. Consult source_text/ for exact extracted wording and reference/ for original formatting and images.

Your first response should establish what exists (design documents and reference images), what is not verified (any playable Godot implementation), the current RTS-first scope, and the gaps affecting execution. This handoff alone authorizes analysis/planning, not starting the game build. If the user subsequently authorizes development, proceed within that instruction and do not repeatedly ask for already granted permission.

Respect these constraints:

- Offline single-player, shared authoritative simulation, Godot 4 baseline with exact engine/version choices still proposed.
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
