//! RtsCombat: stateless line-of-fire helpers for combat.gd / damage.gd (G3b N1-core-3).
//! line_clear() is an exact port of damage.gd `line_clear` (Amanatides-Woo supercover walk; at an
//! exact cell corner both side cells are tested; any RIDGE, BUILDING or CLIFF cell (G4) or off-map cell blocks). GDScript math
//! is reproduced bit for bit: `to - from` is a Vector2 (f32) subtraction, everything after is f64.
//! line_clear_batch() runs many pairs in one call (input order, no state).

use godot::prelude::*;

#[inline]
fn blocks(terr: &[u8], mw: i32, mh: i32, x: i32, y: i32, ridge: u8) -> bool {
    if x < 0 || y < 0 || x >= mw || y >= mh {
        return true;
    }
    let i = (y * mw + x) as usize;
    i >= terr.len() || terr[i] == ridge || terr[i] == 8 || terr[i] == 12 // G4: RIDGE, BUILDING, CLIFF block LOS
}

/// G6 (PERF6): exact port of Elevation.los_map (ELEV, sim/systems/elevation.gd): cell traversal from a to
/// b (f32 vector difference, f64 stepping, as GDScript); blocked when a cell strictly between the end
/// cells holds a level above the higher endpoint level. Out-of-map cells count as plain (1).
pub fn height_los_core(hg: &[u8], mw: i32, mh: i32, max_level: i32, a: Vector2, b: Vector2) -> bool {
    let lvl = |x: i32, y: i32| -> i32 {
        if x < 0 || y < 0 || x >= mw || y >= mh { 1 } else { hg.get((y * mw + x) as usize).copied().unwrap_or(1) as i32 }
    };
    let (mut cx, mut cy) = (a.x.floor() as i32, a.y.floor() as i32);
    let (ex, ey) = (b.x.floor() as i32, b.y.floor() as i32);
    let top = lvl(cx, cy).max(lvl(ex, ey));
    if top >= max_level || (cx == ex && cy == ey) {
        return true;
    }
    let d = b - a;
    let (dx, dy) = (d.x as f64, d.y as f64);
    let (ax, ay) = (a.x as f64, a.y as f64);
    let sx = if dx > 0.0 { 1 } else { -1 };
    let sy = if dy > 0.0 { 1 } else { -1 };
    let tdx = if dx == 0.0 { f64::INFINITY } else { (1.0 / dx).abs() };
    let tdy = if dy == 0.0 { f64::INFINITY } else { (1.0 / dy).abs() };
    let mut tmx = f64::INFINITY;
    if dx > 0.0 { tmx = ((cx + 1) as f64 - ax) * tdx; } else if dx < 0.0 { tmx = (ax - cx as f64) * tdx; }
    let mut tmy = f64::INFINITY;
    if dy > 0.0 { tmy = ((cy + 1) as f64 - ay) * tdy; } else if dy < 0.0 { tmy = (ay - cy as f64) * tdy; }
    let mut n = (ex - cx).abs() + (ey - cy).abs();
    while n > 0 {
        if tmx < tmy { cx += sx; tmx += tdx; } else { cy += sy; tmy += tdy; }
        n -= 1;
        if cx == ex && cy == ey {
            break;
        }
        if cx >= 0 && cy >= 0 && cx < mw && cy < mh && hg.get((cy * mw + cx) as usize).copied().unwrap_or(0) as i32 > top {
            return false;
        }
    }
    true
}

