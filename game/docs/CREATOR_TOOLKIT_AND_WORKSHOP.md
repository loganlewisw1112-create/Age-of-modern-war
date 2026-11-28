# CREATOR TOOLKIT AND WORKSHOP

Owner-approved expanded design direction; implementation pending. Proposed IDs, interfaces and pseudocode are design artifacts only. Reuse the Godot/Rust simulation, current director scheduler, validators and event ledger.

## Product
Local procedural creator and full edit mode, safe native modding SDK, community Workshop and Creator Store on independently owned platform. Players can create new game-mode configurations by composing supported scenario rules, objectives, maps and eligible simulation services; not arbitrary code execution or automatic new engines. Offline tools work without platform accounts. Quick create and full editor share one versioned schema, normal match authority and validation. No weakening of official faction rights/entitlements, secrets, competitive integrity or G10 gameplay.

| Editor | Capability |
|---|---|
| Terrain/world | Elevation, water, biomes, weather, seasons, lighting and hazard configuration |
| Infrastructure | Roads, rail, ports, airfields, settlements, templates, facilities |
| Forces | Units, formations, equipment, legal loadouts, faction/stage/doctrine |
| Objectives | Win/lose/partial, AND/OR/time/hold, conditions and causal events |
| Rules | Starting resources, teams, fog, economy, allowed directors and difficulty |
| Underground | Legal geology/geometry, existing prebuilt sites, Human A-only protected build rights |
| Campaign | Linked scenario graph, explicit persistent transfer and prerequisites |
| Full edit mode | Manual add/remove/move/rotate/inspect, selection, layers, undo/redo, validate, test launch |
| Procedural | Seeded quick generation, preview, selective regeneration with pinned authored sections |
| New mode config | Composable allowed rules/templates, icons/description, no new privileged directors or code |

Editor transaction/undo operates on draft scenario, not live campaign/online authoritative state. Validation checks references, legal starts, resource/route viability, win conditions, ownership, protected construction, performance and visibility. Instant test launch in isolated disposable save, report issues and return to draft. Import/export versioned local packages with manifest, thumbnails, author/provenance, license, content dependencies, seed/generator versions, checksum, schema. Scenario package cannot embed unauthorized DLC data or bypass faction playability. Community authored faction packages use supported rules; never override protected official capabilities. Original campaign secrets and protected scripts not exportable by default.

## Native mod SDK
Support declarative definitions for custom units, buildings, tech, faction packages, maps/scenarios, audio/assets, legal AI configuration and limited UI presentation. Versioned schema/docs, samples, schema validation, dependency graph, namespaces and conflict policy, deterministic mod load order, signed official manifests, compatibility matrix, local isolated test fixtures. Mod files untrusted: path traversal, archive bombs, malicious asset metadata, invalid refs and excessive resource usage rejected; no native binaries, unrestricted scripts, filesystem/network access or secret exposure in initial SDK. Advanced scripting only after explicit sandbox/security review and approval. Avoid exposing authoritative internal privileged methods. Multiplayer requires identical approved manifests, entitlement and host/session rules; ranked rules permit only verified content, unranked mod lobbies clearly labeled. Safe disable/remove, preserve save with missing dependency explanation, do not silently corrupt. No distribution of unauthorized game assets or third-party IP.

## Workshop + Creator Store
Publish free maps, scenarios, campaigns, new mode configs, base designs/templates, formation and faction/tech configurations, mods and eligible replays. Creator profiles, pages, screenshots/preview, categories/tags, search/filter, ratings, favorites, collections, dependency/version display, safe automatic resolution with consent, subscribe/update/pin, report, moderation, removals and rollback. Download verifies package hash/signature/schema, scans and validates before importing; untrusted content isolated. Do not force updates into existing saves/matches; pin version, archive when lawful, clear missing content warning. Keep local files playable offline; offline profiles private. Online account only for publishing/sharing/store actions. Minimal service using existing platform identity, storage/CDN and catalog; no always-on game servers. Content rules, provenance/license attestation, moderation queue, abuse quotas and creator appeal; distinguish official vs community content. Provide local sharing even when service unavailable.

Creator Store launch supports free discovery/distribution; paid content optional phased after licensing, creator payouts/revenue share, commerce/tax/refund, fraud/chargeback, support and moderation policy approved and operational. No pay-to-win, forced purchase for base competitive access or guaranteed creator earnings. Platform remains open source with owner-controlled hosting/brand/keys, license pending. [Platform roadmap](PLATFORM_PRODUCT_ROADMAP.md). G12 procedural/editor foundation, G14 SDK, G18 public tools, Workshop/free store launch and safe release. Acceptance includes create/play/share all supported types, version pin/deps, malicious package rejection, legal faction/ownership, offline import/export, matched online mods, report/takedown/rollback, creator UI and cost validation.

## G21 — Beyond Evolution extension (2026-11-27)

G21 extends existing creator pipeline with validated world, species, civilization and megastructure templates; no executable imports. Planned only; no runtime or frozen gate changes. This additive scope supersedes earlier two-DLC-only roadmap wording where applicable, not earlier mode restrictions. [Master GDD](BEYOND_EVOLUTION_GDD.md) · [Architecture](BEYOND_EVOLUTION_ARCHITECTURE.md) · [Delivery](BEYOND_EVOLUTION_DELIVERY_PLAN.md).
