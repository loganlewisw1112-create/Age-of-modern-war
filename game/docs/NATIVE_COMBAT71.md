# NATIVE_COMBAT71: the full native combat port (G7.1 E2, owner option A)

Owner decision (board `owner.sim_gate.answer`, seq 358): **full native combat port**. The gate is unchanged: the 2k
benchmark sim ms/tick at or below G6 on the same PC (alternating pairs, median). If the port lands and the gate is still
missed, stop and ask the owner again (`owner.sim_gate.ask` with numbers). Author: PERFSIM71-4 (2026-11-08). Successors
update the phase table (section 8) with measured numbers; nothing here is a promise until it has a log line.

## 1. Where the time is (start of the port)

2k fight (river_crossing_s, 600 ticks), loaded PC, medians: G6 34.0 ms/tick, G7.1 49.9 ms (1.71x, `base4_pairs.txt`).
Profiled G7.1 44.2 ms (`runs/prof_g71_b.log`): combat 25.7 (cmb.act 20.5, cmb.np 3.8, cmb.ngrid 1.3), movement 6.0,
morale 2.1, blast8 1.8, fog 1.6, wounds 1.5, supply 1.5, intel 1.1, squad_ai 0.9. G6 profiled 23.5.

Inside cmb.act (20.5): cmb.find 2.8 (f.units 2.1, f.eb 0.5), fire.stray 2.5, fire.dmg 2.2, PERF8_muzzle 1.7 (sidestep 1.15),
fire.resolve 1.6, eng.chase_path 1.2, dmg.near_miss 0.9, PERF8_sq 0.8, accmult 0.4, splash 0.3. The other ~6-7 ms is
GDScript dispatch: _unit_tick / _pick / _valid_target / _engage / _fire early exits for ~150-250 acting units a tick.

Two facts set the design (PERFSIM71-2/-3):
- Prefiltering in native and finishing in GDScript saves nothing (ss_split / mz_cands: ~0.03 ms): the cost is the
  GDScript statements and Dictionary reads per candidate, not the geometry.
- Rust reading entity Dictionaries through `Variant::get_named` (combat_prep.rs `gn`) costs ~1.9-4 us per unit for ~12
  fields. PERFSIM71-4 tried pointer-level reads (`fastdict.rs`, `dictionary_operator_index_const`, no Variant clone) for
  the prep: **no faster** (section 8). Every Dictionary field access costs ~150-250 ns from Rust; the win has to come
  from reading each field once per tick (the mirror) and deleting GDScript work, not from a faster read.

## 2. What combat reads and writes

Per acting unit e (shooter) and per candidate / target c. "Writers" = files that assign the field (grep
`\.<field> *=`, 2026-11-08, sim/): the list shows why write hooks on every field are not an option.

| Field | Read by (combat path) | Writers | During Combat.tick | Mirror strategy |
|---|---|---|---|---|
| id, kind, def, owner | everything | spawn only | fixed | per-tick fill (owner), def -> dx table (cmb_tabs) |
| pos | find, range, LOS, splash, stray | movement + 20 others (air, transport, blast8, ...) | fixed (checked: mirror_check after act) | per-tick fill |
| team / tf flags | find, ally tests | derived (cmb_tabs, rebuilt on team change) | fixed | cmb_tabs |
| air_landed | find flags, can_target | air, vanta7 | fixed | per-tick fill (nflags bit) |
| target | _unit_tick, _pick, act skip | 33 files; combat writes it in the act loop | **volatile** | live read / write-through by the native loop |
| moving, path | _unit_tick, _engage, Accuracy8 | movement + 9; combat via Movement.stop_path / order_path | **volatile** | live read after a callback |
| cd_ticks, cooldown | _unit_tick, _fire | combat (prep countdown + _fire), blast8, morale, wounds, g5_mech | **volatile** (_fire writes) | prep value, write-through |
| order (type, engaged, target_id, bk, lost, last_pos) | _unit_tick dispatch | 40 files; combat in the act loop | **volatile** (own row only) | live read |
| broken | _unit_tick | morale, medical, world, combat | fixed in combat (morale runs before) | per-tick fill (checked) |
| hp, wounded, hid, last_hit_tick, last_attacker, suppression, morale | target validity, Damage, Accuracy8 | damage, wounds, medical, g4b_mech, ... | **volatile** via Damage.apply_hit | the hit set (w.cache.cmb_ev) |
| last_fired_tick | Fog.concealed (forest) | combat, g5_mech, naval | **volatile** (shooter) | shooter row refresh |

