# PLATFORM PRODUCT ROADMAP

Owner-approved expanded design direction; implementation pending. Candidate contracts and acceptance criteria are documentation only, not shipped capabilities.

## Independently owned reusable gaming platform
Extends [G18 platform](G18_OPEN_GAMING_PLATFORM.md) from AOMW multiplayer to a modular reusable platform for our future games. Own and control repository, deployment, domains, signing keys, data export and brand; open-source platform license and contribution policy pending. No mandatory Steam or external store account, no required login for offline play. Reuse mature standard security/transport dependencies; do not copy proprietary branding/code. Maintain low indie cost, direct hosting plus relay as needed, optional dedicated hosts; no always-running simulation.

| Product component | Scope / staging |
|---|---|
| Game library | Owned/installed/available titles, local install detection, versions, offline launch |
| Independent launcher | Install/update/repair/launch, signed manifests, resumable downloads, rollback |
| Accounts | Shared player identity, recovery/revocation, privacy, optional MFA |
| Profiles | Eligible online achievements/trophies/records, cosmetic display and privacy |
| Friends/social | Friends, invites, block/report |
| Multiplayer | Existing matchmaking, public/private lobbies, direct/relay, reconnect/migration |
| Workshop | Free community maps, scenarios, new mode configs, mods, templates |
| Creator Store | Search/discovery/preview, free downloads, optional future paid creator content |
| Replay library | Local and eligible shared replays, search/preview/version compatibility |
| Developer portal | Project/game registry, builds, releases, integration credentials, role-based access |
| Distribution | Signed artifacts, channels, updates, storage/CDN, version/entitlement manifests |
| Commerce | Chosen base-game/DLC purchase solution, entitlement, refunds, taxes; phased broader marketplace |
| Public SDK/API | Versioned identity/lobby/ownership/content/release interfaces, docs, sample integrations |
| Community safety | Content reports, moderation, abuse protection, appeals, privacy and security |
| Recovery | Backup/restore, outage fallback, portability, key rotation, incident response |

Launch-critical G18: functional library/launcher, account/social/multiplayer, free Workshop/Creator Store and replay catalog, minimally usable owner developer portal and versioned integration SDK/API, signed distribution, chosen commercial/entitlement flow, safety and recovery. Future phased commercial scale: public third-party publishing, full multi-game discovery, paid creator marketplace, payouts, broader storefront/reviews and additional provider integrations. These are approved product direction but not forced expensive launch features; exact rollout and commercial requirements need owner gate sign-off. No need to simulate an entire Steam-sized business before AOMW release. AOMW first tenant/product, IDs and scopes generic enough for future games.

Candidate model Game {id, owner_org, namespace, supported_protocols, metadata}; Release {game_id, channel, version, artifacts, signature, content_manifest}; LibraryEntry {account, product, entitlement, install_ref}; CreatorItem {game_id, package_id, version, author, license, manifest, moderation_status}; DeveloperRole {org, subject, scopes}; Purchase {id, product, provider_ref, status, entitlement_ref}; no payment card storage by game service. Versioned API: auth/session, library/entitlements, catalog, releases, install manifests, social/lobbies/routes, creator publish/search/download, reports, replay metadata. Scoped credentials, quotas, audit and revocation; per-game namespace isolation, no developer access to other titles or private users. Minimal developer portal owner workflows: register game, upload signed build, set channel, inspect verification, promote/rollback, revoke credentials, read permitted aggregate ops counters. Public docs and example integration; no embedded secrets. User data export/deletion, retention, moderation, content license provenance, backup restore and service outage plan. Offline local receipts verified according to final entitlement policy.

Commerce design: choose payment provider/merchant model based on costs, jurisdiction, taxes, consumer rights and refund obligations; never implement raw card handling. Verify provider events, idempotently issue/revoke entitlement per policy, reconcile transactions, support clear refunds and dispute workflows. Paid creator content only after explicit payout/revenue-share, IP/license, tax, moderation, fraud, chargeback, support and refund policy and financial review; free sharing first, no pay-to-win or mandatory marketplace. Base-game price, DLC prices, creator revenue split, licensing/provider/host budget and platform name remain pending; no promised revenue or free operation.

Cost model extends direct/relay budget with artifact/Workshop/replay storage and egress, moderation/support, payment fees, backup and monitoring. Measure actual usage, quotas and founder-approved spend alerts/caps, no silent active-match cutoff for ordinary limits. Prefer shared modular control plane, transactional DB and object storage, no premature microservices. Acceptance: install/update/repair/rollback, offline launch, entitlement/refund fixtures, game namespace separation, developer release and scoped API, free creator workflow, replay catalog, account privacy/deletion, restore/outage and security drills, actual traffic/cost and operational owner control. [Creator](CREATOR_TOOLKIT_AND_WORKSHOP.md) · [Production](PRODUCTION_RELEASE_FRAMEWORK.md).

## G21 — Beyond Evolution extension (2026-11-27)

G21 adds compatible declarative world/species/system templates; offline solo core and existing ownership rules remain. Planned only; no runtime or frozen gate changes. This additive scope supersedes earlier two-DLC-only roadmap wording where applicable, not earlier mode restrictions. [Master GDD](BEYOND_EVOLUTION_GDD.md) · [Architecture](BEYOND_EVOLUTION_ARCHITECTURE.md) · [Delivery](BEYOND_EVOLUTION_DELIVERY_PLAN.md).
