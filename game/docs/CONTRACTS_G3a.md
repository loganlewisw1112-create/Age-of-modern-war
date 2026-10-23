# Integration contracts: G3a "Factions + Skirmish"

Extends `docs/CONTRACTS.md` and `docs/CONTRACTS_G2.md`; all of their hard rules still apply. Scaffold commit `48332f1`. Every number is PROVISIONAL.

## 1. What the scaffold already did (ORCH)
- `content/factions.json`: three factions (`human_a`, `human_b`, `machine`). Each has a **roles** table, `start_units`, `name` and `blurb`. Every building, unit and production def has a `faction` field.
  - Helpers: `Content.faction(id)`, `Content.faction_ids()`, `Content.role(faction_id, role)`, `Content.buildable_for(faction_id)`, `Content.econ(profile, key)`.
  - **Never hard-code def names (`"hq"`, `"barracks"`, `"engineer"`...) in new code.** Use roles or building/unit flags.
- Building flags: `is_hq`, `deposit`, `supply_point` (resupply), `home` (retreat target), `refines` (refinery cycle), `recharge=R` (free charge radius for energy units), `scrap_magnet=R` (Salvage Yard), `weapon`, `produces`, `requires`.
- Unit flags:
  - `can_build`, `can_gather` (Machine splits these: m_repair_bot builds, m_hauler gathers), `can_repair` (non-engineer repairers: b_recovery_truck, m_repair_bot), `is_supply`, `is_officer`;
  - `energy` (Machine: no fuel stock; recharge);
  - `is_air` + `move_class:"air"` (m_drone);
  - **Machine units have no `morale` field, so they are immune to suppression and morale.**
- Weapon fields: `anti_air` (only these can target `is_air` units); `indirect`, `min_range` and `splash` (artillery: howitzer, plasma_mortar).
- World:
  - 2–4 sides; `cfg.sides[i].team`; `w.is_enemy(a, b)` and `w.is_ally(a, b)` are team-based.
  - Side i uses `map.spawns[i]`. River Crossing has 4 spawns: 0/1 diagonal corners, 2/3 one per bank.
  - `cfg.economy` is "arcade" | "standard" | "simulation", and `w.econ(key)` returns the multiplier (`gather_mult`, `ammo_use_mult`, `fuel_use_mult`, `build_time_mult`).
  - `default_config()` stays Human A vs Human A.
- Systems already converted from def names to flags: refinery, supply points, morale home, ops resupply. Construction rejects buildings from another faction.

## 2. Ownership (G3a)
| Agent | Owns |
|---|---|
| S3-sim | `sim/systems/combat.gd`, `damage.gd`, `movement.gd`, `supply.gd`, `repair.gd`, `gather.gd`, `construction.gd`, `economy.gd`, `production.gd`, `status.gd`, `tests/test_factions.gd` |
| V3-victory | `sim/systems/victory.gd`, new `sim/systems/territory.gd`, `sim/systems/fog.gd` (allied vision), `tests/test_victory.gd`. Add Territory to `SYSTEM_ORDER` via CHANGE_REQUEST, or call it from victory.gd's tick. |
| AI3 | `sim/ai/**`, `tests/test_ai.gd` |
| UI3 | `presentation/**` except `presentation/art/**` |
| ART3-B | `tools/art/faction_b*.gd`, plus Human B entries in `assets/generated/**` |
| ART3-M | `tools/art/faction_m*.gd`, plus Machine entries in `assets/generated/**` |
| ORCH | `sim/world.gd`, `sim/content.gd`, `sim/map_gen.gd`, `content/*`, `tools/gen_art.gd`, `tests/test_base.gd`, `tests/test_core.gd`, docs |

The art agents never touch each other's modules or `presentation/art/art_catalog.gd`. The catalog is manifest-driven, so new manifest entries (infantry/vehicles/buildings/icons) appear automatically. **Only one art agent may run the full generator at a time.** Each one regenerates all assets, so coordinate via the board: post `fact art.gen_lock {"by": id}` before generating and `fact art.gen_unlock` after. Check `read.mjs --topic art.gen_lock` first.

## 3. Faction mechanics (S3-sim)
1. **Artillery** (`indirect` weapons):
   - Fires at any visible enemy within `range` and beyond `min_range`, and ignores `Damage.line_clear` (indirect fire).
   - Applies `splash` damage to every entity within the splash radius of the impact point, enemies AND allies (friendly fire), with linear falloff to 50% at the edge.
   - Emits one `ShotFired` with `indirect:true` and one `Damage` event per entity hit.
   - Never targets air units.
