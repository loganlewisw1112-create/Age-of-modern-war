# SIM10K: 10,000 fighting units within budget (successor to PERF10K / PERF10K-2)
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §4. Read `.plan/board.jsonl` entry seq 2153 (PERF10K-2 done) and the report summary below.

**Why you exist.** Done-when 2 (frozen) needs **10k sim p95 < 50 ms, OR >= 0.8x game speed (avg <= 62.5 ms/tick) with smooth frames**. After PERF10K-2 (commit d506969), the numbers on a loaded machine (about 1.5x slower than quiet) are:

| scenario | avg / p95 ms |
|---|---|
| 10k valley march | 98 / 140 |
| 10k valley fight | 283 / 353 |

The 10k-fight system breakdown (avg ms) is:
- combat **159.5**
- movement 73.3, of which mv.gather is 45.0, apply 11.9, drain 8.4 and native_step 7.2
- supply 15.0
- morale 11.5
- fog 11.5
- economy 5.0
- victory 3.1

In the fight, 9,242 of 10,000 units are FULL tier, so tiers do not help. Combat is the target.

**Owns** (PERF10K-2 is finished; the orchestrator hands these to you):
- sim: `sim/systems/combat.gd`, `damage.gd`, `movement.gd`, `morale.gd`, `supply.gd`, `fog.gd`, `tiers.gd`, `territory.gd`, `sim_index.gd`, `unit_subsets.gd`
- native: `sim/native_core.gd`, `native/**`, `bin/**`, `tools/build_native.sh`
- bench and tests: `tools/scale_bench.gd`, `tests/test_perf.gd`, `tests/test_perf_systems.gd`, `tests/test_native.gd`, plus new tests you create
**Do not touch:**
- `sim/ai/**`, `tools/soak.gd`, `tests/test_ai.gd` (AI5-2 is live);
- `presentation/**`, `sim/render_snap.gd`, `tools/ui_playtest.gd` (UI4B-3 is live);
- `sim/world.gd`, `content/**` (ORCH). Send a CHANGE_REQUEST for these.

**Hard rules:**
1. **Hash-equal by default.** Every change must give the same state_hash as HEAD (A/B on 2k rc_s fight, 2k mixed, 10k valley fight, 10k valley march, 300+ ticks) AND native-on == native-off (fallback) AND threaded == unthreaded. PERF10K-2's A/B scripts are in `C:\Users\logan\AppData\Local\Temp\claude\D--CODING-PROJECTS---CURRENTLY-WORKING-ON-RTS-Age-of-Modern-Warfare\db91159d-f488-44a1-9b4e-0e72e30b8f1b\scratchpad\P2\` (`ab.sh`, `sync_b.sh`); copy them to your own scratch dir `...\scratchpad\SIM10K\`.
2. **Changes to results** (e.g. a target re-acquire cadence, batched splash) are allowed ONLY behind a `rules.json`-style flag that defaults OFF. They must be deterministic and save-exact, with the measured gain reported. Do not turn one on: the owner decides. (Owner decision D7: the REDUCED movement stride stays OFF. Don't touch it.)
3. **DLL:** other agents run godot, which locks `bin/rts_core.dll`. Always build with `bash tools/build_native.sh --stage`, test the staged DLL, then `--swap`. Never overwrite in place. Bump the rts_core version (0.3.x) when native APIs change, and keep `NativeCore` working when the DLL is missing (the fallback path is the hash oracle).
4. Never weaken a test or threshold.

**Tasks (in this order):**
1. **Profile combat** at 10k fight. Add sub-timers inside combat.gd (gated like the existing bench timers, zero cost when off): target search, cooldown/ready scan, fire resolution, LOS, damage apply, splash, death handling. Report the split.
2. **Cut combat.** Move the hottest loop(s) into native `RtsCombat` as one batch call per tick. Packed arrays in and out; no per-unit GDScript→native calls. Likely candidates: the ready/cooldown scan plus range check plus fire resolution with the deterministic RNG, or damage apply. Keep the exact RNG draw order. Also cut GDScript overhead where native isn't needed (per-unit Dictionary reads in hot loops → packed mirrors kept in sync, like PERF10K-2's held mover state).
3. **Movement gather** (45 ms): extend the held state so positions/status don't need a per-unit dict read each tick (dirty flags or native-held positions with one write API for every writer). Only if hash-equal.
4. Then, as budget allows: supply 15 / morale 11.5 / fog 11.5 (cadence buckets that are hash-equal, or a native batch).
5. **Report** a before/after table (avg / p95 / per-system) for 2k rc_s fight, 10k valley march and 10k valley fight. Note the CPU load at each run (other agents share the machine). Give the honest gap against "p95 < 50 ms or avg <= 62.5 ms".
6. **Tests:**
   - a native-vs-fallback parity test for each new native batch;
   - an A/B hash equality test (or a script with logged evidence);
   - the full suite once at the end inside `.plan/hb.sh`.

Done when: tasks 1, 2, 5, 6 are done (3-4 as far as budget allows), every hash is equal, and the full suite is green.
**MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `SIM10K`.** Post `status` every 5 calls (calls_used, tokens_used_est, next_action). At 70% of the projection, write `.plan/handoff/SIM10K-1.json` and stop. Do not commit. No GENESIS/postflight offer in your report.
