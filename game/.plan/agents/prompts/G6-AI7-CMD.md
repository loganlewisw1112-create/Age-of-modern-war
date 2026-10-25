# G6-AI7-CMD: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §16 (AI Commanders, ally), §15 (waves), §4 (AiCommand commands). **Plan:** PLAN_G6 §9, D41.
**Board / bus id:** `AI7-CMD`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_ai_commanders.gd`, `tests/pending_g6/test_ally_cmds.gd`, `tests/pending_g6/test_wave_ai.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### AI7-CMD: AI Commanders, ally commands, Wave AI
- **Role:** player-side assist commanders (formation or role, objective + stance, 4 playstyles, never fighting the player), ally requests, and the survival wave attacker.
- **Owns:** see CONTRACTS_G6 §1 row AI7-CMD (`commanders`, `ally_cmds`, `wave_ai`, `sim/systems/ai_command.gd`, their tests).
- **Inputs:** `Doctrine.plan_for` (AI7-DOC), ARMY6's formations, MODES6's waves.
- **Tasks (in order):**
  1. `ai_command.gd` commands + `slots`; badge field on commanded units. Post `fact aicmd.api_ready` (partial).
  2. `Commanders.think_player`: the four playstyles drive doctrine plans for their formation or role; never order a unit within 20 s of a player order (`e.player_order_tick`; CR ORCH to stamp it in `world.submit` for direct orders); recall at once.
  3. `ally_request` handling (attack / defend / air support within the ally's means).
  4. `WaveAI.think`: commands MODES6's waves with doctrine (escalating, company-based).
  5. Make the three acceptance files green.
- **Publishes:** `aicmd.api_ready`.
- **Done-when:**
  - the three acceptance files green
  - full suite green
- **Never:** edit doctrine files (AI7-DOC) or ai_controller (AI7-USE).
