# Task 1 Report — HIVE9+ blended catalog and soak visibility

## Status

Complete. HIVE9+ now exposes `Hive9.catalog_count()`, generates a 60-key blended Machine vehicle catalog, reports modular merge/split counters on `Hive9.board(w)`, keeps the LP-only activation gate, and ships G71 look-checkpoint samples.

## Implementation

- `game/tools/art/g71_hive9.gd`
  - Covers every current Machine unit definition with a best matching Machine source silhouette fallback.
  - Generates 13 deterministic modular blend variants after the 47 content-backed Machine definitions, for exactly 60 blended vehicle keys.
  - Writes 1x/2x catalog strips to `game/.plan/shots/G71_LOOK/`.
- `game/sim/systems/hive9.gd`
  - Added `catalog_count() -> int`.
  - Versioned state to v2 and added persistent `modular_events = {merge, split}`.
  - Wreck intake increments merge events and nanites; successful minimal replication increments split events.
  - `board(w)` now includes `eaten`, `replicas`, `adapt`, and `modular_events`.
  - Kept `active(w)` LP-only. SKIRM9 has a separate Machine director state and does not consume Hive9 state, so widening this gate would unnecessarily alter skirmish hashes.
- `game/content/g71/rules_g71_hive9.json`
  - PROVISIONAL tuning: nanite intake/cap, 90-tick replication cadence, cost 5, dread floor 0.4, replica cap 10, adaptation cap 0.3.
- Existing `art_catalog.gd` `g71_hive9` override was inspected and already correctly overrides prior vehicle/infantry/icon entries; no edit was required.

## TDD evidence

RED 1:

`--only=test_hive9` failed to parse because `Hive9.catalog_count()` did not exist.

RED 2:

After adding the interface, `test_catalog_ge_60` failed at the existing catalog count of 47 (`pass=3 fail=1`).

GREEN 1:

After generator expansion and regeneration, `test_catalog_ge_60` passed with 60 manifest vehicle keys (`pass=4 fail=0`).

RED 3:

`test_modular_events_visible_on_eat_and_replicate` failed both merge and split assertions because the counters were absent (`pass=4 fail=1`).

GREEN/final:

`godot --headless --path game -s res://tests/run_tests.gd -- --only=test_hive9`

Result: `pass=5 fail=0 files=1`.

IDE diagnostics: no linter errors in the changed GDScript files.

## Generator and look evidence

- Generator: `G71_HIVE9 defs=60 files=121`.
- Samples:
  - `game/.plan/shots/G71_LOOK/strip_g71_hive9_catalog.png`
  - `game/.plan/shots/G71_LOOK/strip_g71_hive9_catalog_2x.png`

## Soak evidence

Command: `g71_soak_short.gd -- --secs=180`

Log: `game/.plan/upgrade_board/evidence/hive9_depth.log`

At 150 seconds: `eaten=1`, `nanite=0.4`, `evolve=1`, `modular_events.merge=1`. Final: `eaten=1`, `nanite=0.5`, `adapt=0.29`, `evolve=1`, `harvest_mass=3.0`; soak exited successfully.

## Concerns

- The 60-key art catalog consists of all 47 current content-backed Machine definitions plus 13 deterministic modular visual variants. The variants are catalog/look assets, not separate spawnable content definitions.
- Balance numbers remain explicitly PROVISIONAL pending owner tuning.

## Commits

- Implementation: `959e98e1` (`feat: deepen HIVE9 catalog and replication`)
- Board handoff: recorded in the task response after the final board commit.
