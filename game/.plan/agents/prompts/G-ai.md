# G-ai: fair autonomous AI opponent
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model opus (planning judgement, fairness)

You own `sim/ai/**` and `tests/test_ai.gd`. Implement CONTRACTS.md section 6. By now the economy (A), military (B) and
save/soak (F) systems are real. Read their code before designing: `sim/systems/*.gd`, `sim/save_system.gd`, `tools/soak.gd`.

Fairness rules (spec DEC-09, AI-02; non-negotiable):
- Act ONLY through `w.submit({...issuer: fid})`. Tolerate rejections: read `CommandRejected` events for your
  issuer in `w.events`, log the reason, and adapt (don't spam the same rejected command every think).
- Read only: your own entities and faction, the public map (`w.map.terrain`, `spawns`, `resources` positions as
  initially published, `bridge_cells`, `ford_cells`), `Content`, `w.visible_enemies(fid)`, `w.memory[fid]`, your own
  `w.fog[fid]`. NEVER iterate `w.entities` for enemy units/buildings, NEVER read another faction's dict or fog.
  Resource entities are neutral world objects. You may know their positions only if their cell is explored by you
  or they were in the initial `map.resources` list (public map knowledge). Same rule for the player.
- Knowing the enemy's possible start location from `map.spawns` is allowed (classic RTS public info). Knowing which
  units/buildings are there is not, until they are scouted.
- Difficulty (`rules.ai_difficulties[cfg.ai_difficulty]`) changes cadence and thresholds, never knowledge or resources.

Behaviour (bounded state machine + utility scores, deterministic, all state in `w.ai_state[fid]`, serializable):
1. Economy: keep engineers gathering (balance salvage vs ore by need), train engineers up to `max_engineers`,
   build order roughly: generator, barracks, depot (when pop is near cap), second generator when power is short,
   motor pool, guard tower near the HQ facing the river. Use `Construction.placement_error` to search candidate
   origins in rings around the HQ (deterministic order), avoiding resource cells and the road.
2. Military: queue a mix continuously when affordable (rifle squads, AT teams, IFVs/MBTs once the motor pool is up;
   adapt AT/vehicle share to seen enemy vehicles). Rally near the base front.
3. Scouting: send the recon (or one rifleman) toward the enemy spawn early, then patrol fords/bridge.
4. Attack: when army pop >= `attack_army_pop`, attack_move the army toward the last known enemy HQ (`memory`) or
   the enemy spawn if not yet seen. Regroup if the army falls below 40% of its launch size (retreat to the rally point).
   Re-attack when rebuilt. Target priority is enemy units in range, then production buildings, then HQ.
5. Defense: if own buildings/units take fire (ShotFired targeting own entities) or enemies are visible within 14 tiles
   of HQ, pull the army home and engage.
6. Inspector fields (shown by the HUD debug panel later): `objective, strategy_scores, last_command, last_result,
   next_think_tick, known_contacts, log` (last 20 lines, each prefixed with the tick).

Required tests (tests/test_ai.gd):
- AI-01 non-scripted: with BOTH sides AI (`cfg.sides[0].ai = true`), within 9000 ticks each side has built a
  barracks, trained at least one squad, and issued at least one attack_move toward the enemy half. Use 2 seeds.
- AI-02 fairness: instrument with a wrapper. Every `attack` command the AI issued targeted an entity that was in
  `visible_enemies(fid)` at issue time. Also do a static check that `sim/ai/*.gd` never reads `w.factions[<other>]`
  or iterates entities for enemies (grep your own source in the test for forbidden patterns like
  `factions[1 - fid]`, and document the convention).
- Soak: `tools/soak.gd` with seeds 1,2,3 at normal difficulty ends with a winner before 36000 ticks (30 sim-minutes).
  Paste the SOAK RESULT lines. If matches stall (no winner), diagnose the funnel (which step stopped: economy,
  production, attack launch, pathing, target finding) before tuning, and tune only `sim/ai` thresholds/behaviour.
  Put any content-balance suggestions in CHANGE_REQUESTS, not in the content files.
- Determinism: two identical AI-vs-AI runs give equal `state_hash()` at tick 6000. The save/load/continue hash test still passes.
