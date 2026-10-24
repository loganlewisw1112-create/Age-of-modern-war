# Perf report: G4 (2026-10-24)

The sim ran headless via `tools/scale_bench.gd` with the native core 0.3.1 (commit ddabbe3). Other agents were running on the same machine, so every run notes the Windows CPU load taken just before it.

## Sim per tick (ms, avg / p95). Target: p95 < 50 ms, or avg <= 62.5 ms (0.8x speed)

| scenario | G3b baseline (quiet) | after PERF10K-2 | after SIM10K-2 (final) | load at final run |
|---|---|---|---|---|
| 2k rc_s fight | 29.5 / 38.3 | 41.3 / 63.5 (51% load) | **21.3 / 36.1** | 19% |
| 10k valley march | 86.7 / 124 | 98.2 / 139.8 (68% load) | **63.2 / 85.9** | 17% |
| 10k valley fight | (not measured in G3b) | 283.1 / 352.7 (100% load) | **104.3 / 131.1** | 23% |

- **2k:** inside the 20 Hz budget (50 ms).
- **10k march:** at the 0.8x-speed bound on average (63.2 vs 62.5); p95 is over.
- **10k all-fighting: NOT met.** It is about 1.7x over on average and 2.6x over on p95, so the game runs at about half speed.

### Same results before and after
Every change was checked against HEAD by comparing state hashes, and every hash was equal:

| run | state hash |
|---|---|
| 2k fight | 73b0408056607c49 |
| 2k mixed | 491138e5ee11660f |
| 2k fight with the native core off | 66e034734a9b8f43 |
| 10k fight | 6e0d5fff42075473 |
| 10k march | e5f5ae8d44990a0e |

PERF10K-2 ran the same check on its own changes (in the scratchpad P2 tables).

## Where the 10k-fight time goes (final, profiled, 15% load)

| system | ms/tick |
|---|---|
| combat | 40.3 (was ~135–160) |
| └ native prep | 23.4 |
| └ act | 13.0 |
| └ finds (64 per tick, down from 2001) | 1.4 |
| └ fire, LOS and damage | about 4 in total |
| movement | 37.9 |
| └ gather | 23.3 |
| supply | 7.3 |
| morale | 6.2 |
| fog | 5.8 |
| economy | 2.4 |
| victory | 1.3 |

The remaining cost is reading and writing each unit's Dictionary: about 2–3 µs per unit per system pass, even from native code.

**Next step (G4 follow-up):** keep the hot entity state (pos, moving, cooldown, target, order kind) in packed per-id arrays in `world.gd`, with one write API, flushed to dicts only for hashing and saves (SIM10K-2's CR).

## What changed in G4
**PERF10K / PERF10K-2:**
- held mover state;
- a tier bucket grid;
- one-pass territory;
- supply due buckets;
- cargo-safe unit subsets.

**SIM10K-2:**
- combat act-skip (no-op unit ticks are skipped, and a hit wakes the unit);
- native `RtsCombat.prep_units`;
- a skip for searches that can only come back empty.

**THREAD:** the sim runs on a WorkerThreadPool task. The renderer reads a snapshot, so frames no longer wait for the sim tick.

## Not measured in this report
Windowed fps (2k fighting on screen, 10k zoomed out with the sim running) was not re-measured on a quiet machine for G4. Done-when 2's fps items are **unverified**.