The exactness trap (PERFSIM71-2): a value cached at prep time is only exact for a field that nothing writes during the act
loop. Everything marked volatile must be read live (fastdict pointer read: ~tens of ns) or updated in the mirror at the
write. Combat itself already has the right dirty set: `Damage.apply_hit` records every hit entity id in `w.cache.cmb_ev`
(the SIM10K act-skip proof uses it), deaths go through the same path, and the shooter is the only other entity a
`_unit_tick` writes. So after every GDScript callback the native loop refreshes the shooter row, the rows of ids added
to cmb_ev, and drops dead ids.

## 3. The mirror (rts_core 0.6.0, `native/rts_core/src/mirror.rs`)

Owned by the `RtsCombat` object combat.gd already keeps in `w.cache.combat_lc` (never saved, never hashed; a fresh
world builds it again, so save/load and hot_state are unaffected). Rows = the live FULL units of this tick in input
(ascending id) order; `row[id]` maps back. Columns: ids, pos (Vector2 f32, the dict value bit for bit), owner, tf, dx,
target, moving, cd (after the countdown), ocode (0 idle, 1 hold, 2 attack_move, 3 attack, 4 other), broken.

Filled by `RtsCombat.prep_mirror`, a drop-in for `prep_units_ids`: same arguments, same 13-entry result, same writes
(firing - 1, cd_ticks - 1, cooldown = cd / TICK_RATE, same Variant types), same `[need_ids]` no-write early return. Reads:
always-present keys (pos, firing, target, moving, order, owner: set at spawn, never erased, grep 2026-11-08) by
pointer; optional keys (cd_ticks, cooldown, broken, last_hit_tick, air_landed, order.type, order.engaged) through
`variant_get_named` on the element pointer (no clone of the unit or order Dictionary); writes in place through
`dictionary_operator_index`. Order-type compares stay Variant `==` (same semantics as the 0.5.x prep).

Phase 2+ add columns the same way (stats by dx: range, sight, min_range, aa, indirect, builder, armed, is_air, roof,
naval_only, roof_out; then hp/armor for Damage). Building rows (towers act too) come with the act-loop phase.

## 4. Sync strategy

- **Tick-fixed fields** (pos, owner, def, team flags, air_landed, broken): filled once per tick in prep_mirror. Proof:
  `Combat.mirror_debug` runs `_mirror_check` (GDScript reads, independent of the Rust code) right after prep (every
  column vs the Dictionaries) and after the act loop (pos, owner must still match every live row): 0 mismatches expected.
  The after-act pass also counts act-time changes of the volatile columns (`mirror_vol`) so later phases know their size.
- **Volatile fields**: never trusted from the snapshot after the first write. The native act loop (phase 3) is the
  writer of target / cd / order for the shooter it is running (writes go to the Dictionary and the row together); after
  any GDScript callback (fire, Damage, Movement.order_path, Spread8) it re-reads the shooter row and the cmb_ev rows.
- **Write hooks in other systems: none.** Too many writers (section 2) and none of them run inside Combat.tick.

Measured (PERFSIM71-4, `runs/m4_dbg.log`, 2k fight 600 ticks, `sim_ab3.gd --dbg=1`): 899,011 mirror rows, **0
mismatches** at prep and 0 for pos / owner after the act loop (so pos and owner really are tick-fixed in Combat.tick);
volatile changes during the act loop: target 63,793 rows (~106 a tick), cd 17,141, moving 16,175, order code 516,
broken 0. Same hash 8fd794b3 with the check on (it only reads).

## 5. rng draw order

Combat's draws all happen in `_fire` (one `w.rng.chance(acc)`, two `randf_range` on a miss), `Stray8.on_miss` (<= 1),
`Damage.apply_hit` / Wounds / Shrapnel (their own), `_splash`. The act loop runs shooters in ascending id order with
buildings interleaved (`ablds`). A native act loop keeps that order and **calls back into GDScript for every shot**
(phase 3), so every draw still happens in GDScript, on `w.rng`, in the same order. A later phase that ports a draw site
must take the generator state in and give it back (SimRng is a GDScript object: its algorithm is ported bit for bit
and its state written back before any GDScript draw runs), one draw site at a time, each with its own A/B hash.

## 6. Fallback and A/B oracle

Every phase is a static toggle in the owning GDScript file, default on, with the old path kept:
`Combat.native_mirror` (phase 1), later `Combat.native_find`, `Combat.native_act`, ... A missing method (older DLL)
falls back silently. Oracle per phase: native on == off state hash (sim_ab3 `--pm=0|1` style flag), two identical runs,
test_hot_state GOLD / GOLD_FLAT 17/17, tests/test_perfsim71.gd (adds the toggle to PATHS), mirror_debug 0 mismatches.

## 7. Phase order

