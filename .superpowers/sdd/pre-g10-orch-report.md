# Pre-G10 ORCH final report

Date: 2026-11-23
Branch: `g71`

## Shipped

- Approved addendum folded into scope, implementation plan, roster, and board.
- COUNT9+ Task 2 review blockers corrected:
  - all thirteen counters have production command-dispatch routes;
  - power starvation causes a saved timed generation penalty consumed by Economy;
  - decapitation accepts command-class targets only;
  - coalition expiry preserves newer diplomacy/team changes.
- PACE71 scaffold wired into both native and fallback movement paths:
  - ~1.7x open-ground vehicle locomotion;
  - roads/cleared net about +20%;
  - creep/mud/rubble about -30%;
  - acceleration, turning, and deployment systems remain separate.
- Hive network scaffold: distance/terrain/EW quality, mesh/spine telemetry, linked last-seen sharing, severed peer fog, creep weak-signal floor, fire/dead-zone cable cuts.
- Warmind scaffold: evidence-held doctrine, threat budget, node-killer counter-memory, and readable `WarmindIntent`/board priority.
- COMBAT9+: persistent forts, EW in skirmish/LP, crew bail/recrew, deterministic wear/breakdown/recovery and multi-class ballistics.
- SKIRM9+: setup `director_adapt` toggle and capped siege attack-move.
- AI9: evidence adaptation, five named generals, temporary anti-Machine diplomacy, no-cheat Hard and phased operations.
- ECON9: gathered rare metals, location-mix trade posts, territory/civilian support, tiered research and black-market purchases.

## Verification

- `test_count9`: 14 pass / 0 fail
- `test_pace71`: 1 pass / 0 fail
- `test_warmind71`: 3 pass / 0 fail, no script errors on rerun
- `test_hive9`: 6 pass / 0 fail
- `test_combat9`: 10 pass / 0 fail
- `test_skirm9`: 5 pass / 0 fail
- `test_ai9`: 5 pass / 0 fail
- `test_econ9`: 5 pass / 0 fail
- `test_hot_state`: 17 pass / 0 fail after PACE71 GOLD/GOLD_FLAT refresh; two independent capture runs matched 16/16.
- Expanded smoke: 33 suites, 0 assertion failures / 0 script errors. The long wrapper was interrupted at `test_airfix71`; isolated Airfix passed 6/0 and the 13-suite remainder passed 0 fail.
- Coalition soak: formed and broke the two-human truce with `threat_high=14.5`.
- Peak remasure: p10 116.8, avg 127.3, min 110.8 at peak 1000.

## Commits

- `cab9bf21` — Task 2 review fix + approved addendum freeze
- `beb24a2e` — Hive network, Warmind, and PACE71 scaffold
- `62bcc256` — checkpoint board FACT
- `7905bdac` — reopened false Pre-G10 lock
- `a439359` — Tasks 3-16 depth, AI9, ECON9 and integration harnesses
- Final lock/package commit: see board `pre_g10.lock` FACT and `git log`.

## Package

Packaged with note `pre_g10.lock`; exact SHA-stamped folder and zip are recorded after package completion.

## Lock

`pre_g10.lock` is CLOSED. Done-when #1-#8 are evidenced; G10 remains Shadow Coalition-only.
