# G6-ECON-AIRF6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §13, D25-D27. **Plan:** PLAN_G6 §5.
**Board / bus id:** `ECON-AIRF6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_market.gd`, `tests/pending_g6/test_airfield_g6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ECON-AIRF6: marketplace + airfield v2
- **Role:** the market and the airfield overhaul with G5 migration.
- **Owns:** see CONTRACTS_G6 §1 row ECON-AIRF6 (`market`, `airfield`, `air`, `economy`, `content/g5/air.json` geometry keys, `rules_market.json`, their tests).
- **Inputs:** the G5 airfield/air code + tests; economy ledger API; D25-D27.
- **Tasks (in order):**
  1. Market: `market_trade` with buy / sell (70%), ±1% price per unit, drift back over 180 s, per-60 s limit, ledger cause `market:<res>`, `price`, `limit_left`, saved state. Post `fact market.api_ready`.
  2. Airfield v2:
  3.   - base 2×2 + apron + runway 12 (airstrip 8, forward 6, launch rail 6);
  4.   - 6 auto-filled hangar slots, extra strip = +1 runway +2 slots;
  5.   - the G5 flight / holding / crater / divert / engineer logic on the new geometry;
  6.   - G5 save/map migration;
  7.   - `register_mobile_field` for carriers.
  8.   Post `fact airfield6.api_ready`.
  9. Make test_market + test_airfield_g6 green; keep test_air, test_airfield, test_air_transport and test_econ green (update their geometry expectations only where §13 changes them, and say so in CONTRACT_DEVIATIONS).
- **Publishes:** `market.api_ready`, `airfield6.api_ready`.
- **Done-when:**
  - both acceptance files + the owned G5 tests green
  - full suite green
- **Never:** write AI (AI7-USE uses your API) or UI (UI6a).
