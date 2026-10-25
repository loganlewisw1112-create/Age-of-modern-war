# G6-EXO6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §14, §3.4, D32-D35. **Plan:** PLAN_G6 §7.
**Board / bus id:** `EXO6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_exo.gd`, `tests/pending_g6/test_loadouts.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### EXO6: exo-suits, loadouts, research effects
- **Role:** the Exo-Suit Garage, suit gating, pilot eject and re-suit, per-squad loadouts, and the EXO-owned research effects.
- **Owns:** see CONTRACTS_G6 §1 row EXO6 (`exo`, `loadouts`, `medical`, `rules_exo.json`, their tests).
- **Inputs:** G5 medical (wounded, evac); CONTENT6 defs (`a_exo_*`, the garage, `a_exo_trooper`); the §5.1 hooks (`armor_mult`, `acc_mult`, `speed_mult`).
- **Tasks (in order):**
  1. `Exo.can_produce` (stage + garage); the suit counts as a vehicle element (FOUND-line it for ARMY6). Post `fact exo.api_ready` (partial).
  2. `on_destroyed`: the pilot ejects as a wounded `rifleman` with `pilot_of`; `resuit` at a garage for 60%.
  3. Loadouts: sets per faction (§3.4), `set_loadout` near a barracks or Company HQ with a cost, stat modifiers through the Loadouts lib, `exo` tier → `e.art_def = "a_exo_trooper"` (never changes `e.def`).
  4. Research effects for `g6_armor_kits_1`, `g6_infantry_plates_1`, `g6_exo_armor_1`, `g6_exo_weapons_1`.
  5. Make test_exo + test_loadouts green; keep test_medical green.
- **Perf contract (G6Hooks.active mask, CONTRACTS_G6 §5.1):** keep `w.sys_state.loadouts.nonstandard` = the count of units with a non-standard loadout, always current. The hot loops skip `Loadouts.speed_mult` / `armor_mult` / `acc_mult` when it is 0, so keep each delegate cheap (no scans per call).
- **Publishes:** `exo.api_ready`.
- **Done-when:**
  - test_exo + test_loadouts + test_medical green
  - full suite green
- **Never:** write UI (UI6b) or art.
