# G71-FLOW71: fewer steps to battle (A3)

You are FLOW71. Read `G71_COMMON.md` first and follow it. Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140.
Scope: `docs/G71_SCOPE.md` part A3 in full (and D7 / H3 for how later waves will build on your templates).

## Build
1. **One-click "send to front" / "attack here"** from any card or building (cardbar8 cards, building cards, ops card,
   reserve card). "Front" = the most threatened wall face / contact line (pick a cheap, deterministic rule from existing
   threat data; PROVISIONAL), or a point the player clicks. **New units auto-form squads and go**: a production toggle
   per producer ("auto-deploy") so fresh units form a squad (SquadAI / formations7 APIs) and move to the front.
2. **Auto logistics toggles**: refuel, rearm, reinforce (top up squads from reserve / production), re-train
   (replace lost specialists). Per unit / squad / company, plus a global default. No babysitting: units leave to
   service and come back to their task. Reuse supply / ammo_bearer / repair / medical systems; don't duplicate them.
3. **Mission templates**: save a package (e.g. APCs + team + dropship + escort + support) from the current selection
   or a card, name it, launch it in one click at a target. Saved in the match state (hashed) and as a player preset
   (user file, outside the sim).
4. **Target: card -> fighting in <= 3 clicks.** Prove it in the flow by counting clicks for: a fresh infantry squad, a
   CN strike package, an armour company, an air package.

## Files and commands
- New `sim/systems/flow71.gd`, commands `flow_send`, `flow_auto`, `flow_template_save`, `flow_template_launch`.
  ORCH registers commands + the system slot: send a `change_request` with exact names and SYSTEM_ORDER position in your
  first 10 tool calls, and post `fact flow71.api` as a compiling stub.
- AI never overrides a fresh player order; auto-deploy never moves a unit on Hold Position.
- Tests `tests/test_flow71.gd` (determinism two-run hash, save/load mid-template, toggles), flow `tools/pt71_flow71.gd`
  (windowed; click counts logged; screenshots posted as `fact shots.best`).
- New panels pass tools/ui_fit_test.gd at all resolutions.
- Cost: nothing per tick when no toggle / template is active; staggered cadence when they are.
