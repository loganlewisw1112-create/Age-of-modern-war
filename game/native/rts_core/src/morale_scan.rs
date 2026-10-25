//! G6 PERF6-4: morale.gd tick FULL loop as one native batch (RtsCombat.morale_scan). An exact port of
//! the GDScript loop (cover test + in_cover write, steady-state exit, _update_unit's supp / pinned /
//! morale writes) for the case the G6 MORALE hook bit is clear (morale_delta == 0.0 for every unit).
//! _break / _rally (orders, paths, events) stay in GDScript: the batch returns the units that need
//! them, in input order; nothing a later unit's update reads is changed by them, so calling them
//! after the batch is the same as calling them inside the loop. The GDScript loop stays the fallback
//! and the hash oracle (native-on == native-off). Deterministic: one pass in input (ascending id) order.

use godot::prelude::*;
use godot::sys;
use std::collections::HashMap;

fn vint(v: &Variant) -> i64 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>(),
        VariantType::FLOAT => v.to::<f64>() as i64,
        VariantType::BOOL => v.to::<bool>() as i64,
        _ => 0,
    }
}

fn vfloat(v: &Variant) -> f64 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>() as f64,
        VariantType::FLOAT => v.to::<f64>(),
        VariantType::BOOL => (v.to::<bool>() as i64) as f64,
        _ => 0.0,
    }
}

/// Variant::get_named (GDScript e.key / e.get(key)); None when the key is missing.
#[inline]
fn gk(e: &Variant, key: &StringName) -> Option<Variant> {
    let mut valid: sys::GDExtensionBool = 0;
    // SAFETY: e and key are live; get_named always initializes r_ret.
    let v = unsafe {
        Variant::new_with_var_uninit(|ptr| {
            sys::interface_fn!(variant_get_named)(e.var_sys(), key.string_sys(), ptr, &mut valid)
        })
    };
    if valid != 0 { Some(v) } else { None }
}

/// GDScript `e.key = value` (Variant::set_named on the shared Dictionary).
#[inline]
fn sn(e: &mut Variant, key: &StringName, value: &Variant) {
    let mut valid: sys::GDExtensionBool = 0;
    // SAFETY: all pointers live for the call.
    unsafe { sys::interface_fn!(variant_set_named)(e.var_sys_mut(), key.string_sys(), value.var_sys(), &mut valid) };
}

/// Math::snapped(double, double)
#[inline]
fn snapped(v: f64, step: f64) -> f64 {
    if step != 0.0 { (v / step + 0.5).floor() * step } else { v }
}

/// Godot CLAMP(a, lo, hi) for doubles (clampf)
#[inline]
fn clampd(a: f64, lo: f64, hi: f64) -> f64 {
    if a < lo { lo } else if a > hi { hi } else { a }
}

/// morale.gd _cover_index + _near_cover over Rect2 (f32) rects [px, py, sx, sy] in source order.
struct Cover {
    rects: Vec<[f32; 4]>,
    buckets: HashMap<i64, Vec<usize>>,
    cr: f64,
    cb: f64,
    stride: i64,
}

impl Cover {
    fn new(flat: &[f32], cr: f64, cb: f64, stride: i64) -> Self {
        let mut rects = Vec::with_capacity(flat.len() / 4);
        let mut buckets: HashMap<i64, Vec<usize>> = HashMap::new();
        let a = cr as f32; // Rect2::grow(real_t)
        let mut i = 0;
        while i + 3 < flat.len() {
            let (px, py, sx, sy) = (flat[i], flat[i + 1], flat[i + 2], flat[i + 3]);
            let ri = rects.len();
            rects.push([px, py, sx, sy]);
            let gx = px - a;
            let gy = py - a;
            let gw = sx + a * 2.0;
            let gh = sy + a * 2.0;
            let (ex, ey) = (gx + gw, gy + gh);
            let by0 = (gy as f64 / cb).floor() as i64;
            let by1 = (ey as f64 / cb).floor() as i64;
            let bx0 = (gx as f64 / cb).floor() as i64;
            let bx1 = (ex as f64 / cb).floor() as i64;
            for by in by0..=by1 {
                for bx in bx0..=bx1 {
                    buckets.entry(bx + by * stride).or_default().push(ri);
                }
            }
            i += 4;
        }
        Cover { rects, buckets, cr, cb, stride }
    }

    fn near(&self, p: Vector2) -> bool {
        let k = (p.x as f64 / self.cb).floor() as i64 + (p.y as f64 / self.cb).floor() as i64 * self.stride;
        let arr = match self.buckets.get(&k) { Some(a) => a, None => return false };
        let lim = self.cr * self.cr;
        for &ri in arr {
            let [px, py, sx, sy] = self.rects[ri];
            let (ex, ey) = (px + sx, py + sy); // Rect2::get_end (real_t)
            let qx = clampd(p.x as f64, px as f64, ex as f64) as f32;
            let qy = clampd(p.y as f64, py as f64, ey as f64) as f32;
            let dx = p.x - qx;
            let dy = p.y - qy;
            let d2 = dx * dx + dy * dy; // Vector2::distance_squared_to (real_t)
            if (d2 as f64) <= lim {
                return true;
            }
        }
        false
    }
}

