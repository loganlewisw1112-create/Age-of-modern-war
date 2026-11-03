# G7-LPPERF7: Last Protocol sim cost + fissure terrain (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Then the board change requests seq 675 (LPMAP7-2, change_request.lp_wall_sim_cost: read
it in full), 711 (FISSURE7, CHASM terrain code) and 755 (FISSURE7, incremental terrain update), plus the handoff /
report notes in .plan/handoff/LPMAP7-1.json and .plan/fissure7/ (lp_cost*.log).

## The problem
On the Last Protocol map (`--map=last_protocol`, or `LastProtocol.make_config(seed, "last_protocol")`) one sim step
costs ~54 ms on a shared PC, above the 50 ms budget at 20 Hz, so the game cannot keep real time. LPMAP7-2 measured
that the 1143 plain `a_wall` entities of the pre-built rings (one entity per wall cell) cost ~31 ms of it: per-system
deltas combat 5.8, economy 5.2, movement 4.4, morale 3.4, supply 3.1, counter_nanite 2.1, production 2, fog 1.3,
fortify 1.1. Plain walls do nothing per tick until something hits them.

## Deliver, in order
1. **Make inert buildings (plain walls first) cost ~nothing per tick** in the systems that iterate every building:
   skip them in per-tick loops, keep them in spatial indexes / damage / pathing exactly as today. Hard rule: every
   existing match must stay **hash-identical** (test_hot_state GOLD/GOLD_FLAT/HEAD unchanged for the non-G7 cases;
   capture before/after on the same tree with the same command and compare) - a pure skip of work that had no
   effect. Do NOT change how the base is laid out (LPMODE7/LPMAP7 keep one wall per cell). Measure on last_protocol
   before/after (median of several runs, report per-system ms) and target a step well under 50 ms with headroom.
2. **CHASM terrain code** (FISSURE7 CR 711): a terrain code passable only for air classes, speed 0, does NOT block
   line of sight / line of fire, not buildable; give it a look in the terrain layer that matches FISSURE7's canyon
   shader (presentation/view/fissure_layer.gd draws the opening on top; the base tile just needs to read as dark
   ground). Then switch `content/g7/defs_g7_fissures.json` stage_codes.canyon to it and prove canyons now block all
   ground movement but not fire across (extend tests/test_fissure7.gd; FISSURE7 is finished, you own its test and
   defs for this).
3. **Incremental terrain update** (FISSURE7 CR 755): `Movement.on_cells_changed(w, cells)` updating nav for only the
   changed cells + re-requesting only paths that cross them, replacing the ~130 ms `on_terrain_changed` spike per
   fissure batch on the Last Protocol map. **movement.gd is shared with SQUAD7-5, which is live**: before editing it,
   post a `need` to SQUAD7-5 on the board, wait for its ack, keep your edit to one new function + the call site in
   fissures7.gd, and re-read the file immediately before writing. If SQUAD7-5 has not acked within ~10 minutes, do
   steps 1-2 fully first and leave step 3 as a precise handoff.

Files you own for this: sim/systems/combat.gd, economy.gd, supply.gd, production.gd, fog.gd, fortify.gd, morale.gd
(per-tick building loops only), sim/terrain.gd (+ the terrain layer / art for the new code), sim/systems/fissures7.gd,
content/g7/defs_g7_fissures.json, tests/test_fissure7.gd, a new tests/test_lpperf7.gd (wall-skip parity: a fight
against walls deals the same damage, walls still block paths, same hash with the skip on/off), .plan/lpperf7/.
counter_nanite.gd / apc7.gd belong to CNSIM7-5: send it a change_request for its 2.1 ms share instead of editing.
Report shared-PC numbers as shared-PC, not gate numbers. Do not re-baseline test_hot_state; prove it unchanged.
