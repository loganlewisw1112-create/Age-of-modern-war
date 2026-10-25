# G5-AI6: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §4, §5, §9, §10. **Plan:** Plan section 8 (Workstream G) and section 2 A2.1.
**Board / bus id:** `AI6`. **Budget: MAX_TOKENS 900000, MAX_TOOL_CALLS 220** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_ai_g5.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### AI6: Valley fix, ground units, support use, soaks
- **Owns:** `sim/ai/**` except `ai_air.gd` and `ai_naval.gd`; `tools/soak.gd`, `tests/test_ai.gd`, `sim/ai/tools/ai_bench.gd`.
- **Inputs:** AI5-4's work-in-progress patch in `build/_ai5-4_wip/`, `.plan/handoff/AI5-3.json` and `AI5-4.json`; `units5.api_ready`, `support.api_ready`, `medical.api_ready`.
- **Tasks:**
  1. **Day one, Valley fix:** the bank uses the launch army plus a late-game bank drop, with no retarget penalty. Start the Valley s1/s2 soaks immediately (the long-running checks overlap everything else).
  2. Drone Team usage by type, tactical breaching, new ground units in production plans.
  3. Medics/ambulances on Auto with hospitals; a logistics truck on Auto behind every army.
  4. Call into AI6-AN's `AiAir.manage(ctx)` / `AiNaval.manage(ctx)` hooks (stubs from the ORCH scaffold).
  5. Soak lane (max 3 at once): 4 maps × 2 seeds + 1 editor map, with usage log lines.
  6. ai_bench < 2 ms per side at 5k units.
- **Done-when:** every soak ends with a winner with 0 invariant failures and the usage logs present; test_ai green; full suite green.
- **Budget:** 900k / 220, with successors if needed.
- **Never:** change soak criteria or max_ticks.
