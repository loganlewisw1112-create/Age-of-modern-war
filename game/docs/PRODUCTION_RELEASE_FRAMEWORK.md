# PRODUCTION RELEASE FRAMEWORK

Owner-approved expanded design direction; implementation pending. Candidate contracts and acceptance criteria are documentation only, not shipped capabilities.

## Engineering and release-readiness contract
Protect current playable G10 build, close G10.1 broad regression before new work; no change to current gate status. Existing frozen scopes/GOAL and Done-when remain until owner-approved revision. All proposed checks need evidence, not documentation sign-off. Build shared foundations early, no executable implementation in this design push.

## Benchmark and performance assistant
Built-in optional benchmark using reproducible representative scenes (classic RTS, dense mixed formations, urban/underground, distant theatre/civilization, online where relevant). Measure frame/tick distributions, CPU/GPU/RAM/VRAM, pathing, storage/snapshot and network costs on specified hardware; report measured limits and recommend visuals, simulation fidelity budget and scenario scale. Distinguish rendering LOD from authoritative simulation outcomes. No hidden simulation outcome changes or forced quality degradation; if unsupported scenario warn and offer lower scale. Existing Last Protocol and other locked requirements protected. Minimum/recommended hardware only after repeatable tests across actual supported configurations; Windows first, Linux/macOS feasibility evaluated without promising support. No speculative unlimited unit counts. Long-duration soaks verify deterministic persistence, conservation, director scheduling, promotion/demotion and stable memory. XENOGENESIS/Myrieme Forge acceptance by G17 unchanged.

## Durable saves
Versioned envelope {schema, game/build, content_manifest, save_id, lineage, mode, world_seed, authoritative_snapshot, ledger_cursor, RNG, checksums, required_entitlements}; write temporary verified file then atomic replace, rotating local backups and named checkpoints; protect prior good save on migration/failure. Transactional migration registry with preflight, copy, invariant/hash verification, recovery and rollback. Never destructively rewrite sole Dynasty save. Corruption/missing mods/ownership/version clear explanation and recovery options, no silent data loss/substitution. Test interrupted writes, disk full, corrupt chunks, migration across versions, native/fallback, long save, offline no-account, no campaign/online merge; local backup export. Optional future cloud only for eligible non-campaign records by consent, no mandatory cloud or offline campaign upload.

## Content production pipeline
Data-driven shared schemas for unit/building/faction/stage/tech/role, assets, four-facing sprites, animations, audio, maps, scenarios, blueprints, legal capabilities and localization. Source provenance/license and owner visual approvals, original art identity and real-world proportions; validate required art/facings/animation states, references/IDs, duplicate definitions, tech cycles, resource prerequisites, vehicle clearance, role parity, terrain graphs, objective reachability, entitlement/secret boundaries. Automated generation and review strips, deterministic fixtures, schema diffs, preview tool and manual quality gate. Missing/invalid assets fail validation, no misleading placeholder as shipped. No forced new visual style. Creator SDK shares validation without exposing internal privileged assets. Measure authoring throughput and reduce repeated manual work. G12–G14 foundations, G16/G17 stress, G18 release validation.

## Release plan and operational readiness
| Area | Required deliverable |
|---|---|
| QA | Clean full regression; per-gate frozen acceptance, native/fallback, UI, packaged build, AI soaks, mode matrix, actual internet playtests, hardware tests, manual external testers |
| Packaging | Reproducible signed artifacts, manifests, dependency inventory, clean machine install/update/rollback, crash-safe patching |
| Performance | Published supported configurations, measured frame/tick/network budgets, scale presets and diagnostics |
| Accessibility | Remapping, UI scale, visual/audio cues, reduced flash/shake, keyboard flows; tested with players |
| Localization | Externalized strings, fonts/encoding/layout/pluralization, text expansion, launch language choices, translated QA; fictional language runtime separate |
| Licensing | Game asset/audio/code provenance, third-party notices, contributor policy and platform OSS license, community content rights |
| Commerce | Base and DLC pricing/business model, distribution, tax/refund/entitlement policy, clear product/store descriptions |
| Launch | Closed alpha/beta or controlled test cohorts, feedback triage, public trailers/screenshots from actual builds or labeled concepts, store page/press materials |
| Support | Help docs, known issues, opt-in redacted diagnostics, bug reporting, support ownership and incident process |
| Security/privacy | Dependency review, abuse/relay controls, data minimization, deletion/export, signed updates, recovery drill |
| Post-launch | Patch/balance/security cadence, compatibility/migration policy, rollback, transparent changelog and support budget |
| Sustainability | Measured platform costs, founder-approved budget, staffing/support needs, release readiness sign-off |
No dates, financial forecasts or minimum system specs claimed. Platform license, price, launch countries/languages, payment/provider choices, exact hardware and performance budgets require production decisions. Use actual gameplay capture for marketing; no fabricated features. Optional diagnostics must be opt-in, redacted, no private campaign stats upload. No release of G19/G20 before G18 full base-game acceptance. [Integrated delivery](EXPANDED_GAMEPLAY_DELIVERY_PLAN.md).
