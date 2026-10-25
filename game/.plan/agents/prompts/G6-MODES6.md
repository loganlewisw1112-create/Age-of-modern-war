# G6-MODES6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §15 (survival), §3.6. **Plan:** PLAN_G6 §8.
**Board / bus id:** `MODES6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_survival.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### MODES6: survival mode + 2 stronghold maps
- **Role:** the `survive` and `repel_waves` victory types, the wave spawner, and the Ridge Bastion and River Dam maps.
- **Owns:** see CONTRACTS_G6 §1 row MODES6 (`victory`, `waves`, the two map scripts, `rules_survival.json`, test_survival, test_victory).
- **Inputs:** `victory.gd`; `sim/maps/*.gd` + `map_util` (ELEV owns them: read and reuse); ELEV's height API; ARMY6's templates (waves use companies).
- **Tasks (in order):**
  1. Victory types `survive {seconds}` and `repel_waves {count}`. Post `fact survival.api_ready` (partial).
  2. `waves.gd`: edge (or `wave_spawns`) spawns every 90 s, escalation table, company-template composition; `next_wave` for the UI. AI7-CMD's wave AI commands them.
  3. Maps `ridge_bastion` (walled ridge, 2 ramps, 4 lanes) and `river_dam` (dam + bridges) with authored height; both validate. Post `fact map.survival_ready`; ORCH registers `ridge_bastion_m` / `river_dam_m`.
  4. Make test_survival green; keep test_victory green.
- **Publishes:** `survival.api_ready`, `map.survival_ready`.
- **Done-when:**
  - test_survival + test_victory green
  - full suite green
- **Never:** edit ELEV's map files (reuse them through calls).
