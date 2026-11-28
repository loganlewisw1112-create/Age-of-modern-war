# REPLAY SPECTATOR AND RECORDS

Owner-approved expanded design direction; implementation pending. Candidate contracts and acceptance criteria are documentation only, not shipped capabilities.

## Complete replay architecture
Beyond the existing director camera, highlights and after-action report: record complete eligible offline and online tactical matches, allow pause, speed, rewind, seek, permitted viewpoints, timeline bookmarks, battle statistics, formation/operation inspection, screenshots/highlights and local library. Preserve private offline Dynasty archives locally; never auto-upload Inheritance/Living World. Existing campaign battle rules unchanged. Replays are not editable live saves. Shared eligible replay packages versioned and clearly labeled modded/unranked; no hidden campaign content or unowned asset distribution.

Replay header {schema, build/protocol, content_manifest, scenario_id, rules_hash, seed, session_id, allowed_viewers, timebase}; stream {tick, authority_epoch, accepted_command/event, sequence, checksum}; index {tick, authoritative_checkpoint_ref, event_cursor, visible_summary}; trailer {final_hash, outcomes, verification_status, author/provenance}. Candidate design: deterministic command/event stream + periodic authoritative snapshots, with measured snapshot fallback if native/fallback or platform determinism diverges. Record accepted orders, RNG states, director decisions where required, authority epochs, migrations and visible event timeline. Atomic append, bounded compression/size, checkpoint integrity and crash recovery. Seek nearest legal snapshot then advance to target, reverse via seek; never rewind simulation in live match. Validate manifest before playback, explicit version incompatibility, preserve compatible replay runtime or export permitted highlights when practical. Camera, speed and UI do not affect authoritative results. Post-match fog revelation depends on rules and consent; exported perspective filters must not contain secret full-state data. Local storage quotas configurable, user chooses delete/export. No compulsory cloud storage or hidden upload.

## Online spectator
Host/session policy: disabled, invited, eligible public, permitted team view or delayed neutral view. Separate observer role with no command rights; enforce visibility on server/authority, not just client UI. Competitive delay and anti-leak policy fixed before match, delayed snapshots/events and bounded buffer; never send current hidden state to spectators. Optional full-information observation after match if policy allows. Show strategic map, army comparisons and statistics only where permitted, perspective selection, highlights and cinematic observation; no individual-soldier follow in the new modes. Spectator load budget and slot caps, relay and bandwidth measured. Reconnect to delayed cursor, revoke access, host migration preserves policy. Player-hosted trust limitations disclosed; no perfect anti-cheat promise. Dedicated authority preferred for verified competitive records where feasible.

## Meaningful accomplishments
| Recognition | Example |
|---|---|
| Achievement | Complete meaningful scenario milestone |
| Medal | Objective success, recovery or efficiency in an operation |
| Trophy | Major campaign/challenge accomplishment |
| Record | Survival duration, victory, discovery or challenge performance |
| Formation honor | Persistent institutional accomplishment |
| Challenge rank | Crucible score by seed, rule version and eligible conditions |
| Multiplayer record | Eligible victories and match history |
| Civilization legacy | Generational achievements recorded privately offline |
| Cosmetic reward | Insignia, banners, profile customization |
Rules versioned, deterministic predicates over validated events; stable award ID, qualifying event IDs, mode/rules hash, tick and scope. Deduped awards, no client-authored wins, no casualty farming, paid stat advantage, login grind, loot-box obligation or forced progression. Clear requirement and earned date; no spoilers. Offline awards stored locally; optional online profile records only eligible online matches/challenges, opt-in publication. Inheritance/Living World no online stats/leaderboards. Separate unverified host/mod records from verified ranked results; ranked trust policy, anti-abuse and appeal needed before publishing. Compare like rules/seed/assist/manifest, transparent tie-break. Cosmetic assets must be legal/owned and not obscure team cues. Community replay sharing uses Workshop safeguards. G12 recording foundation, G15/G17 archive integration, G18 playback/spectator/records and platform library. Test replay hashes, seek, interrupted recording, migration, fog/spoilers, privacy, mod mismatch, spectator delay/revoke, duplicate awards and ranked eligibility. [Archive](WORLD_ARCHIVE.md) · [Creator toolkit](CREATOR_TOOLKIT_AND_WORKSHOP.md).