1. **Mirror + prep (this generation).** prep_mirror replaces prep_units_ids (cmb.np). Exact on its own.
2. **Native target search.** `_find` whole (unit candidates with all filters + enemy-building cells) on mirror columns:
   Fog.concealed_enemy / G4bMech hidden (`hid`) / _g6_hidden / WallFire7.cand_ok fall back to the GDScript _find
   whenever their trigger is present (any `hid` entity of that team, WallFire7.any, a G6 hidden bit, a concealable
   candidate in forest) so the native path covers the common case exactly. Needs: stats columns, visible cells (already
   passed to scan_vis), the eb grid as packed rects. The candidate filter chain to port or guard (in _find order):
   team / range / min range / visible cell (packed already) -> alive -> `Fog.concealed_enemy` (unit with `morale` key:
   `hid` + `spot` team list; `last_fired_tick` within REVEAL_TICKS reveals; `Senses7.hidden(w, fid, c)`; FOREST cell and
   not `_spotted`) -> `G4bMech.hidden_from` (only when `hid`) -> `_g6_hidden` (G6_VIS bit only) -> air / landed / aa ->
   `_g5_ok` (naval_only, wounded, Air.can_target for air) -> `WallFire7.cand_ok` (only when WallFire7.any and the
   shooter is not exempt). Senses7.hidden and _spotted read the senses7 spot state: either port that state as packed
   per-team arrays (rts_core RtsSpot already holds the spot pass) or guard: native returns "fallback" for a candidate
   that has `morale` and is not revealed by firing, and GDScript finishes that one query.
3. **Native act driver.** One call runs the act loop (skip codes, ablds interleave, _unit_tick dispatch for idle / hold /
   attack_move / attack / move-return-fire / bk, _pick, _valid_target, range / LOS (native line_clear + height_los) /
   min range, cooldown / Status gate) and calls a GDScript Callable only to fire (`_fire` body from Traverse7.lay on),
   to chase (`Movement.order_path`), to stop a path, for Spread8.mark and for a building's Cards8a filter. Rows refreshed
   after each callback (section 4).
4. **Fire resolve native**: muzzle_blocked + Accuracy8.mult + Status / Morale / Wounds multipliers as packed columns;
   the hit draw still through the callback until (5).
5. **Draw sites native** (section 5), then Stray8.on_miss, then Damage.apply_hit's common path (armor facing, cover,
   suppression) with Wounds / Shrapnel / Morale hooks as callbacks.
6. **Other systems** (movement 6.0, morale 2.1, blast8 1.8, fog 1.6, wounds 1.5, intel 1.1): the gate needs ~3 ms from here
   as well, whatever combat reaches (PERFSIM71-2 Amdahl).

## 8. Phases: estimate vs measured

Estimates are profiled-ms per tick saved on the 2k fight (profiled totals inflate ~10-15%); measured = paired runs.

| Phase | Estimate (saved) | Risk | Measured | Evidence |
|---|---|---|---|---|
| 1 mirror + prep_mirror | 1.5-2.5 of cmb.np 3.8 | low (drop-in, oracle) | **~0** (cmb.np on 3.57 / 3.97 vs off 3.67 / 3.84, two profiled pairs) | .plan/perfsim71/m4p_pairs.txt, runs/m4p_q* |
| 2 native _find | 2.0 of 2.8 | medium (filters) | **1.5 profiled** (cmb.find off 2.08 / 2.10 -> on 0.57 / 0.58; cmb.act 13.92 / 14.01 -> 12.18 / 12.33; two profiled pairs). Unprofiled medians nf off 29.60 -> on 27.45 ms (4 clean pairs; per-pair -2.9..+4.2, noisy) | .plan/perfsim71/n5p_pairs.txt, runs/n5p_*, oracles runs/n5_* |
| 3 native act driver | 5-7 of the ~7 dispatch; step 0 ceiling 5.9 (4.1 dispatch-only ticks + 1.8 dispatch inside callback ticks) + part of 1.5 loop; **3a** (no-callback ticks only) est. ~3-4 | high (largest exactness surface) | 3a: **1.6 profiled** (cmb.act na0 13.05 -> na1 11.42, one profiled pair; cmb.find 0.61 -> 0.19). Unprofiled medians na0 28.61 -> na1 26.67 ms (3 clean pairs, per pair -1.94 / -2.39 / -1.26); G6 15.95 -> **G7.1 1.67x G6** | .plan/perfsim71/n6p_pairs.txt, runs/n6p_*, oracles runs/o6c_* o6d_*, step 0 runs/s6_pu2.log |
| 4 fire resolve | 2-3 (muzzle 1.7, resolve 1.6, accmult 0.4) | medium | - | - |
| 5 draws + stray + damage | 3-5 (stray 2.5, dmg 2.2, near_miss 0.9) | high (rng, many hooks) | - | - |
| 6 other systems | >= 3 needed | medium | - | - |

