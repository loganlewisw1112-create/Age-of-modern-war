# N1-core: Rust native core + movement (CONTRACTS_G3b §5)
Read G3B_COMMON.md first.

Measured baseline (this PC, GDScript, `--spawn-test` fight): 65 µs per unit per tick, linear; movement + combat are about 75% of it. At 1,000 units a tick takes about 70 ms (budget 50); `bench.gd --g2 --sizes=1024` averages 166 ms. Targets: 2,000 FULL units at p95 < 50 ms total tick, and 10,000 on the large map later (with PERF4's fidelity tiers).

Toolchain on this PC: rustc/cargo 1.96 (msvc target) at `~/.cargo/bin`, plus VS 2022 Build Tools (C++). Use **godot-rust gdext** (crate `godot` from crates.io), with an API feature compatible with Godot 4.7.2 (GDExtension is forward compatible, so building against the newest api feature the crate offers is fine). `cargo` fetching crates from crates.io is approved.

Order:
1. Scaffold `native/rts_core` + `bin/rts_core.gdextension` + `tools/build_native.sh`. Prove the DLL loads headless: a test prints `NATIVE rts_core loaded`. Commit nothing; the orchestrator commits. **Then prove it loads in a packaged build**:
   - `"$G" --headless --path . --export-pack "Windows Desktop" <tmpdir>/RTS_Age_of_Modern_War.pck`;
   - copy `Godot_v4.7.2-stable_win64_console.exe` there as `RTS_Age_of_Modern_War_console.exe` (plus the non-console exe as `RTS_Age_of_Modern_War.exe`), and the DLL as the .gdextension expects;
   - run with `--headless -- --autostart --quit-after...` or similar, and look for the load line.
   - Find out what path layout works (export-pack may not copy the DLL; you may need `bin/` next to the exe, or an `export_presets.cfg` change). Put the exact packaging recipe in your report. If it can't load at all, post a blocker immediately.
2. `sim/native_core.gd` facade with GDScript fallbacks; `w.native_enabled`.
3. Port the movement hot paths: spatial hash separation (`_separate`), the step/collision checks, and pathfinding. Use flow fields for groups sharing a goal (formation/attack-move orders give many units the same destination), and native A* for single paths, replacing the AStarGrid2D budget queue. Keep movement.gd's public API (`order_move`, `order_path`, `can_reach`, `nearest_free_cell`, `is_passable`, `on_footprint_changed`, `on_terrain_changed`, `formation_slots`, `rebuild_nav`) unchanged, because other systems call them.
4. Expose `RtsGrid.nearest_enemy_batch` and `query_radius` for combat. PERF4 wires combat to them in wave 2, but write a micro-test now.
5. `tools/scale_bench.gd`: run it at 500/1000/2000 units on river_crossing_s, native on and off. Report the table.
6. `tests/test_native.gd`: loads; fallback parity of behaviour (units reach goals, no overlaps, blocked cells respected); same seed gives the same hash with native on; save/load round trip mid-move.

Keep every existing movement test green (test_core / test_mil / test_g2_scenarios / test_factions). MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `N1-core`.
