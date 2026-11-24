# Pre-G10 ORCH checkpoint

Date: 2026-11-23
Branch: `g71`

## Shipped at this checkpoint

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

## Verification

- `test_count9`: 14 pass / 0 fail
- `test_pace71`: 1 pass / 0 fail
- `test_warmind71`: 3 pass / 0 fail, no script errors on rerun
- `test_hive9`: 6 pass / 0 fail
- `test_hot_state`: historical gold/hash tests fail as expected after the intentional global pace/hash change; parity subtests observed passing. Gold refresh and complete integration verification remain for D4.

## Commits

- `cab9bf21` — Task 2 review fix + approved addendum freeze
- Addendum scaffold commit: see subsequent commit in branch log.

## Package

No package at this checkpoint. Package remains gated on a playable D1 vertical/integration pass.

## Remaining

Tasks 3-4, 6-17 from the plan: COMBAT9+, SKIRM9+, full AI9 integration, ECON9, smoke/coalition soak, hash/gold update, peak remasure, docs lock, package, and push.
