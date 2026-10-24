# AI5: AI uses walls, gates, transports, new units, file maps
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §5-8. Previous AI handoffs `.plan/handoff/AI4-*.json`: the gotchas are binding (fairness regex, MapGenS preload, no preload cycles).
**Owns:** `sim/ai/**`, `tests/test_ai.gd`, `tools/soak.gd`.

Tasks:
1. **Walls:** on Normal+, wall in base chokepoints (from map crossings and approach paths), with gates on own exit routes and towers at gates (Hard: more). Don't wall over gather routes.
2. **Breach:** when attack paths are blocked, bring artillery/AT/engineer charges to the weakest segment.
3. **Transports:** ferry infantry to the front in APC/half-tracks; unload short of the enemy line.
4. **New units in the mix:**
   - snipers vs infantry-heavy foes;
   - mortars deployed behind the line;
   - engineers lay mines at chokes and plant charges on walls;
   - flamers vs forest-hiding infantry;
   - scrap mech / rocket trucks in heavy waves.
5. **File maps:** the AI plays on editor maps (spawns from file; no assumptions about built-in maps); obeys `ai_target` triggers.
6. AI think stays < 2 ms per tick per side at 5k units (ai_bench).
7. **Soaks:** 3 built-in maps × seeds 1-2, plus one editor-made map. Winners, 0 invariant failures, and log lines showing walls built, transports used and new units fielded. Report every SOAK RESULT.

Done when: tasks 1-7 are done and green. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `AI5`.