2. **Air** (`move_class:"air"`):
   - Paths are straight lines, ignoring terrain and footprints (clamped to the map). There is no AStarGrid for air.
   - Separation applies only among air units. Air units never block ground units, and ground units never block them.
   - **Only `anti_air` weapons can target `is_air` units.** Combat's target search filters this.
3. **Energy** (Machine `energy:true` units):
   - Their `fuel` is charge. It drains per tile moved like fuel, × `w.econ("fuel_use_mult")`.
   - It refills for free (no ledger draw) by `supply.refill_per_second.fuel` while within the `recharge` radius of an own built building that has `recharge`, and only while that faction's `power_prod >= power_use`.
   - Energy units never draw from the `fuel` stock. Their ammo still uses the stock: the Machine reprocessor `refines` makes ammo and fuel.
4. **Salvage Yard** (`scrap_magnet=R`): every 20 ticks, each built yard pulls up to 1 salvage per second from each salvage resource pile within R tiles. The pile's amount is decremented and the amount credited via `w.credit(..., "scrap_magnet")`. This is conserving.
5. **`can_repair` units:** repair.gd accepts any unit with `can_repair` or `can_build`, not only engineers. A recovery truck repairs vehicles only. The repair bot repairs everything, like an engineer.
6. **Gather/build split:** gather validation uses `can_gather` and construction validation uses `can_build`. Check that this already works for m_hauler and m_repair_bot.
7. **Economy profiles:**
   - `gather_mult` scales the harvest rate, with integer accounting kept.
   - `ammo_use_mult`: 0 disables ammo use; 1.5 means 1 round plus 50% chance accumulated deterministically via an accumulator, not the rng.
   - `fuel_use_mult` scales fuel and charge drain.
   - `build_time_mult` scales construction time.
8. **Faction-checked commands:** queue_unit is only valid if the item's `faction` matches the issuer's faction (defence in depth). Production spawns already come from the building's `produces`.
9. **Tests** (`tests/test_factions.gd`): each of the three factions can place its start HQ, train its builder and gatherer, and build its barracks-role building via roles. Also:
   - artillery splash damages 2 clustered targets plus an ally, and respects min_range;
   - a drone flies over water/forest in a straight line;
   - rifles can hit drones but AT rockets/tank cannons cannot target them;
   - Machine charge refills only near a recharge building with power ok, and never touches the fuel stock (journal check);
   - the scrap magnet conserves (pile decrement equals credit);
   - the recovery truck repairs a vehicle;
   - economy profiles change gather rate and ammo use;
   - a Machine unit under heavy fire never gets `pinned`.

## 4. Victory, territory, teams (V3-victory)
- `cfg.victory`: "hq_elimination" | "territory" | "hold_bridge" | "combined" | "endless".
- `cfg.victory_rules` (used for "combined"; optional otherwise): `{"op": "and"|"or", "terms": [{"type": "hq_elimination"}, {"type": "territory", "percent": 60}, {"type": "hold_bridge", "seconds": 300}]}`. Single-type modes may carry params: `cfg.victory_params = {"percent": 60}` or `{"seconds": 300}`.
- **Territory** (`territory.gd`):
  - The map is split into sectors of `rules.territory.sector_size` (12×12 tiles). Only sectors with at least 30% passable foot cells count.
  - A sector becomes controlled by a team when only that team has units or buildings in it for `capture_seconds`. Control is sticky until another team captures it.
  - State lives in `w.sys_state.territory`, recomputed every 20 ticks.
  - API: `Territory.percent(w, team) -> float` and `Territory.sector_owner(w, sector)` for the HUD.
- **hold_bridge:** a team holds the bridge while it has the only units within 4 tiles of the bridge entity's pos and the bridge is intact. It counts consecutive seconds, and the counter resets if contested or lost.
- **Evaluation:**
  - Each term is satisfied per team; a team wins when the expression is true for it.
  - **Teams are eliminated together:** a team is out when all its sides have no HQ.
  - hq_elimination is satisfied for a team when all enemy teams are eliminated.
  - `MatchEnded {winner_team, winners:[fids], reason}`, plus the `winner` field (lowest fid of the winning team) for G1 compatibility.
  - Endless never ends, but eliminations still happen.
  - Expose `Victory.progress(w, team) -> Dictionary` for the HUD's checklist (term states).
- `validate_rules(cfg)` returns a reason for:
  - an unknown term;
  - percent outside 10..100;
  - seconds outside 30..3600;
  - endless combined with any term;
  - an empty terms array;
  - hold_bridge on a map without a bridge;
  - an op other than and/or;
  - duplicate terms.
