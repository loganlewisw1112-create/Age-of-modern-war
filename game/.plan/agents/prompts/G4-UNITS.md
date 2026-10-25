# UNITS: 8 new human units + their mechanics
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §2.1, **§8** (yours; IDs and mechanics fixed).
**Owns:** `sim/systems/g4b_mech.gd`, `sim/systems/combat.gd` (keep every PERF4-x optimisation and the hash-equal paths), `content/g4/units_g4b.json`, `tests/test_units_g4b.gd`.
**Peers:**
- TRANS: cargo fields on `a_apc`/`b_halftrack`. Put `cargo_slots`/`cargo_accepts` in your own fragment for those two, exactly as TRANS's `trans.api_ready` fact specifies.
- FORT: wall targets and `fortification` armor.
- ART-U: art.
- AI5: uses roles.

Tasks:
1. **Content:**
   - all 8 units + production + weapons (stats PROVISIONAL, balanced against the existing rosters, stage per §8);
   - `faction_roles`: sniper, mortar, engineer_combat, flamer, transport;
   - hotkeys that don't collide.
2. **Mechanics** in g4b_mech.gd + combat hooks:
   - **Sniper concealment** (`conceal_still`): hidden from enemy fog and targeting beyond 3 tiles after 60 still, non-firing ticks.
   - **Mortar `deploy`/set-up time** (`setup_ticks`): can't fire while packed; packs to move.
   - **Mines** (`lay_mine`; entity kind `mine`): hidden; detection by engineer/recon within 4 tiles; trigger and damage.
   - **Demolition charges** (`plant_charge` on walls/buildings/bridges): a 100-tick fuse.
   - **Flamethrower:** ignores cover; fire spread on FOREST (§8: seeded, deterministic). Burning damages units; burnt forest becomes DIRT through the existing terrain-change path (Movement.on_terrain_changed, Fog). Emit an event so the renderer rebakes.
   - **Scrap mech:** crush damage to enemy infantry under it; front armor ×1.5.
   - **Rocket truck:** 6-rocket salvo with splash and a long reload.
3. Every new kind/state saves and loads (`mine`, `charge`, fire cells in `w.map.fire` or entities). Determinism holds.
4. **Tests:** one test per mechanic (concealment, deploy, mine trigger/detect, charge vs wall/bridge, fire spread/burnout/terrain change, crush, salvo), save mid-fire, and that existing combat tests stay green.
Done when: tasks 1-4 are green and the full suite is green. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `UNITS`.

## Pending change request for your combat.gd (from FORT, board): walls block direct fire
- `const Fortify = preload("res://sim/systems/fortify.gd")`
- In `_engage`: `(bool(s.indirect) or (_los(w, e.pos, t.pos) and not Fortify.fire_blocked(w, e, t)))`
- In `_fire`: `if not indirect and not los_ok and (not _los(w, e.pos, t.pos) or Fortify.fire_blocked(w, e, t)): return`
- Apply it early. test_fort switches to its real path once the hook text is present.
