# Performance report: G2 "Smart Warfare" slice

Measured 2026-10-23 on a quiet machine: no other Godot processes were running (checked with `tasklist`).
- **Hardware:** AMD Ryzen 5 8640HS (12 logical cores), Radeon 760M integrated GPU, 15.3 GiB RAM, Windows 11.
- **Build:** Godot 4.7.2-stable official, run from source, Compatibility renderer.
- **Code:** git `aaed0f5` plus the UI-playtest changes. All G2 systems were real during the runs.

## Simulation cost (headless `tools/bench.gd`, 600 ticks, 50 ms/tick budget at 20 Hz)

| Units | G1 report (G1 code) | G1 battle scenario, G2 code | G2 battle scenario (`--g2`: officers + missions, forest cover, logistics trucks) |
|---|---|---|---|
| 64 | 3.2 avg | 1.3 avg / 2.7 p95 | 1.5 avg / 2.9 p95 |
| 128 | 5.2 | 3.2 / 5.5 | 4.6 / 7.3 |
| 256 | 11.9 | 9.4 / 15.7 | 12.0 / 18.8 |
| 512 | 75.3 (over budget) | 20.0 / 32.3 | 29.1 / 42.4 |

**Measured supported cap (sim): 512 fighting units, with every G2 system active, held within the 20 Hz budget at the p95 tick (42 ms of 50 ms).** That beats G1's ~256 cap. The A* budget, separation hashing, staggered target scans and morale skipping more than paid for the new systems. Max-tick spikes are 18–86 ms (first-tick path warm-up). 1,000+ units has not been measured, so the design's 500–2,000 range is only half-demonstrated.

## Rendered frame rate (windowed 1600x900, vsync, `--spawn-test=N --fps-log`)

| Units on map | fps | Sim ticks/s | Note |
|---|---|---|---|
| ~105 | 53–60 | 20 | |
| ~210 | 45–53 | 20 | Same as G1 despite the G2 overlays |
| ~440 | 21–24 | 20 | The sim keeps real time, but rendering gets choppy because the sim takes ~420 ms of each second on the main thread |

## Not measured / caveats
- 1,000+ units.
- Memory per N.
- An exported release build (only the editor runtime with a packed .pck).
- Other hardware.
- Long-session memory growth.

**Next lever:** moving the sim to a worker thread would decouple fps from sim cost at 400+ units.
