# G6-PT6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §12.4 (PLAN_G6). **Plan:** PLAN_G6 §12.4.
**Board / bus id:** `PT6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** none (your checks are the playtest flows).
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### PT6: playtests for every new flow (incl. parallel)
- **Role:** windowed playtest flows for every G6 feature, each passing twice including 2 at a time, and fixing the two G5 parallel-run flakes (stages, tutorial).
- **Owns:** see CONTRACTS_G6 §1 row PT6 (`tools/ui_playtest.gd`, `tools/editor_playtest.gd`, `.plan/shots/PT6/**`).
- **Inputs:** the existing 12 flows; every G6 `*.ready` fact; the G5 flake notes (PROGRESS G5 evidence item 4).
- **Tasks (in order):**
  1. Fix the parallel flakes first: make the stages and tutorial flows deterministic when 2 run at once (wait on state, not on time).
  2. Add the 14 G6 flows of PLAN_G6 §12.4 (elevation, company, AI Commander, mines, garrison, naval G6, air defence, exo, loadout, market, airfield v2, survival, editor Live, height brushes) as they become possible (watch the facts).
  3. Run every flow twice, including 2 at a time (at most 2 windowed at once machine-wide); logs under `.plan/shots/PT6/`.
  4. Report each flow's result line raw.
- **Publishes:** `pt6.flows_green`.
- **Done-when:**
  - all 26 flows pass twice, including 2 at a time
  - logs under .plan/shots/PT6/
- **Never:** change game code (CR the owner with the failing step).
