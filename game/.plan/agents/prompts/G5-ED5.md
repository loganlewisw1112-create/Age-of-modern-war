# G5-ED5: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §3, §4, §5. **Plan:** Plan section 9 (Workstream H).
**Board / bus id:** `ED5`. **Budget: MAX_TOKENS 850000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_tutorial.gd`, `tests/pending_g5/test_editor_g5.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ED5: editor additions, tutorial, polish
- **Owns:**
  - `presentation/editor/**`;
  - `sim/systems/triggers.gd` (new conditions: aircraft landed, unit evacuated, beach landing);
  - `content/scenarios/tutorial.rtsmap`;
  - `presentation/main.gd`;
  - the polish items in files it owns, with CRs for the rest.
- **Inputs:** `ui5.kit_ready`; all content IDs.
- **Tasks:**
  1. Editor palettes show the new units/buildings. Place airfields with strips/hangars and aircraft already parked, plus helipads, shipyards, hospitals and ships on water. Validate the new placements.
  2. New trigger conditions.
  3. The tutorial match: move, gather, build, train, attack, advance a stage, walls, transports, Auto resupply, airfield (buy a hangar, build a jet, take off/land), med evac. Step prompts in the new UI; reachable from the main menu.
  4. The polish list (§9).
- **Done-when:** the editor playtest passes; the tutorial completes in PT5's flow; test_editor_* green; full suite green.
- **Budget:** 600k / 150.