pub fn line_clear_core(terr: &[u8], mw: i32, mh: i32, ridge: u8, from: Vector2, to: Vector2) -> bool {
    let (mut cx, mut cy) = ((from.x as f64).floor() as i32, (from.y as f64).floor() as i32);
    let (ex, ey) = ((to.x as f64).floor() as i32, (to.y as f64).floor() as i32);
    if blocks(terr, mw, mh, cx, cy, ridge) {
        return false;
    }
    let d = to - from; // f32, as in GDScript
    let (dx, dy) = (d.x as f64, d.y as f64);
    let sx = if dx > 0.0 { 1 } else { -1 };
    let sy = if dy > 0.0 { 1 } else { -1 };
    let tdx = if dx == 0.0 { f64::INFINITY } else { (1.0 / dx).abs() };
    let tdy = if dy == 0.0 { f64::INFINITY } else { (1.0 / dy).abs() };
    let mut tmx = f64::INFINITY;
    if dx > 0.0 {
        tmx = ((cx + 1) as f64 - from.x as f64) * tdx;
    } else if dx < 0.0 {
        tmx = (from.x as f64 - cx as f64) * tdx;
    }
    let mut tmy = f64::INFINITY;
    if dy > 0.0 {
        tmy = ((cy + 1) as f64 - from.y as f64) * tdy;
    } else if dy < 0.0 {
        tmy = (from.y as f64 - cy as f64) * tdy;
    }
    let mut n = (ex - cx).abs() + (ey - cy).abs();
    while n > 0 {
        if (tmx - tmy).abs() < 1e-9 {
            if blocks(terr, mw, mh, cx + sx, cy, ridge) || blocks(terr, mw, mh, cx, cy + sy, ridge) {
                return false;
            }
            cx += sx;
            cy += sy;
            tmx += tdx;
            tmy += tdy;
            n -= 2;
        } else if tmx < tmy {
            cx += sx;
            tmx += tdx;
            n -= 1;
        } else {
            cy += sy;
            tmy += tdy;
            n -= 1;
        }
        if blocks(terr, mw, mh, cx, cy, ridge) {
            return false;
        }
    }
    true
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsCombat {}

#[godot_api]
impl RtsCombat {
    /// Exact damage.gd line_clear: false if the segment crosses a `ridge` cell or leaves the map.
    /// terrain = w.map.terrain (map_w * map_h codes). Passing the PackedByteArray costs no copy.
    /// G6 (PERF6): Elevation.los (height line of sight) in native; == Elevation.los_map bit for bit.
    #[func]
    fn height_los(&self, map_w: i32, map_h: i32, height: PackedByteArray, max_level: i32, from: Vector2, to: Vector2) -> bool {
        height_los_core(height.as_slice(), map_w, map_h, max_level, from, to)
    }

    #[func]
    fn line_clear(&self, map_w: i32, map_h: i32, terrain: PackedByteArray, ridge: i32, from: Vector2, to: Vector2) -> bool {
        line_clear_core(terrain.as_slice(), map_w, map_h, ridge as u8, from, to)
    }

    /// line_clear for every pair i (from[i] -> to[i]); returns 1 clear / 0 blocked per pair.
    #[func]
    fn line_clear_batch(&self, map_w: i32, map_h: i32, terrain: PackedByteArray, ridge: i32,
                        from: PackedVector2Array, to: PackedVector2Array) -> PackedByteArray {
        let t = terrain.as_slice();
        let (f, g) = (from.as_slice(), to.as_slice());
        let n = f.len().min(g.len());
        let mut out = vec![0u8; n];
        for i in 0..n {
            out[i] = line_clear_core(t, map_w, map_h, ridge as u8, f[i], g[i]) as u8;
        }
        PackedByteArray::from(out.as_slice())
    }

    /// Cooldown/firing-hint step for many shooters in one call (combat.gd tick prep): per i,
    /// cd[i] = max(cd[i] - dec, 0) and firing[i] = max(firing[i] - dec, 0). Returns cd then firing
    /// concatenated (2n ints) so a caller writes back only the entries that changed.
    #[func]
    fn countdown(&self, cd: PackedInt32Array, firing: PackedInt32Array, dec: i32) -> PackedInt32Array {
        let (c, f) = (cd.as_slice(), firing.as_slice());
        let mut out = Vec::with_capacity(c.len() + f.len());
        out.extend(c.iter().map(|&v| (v - dec).max(0)));
        out.extend(f.iter().map(|&v| (v - dec).max(0)));
        PackedInt32Array::from(out.as_slice())
    }

    /// SIM10K (rts_core 0.3.1): combat.gd tick prep for the FULL unit list in ONE call. Reads each
    /// unit Dictionary (id, pos, firing, cd_ticks/cooldown, target, broken, moving, order.type,
    /// last_hit_tick, order.engaged), applies the same firing / cooldown countdown writes as the
    /// GDScript prep (same Variant types: int firing, int cd_ticks, float cooldown = cd / trf), and
    /// returns the per-tick RtsGrid inputs, the scan-slot pre-batch and the act list.
    /// Per-id tables (combat.gd cmb_tabs, owner/def never change): tf (team flags, 0 = unfilled) and
    /// dx (def index) into d_range / d_search (f32, as PackedFloat32Array.append stores them) and
    /// d_flags (1 anti_air, 2 armed, 4 builder).
    /// Returns [need_ids] alone (no writes done) when some live unit has tf == 0; else
    /// [nids, npos, nteam, nflags, nidx, scan_src, scan_r, scan_need, scan_ids, act_idx, act_code, act_tg]
    /// where the act list holds every live unit (input order) whose skip code is not 1
    /// (codes: 0 call _unit_tick, 2 no-op unless its target act_tg is hit, 3 no-op unless it is hit).
    #[func]
    fn prep_units(&self, units: VarArray, ents: VarDictionary, tick: i64, tf: PackedInt32Array, dx: PackedInt32Array,
                  d_range: PackedFloat32Array, d_search: PackedFloat32Array, d_flags: PackedInt32Array,
                  next_id: i64, trf: f64, scan_every: i64, ret_fire: i64) -> VarArray {
        crate::combat_prep::prep_units(units, ents, tick, tf, dx, d_range, d_search, d_flags, next_id, trf, scan_every, ret_fire)
    }

    /// CORE10K-2 (rts_core 0.4.2): prep_units with `ids` parallel to `units` (pass 1 reads no dict)
    /// and tabs = [tf, dx, d_range, d_search, d_flags]. Returns prep_units' list plus act_ids (13 entries)
    /// when ids match units, else exactly prep_units' result.
    #[func]
    fn prep_units_ids(&self, units: VarArray, ents: VarDictionary, ids: PackedInt32Array, tick: i64, tabs: VarArray,
                      next_id: i64, trf: f64, scan_every: i64, ret_fire: i64) -> VarArray {
        let pi = |j: usize| -> PackedInt32Array { tabs.at(j).try_to::<PackedInt32Array>().unwrap_or_default() };
        let pf = |j: usize| -> PackedFloat32Array { tabs.at(j).try_to::<PackedFloat32Array>().unwrap_or_default() };
        crate::combat_prep::prep_units_ids(units, ents, ids.as_slice(), tick, pi(0), pi(1), pf(2), pf(3), pi(4), next_id, trf, scan_every, ret_fire)
    }

    /// G6 PERF6-4 (rts_core 0.5.1): morale.gd FULL-loop batch (G6 MORALE bit clear). ids parallel to
    /// units (or empty), mmax per id (0.0 = unfilled), terr = w.map.terrain, mw = map width, rects =
    /// cover Rect2s [px, py, sx, sy] (f32, _cover_index source order), prm = [decay, pin_at, drain,
    /// recover, break_at, rally_at, Q, COVER_R, CB, CB_STRIDE, UNDER_FIRE_TICKS, OUT_OF_COMBAT_TICKS,
    /// FOREST, md]. Returns [need_ids] (no writes) or [idx, code] (1 _break, 2 _rally), input order.
    #[func]
    fn morale_scan(&self, units: VarArray, ents: VarDictionary, ids: PackedInt32Array, mmax: PackedFloat64Array,
                   terr: PackedByteArray, mw: i64, rects: PackedFloat32Array, prm: PackedFloat64Array, tick: i64) -> VarArray {
        crate::morale_scan::morale_scan(units, ents, ids.as_slice(), mmax.as_slice(), terr.as_slice(), mw,
                                        rects.as_slice(), prm.as_slice(), tick)
    }

    /// G6 PERF6-4 (rts_core 0.5.1): fog.gd recompute source gather (G6 SIGHT hook not running). lists =
    /// the gather lists (building list last), rmap[fid] = source slot of the fid's root (-1 = skip),
    /// usight / bsight = fog.gd def -> sight caches, uair = unit def -> is_air, jm[fid] = Status.jam_mult,
    /// hb = height bytes when the height term applies (else empty), prm = [mw, mh, PLAIN, sight_per_level,
    /// tick]. Returns [need entity dicts] or [cells, sights] per slot (first-wins key order).
    #[func]
    fn fog_gather(&self, lists: VarArray, ents: VarDictionary, rmap: PackedInt32Array, nslots: i64, usight: VarDictionary,
                  bsight: VarDictionary, uair: VarDictionary, jm: PackedFloat64Array, hb: PackedByteArray,
                  prm: PackedFloat64Array) -> VarArray {
        crate::fog_gather::fog_gather(lists, ents, rmap.as_slice(), nslots, usight, bsight, uair, jm.as_slice(),
                                      hb.as_slice(), prm.as_slice())
    }
}
