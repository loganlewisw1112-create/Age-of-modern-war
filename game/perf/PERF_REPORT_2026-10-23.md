# Performance report: G0+G1 slice (PERF-01, first measurement)

Measured 2026-10-23 on the owner's PC with no other Godot processes running. These are measurements, not targets.

- **Hardware:** AMD Ryzen 5 8640HS (12 logical cores), Radeon 760M integrated GPU, 15.3 GiB RAM, Windows 11 (10.0.26200)
- **Build:** Godot 4.7.2-stable official, project run from source (`--path`), Compatibility renderer. This is not an exported release build.
- **Code:** git `2ac8c1d` plus the working-tree changes committed with this report.

## Simulation cost (headless, `tools/bench.gd`)

Scenario: N units in a 10% MBT / 15% IFV / 15% AT / 60% rifle mix, two sides attack-moving into each other on open ground, 600 ticks (30 s of game time). The tick budget at 20 Hz is 50 ms. Full table: `BENCH_2026-10-23.md`.

| Units | avg ms/tick | p95 ms | max ms | Verdict |
|---|---|---|---|---|
| 64 | 3.2 | 5.5 | 193 | well within budget (G0 64-actor baseline) |
| 128 | 5.2 | 8.9 | 200 | within budget |
| 256 | 11.9 | 27.1 | 274 | within budget (p95 headroom 1.8x) |
| 512 | 75.3 | 302 | 2372 | **over budget**: the sim cannot hold 20 Hz |

**Measured supported cap: about 256 simultaneously fighting units.** 512 fails. The 500–2,000 target in the design remains an unmet stretch goal (DEC-13).

The max column has a one-off spike of about 200 ms at every N. It is probably the first-tick path/nav warm-up. It has not been isolated.

## Rendered frame rate (windowed 1600x900, vsync on, `--spawn-test=N --fps-log`)

| Units on map | fps | sim ms per real second | view ms per real second |
|---|---|---|---|
| ~64 | 53–60 (vsync cap 60) | ~50 | ~100 |
| ~128 | 53–60 | ~100 | ~180 |
| ~250 | 45–52 | ~240 | ~290 |

The renderer alone, with the sim paused, ran 175–180 fps at ~212 units (D-view's measurement, 2026-10-22). Above ~128 units the limiter is sim CPU time, not drawing.

## Not measured / caveats
- Memory use per N.
- An exported release build, which is expected to be faster than running from source. No export preset exists yet.
- Other hardware.
- Long-session soak memory growth.
- An AI-vs-AI full match runs at about 2.5 ms/tick headless.
