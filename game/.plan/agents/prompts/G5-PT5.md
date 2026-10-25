# G5-PT5: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §4, §5. **Plan:** Plan section 12 item 4.
**Board / bus id:** `PT5`. **Budget: MAX_TOKENS 500000, MAX_TOOL_CALLS 120** (registered by ORCH; never raised).
**Your acceptance skeletons:** (none: your evidence is the playtest output). `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### PT5: playtests for every new flow
- **Owns:** `tools/ui_playtest.gd`, `tools/editor_playtest.gd`, `.plan/shots/PT5/**`.
- **Inputs:** `ui5.kit_ready`, UI5b panels, every `api_ready`.
- **Tasks:** add synthetic-input flows (screenshots at each step) for:
  - **air:** place airfield → buy hangar → assign engineers → build a jet → takeoff → sortie → land; VTOL loads 2 vehicles + 8 → flies → unloads; a helicopter lands on open ground outside the base → takes off → is serviced at a helipad with engineers assigned;
  - **naval:** shipyard → landing craft → load → beach landing;
  - **Drone Team:** 4 launches of chosen types → tactical breach;
  - **Auto resupply:** station and roam;
  - **medical:** wounded → evac → Hospital → reinforcement;
  - **tutorial:** a full run-through.

  Keep the existing 6 flows passing.
- **Done-when:** every flow prints `PLAYTEST RESULT pass=N fail=0` twice in a row; screenshots self-checked.
- **Budget:** 500k / 120.
