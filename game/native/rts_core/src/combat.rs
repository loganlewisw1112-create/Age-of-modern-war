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
}