**Phase 1 result and what it changes (PERFSIM71-4).** Pointer-level reads did not make prep cheaper: the profiled cmb.np
is the same with prep_mirror and with prep_units_ids (above; unprofiled pairs were too noisy to resolve anything, a
PERFDRAW71 10k run overlapped them). So the hypothesis "Variant clones / get_named are the cost" is falsified: a native
read of one Dictionary field costs ~150-250 ns whatever the method (Godot hashes the String key and walks the HashMap on
every access; ~15 field accesses + 3 writes per unit ~= the ~2.5-3 us/unit measured). Consequences for every later phase:
(a) never refill a column from Dictionaries a second time in a tick: prep already pays one read per field per unit, so
every later native phase must take tick-fixed values from the mirror (they are free now) and read only the volatile
fields live, and only for the units it actually decides on; (b) the saving of phases 2-5 comes from removing GDScript
statements (dispatch, filters, math), not from faster reads, so estimate a phase by the GDScript it deletes minus ~0.2 us
per live Dictionary read it keeps; (c) a cheaper prep needs fewer reads, not faster ones (e.g. a per-unit "unchanged
since last tick" proof) and is not on the critical path.

**Phase 2 as built (PERFSIM71-5, rts_core 0.6.1).** `native/rts_core/src/find.rs`: `RtsCombat.find(eid, radius)` returns
the `_find` pick (unit / building id, -1 none) or -2 = run the GDScript `_find` body. `find_setup([...])` once per tick
in Combat.tick (after the RtsGrid rebuild and the scan pre-batch; combat.gd `_nf_args`) hands it the grid, w.entities,
w.fog, w.map, Senses7 `st.spot`, faction teams + tkeys, the pre-batch (scan_ids, res, scan_r), the per-def columns and the
tick's `blds` (id, owner, cell, size read once). Per-def columns are filled once per def in `_dx_of` (`tabs.dmr` =
min_range, `tabs.dcf` bits 1 is_air, 2 naval_ship, 4 naval_only, 8 roof_out, 16 Senses7 infantry def, 32 unit kind; aa
from `df`). Path for path as `_find`: the pre-batched (or one `nearest_one`) candidate if legal, else the first legal id
of the sorted visible scan (`scan_sorted_buf`, the same code as `scan_vis_sorted`; `nearest_enemy_batch` and
`scan_vis_sorted` now call the shared cores, unchanged), then enemy buildings by (footprint distance, id) with the
f32/f64 math of the GDScript loop (linear over `blds` = the same legal set as the EB_CS cells). Tick-fixed shooter /
candidate values (pos, owner, def index, team) come from the mirror; live reads only for the candidate being decided:
alive, wounded, air_landed (aircraft only), hid, morale, last_fired_tick, the Senses7 spot set, terrain (forest test),
the G6 keys, and per call the shooter's fog `visible`. Rules without a native port return -2 when they could decide:
`hid` truthy (spot lists), an unrevealed soldier on FOREST (`Fog._spotted`), an aircraft (`Air.can_target`), a G6 key
present (submerged / camo_net / cloak_hid / garrisoned_in, units and buildings), a roof_out shooter, no mirror row /
grid index / columns. Per-tick guards in combat.gd (no find_setup that tick): `WallFire7.any(w)` (so the LP map, which
has facility walls, stays on GDScript), `SimIndex.g6_spy`, `scan_ab`. Toggle `Combat.native_find` (default on);
`native_find_ab` asks both and counts differing picks. Oracles (`.plan/perfsim71/sim_ab4.gd`, runs/n5_*.log): same
hash nf 0 / 1 / 1 / ab on the 2k fight (8fd794b3), 2k mixed (a1e5af17) and 10k fight 200 ticks (41b5f765); per-call
compare 74,552 + 46,181 + 14,147 calls, **0 diffs, 0 fallbacks** (none of the three benches has a forest-concealed,
hid, air or G6-key candidate, so the -2 paths are exercised only by construction); test_perfsim71 5/0 with native_find
in PATHS, test_hot_state 17/0 with it on (t5_test_perfsim71.log, t5b_test_hot_state.log).

Honest total (start of the port, PERFSIM71-4): phases 1-5 at their estimates remove ~14-19 profiled ms of combat's 25.7,
i.e. G7.1 ~1.25-1.35x G6 before phase 6. The gate needs phase 6 too. Expected generations: 1 (phase 1) + 1 (2) + 2-3 (3)
+ 1 (4) + 2-3 (5) + 1-2 (6).

