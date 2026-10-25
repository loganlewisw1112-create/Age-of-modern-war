//! G6 PERF6-4: fog.gd recompute source gather as one native batch (RtsCombat.fog_gather). An exact port
//! of the GDScript gather loop for the case the G6 SIGHT hook does not run (sight split: the packed
//! height term only): per-def sight (fog.gd _usight / _bsight), Status.sight_mult (comp.sensors and
//! jammed_until x the owner's jam_mult), the Elevation.sight_bonus height term (map_level - PLAIN levels
//! x sight_per_level, aircraft none), the stamp key and the first-wins source per key and team root.
//! Lists, entities and keys are visited in the GDScript order, so every root's sources come out in the
//! Dictionary insertion order the GDScript gather produces. Deterministic; the GDScript loop stays the
//! fallback and the hash oracle.

use godot::prelude::*;
use godot::sys;
use std::collections::HashSet;

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

/// lists: the GDScript gather lists (unit lists of active owners, then the building list LAST).
/// rmap[fid] = source slot of the fid's team root when that root is gathered this phase, else -1.
/// usight / bsight: fog.gd sight caches (def -> float); uair: unit def -> is_air.
/// jm[fid] = Status.jam_mult(w, fid). hb = w.map.height when the height term applies, else empty.
/// prm = [mw, mh, PLAIN, sight_per_level, tick].
/// Returns [need (Array of entity dicts whose def is missing from a cache)] or, per slot,
/// [cells (PackedInt32Array, key >> 7), sights (PackedFloat64Array)] concatenated (2 entries per slot).
#[allow(clippy::too_many_arguments)]
pub fn fog_gather(lists: VarArray, ents: VarDictionary, rmap: &[i32], nslots: i64, usight: VarDictionary,
                  bsight: VarDictionary, uair: VarDictionary, jm: &[f64], hb: &[u8], prm: &[f64]) -> VarArray {
    let mut out = VarArray::new();
    if prm.len() < 5 || nslots < 0 {
        return out;
    }
    let (mw, mh, plain, spl, tick) = (prm[0] as i64, prm[1] as i64, prm[2] as i64, prm[3], prm[4] as i64);
    let k_owner = StringName::from("owner");
    let k_id = StringName::from("id");
    let k_def = StringName::from("def");
    let k_comp = StringName::from("comp");
    let k_jam = StringName::from("jammed_until");
    let k_pos = StringName::from("pos");
    let k_sensors = StringName::from("sensors");
    let ns = nslots as usize;
    let nl = lists.len();
    // pass 1: every def the gather will read must be cached (no output until it is)
    let mut need = VarArray::new();
    let mut picked: Vec<(Variant, usize, f64, bool, Vector2)> = Vec::new(); // (e, slot, base sight, air, pos)
    for li in 0..nl {
        let lv = lists.at(li);
        let lst = match lv.try_to::<VarArray>() { Ok(a) => a, Err(_) => continue };
        let bld = li + 1 == nl;
        for j in 0..lst.len() {
            let e = lst.at(j);
            if e.get_type() != VariantType::DICTIONARY {
                continue;
            }
            let o = gk(&e, &k_owner).map(|v| vint(&v)).unwrap_or(-1);
            if o < 0 || o as usize >= rmap.len() || rmap[o as usize] < 0 {
                continue;
            }
            let slot = rmap[o as usize] as usize;
            if slot >= ns {
                continue;
            }
            let id = gk(&e, &k_id).unwrap_or_default();
            if !ents.contains_key(&id) {
                continue;
            }
            let def = gk(&e, &k_def).unwrap_or_default();
            let sv = if bld { bsight.get(&def) } else { usight.get(&def) };
            let av = if bld { Some(false.to_variant()) } else { uair.get(&def) };
            let (s, air) = match (sv, av) {
                (Some(s), Some(a)) => (vfloat(&s), a.booleanize()),
                _ => {
                    need.push(&e);
                    continue;
                }
            };
            let p: Vector2 = gk(&e, &k_pos).and_then(|v| v.try_to::<Vector2>().ok()).unwrap_or(Vector2::ZERO);
            picked.push((e, slot, s, air, p));
        }
    }
    if !need.is_empty() {
        out.push(&need.to_variant());
        return out;
    }
    let mut seen: Vec<HashSet<i64>> = (0..ns).map(|_| HashSet::new()).collect();
    let mut cells: Vec<Vec<i32>> = (0..ns).map(|_| Vec::new()).collect();
    let mut sights: Vec<Vec<f64>> = (0..ns).map(|_| Vec::new()).collect();
    let has_hb = !hb.is_empty();
    for (e, slot, s0, air, p) in picked.into_iter() {
        let mut s = s0;
        let comp = gk(&e, &k_comp);
        let jam = gk(&e, &k_jam);
        if comp.is_some() || jam.is_some() {
            // Status.sight_mult
            let mut m = 1.0f64;
            if let Some(c) = &comp {
                let sens = if c.get_type() == VariantType::DICTIONARY {
                    gk(c, &k_sensors).map(|v| vfloat(&v)).unwrap_or(100.0)
                } else {
                    100.0
                };
                if sens <= 0.0 {
                    m = 0.5;
                }
            }
            let ju = jam.as_ref().map(vint).unwrap_or(-1);
            if ju > tick {
                let o = gk(&e, &k_owner).map(|v| vint(&v)).unwrap_or(-1);
                m *= if o >= 0 && (o as usize) < jm.len() { jm[o as usize] } else { 1.0 };
            }
            s *= m;
        }
        let qx = (p.x as f64).floor() as i64;
        let qy = (p.y as f64).floor() as i64;
        if has_hb && s > 0.0 && qx >= 0 && qy >= 0 && qx < mw && qy < mh {
            let lvl = hb[(qy * mw + qx) as usize] as i64;
            if lvl > plain {
                // Elevation.sight_bonus: (map_level - PLAIN) levels x sight_per_level, aircraft 0.0
                s += if air { 0.0 } else { spl * ((lvl - plain) as f64) };
            }
        }
        if s <= 0.0 {
            continue;
        }
        let key = (qy * mw + qx) * 128 + (s * 4.0) as i64;
        if seen[slot].insert(key) {
            cells[slot].push((key >> 7) as i32);
            sights[slot].push(s);
        }
    }
    for k in 0..ns {
        out.push(&PackedInt32Array::from(cells[k].as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(sights[k].as_slice()).to_variant());
    }
    out
}
