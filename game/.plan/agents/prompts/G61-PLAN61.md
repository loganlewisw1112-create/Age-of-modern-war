# G61-PLAN61: the command layer: orders to officers and plans drawn on the map (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: plan61.

The owner wants both layers: classic RTS micro (SQUAD61) AND a command layer where the player gives orders to officers
and draws plans on the map that the chain of command carries out.

## Sim (new sim/systems/plans.gd)
- A plan = {id, owner, formation (company/army/platoon id), intent (attack, defend, raid, screen, withdraw),
  objectives [cells/areas], axis of advance (polyline), phase lines [polylines with names], timing (go now / on signal /
  at time), main effort flag, fire support requests}.
- Commands (ask ORCH for COMMANDS entries by change_request): `issue_plan {issuer, plan}`, `cancel_plan`,
  `plan_signal {issuer, plan_id, signal}` (e.g. "go", "phase 2", "withdraw").
- On issue, plans.gd converts the plan into chain-of-command orders (CHAIN61 `CommandNet.issue`; until it lands, OFF61's
  `Doctrine.execute_order` or the existing Ops `set_mission`) so captains/lieutenants execute it with their drills.
- Progress tracking: per plan, which phase line was reached, objectives held, losses; readable status lines.
- Same validation as any command (ownership, formation alive, cells in bounds); saved and hashed.

## UI (new presentation/ui6/command_layer/*)
- A **Command mode** toggle (button + hotkey, e.g. Tab or C; request the hotkey from SQUAD61): the map dims slightly and
  shows formations as NATO-style unit symbols with their officers.
- Select a formation (or an officer), then draw: click objectives, drag an axis of advance, drag phase lines (auto-named
  PL ALPHA, BRAVO...), pick intent and timing from a small radial/menu, confirm -> issue_plan.
- Plans stay drawn on the map (colour per plan, progress ticks on phase lines) and can be edited or cancelled; signals
  from the plan card.
- Officer orders: right-click an officer in command mode for quick orders (attack here, hold here, withdraw to, screen
  this line) that go through the chain.
- Must pass the UI-fit check at all resolutions; readable at 0.75 and 1.5 scale.

## Tests (tests/test_plans61.gd)
issue_plan validation (ownership, dead formation, bad cells); a plan with axis + 2 phase lines makes the company reach PL1
then PL2 in order and halt at each until the signal/timing; objective reached -> hold; cancel_plan stops it; signals;
save/load mid-plan + determinism.
Playtest flow tools/pt61_plan61.gd: enter command mode, draw an axis, two phase lines and an objective for a company,
issue, watch it advance (shots at each phase line), cancel another plan.