**Updated projection after phase 2 (PERFSIM71-5, clean pairs 17:44-17:54Z 2026-11-08, `n5p_pairs.txt`).** The PC ran
faster than at the start of the port (G6 median 14.82 ms on 3 clean runs vs ~21-22 earlier), so compare ratios, not ms:
G7.1 with phases 1+2 = 27.45 ms = **1.85x G6**; the gate needs -12.6 ms unprofiled (~46% of the tick). Phases 1+2
measured ~1.5 profiled ms against a 3.5-4.5 estimate (phase 1 ~0, phase 2 ~75% of its own). Today's profiled cmb.act
(nf on) is 12.2 ms vs 20.5 at the start, so the phase 3-5 estimates (10-15 at the start scale) are roughly 6-9 ms on
today's numbers if they land; at phase 2's hit rate 4.5-7 ms. G7.1 after phases 3-5: ~18.5-23 ms = **1.25-1.55x G6**;
the remaining >= 3.5-8.5 ms must come from phase 6 (movement, morale, blast8, fog, wounds, supply, intel). The gate
therefore needs every remaining combat phase at or near its estimate AND deep exact cuts outside combat. Generations
left: 2-3 (3) + 1 (4) + 2-3 (5) + 1-2 (6) = 6-9.

**Phase 3 design notes (for the next generation).** Measure the ceiling first: `Combat.prof_units` (bench) times each
`_unit_tick` by order type; the phase-3 saving is only the dispatch that does NOT end in `_fire` / `Movement.order_path`
(those stay GDScript callbacks in phase 3). If that dispatch share is under ~3 profiled ms, the 5-7 ms estimate is wrong:
report before building. Build: `RtsCombat.act(...)` runs the act loop (act_ix / act_id / askip / atg from prep, `ablds`
interleaved through a GDScript Callable for buildings), native for idle / hold / attack_move units: broken -> target -1;
the `_unit_tick` fast paths; `_pick` (current-target keep: a native `_valid_target` port or a Callable, `dist_to`,
`_scan_due`, then phase 2's find); writes target / order.engaged through `dset` on the Dictionary and the row together.
Callables (whole unit, exact by construction): ot == "attack" (`_attack_order`), builders, return-fire / bk move orders,
a live G6_RANGE bit (`_rm` != 1 on raised cells / WallWalk7), `wallwalk7` state or a parked CN team, `_fire`, `_engage`'s
chase. After every Callable refresh the shooter row and the `w.cache.cmb_ev` rows (section 4). Oracle as phase 2: a
`native_act` toggle, hash x2 on/off on 2k fight / mixed / 10k, plus a per-unit write log compare (target, order, cd)
over 600 ticks.

**Phase 3 step 0 (PERFSIM71-6, clean run `runs/s6_pu2.log`, other_godot 0/0, cpu 16% / 15%; `s6_pu1` discarded: it overlapped
a test_perfdraw71 run).** `combat.gd` prof_units now splits every profiled `_unit_tick` into `u.<type>[.t][.mv].F` (it reached a
phase-3 callback: `_fire` from Traverse7.lay on, or the chase `Movement.order_path`, read from the PU_CB_KEYS profile deltas)
and `.D` (dispatch only), plus `pu.cb.<type>` = the callback time inside the .F ticks (`.plan/perfsim71/pusplit.py`). Profiled
ms/tick: `_unit_tick` total 13.11, callbacks that stay GDScript 7.16, dispatch-only ticks of idle / hold / attack_move 4.10,
dispatch inside the callback ticks 1.80, act loop + buildings outside `_unit_tick` 1.50 (minus 1.44 of the split's own
wrapper cost), native work nested in the dispatch (cmb.find + cmb.los) 0.77. attack_move dominates (D 3.01, F-dispatch 1.50).
Ceiling ~5.4-6.6 >= 3: build. The 2k fight runs with the G6 RANGE, LOS and VIS bits live (g6m = 687, `.plan/perfsim71/na_probe.gd`),
so `_rm`, `_hlos` and `visible_to` had to be handled, not guarded off.

**Phase 3a as built (PERFSIM71-6, rts_core 0.6.2, `native/rts_core/src/act.rs`, a child module of find.rs).** `RtsCombat.act_setup(args)`
once per tick after find_setup (combat.gd `_na_setup`) and `act_run(i0, stop_id)`: runs the act entries in order and returns
2j (stop: an armed building with a lower id acts first; GDScript runs the `ablds` interleave as before), 2j+1 (entry j goes to
the GDScript body `_act_one`, a line-for-line copy of the loop body; nothing of it was written) or 2n (done). An entry is
finished natively only when its whole body is decided by ported rules and writes at most `target` and `order.engaged = true`:
dead / skip codes / nores skips, every `_unit_tick` early exit, broken, the PERF4-2 fast paths, and for idle / hold /
attack_move the `_pick` (current-target keep through a native `_valid_target`: mirror pos / owner, is_enemy, fog cell, find.rs
`legal()`; scan slots; phase 2's find) followed by an `_engage` / hold outcome that ends without a callback (in range with LOS
`line_clear_core` + `height_los_core` and `_cd > 0`; out of range, still moving, no repath due). Everything else hands the whole
unit back BEFORE any write: a shot past the cooldown gate (d_fire), a chase repath / min-range back-off (d_chase), stop_path
(d_stop), an order rewrite (d_order), attack orders / builders / move-class orders (d_attack), a possible Spread8.mark (d_sp8:
no sp8 key, Accuracy8 infantry def, spread on), G6_RANGE with s7 / wall-walk state / a raised cell (d_range), a building /
structure / marked / hid / forest / air / G6-key / REDUCED target (d_valid), find == -2 (d_find). Per-tick guards: native find
live (WallFire7.any, G6 spy, scan_ab), G6_LOS only with the native height LOS (`native_elev` + ng.hl), WallFire7.blocked at
its cheap false exit (`Fortify._los_mask == null`), not prof_units / native_find_ab. Per-def columns `tabs.dar` / `das`
(float64 range / sight) and `daf` (1 indirect, 2 Accuracy8 infantry profile rule) in `_dx_of`. Toggle `Combat.native_act`
(default on); `native_act_ab` (bench) undoes each native result, runs the GDScript body and compares the whole shooter
Dictionary (`var_to_str`).
Oracles (`.plan/perfsim71/orc6.sh`, `sim_ab4.gd --na=0|1 --naab=1`): same hash na0 / na1 / naab on the 2k fight (8fd794b3,
runs/o6c_f_na1, o6c_f_naab, o6d_f_na0), 2k mixed (a1e5af17, o6d_mx_*), 10k fight 200 ticks (41b5f765, o6d_k10_na1 / naab;
na0 = phase 2's reference, not rerun); whole-shooter compare 426,155 + 758,761 + 607,365 natively finished entries, **0 diffs**,
0 SCRIPT ERRORs; test_perfsim71 5/0 with native_act in PATHS (t6_test_perfsim71.log), test_hot_state 17/0 (t6_test_hot_state.log).
2k fight NASTATS: 489,399 entries, 426,770 native (285,408 skips, 54,141 fast exits, 87,221 picks), 62,629 handed back
(d_sp8 24,195, d_fire 16,863, d_stop 9,355, d_attack 6,249, d_chase 5,076, d_order 871, d_range 20).
**Phase 3a measured (PERFSIM71-6, `n6p_pairs.txt`, ~18:50-19:03Z 2026-11-08, 11 runs + pu3, every run other_godot 0/0,
quiet-gated).** Unprofiled ms/tick: G6 15.95 / 15.98 / 15.73 (median 15.95), G7.1 native_act on 26.67 / 26.84 / 26.26 (26.67),
off 28.61 / 29.23 / 27.52 (28.61): phase 3a saves ~1.9 unprofiled, 1.6 profiled ms (cmb.act 13.05 -> 11.42), against its
3-4 ms estimate = ~45-55 %, at the "under half" line of the brief; so PERFSIM71-6 posted owner.sim_gate.ask instead of starting
phase 3b. The step-0 rerun on the same PC (`runs/n6p_pu3.log`, clean) confirms the ceiling: dispatch 5.64 (3.92 + 1.72), loop
outside `_unit_tick` 1.33. Why 3a is below its ceiling: (1) 62,629 of 489,399 entries a run still go back to GDScript and pay
the native decision first (d_sp8 24,195 is the largest: units without `sp8` re-run in GDScript every engage); (2) the native
decision is not free: ~8-12 live Dictionary reads per finished unit (~0.2 us each, the phase 1 finding) plus the act_run
round trip per handed-back entry; (3) the callback ticks' own dispatch (1.7) is untouched by 3a.

**Updated projection after phase 3a.** G7.1 = 26.67 ms = 1.67x G6 (15.95); the gate needs -10.7 ms unprofiled (~40 % of the
tick). Left in combat at the hit rate measured so far (~50 % of estimates): 3b (callback-tick dispatch + Spread8 / stop_path /
fire hand-backs done natively with callbacks, ceiling ~2.5) ~1-1.5, phase 4 (fire resolve, est. 2-3) ~1-1.5, phase 5 (draws /
stray / damage, est. 3-5) ~1.5-2.5: ~3.5-5.5 ms -> G7.1 ~21-23 ms = **1.3-1.45x G6** after phase 5, so phase 6 (systems outside
combat: movement, morale, blast8, fog, wounds, supply, intel) would have to find another ~5.5-7.5 ms exactly. Generations left
at this rate: 1 (3b) + 1 (4) + 2-3 (5) + 2-3 (6) = 6-8, with the gate not yet in sight. Next step if the owner continues:
phase 3b, first d_sp8 (port Spread8.can_open + mark as a callback that keeps the native result), then the fire / chase
callbacks (call `_fire` / `Movement.order_path` from Rust through a Callable after the native writes), measured the same way.

## 9. Phase 6 probe (PERFSIM71-7, 2026-11-09, owner answer2 "Probe other systems first")

**Method.** 2k fight (river_crossing_s, 600 ticks), quiet PC (CPU < 30 % twice, 0 other godot before every run;
`perfsim71.timing_batch` posted). Per-system timers: `tools/perf71_prof.gd` run in both trees (G6 worktree 979a6d8 and
g71), alternating, 2 pairs (`.plan/perfsim71/p7/a_s1_*`, `a_s2_*`, script `prof7.sh`, out `p7/a.out`). Sub-timers inside the
non-combat systems: `.plan/perfsim71/probe7.gd` replicates the morale / blast8 / intel / squad_ai ticks statement for
statement with timers between the calls and switches Movement.profile / SimIndex.profiling on only around movement,
wounds, fog and supply (combat runs unprofiled); its final hash equals the plain run's on every run (8fd794b3d43ae31d,
`p7/pa_r1`, `pa_r2`, `pb_r1`). All numbers are profiled ms per tick (per-system timers only: G6 18.11 vs G7.1 26.86 in this
session, 1.48x; the clean unprofiled anchor stays section 8's 15.95 vs 26.67, 1.67x, measured in another session).

| System | G6 | G7.1 | Gap | What the G7.1 time is (probe7) | New G6.1/G7 work vs same work |
|---|---|---|---|---|---|
| combat | 12.29 | 14.38 | +2.09 | native find + act on (phases 2, 3a) | same work, more of it (A5 speed, G7 per-shot rules) |
| blast8 | - | 1.32 | +1.32 | `_unc_pass` 1.26-1.30 for ~154 unconscious soldiers a tick (8.4 us each: re-freeze + HotState.touch every tick), `_fl_pass` 0.07 (~4 flying), dz 0.01 | all new (G7 BLAST8) |
| movement | 2.80 | 3.92 | +1.12 | Spread8 radii `PERF8_sp8b` 1.17 (~487 marked units a tick, ~2.4 us each), `PERF8_g6speed` 0.16, ng_call 1.10, apply 0.81, native_step 0.55, drain 0.34 | new ~1.3 (sp8b + g6speed); the rest is the same gather / apply / path queue doing more (G6 ng_call 0.57, apply 0.52, drain 0.19 in the --sub pair) |
| wounds | - | 1.08 | +1.08 | wd.vis 0.46, wd.care 0.25, wd.auto 0.20, wd.bleed 0.18 | all new (G7 WOUND7) |
| morale | 0.47 | 1.47 | +1.00 | realism pass 0.86-0.93 (~45 units a tick, ~19 us each: fatigue, XP, mvm / rz terms; 0 leader candidates in this bench), Veterancy.on_tick 0.08, objectives 0.05, full loop 0.44-0.46 (G6 0.29) | new ~0.95 (G6.1 REAL61 + G7 terms), same ~0.15 |
| intel | - | 0.74 | +0.74 | 60 refreshes a run (~7.3 ms each, a spike every 10 ticks): the visible-enemy list 0.43 (G6's bench never builds it), the book loop 0.28 | all new (G6.1 command) |
| squad_ai | - | 0.63 | +0.63 | ~150 thinks a tick (58 with a target), ~4.5 us each | all new (G6.1 / G7 SQUAD7) |
| fog | 0.58 | 1.03 | +0.45 | Senses7 0.45-0.51 (spot 0.22-0.24), gather 0.40-0.47 (G6 0.33) | new ~0.45 (G7 SENSE7), same ~+0.05 |
| _cmds | 0.11 | 0.24 | +0.13 | command validate / apply | same work, more commands |
| command_net | - | 0.13 | +0.13 | | new |
| veh_drive7 | - | 0.06 | +0.06 | | new |
| ~60 small systems | 0.36 | 0.51 | +0.15 | each < 0.02 (mostly empty G7 ticks) | mostly new |
| supply / economy / victory | 1.49 | 1.34 | -0.16 | | same |
| **total** | **18.11** | **26.86** | **+8.75** | outside combat **+6.66** | **~6.1 new work, ~0.5 same work done more** |

**What this changes.** Outside combat is now the larger part of the gap (6.7 of 8.75 profiled ms; combat is +2.1 after
phases 2 + 3a). But ~6.1 ms of it is G6.1 / G7 features that G6 does not have at all (blast8, wounds, intel, squad_ai,
Senses7, Spread8 radii, the morale realism pass, command_net), and each of them is a per-unit GDScript loop already at
the Dictionary-read floor (~0.16 us per read in GDScript, ~0.2 us from Rust: section 8's lesson), so neither "skip when
unchanged" (no change tracking; write hooks were rejected in section 2) nor a native port (same reads) removes much.

**Cuts tried (built, exact, toggle, measured).**
Cut 1 `Fog.lean_vis` (fog.gd `_g6_vis`, used by `entity_visible` and `enemy_visible`): G6Hooks.visible_to returns true
without its four-call hook chain when the entity has none of `submerged` / `camo_net` / `cloak_hid` / `garrisoned_in` (the
first test of each hook; a test spy runs the real chain). Exact by construction. Oracles before the run was stopped: 2k
fight on / off **same hash 8fd794b3** (`p7/c7_f1.log`, `c7_f0.log`), 2k mixed on **a1e5af17** = the reference (`c7_m1.log`);
2k mixed off, 10k 200t, test_hot_state, test_perfsim71 and the timing pairs **not run** (the PC was loaded by another
session's 12-process python job, avg 60-91 ms/tick, and the budget hand-off came). Expected saving (from probe7): a share
of intel's visible-enemy list (0.43) plus other entity_visible callers, ~0.05-0.15 ms: **unmeasured**. **Not installed**:
the live fog.gd is back to today's code (backup `.plan/perfsim71/chk/fog.gd.orig7`); the parse-checked patched file is
`.plan/perfsim71/chk/fog.gd` for the successor (finish the oracles + tests with `.plan/perfsim71/cut7.sh`, then install).
No other cut was built: the probe showed no single exact cut outside combat worth more than ~0.3 ms.

**The rest, estimated (raw saving -> at the 50-75 % hit rate of phases 1-3a).**
| Cut | Raw | Discounted | Why not more |
|---|---|---|---|
| blast8 `_unc_pass`: inline `_freeze` + the HotState.touch fast path for an already-frozen soldier (cd_ticks is rewritten every tick because Combat counts it down, so the touch cannot be skipped exactly) | 0.3-0.4 | 0.2-0.3 | the writes are real; only call overhead goes |
| movement `_sp8_apply`: per-id def radius cache, test order | 0.2-0.3 | 0.1-0.2 | ~15 reads per marked unit per tick are needed for the exact test; an "unchanged" proof needs write hooks |
| morale realism pass: per-def / per-tick caches (rest points, trait weights, leader-def), bucket list instead of the 900-id modulo scan | 0.2-0.4 | 0.1-0.3 | fatigue / XP / mvm writes are per unit by design |
| intel book loop (0.28) + the rest of the visible-enemy list after cut 1 | 0.1-0.2 | 0.05-0.15 | the list is new work Intel needs |
| wounds: wd.vis due ids bucketed by id % 4, care / auto loops | 0.15-0.3 | 0.1-0.2 | |
| squad_ai: widen the exact early-out | 0.1-0.2 | 0.05-0.15 | units with a target or a squad must think |
| Senses7 spot pass | 0.1-0.2 | 0.05-0.15 | |
| movement same-work (ng_call / apply / drain above G6) | 0.2-0.3 | 0.1-0.2 | mostly the A5 x1.2 workload |
| **sum not built** | **1.4-2.3** | **0.8-1.7** | |

**Verdict.** Phase 6 can realistically deliver **~1-2 ms** of exact cuts outside combat (cut 1 unmeasured, ~0.05-0.15 expected, + 0.8-1.7 estimated for the rest),
**not ~5 ms**: the outside-combat gap is real (6.7 ms) but it is new feature work, not old work done slower. Combined with
the combat projection (phases 3b-5: -3.5 to -5.5 profiled ms at the hit rate so far, which would take combat below G6's
own 12.3), G7.1 lands at about 26.9 - (3.5..5.5) - (1..2) = **19.4-22.4 profiled ms = 1.07-1.24x G6** in this session's
profiled terms (and nearer 1.2-1.4x by section 8's unprofiled ratio). **G6 is reached only if every remaining combat phase
lands at or above its full estimate and phase 6 at its top**, after ~7-9 more generations; on the record so far (phases at
~50 % of estimate) it is not reachable with exact cuts. Closing the last 1.5-4 ms would need option D (behaviour-equivalent
approximations through tiers.gd for big fights) or a restated gate.