/// prm = [decay, pin_at, drain, recover, break_at, rally_at, Q, COVER_R, CB, CB_STRIDE,
///        UNDER_FIRE_TICKS, OUT_OF_COMBAT_TICKS, FOREST, md].
/// Returns [need_ids] (no writes) when a live unit with morale has no mmax entry (0.0 = unfilled),
/// else [idx (into units), code (1 = _break, 2 = _rally)] in input order.
#[allow(clippy::too_many_arguments)]
pub fn morale_scan(units: VarArray, ents: VarDictionary, ids: &[i32], mmax: &[f64], terr: &[u8], mw: i64,
                   rects: &[f32], prm: &[f64], tick: i64) -> VarArray {
    let mut out = VarArray::new();
    if prm.len() < 14 {
        return out;
    }
    let (decay, pin_at, drain, recover, break_at, rally_at, q) = (prm[0], prm[1], prm[2], prm[3], prm[4], prm[5], prm[6]);
    let (cr, cb, stride) = (prm[7], prm[8], prm[9] as i64);
    let (under_fire, ooc, forest, md) = (prm[10] as i64, prm[11] as i64, prm[12] as i64, prm[13]);
    let k_id = StringName::from("id");
    let k_morale = StringName::from("morale");
    let k_pos = StringName::from("pos");
    let k_in_cover = StringName::from("in_cover");
    let k_supp = StringName::from("supp");
    let k_pinned = StringName::from("pinned");
    let k_broken = StringName::from("broken");
    let k_supp_tick = StringName::from("supp_tick");
    let use_ids = !ids.is_empty() && ids.len() == units.len();
    let n = units.len();
    // pass 1: liveness + table check (no writes)
    let mut live: Vec<Option<(Variant, i64)>> = Vec::with_capacity(n);
    let mut need: Vec<i32> = Vec::new();
    for i in 0..n {
        let e = units.at(i);
        if e.get_type() != VariantType::DICTIONARY {
            live.push(None);
            continue;
        }
        if gk(&e, &k_morale).is_none() {
            live.push(None);
            continue;
        }
        let id = if use_ids { ids[i] as i64 } else { gk(&e, &k_id).map(|v| vint(&v)).unwrap_or(-1) };
        if !ents.contains_key(&id.to_variant()) {
            live.push(None);
            continue;
        }
        if id < 0 || id as usize >= mmax.len() || mmax[id as usize] == 0.0 {
            need.push(id as i32);
        }
        live.push(Some((e, id)));
    }
    if !need.is_empty() {
        out.push(&PackedInt32Array::from(need.as_slice()).to_variant());
        return out;
    }
    let nterr = terr.len() as i64;
    let mut cover: Option<Cover> = None;
    let (mut ix, mut code): (Vec<i32>, Vec<i32>) = (Vec::new(), Vec::new());
    for (i, slot) in live.into_iter().enumerate() {
        let (mut e, id) = match slot { Some(x) => x, None => continue };
        let pos: Vector2 = gk(&e, &k_pos).and_then(|v| v.try_to::<Vector2>().ok()).unwrap_or(Vector2::ZERO);
        let cx = (pos.x as f64).floor() as i64;
        let cy = (pos.y as f64).floor() as i64;
        let cov = if cx >= 0 && cy >= 0 && cx < mw && cy * mw + cx < nterr && terr[(cy * mw + cx) as usize] as i64 == forest {
            true
        } else {
            if cover.is_none() {
                cover = Some(Cover::new(rects, cr, cb, stride));
            }
            cover.as_ref().unwrap().near(pos)
        };
        sn(&mut e, &k_in_cover, &cov.to_variant());
        let mm = mmax[id as usize];
        let supp0 = gk(&e, &k_supp).map(|v| vfloat(&v)).unwrap_or(0.0);
        let pinned0 = gk(&e, &k_pinned).map(|v| v.booleanize()).unwrap_or(false);
        let broken0 = gk(&e, &k_broken).map(|v| v.booleanize()).unwrap_or(false);
        let m0 = gk(&e, &k_morale).map(|v| vfloat(&v)).unwrap_or(0.0);
        if md >= 0.0 && supp0 <= 0.0 && !pinned0 && !broken0 && m0 >= mm {
            continue;
        }
        // _update_unit
        let since = tick - gk(&e, &k_supp_tick).map(|v| vint(&v)).unwrap_or(-100000);
        let mut supp = supp0;
        if supp > 0.0 && since >= under_fire {
            let d = supp - decay;
            supp = snapped(if d > 0.0 { d } else { 0.0 }, q);
            sn(&mut e, &k_supp, &supp.to_variant());
        }
        let pinned = supp >= pin_at;
        sn(&mut e, &k_pinned, &pinned.to_variant());
        let mut m = m0;
        if pinned {
            m -= drain;
        } else if since >= ooc {
            m += recover;
        }
        m += md;
        m = snapped(clampd(m, 0.0, mm), q);
        sn(&mut e, &k_morale, &m.to_variant());
        if !broken0 && m < break_at {
            ix.push(i as i32);
            code.push(1);
        } else if broken0 && m >= rally_at {
            ix.push(i as i32);
            code.push(2);
        }
        let _ = id;
    }
    out.push(&PackedInt32Array::from(ix.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(code.as_slice()).to_variant());
    out
}
