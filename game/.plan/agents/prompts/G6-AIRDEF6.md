# G6-AIRDEF6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §12. **Plan:** PLAN_G6 §4 rows Radar/Counter-drone.
**Board / bus id:** `AIRDEF6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_airdef.gd`, `tests/pending_g6/test_counterdrone.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### AIRDEF6: radar-gated SAMs, AWACS, counter-drone
- **Role:** everything in §12, plus drone capture/jamming inside the G5 drone code.
- **Owns:** see CONTRACTS_G6 §1 row AIRDEF6 (`airdef`, `counterdrone`, `status`, `g5_mech`, `rules_airdef.json`, their tests).
- **Inputs:** `status.gd` (EW jamming), `g5_mech.gd` (launched drones), combat targeting rules (read-only; CR PERF6 if a hook is missing).
- **Tasks (in order):**
  1. Radar coverage (`radar_covers`), SAM gating (no radar = no fire), radar warnings (events for the minimap), AWACS reveal + AA bonus (`air_picture`). Post `fact airdef.api_ready` (partial).
  2. Counter-drone: Laser CIWS (kills drones, rockets, shells in radius, rate-limited; also intercepts MECH6b's cruise strike), net post capture + salvage, jamming fields (`jammed`) that drop drones and guided shots, scrap AA anti-drone.
  3. Drone Control Center hooks for MECH6c (an API for the +1 charge cap / range).
  4. Make both acceptance files green; keep test_drone_team and test_units_g5 green.
- **Publishes:** `airdef.api_ready`.
- **Done-when:**
  - test_airdef + test_counterdrone green
  - the owned G5 drone tests green
  - full suite green
- **Never:** edit combat.gd (PERF6).
