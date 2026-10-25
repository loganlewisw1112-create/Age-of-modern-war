# G6-MECH6c: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §9 (call-ins, auras, mobility). **Plan:** PLAN_G6 §4.
**Board / bus id:** `MECH6c`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_callins.gd`, `tests/pending_g6/test_auras.gd`, `tests/pending_g6/test_mobility.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### MECH6c: call-ins, auras, mobility
- **Role:** JTAC designation, the aerostat, Drone Control Center bonuses, the AWACS hook, auras and propaganda, the bridge layer, airdrops and marine fast-unload.
- **Owns:** see CONTRACTS_G6 §1 row MECH6c (`callins`, `auras`, `mobility`, `rules_support_g6.json`, their tests).
- **Inputs:** the G5 transport (`transport.gd`, NAVAL6 owns it: CR for drop hooks) and drone team (`g5_mech.gd`, AIRDEF6 owns it); `Airdef.air_picture`.
- **Tasks (in order):**
  1. Call-ins: `designate` (accuracy ×1.25, −30% delay for friendly strikes on the target), `aerostat` (+12 sight deployed), Drone CC (+1 charge cap, +50% range for drone teams in range; via AIRDEF6's g5_mech API or a CR). Post `fact mech_c.api_ready`.
  2. Auras: Command Vehicle, Commander and propaganda team/tower (`acc_mult`, `morale_delta`; propaganda drains enemy morale).
  3. Mobility: `deploy_bridge` / `pack_bridge` (a 1×N span over water ≤ 6), `airdrop` (paratroopers or supply pallet into a 3×3 area), marines unloading ×2 faster.
  4. Make the three acceptance files green.
- **Perf contract (G6Hooks.active mask, CONTRACTS_G6 §5.1):** keep `w.sys_state.callins.aerostats` (Dictionary of deployed aerostats; empty when none) and `w.sys_state.auras.sources` (Array of active aura source ids; empty when none) always current. The hot loops skip your `sight_bonus` / `morale_delta` / `acc_mult` delegates entirely when these are empty, so keep each delegate cheap (per-tick caches, no full scans per call).
- **Publishes:** `mech_c.api_ready`.
- **Done-when:**
  - test_callins, test_auras, test_mobility green
  - full suite green
- **Never:** edit transport.gd or g5_mech.gd yourself (CR NAVAL6 / AIRDEF6).
