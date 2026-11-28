# Myrieme Forge — full DLC integration specification
Owner-approved 2026-11-27; independent proprietary tool and game runtime are planned, not implemented. Source: owner-supplied MYRIEME_FORGE_README.md (procedural language foundry). All fifteen engines and eight game integration modules approved. [Master DLC GDD](BEYOND_CIVILIZATION_GDD.md) · [XENOGENESIS](XENOGENESIS.md).

## Production pipeline
Seed + version + civilization profile → phonology → phonotactics → prosody → morphology → syntax → lexicon → names → scripts → controlled translation → audio → evolution → quality → exports → human canon approval. Maintain stable semantic IDs and mappings. Same seed/config/engine version reproduces output. Canon lock prevents silent replacement of established words, names, glyphs, grammar and pronunciation; additive changes versioned, breaking changes require explicit approval/migration. Preserve existing Vhessar/Unbound canon and human nicknames; no replacement by generated output.

| Engine | Production output | Offline runtime role |
|---|---|---|
| 01 Seed | Reproducible versioned project seeds | Stable derived RNG streams for new names/events |
| 02 World Profile | Biology, culture, environment, values, taboos, history | Consume approved profile revisions and contextual registers |
| 03 Phonology | Inventories and sound restrictions | Validate generated words |
| 04 Phonotactics | Syllable and combination rules | Generate legal new forms |
| 05 Prosody | Stress, cadence, tone and register | Select contextual cadence/audio references |
| 06 Morphology | Inflection, derivation, tense, case, plural, honorifics | Bounded word formation |
| 07 Syntax | Grammar and sentence ordering | Controlled semantic templates and parsing |
| 08 Lexicon | Semantic fields, dictionaries, technology, war, trade and culture | Stable concept IDs; bounded new terms |
| 09 NameForge | Personal, clan, planet, city, fleet, artifact and operation names | Deterministic naming with collision checks |
| 10 Script & Glyph | Writing systems, glyph IDs, SVG/PNG/atlas and eroded variants | Render cached mapped glyphs, signage and historical variants |
| 11 Translation | Controlled bidirectional translation, literal gloss, native script, readable subtitles | Interpret known semantic messages; confidence/unknown fragments, not universal free-text translation |
| 12 Audio | Pronunciation guides, phonemes, voice directions, speech/chant/radio clips | Cached clips and optional bounded offline synthesis, fallback text |
| 13 Evolution | Proto/daughter languages, dialects, borrowing and sound shifts | Event-driven divergence constrained by elapsed time, contact and canon |
| 14 Quality | Collision, consistency, pronounceability, uniqueness, faction fit, glyph/UI readability | Validate additions, reject malformed output, fallback |
| 15 Exporter | JSON, CSV, Markdown language bible, HTML, SVG/PNG atlases, WAV/MP3, localization/engine packs | Read validated compact packages; no heavyweight exporter in active RTS ticks |

## Eight integration modules
| ID | Module | Contract |
|---|---|---|
| MF-A01 | Civilization Language Bridge | Stable civilization/language IDs; consume committed migration, split, merger, cultural and technology events once; emit language updates only |
| MF-A02 | Multimodal Communication | Acoustic, visual, vibrational, chemical and synthetic modalities; authored channels/encodings; accessible text/visual alternatives; extension beyond original speech/glyph plans |
| MF-A03 | First Contact Intelligence | Observation evidence, decipherment state and confidence; unknown fragments remain unknown; no instant omniscience or required puzzles |
| MF-A04 | Xenolinguistic Archaeology | Historical corpora, artifacts, damaged glyphs, extinct dialect reconstruction; provenance and uncertainty |
| MF-A05 | Interstellar Naming Registry | Stable IDs, native/exonym aliases, collision scopes, historical names; never rename physical geography by changing display name |
| MF-A06 | Cultural Exchange | Trade, migration, isolation and contact drive borrowing/daughter languages at plausible timescales |
| MF-A07 | Environmental Language | Semantic labels → cached decals/signage/inscriptions/banners/ship markings; preserve atlas mappings and readability |
| MF-A08 | Runtime Communication | Typed military/diplomatic/scientific intents → native text, readable subtitles and optional audio; cache/rate-limit; no simulation authority |

