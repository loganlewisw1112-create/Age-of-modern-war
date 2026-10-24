# FORT: walls, gates, towers (sim)
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §2.1 (fragments), §3 (gate nav API from NAT), **§6** (yours; IDs fixed).
**Owns:** `sim/systems/fortify.gd`, `sim/systems/construction.gd`, `content/g4/fort.json`, `tests/test_fort.gd`.
**Depends on:**
- NAT's `Movement.set_gate` (wait for `fact nat.gates_ready`; until then, build the rest and stub the call behind a has-method check);
- ART-F's art (falls back to the generic building look).
**Downstream:** AI5 (wall planning), UI4B (drag UI calls your `build_line`). Post `fact fort.api_ready` with the exact command/field API early.

Tasks:
1. **Content** (`content/g4/fort.json`):
   - the 9 defs `a_wall a_gate a_wall_tower b_wall b_gate b_wall_tower m_barrier m_field_gate m_spire`, all size 1, faction-tagged, buildable, `wall`/`gate`/`tower` flags, cheap per segment, stage_min 7 (towers 8);
   - tower weapons;
   - armor type `fortification` via `armor_mult` (artillery/at strong; small arms ≈0.02; a new `demolition` weapon class very strong);
   - `faction_roles`: `wall`, `gate`, `wall_tower`.
2. **`build_line`:**
   - 8-direction snap (Bresenham);
   - one foundation per cell, skipping illegal cells with reasons;
   - charged per segment when that foundation starts;
   - builders work the line queue in order;
   - Shift appends (the command field `append: true`).
3. **`e.conn`** neighbour mask, recomputed on complete/destroy for the cell and its 4 neighbours.
4. **Gates:** call `Movement.set_gate` on complete/destroy/lock; `set_gate_lock` command; allies pass too.
5. **Walls block direct fire:** the LOS check treats completed wall/gate cells as blocking for non-tower shooters (coordinate with NAT; LOS lives in damage.gd, so post a CR). Towers fire over walls.
6. **Breach support:** when `order_path` fails for an attack-move unit because of enemy walls, target the nearest blocking enemy wall segment (a small hook; post a CR to UNITS if combat.gd needs it).
7. **Tests** (`tests/test_fort.gd`): line placement and costs, conn masks, gate passes owner/ally and blocks the enemy (native + fallback), lock, wall blocks LOS, breach by artillery, save mid-construction of a line.
Done when: tasks 1-7 are green and the full suite is green. MAX_TOKENS 600000, MAX_TOOL_CALLS 150, board id `FORT`.