- **Allied vision:** fog `is_visible`, `entity_visible` and `visible_enemies` for fid treat cells seen by ANY ally as visible. Explored is shared. Memory stays per side, merged on read. Keep it cheap.
- **Tests** (`tests/test_victory.gd`):
  - MATCH-01: a 3-side match with independent credits and factions.
  - VICT-01: territory 60% wins; hold_bridge 300 s wins; AND needs both; OR needs one; Endless never ends.
  - QA-011: endless does not end when rivals die.
  - QA-012: combined expressions.
  - Contradictory sets are rejected with distinct reasons.
  - A 2v2 where both sides of a team must lose their HQ.
  - Allied vision: an ally's unit reveals an enemy to fid.
  - Save round trip with territory state.

## 5. AI (AI3)
- Faction-agnostic: every def comes from `Content.role(faction, role)` and building/unit flags.
  - Machine: haulers gather, repair bots build and repair; keep charging hubs near the front for recharge; drones raid; walkers go through forests.
  - Human B: turtle with bunkers, plus artillery trucks behind a carrier/tank line, plus recovery trucks.
  - Human A as in G2.
- Multi-enemy: choose a target among enemy teams, by known HQ distance and weakness; never attack allies; re-target when a target team is eliminated.
- 2v2: allies attack the same enemy when practical (shared target via both reading their own knowledge; no shared AI state, so it stays fair).
- Victory awareness: in territory/hold_bridge modes, hold sectors and the bridge (use officers' hold_zone/secure_point).
- Fairness rules from G1/G2 are unchanged. Allied vision is legal knowledge once V3 lands, via `visible_enemies`.
- **Tests:**
  - AI-01 for each faction (builds its barracks-role building, trains, attacks);
  - QA-005: in a 3-side FFA, the AIs attack each other;
  - 2v2 alliances respected (no attack command ever targets an ally);
  - fairness static scan;
  - determinism.
- **Soaks:**
  - 3-side FFA (one per faction) on seeds 1–3, each ending with a winner;
  - a 2v2 on seeds 1–2;
  - mirror matches still pass.
  - Use `tools/soak.gd` flags; extending soak.gd is allowed for `--sides`/`--factions`/`--teams`/`--victory`.

## 6. UI (UI3)
- **Skirmish setup:**
  - 2–4 slots. Each slot sets player/AI (slot 0 is the human; others AI or closed), faction (with blurb), team, colour, credits and difficulty. Stage stays 8 only in G3a.
  - Match-wide: economy profile, and a victory builder (mode, or a combined AND/OR term list with params, plus Endless).
  - Shows a live `SimWorld.validate_config` reason and a summary line.
- **In-game, per faction:**
  - The build menu comes from `Content.buildable_for(faction)`. Production cards come from the building's `produces`. Hotkeys come from data.
  - The objectives checklist uses role defs (e.g. "Build a Fortified Barracks").
  - Machine HUD labels fuel as "Charge" and shows the recharge radius when a hub is selected.
  - Air units draw with an altitude offset plus a ground shadow. Artillery shells draw as an arc with an impact blast.
  - Ally colours appear in the minimap and in alerts ("Ally under attack").
- **Victory/score panel:** per-team progress for the active terms (territory %, hold-bridge timer, HQs left), and the end screen shows team results.
- Remove remaining hard-coded def names in presentation (objectives, g2 files, main.gd demo code) in favour of roles.
- Extend `tools/ui_playtest.gd` (UI3 may edit it): set up a 3-faction match through the menu, then play the Human B and Machine openings (build barracks-role, train infantry-role) via `--ui-playtest` variants (`--ui-playtest-faction=human_b`).

## 7. Art (ART3-B, ART3-M)
Keep the established style: muted, grounded, readable pixel art, the same iso conventions, team-colour masks, and pivots like the existing sprites. Faction identity must read at 1x:
- **Human B, Industrial:** rust, corrugated iron, riveted plates, brick, smokestacks with soot, welded armour patches, olive-drab and rust-orange accents.
- **Machine, Autonomous Network:** graphite and off-white panels, cyan/teal emissive lights, hexagonal and modular shapes, no windows, glowing seams. Drones hover with a separate ground shadow, and walkers have legs with walk frames.

Each faction needs, at minimum:
- every building in 4 states (built plus 3 construction stages);
- every unit in 8 facings with idle/move/fire (infantry walk_a/walk_b);
- wrecks for vehicles;
- an icon for every production item and building.

Update `tests/test_art.gd` coverage with care: ART3-B owns the test file edits, ART3-M sends test needs to ART3-B via CHANGE_REQUESTS, or adds a separate `tests/test_art_machine.gd`.
