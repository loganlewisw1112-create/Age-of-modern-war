# G18 ONLINE MULTIPLAYER

Owner-approved G18 design direction; implementation pending. Engineering contracts, candidate algorithms and schemas below are documentation-only proposals, not runtime code. Existing source, assets, saves and gate completion statuses are untouched.

## Scope and topology
Offline solo first-class, internet 2–4 player Last Protocol and initial new mode target; Skirmish co-op/PvP legal combinations. No online Inheritance, Living World or DLC Dynasty. Reuse one simulation/transport interface, not separate mode network stacks. Default player-hosted authoritative simulation (host is also a client); direct encrypted authenticated connection when viable, relay fallback for NAT/CGNAT/firewalls; optional headless dedicated authority for community or later operational need. LAN optional, no mandatory cloud for gameplay. Regional relay selection by measured RTT and availability, not forced region locks. No always-on match servers by default. Initial architecture choice is a proposal; compare existing Rust/Godot interfaces, transport maturity and license before locking.

## Session lifecycle
Offline -> Online menu -> account sign-in -> public search/private invite -> lobby -> manifest/capability/ownership agreement -> ready -> allocate host/route -> initial snapshot -> synchronized running -> reconnect/migrate/checkpoint -> end/AAR. Invite token scoped, expiring, not an account credential. Join policy explicit (private, friends, public); late join Last Protocol spectates until checkpoint as original contract. Others join at safe scenario checkpoint when allowed. One authoritative state per session, stable command/entity IDs, monotonic tick, dedupe, bounded queues, per-recipient fog filtering. Host validates orders; clients do not author resources/casualties. Dedicated authority for higher-trust competitive sessions; player-hosted competitive host advantage disclosed, no promise of cheat-proof play. No trust in client claims or peer-supplied ownership.

| Layer | Proposed responsibility |
|---|---|
| Control plane | Identity, lobby, matchmaking, relay tickets, membership, protocol compatibility |
| Data plane | Authenticated encrypted peer/relay transport; simulation commands, snapshots, deltas, heartbeats |
| Simulation | Host Rust authority; validate scope, ownership, legal targets, resource reservations, tick; deterministic AI/director seeds |
| Presentation | Godot input/UI, interpolation of visible state, responsive command acknowledgement, no hidden information |
| Save | Session-scoped versioned checkpoints, command/event cursor, content manifest and roster; no Dynasty merge |

## Synchronization design
Prefer host-authoritative commands + snapshots/deltas; prototype deterministic lockstep vs authoritative state replication with actual current native/fallback determinism and fog/security. Do not require perfect cross-platform lockstep without evidence. Commands scheduled against host tick with adaptive input buffer, stable tie-break by tick/slot/sequence, idempotency; reliable ordered critical data, sequenced replaceable visual deltas. Prediction limited to presentation; reconcile authoritative outcomes. Avoid client rewind of irreversible resource/casualty state. Late packets reject or reschedule under explicit policy. Snapshot chunking, compression and throttling with byte/CPU bounds; interest management for visible/supported regions; no secret full-state broadcasts. State hashes for appropriate scope, periodic authoritative checkpoints and divergence diagnostics; full resync if delta gap. Network I/O decoupled from sim tick. Pause/slow rules explicit per lobby, no client unilateral pause in competitive.

```text
# illustrative only
on_command(peer, envelope):
    require authenticated_member(peer, envelope.session)
    reject_if_stale_epoch_or_duplicate(envelope)
    require rate_limit_and_schema_valid(envelope)
    validate_control_scope_and_legal_target(peer, envelope.intent)
    schedule_at_authority_tick(envelope)
on_tick:
    validate_and_commit_intents_in_stable_order()
    publish_visible_deltas_and_acks()
    checkpoint_if_due()
```
Envelope {session_id, authority_epoch, slot_id, seq, requested_tick, command_id, schema_version, intent}; Snapshot {session_id, epoch, tick, manifest_hash, authoritative_state_ref, ledger_cursor, rng_state, roles, checksum}; Lobby {id, mode, scenario, privacy, roster, teams, rule_hash, build_protocol, content_manifest, host_candidates, status}; Route {direct|relay|dedicated, ticket, expiry, region}. Proposed schemas not current code.

## Disconnection and migration
Heartbeat, transport failover and grace period; retain slot/identity and last acknowledged sequence. Rejoin with fresh short-lived ticket, snapshot and bounded delta replay; dedupe queued commands. AI temporarily manages disconnected player's allowed scope; player reclaims at tick boundary, pending claims reconciled. Last Protocol defense AI fills gaps, no enemy conversion. Host migration: elect eligible reachable host from authenticated roster with deterministic ranking, freeze/pause, signed epoch transition, validated checkpoint and replay; reject old epoch to avoid split brain. Protect fog by limiting authoritative checkpoint access to designated migration authority; encryption/ticketing cannot make malicious hosts trusted. In competitive sessions where safe migration cannot preserve secrecy/integrity, dedicated host or end as unranked/resume from agreed checkpoint; never silently diverge or duplicate resources. If no safe checkpoint, report rollback/failure and offer saved restart. Test host loss during save, attack, relay failure and duplicate reconnect. No cloud save mandatory. Persistent matches local host save, optional encrypted transfer to eligible host, explicit consent; shared save belongs to that session, independent of campaign, schema/entitlements validated. Iron Co-op rules preserve intended no-reload challenge, recovery distinguished from voluntary replay.

## Modes and UX
Last Protocol preserve Human A vs Machine, shared core/countdown/creep/Tide, claims Outer/Economy/Core+CN/Field Strike, free unclaimed units, optional full shared pool, no friendly fire default, AI defense fills gaps; shared resource reservations, explicit walking-core coordination, shared fog/pings/alerts, common AAR and per-player medals; Quick/Full 60–90 min/Iron co-op; fair pressure scaling, existing FPS floor; no PvP. Skirmish team/FFA/co-op vs AI, independent factions or legal shared command, maps/stages/rules and optional advanced setup. New modes use same lobby, save, role and AI replacement. Public search by mode, rules, compatible version, region and latency; private code/invite; ready, cancel, reconnect; clear reason for mismatch. No mandatory voice/text; pings, optional muted/blocked communication, moderation and accessibility. Offline launch must succeed without DNS/account/server.

## Future DLC compatibility
Versioned protocol + content manifest (stable IDs, hashes, owned entitlements, required assets), negotiate exact supported ruleset; DLC 1/2 actual civilization continuations offline; owned factions in Skirmish only, shared compatible maps/units/buildings/tech where permitted, no leakage or forced purchase to play base maps. Define guest content/licensing rules before release; reject unavailable content clearly rather than silent substitution. Expand schema compat with migrations, feature flags and version matrix, not forks. No paid advantage or unsupported shared persistent universe.
[Platform](G18_OPEN_GAMING_PLATFORM.md) · [Acceptance](G18_DELIVERY_PLAN.md).
