# G18 DELIVERY PLAN

Owner-approved G18 design direction; implementation pending. Engineering contracts, candidate algorithms and schemas below are documentation-only proposals, not runtime code. Existing source, assets, saves and gate completion statuses are untouched.

## Execution and dependencies
G17 acceptance of XENOGENESIS and Myrieme Forge mandatory. G18 completes base game; G19/G20 cannot begin until G18 accepted. No executable implementation in this push. Existing Last Protocol co-op contract protected. Candidate implementation workstreams (parallel only when independent, use semantic coordination board, explicit ownership, frozen acceptance per slice):
| ID | Scope / dependency |
|---|---|
| MP-01 | Audit Godot/Rust contracts, simulation determinism, authority and input; freeze scope/performance baseline |
| MP-02 | Shared protocol, host authority, deterministic command validation, snapshots/deltas, fog; MP-01 |
| MP-03 | Direct internet transport, NAT/relay adapter, encryption, latency handling; MP-02 |
| PL-01 | Independent platform repository, license/dependency review, auth/profiles/friends/invites; parallel MP-01 after contracts |
| PL-02 | Public/private lobbies, matchmaking, compatibility, route tickets, region selection; PL-01/MP-03 |
| PL-03 | Relay operations, signed releases/launcher, privacy, moderation, backup, security and cost model; PL-02 |
| MP-04 | Reconnect, AI takeover, saves, host migration, optional dedicated hosting; MP-02/03, PL-02 |
| MP-05 | Last Protocol co-op vertical slice, claims/scaling/AAR; MP-04 |
| MP-06 | Skirmish co-op/PvP, legal teams, fog, manifest and balance; MP-04 |
| DS-01 | PATHOGEN core state, transmission, hordes, ecology, survivor/environment/ledger; existing sim |
| DS-02 | Four DEAD SECTOR scenarios, variants, horror presentation, persistence; DS-01 |
| DS-03 | Online DEAD SECTOR, shared/independent/competitive rules; DS-02/MP-04 |
| SW-01 | DEEPWAR core planning, faction-legal engineering, logistics, adaptive operations; accepted UNDERSTRIKE |
| SW-02 | Five warfare scenarios, dynamic battlefields, commander delegation, atmosphere; SW-01 |
| SW-03 | Online SUBTERRANEAN WARFARE, co-op/PvP, persistence; SW-02/MP-04 |
| G18-Q | End-to-end base game qualification, online platform operational readiness, offline regression, cost/security/accessibility; all above plus EX-A–H in expanded delivery |
Prototype one internet match across distinct networks before scaling; offline modes first in parallel where possible, shared adapters later. No duplicated transport/sim. Ship complete base game only after all required features and quality gates accepted. No release date claimed.

