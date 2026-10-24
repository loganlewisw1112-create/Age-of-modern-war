# Performance report: G3b + Scale "Big Armies", 2026-10-24

- **Hardware:** AMD Ryzen 5 8640HS (12 logical cores), Radeon 760M integrated GPU, 15.3 GiB RAM, Windows 11.
- **Build:** Godot 4.7.2-stable (editor runtime, Compatibility renderer) plus the native core `bin/rts_core.dll` (Rust, godot-rust 0.5.5, rts_core 0.2.2).
- **Code:** commit `947061a` (sim final). The window numbers in §3 also include the presentation commit noted there.

## What changed for scale
- **Native core (Rust):**
  - spatial grid (combat targeting, splash, near-miss);
  - grid A* plus shared flow fields for group orders;
  - one fused native call per tick for path advance and separation;
  - fog stamping;
  - line-of-sight checks.
  - A GDScript fallback runs everything when the DLL is missing.
- **Fidelity tiers:**
  - Units with no enemy within the contact bucket are REDUCED: combat scans every 8 ticks and morale is staggered.
  - Anything hit, ordered to attack, low on fuel, or near an enemy is FULL.
  - Tests show identical fight outcomes to FULL-only (4/4 seeds; fight survivors match).
  - The movement stride for REDUCED units exists but is **off**. With it on, 16-seed tests were not outcome-exact (one winner flip). See "Owner decision" below.
- **Shared per-tick entity index and per-def subsets** replace the separate full entity scans each system used to make. The state hash is identical before and after.
- **De-stacked periodic jobs:** fog teams on tick%4==1/3, tiers on tick%8==6, territory/bridge sampling on tick%20==7. So no tick runs every periodic job at once.
- **Renderer:**
  - one atlas-batched canvas instead of a Sprite2D per entity;
  - off-screen culling;
  - zoom LOD: team-tinted icons below 0.45 zoom;
  - shader fog;
  - lazily baked terrain chunks for the large maps;
  - overlays draw only what is visible;
  - the HUD and minimap are throttled above 400 entities.

## 1. Simulation cost (headless `tools/scale_bench.gd`, quiet machine: 0 other Godot processes)

Scenario: N units of Human A / Human B / Machine. Half of each side attack-moves to the map centre and fights; half marches back and forth.

| Map | Units | Path | avg ms/tick | p95 | max | Notes |
|---|---|---|---|---|---|---|
| river_crossing_s | 1,000 | native | 13.0 | 20.9 | 56.4 | all FULL (fighting) |
| river_crossing_s | 1,000 | GDScript fallback | 28.6 | 39.3 | 81.7 | |
| river_crossing_s | **2,000** | **native** | **29.5** | **38.3** | 106.8 | **all FULL: meets the p95 < 50 ms target** |
| river_crossing_s | 2,000 | GDScript fallback | 61.9 | 88.7 | 172.0 | |
| valley_conquest_l | 2,000 | native | 17.3 | 25.4 | 136.6 | armies had not met: all REDUCED |
| valley_conquest_l | 5,000 | native | 44.3 | 63.7 | 293.8 | all REDUCED |
| valley_conquest_l | **10,000** | **native** | **86.7** | **124.1** | 546.5 | **misses the 50 ms budget**; all REDUCED |

**Before this slice (G3a, same PC):**
- about 65 µs per unit per tick;
- 1,000 units averaged about 70 ms per tick (`bench --g2` 1024: 166 ms);
- 2,000 units were roughly 140 ms+ per tick.

So 2,000 fighting units are now about 4–5x cheaper.

**Where the 10k tick goes** (N1-core-4 breakdown, quiet):
- movement 52.8 ms, mostly GDScript per-unit gather at about 3.7 µs per unit;
- victory / territory spikes;
- combat and fog: smaller.

The next levers are native-held positions (only changed units are touched), and turning on the REDUCED movement stride if the owner accepts it (it cut 10k movement from 58 to 24 ms).

## 2. AI think cost (`sim/ai/tools/ai_bench.gd`, valley_conquest_l, native)
0.36–0.97 ms per tick per side at 2,000–5,000 own units, under the 2 ms target. Huge sides stagger their thinking.

## 3. Rendered frame rate (windowed 1600x900, vsync, native on)

| Scenario | fps avg (min) | Sim ticks/s | Status |
|---|---|---|---|
| 2,000 units, sim paused, normal zoom | 71 (65) | — | render alone is fine |
| 10,000 units, valley_conquest_l, zoom 0.3, sim paused | 171 (154) | — | render alone is fine |
| 2,000 units fighting, normal zoom, sim on the main thread | **22 (13)** | 20 | **misses 60**: the sim blocks frames |
| 10,000 units, valley, zoom 0.3, sim running | **7.5** | 7.5 | **misses 30**: the sim can't keep real time |

The window numbers above were taken on commit `947061a`, before any sim-thread work. The remaining gap is architectural: `world.step()` runs on the main thread, so a 20–35 ms tick lands directly on frame time. Section 4 records the sim-thread result (R5-thread).

## 4. Sim off the main thread
_Pending: filled in from the R5-thread result._

## Owner decision needed
- **REDUCED movement stride:** on saves about 34 ms per tick at 10,000 units, but it is not outcome-exact. On 16 test fights, 13/16 (GDScript) and 9/16 (native) match FULL-only, with one winner flip. CONTRACTS_G3b §0 forbids changing outcomes, so it is off. Turning it on is a design call: "distant marching units move in 4-tick strides".

## Not measured / caveats
- Every number before the final quiet runs was taken on a machine loaded with up to 22 parallel agent processes. Those numbers are in the agents' handoffs and are only comparable as ratios.
- 10,000 units **fighting** (all FULL) was not run; the 10k rows are marching armies (REDUCED).
- Memory per N; long-session growth; an exported release build; other hardware.
