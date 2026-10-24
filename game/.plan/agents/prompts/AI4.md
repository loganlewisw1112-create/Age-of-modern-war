# AI4: stage-aware AI, research/advancement, big maps, big armies (wave 2)
Read G3B_COMMON.md first. Your files: `sim/ai/**`, `tests/test_ai.gd` (CONTRACTS_G3b §1). The AI must stay fair: same commands, same costs, only what it can see.

Inputs that landed in wave 1 (read the board facts and the final reports in `.plan/handoff/` where present):
- STG4: stage gating, research (`research` command), `advance_stage`, `Progression.gate_report(w, fid)` (use this as the single source of what's missing); `Content.role(fdef, role, stage)`.
- MAP4: `industrial_heartland_m` (~160×160) and `valley_conquest_l` (~256×256), with multiple bridges/crossings.
- N1/PERF4: native movement (keep calling the movement API; don't reimplement pathing).

Order:
1. Use stage-aware roles everywhere the AI picks a def, so a Stage 7 AI never tries to queue an MBT. Handle "Requires Stage N" rejections without loops.
2. Research + advancement plan:
   - build the research building early-mid game;
   - research the next stage's projects;
   - satisfy gates (refinery running, power headroom, train officers + line units, comms buildings, recon);
   - advance when eligible and affordable without starving defence.
   - Normal difficulty should reach Stage 8 from 7 by roughly 15-20 game minutes on River Crossing.
   - Log `AI f<id> advanced to stage N at tick T` (soak greps this).
3. Use the Stage 9 units sensibly: EW near the front, AA vs air, guided artillery behind the line.
4. Big maps: scouting radius, expansion and attack routing scale with map size; multiple crossings; attack waves don't get lost.
5. **AI think cost at scale:** profile AI think with 2,000-5,000 own units; it must stay small (<2 ms per tick per side on average). Stagger work.
6. test_ai: stage-7 AI never queues stage-8 defs; the AI researches and advances in a fixture; a big-map AI-vs-AI run of 3,000 ticks has no errors.
7. Soaks with `tools/soak.gd` (add `--map=` and `--stages=7,8,9` flags if missing; tools/soak.gd is yours this wave): a 3-faction FFA with mixed stages on each map must end with a winner, and a 7→8 and 8→9 advancement must appear in the logs. Report every SOAK RESULT line.
MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `AI4`.

## Change requests already addressed to you (from MAP4, board seq 563-564)
1. `sim/ai/ai_util.gd` `spawn_of(w, side)`: return `Vector2(w.factions[side].spawn) + Vector2(0.5,0.5)` when `w.factions.has(side)`. G3b maps assign spawns via `map.spawn_sets`, so `map.spawns[side]` is wrong on the big maps.
2. `ai_mil.gd`, `ai_tactics.gd`, `ai_g3.gd`: crossing points come from `w.map.bridges` (each `{id, name, cells, state}`) plus fords, not only `w.map.bridge_cells` (hold bridge).
STG4 may still be finishing; read `sim/systems/progression.gd` for the real API (`gate_report`, command fields) before coding against it.
