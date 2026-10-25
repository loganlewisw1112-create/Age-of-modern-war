# G5-CORE10K: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §2, §3.6, §5, §6. **Plan:** Plan section 2 (Workstream A).
**Board / bus id:** `CORE10K`. **Budget: MAX_TOKENS 900000, MAX_TOOL_CALLS 220** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_hot_state.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### CORE10K: engine hot state, 10k speed, wall-breach hook
- **Role:** make 10,000 fighting units run at ≥0.8x speed with identical results, and fix the engine-side G4 gaps.
- **Owns:**
  - `sim/hot_state.gd` (new); the hot-state block of `sim/world.gd` (the region marked by ORCH);
  - `sim/systems/{movement,combat,damage,supply,morale,fog,tiers,territory,sim_index,unit_subsets}.gd`;
  - `sim/native_core.gd`, `native/**`, `bin/**`, `tools/build_native.sh`, `tools/scale_bench.gd`;
  - `tests/test_perf*.gd`, `tests/test_hot_state.gd`.
- **Inputs:** SIM10K-2's report and CR (packed per-id arrays), `perf/PERF_REPORT_G4_2026-10-24.md`, `.plan/handoff/SIM10K-2-*`.
- **Tasks (in order):**
  1. Post the hot-state API (`HotState.set_pos/set_target/set_moving/set_cd/set_order/set_hp`, plus array getters) as `fact core.hot_api_ready` within the first hour, stubbed and compiling.
  2. Move movement gather, combat prep, supply, morale and fog onto the arrays, with the dictionaries flushed for hash, save and snapshot.
  3. Native core reads the arrays directly (rts_core 0.4.x).
  4. Wire `Fortify.on_attack_move_blocked` where an attack-move path fails, so player units breach.
  5. Add the `Damage.on_zero_hp(w, e)` hook for SUPPORT's Wounded state: return true = "don't destroy".
  6. Add the air/naval damage-class flags AIRSYS/NAVAL request through CRs.
- **Publishes:** `core.hot_api_ready`, `core.zero_hp_hook_ready`, `core.breach_wired`.
- **Done-when:**
  - A/B state hash equal to HEAD on 2k fight, 2k mixed, 10k fight and 10k march, with native on and off and with the sim thread on and off;
  - 10k fight avg ≤ 62.5 ms/tick in its own run (CPU load noted);
  - test_hot_state + test_perf green;
  - full suite green.
- **Budget:** 900k / 220.
- **Never:** change a gameplay result without a flag that defaults off.