## Per-package scope
Base game and UNDERSTRIKE: existing terminology protected; human military registers, scavenger slang, machine protocols, Coalition codes and isolated bunker dialects where useful. No requirement to retrofit shipped content before current milestones. DLC 1: colony dialects, station/fleet/ship/operation naming, military signals, trade and science vocabulary, independent colony linguistic divergence, machine protocols and cross-cultural exchange, historical records and native environmental markings. Preserve existing arrival war language/nickname concepts. DLC 2: every extraterrestrial civilization receives complete native language families, modality profiles, military and civilian registers, scripts/glyphs, audio, naming, ancient/extinct forms, first contact and evolving cultural exchange. XENOGENESIS supplies events and knowledge, Forge supplies language; translation never directly decides diplomacy or combat. Player sees intelligible UI and uncertainty, not mandatory linguistic management.

## Data and integration
Illustrative package manifest: {schemaVersion, engineVersion, canonVersion, languageId, familyId, seed, profileRef, modalityIds, phonologyRef, grammarRef, lexiconRef, glyphAtlasRef, audioManifestRef, translationTemplatesRef, evolutionRulesRef, checksum}. Stable concept IDs distinct from strings; native spelling/romanization/glyph/pronunciation and locale subtitle stored separately. Runtime language state: {languageId, parentId, version, speakersRef, contactRefs, derivedSeed, lexiconDelta, historicalAliases, deciphermentByObserver, appliedEventIds}. Events carry tick, elapsed simulated time and provenance. Bounded grammar and lexicon growth, versioned snapshots, atomic package validation, offline fallback to approved text, no network or external AI requirement. Precompute expensive assets, lazy load, cache, schedule noncritical work outside active combat; deterministic ordering and save/load; no audio-dependent gameplay. Independent tool remains reusable/proprietary; export only owned/licensed assets. Godot presentation + Rust simulation interfaces; original Forge Unity/Unreal exports remain tool targets, not game dependencies.

## Acceptance
For each engine and adapter: golden seed/config fixtures, reproducibility, malformed inputs, bounded output, canon lock, migration, collisions, language inheritance, controlled translation round trips with ambiguity, glyph ID and atlas validation, audio fallback, modality accessibility, first-contact belief isolation, event deduplication, offline package loading, save/load replay, cache and CPU budgets. Test DLC 1 and DLC 2 independently and base game without entitlement. No required language lessons or manual translation; RTS readability/playtests. All tests NOT RUN; exact budgets and final names pending.


## 2026-11-27 — Authoritative expansion integration

DLC 1 = Space Expansion (G19); DLC 2 = Beyond Civilization (G20). UNDERSTRIKE is integrated base game. True Dynasty is the primary earned progression from Inheritance through Living World and both expansions, preserving the same civilization history. Independent preset/custom starts in either owned DLC are separate saves, never modifying Dynasty; DLC 1 standalone can continue to DLC 2. New DLC factions playable only in Skirmish. Existing campaign battle rules, endings, arrival war, rosters and current gate statuses are protected. All new work is planned, not implemented.

Extend planned 15 engines and eight integrations to colony dialects, fleet/ship/station names, scientific vocabulary, signals and archaeological evidence; independent production tool, offline runtime, no mandatory linguistic micro.

[SPACE EXPANSION GDD](SPACE_EXPANSION_GDD.md) · [STELLAR SYSTEM BIBLE](STELLAR_SYSTEM_BIBLE.md) · [EXOTIC RESOURCE BIBLE](EXOTIC_RESOURCE_BIBLE.md) · [SPACE TECHNOLOGY ARCHITECTURE](SPACE_TECHNOLOGY_ARCHITECTURE.md) · [DYNAMIC SPACE ENVIRONMENT](DYNAMIC_SPACE_ENVIRONMENT.md) · [HIDDEN CHRONICLE](HIDDEN_CHRONICLE.md) · [AUTONOMOUS SPACE COMMAND](AUTONOMOUS_SPACE_COMMAND.md) · [SPACE EXPANSION DELIVERY PLAN](SPACE_EXPANSION_DELIVERY_PLAN.md)