## Acceptance checklist
All NOT RUN. Candidate IDs; lock measurable budgets on documented hardware/network/provider before implementation.
| ID | Required evidence |
|---|---|
| G18-01 | G17 acceptance complete, no regression of existing solo gameplay |
| G18-02 | Offline launch/play/save without network, credentials or platform uptime |
| G18-03 | Inheritance/Living World/Dynasty remain strictly offline single-player; no online save merge |
| G18-04 | Last Protocol original solo and co-op rules, no PvP, claims/economy/scaling and Quick/Full/Iron |
| G18-05 | Skirmish co-op/PvP legal teams/factions/maps and balance |
| G18-06 | Internet sessions across distinct external networks, not merely LAN |
| G18-07 | NAT/CGNAT/firewall cases with relay fallback and region selection |
| G18-08 | Auth, invitations, public/private lobbies, matchmaking, block/report and access control |
| G18-09 | Host authority, dedupe, legal commands, fog/privacy, malformed/abusive inputs |
| G18-10 | Latency/jitter/loss/bandwidth simulation, resync and clear feedback |
| G18-11 | Reconnect and AI takeover without duplicated resources/orders |
| G18-12 | Host loss/migration, epoch safety, checkpoint replay or explicit safe failure |
| G18-13 | Optional dedicated host and direct/LAN compatibility, no separate stack |
| G18-14 | Save compatibility, session identity, no Dynasty merge; Iron policy |
| G18-15 | DLC manifest/entitlement fixtures, no unowned content or unauthorized factions |
| G18-16 | Platform owner control, open-source license/dependency inventory, reproducible release and signature |
| G18-17 | Account recovery/revocation, privacy/export/deletion, audit, moderation and secret rotation |
| G18-18 | Restore backup, service outage and relay capacity/abuse drills; offline unaffected |
| G18-19 | Measured provider/traffic/support costs, founder-approved spend cap and scaling plan |
| G18-20 | All four DEAD SECTOR scenarios solo and supported online rules |
| G18-21 | PATHOGEN causal infection, finite populations, migration/dormancy/evolution/counterplay |
| G18-22 | Survivor autonomy, supplies/medical/morale, faction vulnerabilities and automation |
| G18-23 | Cinematic horror score, low tones/silence, legibility, accessible audio/lighting |
| G18-24 | All five SUBTERRANEAN WARFARE scenarios solo and supported online rules |
| G18-25 | DEEPWAR fog-limited autonomous command, adaptive doctrines, meaningful counterplay |
| G18-26 | Existing Human A-exclusive bunker/borer rights enforced, even capture/multiplayer |
| G18-27 | Excavation, surface/underground routes, geology, damage, repair, persistence and physical logistics |
| G18-28 | Delegate/takeover, conflict arbitration and autonomous response |
| G18-29 | Both new modes quick presets, advanced settings, seeds, objectives, persistent saves; no grind |
| G18-30 | Neither new mode allows individual soldier-follow; RTS camera and controls retained |
| G18-31 | Mode-exclusive directors never run unrelated scenarios; shared authority and deterministic tests |
| G18-32 | Active/distant LOD conservation, tick/frame/CPU/RAM/save size/network budgets and long soaks |
| G18-33 | Offline and online playtests demonstrate fun, replayability, intuitive controls, no forced micromanagement |
| G18-34 | Full base-game release acceptance including EX-A01–40; G19/G20 blocked until sign-off |

## Production risks
Scope: reuse combat, content, UI, directors and transport, no MMO/storefront clone. Host trust: disclose host authority, optional dedicated hosting; do not promise perfect anti-cheat. Privacy/migration: protect hidden state, explicit failure rather than unsafe fallback. Cost: direct first, measure relay traffic, cap spend, avoid always-on simulation. Quality: staged integration, golden replays and actual internet test matrix. Exact platform license/name/provider/stack, networking transport, numerical budgets, final scenario maps/assets/audio, larger player counts and DLC commercial guest policy remain production decisions. No tests run, no code or infrastructure deployed. [Master](G18_MASTER_GDD.md).


## Expanded acceptance overlay

All 34 original G18 checks remain required. [Expanded delivery](EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) adds 40 checks and eight shared workstreams; overlap reuses evidence. Final G18 release qualification includes all eleven experiences, creator/SDK, free Workshop/Store, replays/spectators/records, player experience, platform product and production readiness. All NOT RUN.


## Expanded gameplay and creator authority — 2026-11-27

Expanded owner-approved design authority: eleven base-game experiences, including BLACK OPERATIONS (7), SIEGE WARFARE (7), CONQUEST (6), COMMANDER'S CRUCIBLE (7) and WAR THEATRE (7), in addition to the six existing/planned modes. Three shared systems (OPERATIONAL INTELLIGENCE, WORLD ARCHIVE, DYNAMIC SCENARIO ENGINE), procedural world/fortress generation, engineering templates, full scenario editor/SDK, free Workshop/Creator Store, complete replays/spectators/records, player experience, reusable platform and production readiness are integrated across G11–G18. G18 finalizes all base-game scope. Seven directors unchanged, no new director; no online Inheritance/Living World, no new official playable DLC factions outside Skirmish, Human A-only protected bunker/borer construction, no individual soldier-follow in new modes. Full XENOGENESIS and Forge acceptance at G17; G19 then G20 after G18. All planned, not implemented. Existing frozen scopes and G10.1 regression unchanged.

[Master GDD](EXPANDED_GAMEPLAY_MASTER_GDD.md) · [Delivery](EXPANDED_GAMEPLAY_DELIVERY_PLAN.md) · [Shared scenario engine](DYNAMIC_SCENARIO_ENGINE.md) · [Creator tools](CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Platform](PLATFORM_PRODUCT_ROADMAP.md).
