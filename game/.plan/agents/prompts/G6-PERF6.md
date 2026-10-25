# G6-PERF6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §5.1, §7, D22. **Plan:** PLAN_G6 §2 A2, §0b.
**Board / bus id:** `PERF6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_perf_g6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### PERF6: 10k speed, G6 hooks wiring, elevation in the hot path
- **Role:** wire every G6Hooks call site (GDScript + native), carry the G5 10k-speed miss to <= 62.5 ms/tick on an elevated map, and keep elevation within a 5 ms budget.
- **Owns:** see CONTRACTS_G6 §1 row PERF6 (hot state, movement/combat/damage/supply/morale/fog/tiers/territory/sim_index/unit_subsets, native core, `native/**`, `bin/**`, benches, perf tests).
- **Inputs:** `sim/systems/g6_hooks.gd` (call it; don't edit it), `.plan/handoff/CORE10K-3.json` (where G5 stopped: morale/fog native ports, gather_trust on), `perf/` reports, ELEV's API once posted.
- **Tasks (in order):**
  1. Within the first hours, wire every §5.1 hook:
  2.   - combat: hit and splash `damage_mult` (next to `_g4_mult`), hit roll `accuracy_mult`, acquisition + fire range `range_mult`, LOS `los_ok`;
  3.   - fog: reveal radius `sight_bonus`, `Fog.entity_visible` → `visible_to`;
  4.   - movement: step `speed_mult`, nav build `passable` for building footprints + `Elevation.edge_ok` for cliff edges;
  5.   - morale tick `morale_delta`; Damage before removal `on_destroyed`.
  6.   Do this for both the GDScript and native paths. A/B-prove the hashes are unchanged with the neutral hooks, then post `fact core.g6_hooks_wired`. Keep the overhead low: per-tick caches, and skip a hook when its owner reports it is inactive.
  7. Resume CORE10K-3's next steps (hash-proven native ports of morale and fog, gather_trust kept). Measure 10k all-fighting ms/tick on an elevated map after `elev.maps_ready`, and push it to <= 62.5. Report the CPU load with every number.
  8. Move the elevation LOS, range and edge checks into native where they sit in hot loops (rts_core). Native == GDScript hash on an elevated map.
  9. Windowed fps harness (2k on screen, 10k zoomed out) in `tools/bench.gd` / `scale_bench.gd`. ORCH takes the final numbers on a quiet PC.
  10. Keep test_perf, test_perf_systems, test_native, test_hot_state, test_damage and test_thread green; make test_perf_g6 green.
- **Publishes:** `core.g6_hooks_wired`; bench numbers on the board (`fact perf.g6_bench`).
- **Done-when:**
  - test_perf_g6 + the owned perf tests green
  - A/B hash equality (threaded/unthreaded, native/fallback) on an elevated map
  - a 10k number reported (target <= 62.5 ms/tick)
  - full suite green
- **Never:** change game rules (owners decide rules through their delegates), or rebuild the DLL any way other than `build_native.sh --stage` then `--swap`.