## Corrected owner-approved execution sequence

G11–G17 full XENOGENESIS and Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization (DLC 2). Both systems must be fully implemented, integrated, tested and accepted by G17 exit (before G18 and G19): all 20 XENOGENESIS subsystems; all 15 Myrieme Forge engines and eight integration adapters, including offline runtime. Earlier development is permitted. G20 interstellar gameplay/content production happens after G19; G11–G17 testing uses representative fixtures without requiring full G20 content or exposing unowned DLC. No implementation or gate completion is claimed.


## G11–G17 integrated system development — current owner authority

Owner-approved execution: distribute XENOGENESIS and full Myrieme Forge implementation/integration across G11–G17, with full acceptance required to close G17. G18 Online Multiplayer & Final Base Game → G19 Space Expansion → G20 Beyond Civilization follow in order. Pre-G18 prerequisite remains mandatory but is satisfied at G17; no standalone checkpoint after G19. G20 actual interstellar gameplay and production universe content remain after G19; representative fixtures validate all systems beforehand. Entitlement boundaries and existing gate scopes remain protected; no implementation or completion claimed.

| Gate | Assigned system work |
|---|---|
| G11 | Shared stable IDs, versioned persistence, event ledger, bounded scheduler interfaces, Forge package/schema and independent tool foundation; reuse existing contracts. |
| G12 | Forge language generation and communication foundations; XENOGENESIS species, ecology, population and environment contracts; representative offline fixtures. |
| G13 | Integrate resource, settlement, ecology and archaeology interfaces with underground discoveries; Forge ancient scripts, naming and historical language data; preserve UNDERSTRIKE faction restrictions. |
| G14 | Complete remaining Forge production engines and adapters against faction/stage content; develop XENOGENESIS civilization, economic, political, military, research and engineering capabilities using representative species and factions. |
| G15 | Integrate campaign history, generational state, linguistic evolution, communication, first-contact and archaeological interpretation; protect campaign secrets and personally played battle rules. |
| G16 | Complete outstanding XENOGENESIS subsystems and Forge integration; harden deterministic cross-director arbitration, persistence, performance, offline packages and representative stress tests. |
| G17 | Mandatory full completion and acceptance: all XG-01–20 subsystems, all 15 Forge production engines, all eight integration adapters, lightweight offline runtime, full interoperability with the four existing directors, save/load, entitlement, determinism, performance and regression evidence. No deferral of system capabilities to G18/G19/G20. |


**Current gate authority:** G17 Living World and full XENOGENESIS/Myrieme Forge acceptance → G18 Online Multiplayer & Final Base Game → G19 Space Expansion (DLC 1) → G20 Beyond Civilization (DLC 2). Both DLCs begin only after the base game is complete. No runtime changes or gate completion claimed.


## G18 design integration

G18 final base-game completion includes online Last Protocol co-op, Skirmish co-op/PvP, owned open-source gaming platform, DEAD SECTOR/PATHOGEN and SUBTERRANEAN WARFARE/DEEPWAR. Inheritance and Living World offline solo only; UNDERSTRIKE integrated Human A branch. No soldier-follow in new modes. G17 full XENOGENESIS and Myrieme Forge acceptance precedes G18, then G19 Space Expansion and G20 Beyond Civilization. No new DLC, code changes or completion claims.

Myrieme Forge full G17 acceptance; G18 platform and multiplayer can consume compatible signed versioned language assets without mandatory cloud or duplicate inference; no deferred Forge system capabilities.

[Master GDD](G18_MASTER_GDD.md) · [G18 delivery](G18_DELIVERY_PLAN.md) · [PATHOGEN](PATHOGEN_DIRECTOR.md) · [DEEPWAR](DEEPWAR_DIRECTOR.md).
