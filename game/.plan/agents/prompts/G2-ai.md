# G2-ai: AI upgrade for Smart Warfare
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model opus (planning judgement, fairness)

You own `sim/ai/**` and `tests/test_ai.gd`. The G1 AI is in `sim/ai/` (ai_controller, ai_econ, ai_mil, ai_army, ai_util), built by G-ai/G-ai-2. Read their headers and `docs/CONTRACTS.md` §6 first. Fairness rules are unchanged and binding: commands only via `w.submit` (through `U.submit`); enemy knowledge only via `visible_enemies`/`memory`; the static fairness test must still pass. Also fix the G1 known gap: `known_resources` must not read the remaining `amount` of unexplored deposits; count only explored cells or initially public positions without amounts.

New G2 systems are landed or landing. Read their headers, and use their commands and fields per `docs/CONTRACTS_G2.md`:
- supply: unit `ammo`/`fuel`, faction stock `fuel`/`ammo`, refinery building, logistics_truck, resupply near HQ/depot/truck;
- repair command for engineers;
- officers: `assign_officer`, `set_mission`, `cancel_mission`, plus `Ops.group_led_by`/`group_of` helpers in `sim/systems/ops.gd`;
- `patrol`/`guard`/`set_formation`;
- the bridge structure: an explicit attack demolishes it, and repair restores it;
- morale: broken units retreat on their own (A2's morale.gd);
- damage: rear arcs take x1.7.

Behaviour to add (deterministic, all state in `w.ai_state[fid]`, inspector log lines for each decision):
1. **Logistics:**
   - Build a refinery after the motor pool.
   - Keep `fuel`/`ammo` stock above a floor (reorder refinery ore share in the gather plan).
   - Train one logistics_truck per attack group and keep it ~6 tiles behind the group (move/guard).
   - Units with ammo below 30% or vehicles low on fuel go back to resupply before re-committing.
2. **Officers:**
   - Train an officer per attack wave and `assign_officer` the wave to it.
   - Use `set_mission secure_point` on the chosen crossing (bridge, or the ford for the route personality), then `attack_area` on the enemy base target.
   - React to OfficerReport withdraw (regroup and rebuild).
   - Read the group via `Ops.group_led_by`.
3. **Tactics:**
   - Prefer AT/MBT when enemy vehicles are seen.
   - When attacking a seen enemy vehicle, move part of the AT/MBT group to its side/rear (fair: uses visible facing only).
   - Don't send units through a ruined bridge.
   - If its own route depends on a ruined bridge, send engineers to repair it when safe (no visible enemies within 10 tiles), else reroute via a ford.
   - Optional: demolish the bridge defensively when losing and the enemy army is seen crossing (difficulty hard only).
4. **Repair:** idle engineers repair damaged own vehicles/buildings near base.
5. **Keep the G1 grace period** (`first_attack_tick`) and the all-in endgame.

Tests (`tests/test_ai.gd`; keep the existing 4 green, updating only what the G2 world changes legitimately):
- AI-01 still holds on 2 seeds.
- Within 12000 ticks of AI-vs-AI the AI has built a refinery, trained an officer, and issued `assign_officer` and `set_mission` (scan `w.pending`/CommandApplied).
- Units that dropped below 30% ammo were later resupplied (ammo rose), shown in at least one seed.
- The fairness static scan covers the new modules.
- Determinism at 6000 ticks.

Soak: `tools/soak.gd` seeds 1, 2 and 3 at normal must each end with a winner before 36000 ticks. Paste the SOAK RESULT lines. Diagnose any stall by funnel step before tuning. Content-balance suggestions go to CHANGE_REQUESTS; do not edit `content/`. Done when `--only=test_ai`, the soaks and the full suite are green (quote other agents' failures).
