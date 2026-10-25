# G5-SUPPORT: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1-§6, §10. **Plan:** Plan section 6 (Workstream E).
**Board / bus id:** `SUPPORT`. **Budget: MAX_TOKENS 700000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_support.gd`, `tests/pending_g5/test_medical.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### SUPPORT: Auto resupply, Wounded, evacuation, hospitals
- **Role:** the two auto-support systems and the medical buildings.
- **Owns:**
  - `sim/systems/support.gd` (Auto Resupply: station + roam, thresholds, combat rule, resume orders, truck self-refill, multi-truck split);
  - `sim/systems/medical.gd` (Wounded state via `Damage.on_zero_hp`, 60 s bleed-out, auto evac, Hospital/Field Hospital healing → free reinforcement);
  - `content/g5/support.json` (Hospital, Field Hospital for both human factions);
  - `tests/test_support.gd`, `tests/test_medical.gd`.
- **Inputs:** plan §6; `core.zero_hp_hook_ready`; the Supply API (call only); UNITS5's ambulance/medic IDs.
- **Tasks:**
  1. The `set_auto_resupply {mode: station|roam, area, thresholds}` command and per-truck state.
  2. Units requesting supply go and return to the order they had saved.
  3. A truck refills itself at the nearest depot/refinery.
  4. Wounded: infantry at 0 HP → Wounded (immobile, no fire, counted in pop); bleed-out after 60 s; saved and hashed.
  5. `set_auto_evac {area}` for medic/ambulance; pick-up capacity per unit; delivery to the nearest hospital; Field Hospital triage → Hospital; healed → a free reinforcement at the Hospital.
  6. Works for ships (pier) and helicopters (forward strip) through AIRSYS/NAVAL APIs.
- **Publishes:** `support.api_ready`, `medical.api_ready`.
- **Done-when:**
  - tests green: station and roam resupply, combat rule, resume order, self-refill, two trucks not doubling up, wounded → evac → hospital → reinforcement, bleed-out, save mid-evac;
  - full suite green.
- **Budget:** 700k / 170.
- **Never:** edit `supply.gd` or `damage.gd` (CRs to CORE10K).
