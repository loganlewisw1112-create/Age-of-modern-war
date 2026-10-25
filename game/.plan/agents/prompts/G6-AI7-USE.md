# G6-AI7-USE: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §16, §12.3 soak gates (PLAN_G6). **Plan:** PLAN_G6 §9, §12.3, D22.
**Board / bus id:** `AI7-USE`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_ai_g6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### AI7-USE: AI uses everything + soak lanes (starts day 1)
- **Role:** first fix the G5 soak miss (winners on every config, Valley Conquest included), then make every AI build and use every G6 unit and system, and make the soak logs carry the G6 evidence.
- **Owns:** see CONTRACTS_G6 §1 row AI7-USE (`sim/ai/**` except doctrine/commanders/ally/wave files, `tools/soak.gd`, the AI tests).
- **Inputs:** the PROGRESS G5 evidence item 3 (the soak lane command: `TAG=o1 bash .plan/shots/AI6-2/run_lane.sh ...`), `.plan/handoff/AI5-4.json`, G5 AI code; then each G6 API fact as it lands.
- **Tasks (in order):**
  1. Day 1: re-run the G5 soak lane on the current tree (at most 3 soaks at a time, hb.sh). Fix the draws, Valley Conquest included. Post `fact ai.g5_soaks` with the winner lines.
  2. `ai_g6.gd`: train companies + form an army (ARMY6 API), build the new defences by threat, lay and clear mines, garrison, use subs / carriers / SAM + radar / counter-drone, trade on the market, use airfield v2, set loadouts, build exo suits, reach Stage 10.
  3. `tools/soak.gd`: log the §12.3 evidence counters (companies / army formed, doctrine tags from `AiDecision` events, mines laid/cleared, garrison, sub kill/detection, carrier sortie, market trades, Stage 10, AI-commanded player formation in an assist soak) and add a survival-map config.
  4. Make test_ai_g6 green; keep test_ai, test_ai_g5, test_ai_air_naval, test_mil and test_g2_scenarios green.
- **Publishes:** `ai.g5_soaks`, `ai.g6_use_ready`.
- **Done-when:**
  - test_ai_g6 + the owned AI tests green
  - the soak lane ends with winners on every config, 0 invariant failures
  - full suite green
- **Never:** write doctrine (AI7-DOC) or AI commanders / wave AI (AI7-CMD).
