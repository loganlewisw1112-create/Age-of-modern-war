# G6-ART-G6b: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §3.2. **Plan:** PLAN_G6 §3.
**Board / bus id:** `ART-G6b`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_art_g6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ART-G6b: the new art pieces
- **Role:** draw what the kit does not have: Company HQ ×3, Commanders ×3, captains/lieutenants ×3 factions, Exo-Suit Garage, Rifle/Missile/AA exo suits (Avatar AMP style), and icons for every new G6 command.
- **Owns:** same files as ART-G6 (it has finished; never run together).
- **Inputs:** ART-G6's modules and handoff; `docs/vision/` (2 images max); the G5 figure kit for leaders; vehicle drawers for the suits (2-3× a soldier's height, walking legs, big rifle / shoulder missile pod / AA cannon).
- **Tasks (in order):**
  1. Company HQ per faction (size 3, faction style), team-masked, 4 rotations + states.
  2. Commander, captain and lieutenant figures per faction (officer kit with rank insignia; Machine = command nodes).
  3. Exo-Suit Garage (size 2) + the three suits (vehicle sheets, 8 facings, idle/move/fire + wreck).
  4. Icons for every §4 command (`train_company`, `form_army`, `set_loadout`, `lay_minefield`, `garrison`, `build_rail`, `strike`, `submerge`, `set_ai_commander` ...) + mine marker, garrison pip and sonar ping effect sheets.
  5. Make `new_pieces_company_hq_commanders_leaders_garage_suits` green; post `fact art.g6_new_ready`.
- **Publishes:** `art.g6_new_ready`.
- **Done-when:**
  - test_art_g6 fully green
  - full suite green
- **Never:** draw terrain or edit presentation code.
