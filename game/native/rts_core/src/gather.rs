//! G5 CORE10K: movement.gd `_tick_held` gather loop as one native batch (RtsSteer.gather_held).
//! An exact port of the GDScript loop; the GDScript loop stays the fallback and the hash oracle.
//! Two passes: pass 1 is read-only and decides whether the batch can run natively at all (every
//! unit has its runtime table row, stands on an in-bounds non-solid cell, owes no stride steps);
//! pass 2 then performs exactly the GDScript loop's side effects (held mirrors, set_path, path refs)
//! in ascending input order. No RNG, no hash-order observable, no threads.

use crate::fastdict::{arr_at, dget};
use godot::prelude::*;
use godot::sys;

pub struct GKeys {
    id: StringName, pos: StringName, path: StringName, path_i: StringName, stuck: StringName,
    moving: StringName, path_req: StringName, mv_owed: StringName, comp: StringName, mobility: StringName,
    fuel: StringName, broken: StringName, pinned: StringName,
}

impl GKeys {
    pub fn new() -> Self {
        let n = |s: &str| StringName::from(s);
        GKeys {
            id: n("id"), pos: n("pos"), path: n("path"), path_i: n("path_i"), stuck: n("stuck"),
            moving: n("moving"), path_req: n("path_req"), mv_owed: n("mv_owed"), comp: n("comp"),
            mobility: n("mobility"), fuel: n("fuel"), broken: n("broken"), pinned: n("pinned"),
        }
    }
}

/// e.get(key) with presence: (key present, value or nil). Variant::get_named, one FFI call.
#[inline]
fn gh(e: &Variant, key: &StringName) -> (bool, Variant) {
    let mut valid: sys::GDExtensionBool = 0;
    // SAFETY: e and key are live; get_named always initializes r_ret.
    let v = unsafe {
        Variant::new_with_var_uninit(|ptr| {
            sys::interface_fn!(variant_get_named)(e.var_sys(), key.string_sys(), ptr, &mut valid)
        })
    };
    if valid != 0 { (true, v) } else { (false, Variant::nil()) }
}

#[inline]
fn gn(e: &Variant, key: &StringName) -> Variant {
    gh(e, key).1
}

/// GDScript int(v) for int / float / bool; anything else 0.
fn vint(v: &Variant) -> i64 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>(),
        VariantType::FLOAT => v.to::<f64>() as i64,
        VariantType::BOOL => v.to::<bool>() as i64,
        _ => 0,
    }
}

/// GDScript float(v) for int / float / bool.
fn vfloat(v: &Variant) -> f64 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>() as f64,
        VariantType::FLOAT => v.to::<f64>(),
        VariantType::BOOL => (v.to::<bool>() as i64) as f64,
        _ => 0.0,
    }
}

/// Inputs of one gather (all indexed by entity id except units / sols).
pub struct GatherIn<'a> {
    pub tick: i64,
    pub mw: i32,
    pub mh: i32,
    pub sols: &'a [&'a [u8]],    // class index 0..5 -> solid bytes (empty = not built)
    pub trad: &'a [f32],
    pub tmc: &'a [u8],
    pub tsp: &'a [f32],
    pub uids: &'a [i32],         // ids parallel to units (SimIndex.unit_ids)
}

/// Held mirrors (movement.gd _held): path_i, stuck, path size, flags; grown here like GDScript.
pub struct Held {
    pub hpos: Vec<Vector2>,  // HotState.pos (by id)
    pub mfl: Vec<u8>,        // HotState.mflags: bit 0 synced, bit 1 dirty
    pub pi: Vec<i32>,
    pub st: Vec<i32>,
    pub ps: Vec<i32>,
    pub mv: Vec<u8>,
}

pub enum GatherOut {
    /// ids whose runtime table row is missing (GDScript fills them, then calls again)
    NeedTables(Vec<i32>),
    /// some unit needs the GDScript loop this tick (off-map / solid cell / stride debt / odd path)
    Fallback,
    Done {
        pos: Vec<Vector2>, ids: Vec<i32>, mov: Vec<u8>, mvi: Vec<i32>, spd: Vec<f32>,
        uix: Vec<i32>, arrive: Vec<i32>, paths_set: Vec<(i32, Vec<Vector2>)>,
    },
}

struct Row {
    touched: bool,
    i: usize,
    e: Variant,
    id: i64,
    p: Vector2,
    path: Variant,
    changed: bool,
}

fn path_vec(path: &Variant) -> Option<Vec<Vector2>> {
    let arr = path.try_to::<VarArray>().ok()?;
    let mut out = Vec::with_capacity(arr.len());
    for j in 0..arr.len() {
        out.push(arr.at(j).try_to::<Vector2>().ok()?);
    }
    Some(out)
}

pub static mut GT: [u64; 3] = [0; 3];

pub fn gather(units: &VarArray, ents: &VarDictionary, refs: &mut VarArray, g: &GatherIn, h: &mut Held) -> GatherOut {
    let t0 = std::time::Instant::now();
    let k = GKeys::new();
    let n_in = units.len();
    let tn = g.trad.len();
    let nref = refs.len();
    // ---- pass 1 (read only; pointer reads of id / pos / path, no Variant clones)
    let kid = GString::from("id").to_variant();
    let kpos = GString::from("pos").to_variant();
    let kpath = GString::from("path").to_variant();
    let mut rows: Vec<Row> = Vec::with_capacity(n_in);
    let mut need: Vec<i32> = Vec::new();
    let mut fallback = false;
    let mut gone: Vec<usize> = Vec::new();
    let use_ids = g.uids.len() == n_in;
    for i in 0..n_in {
        // SAFETY: i < units.len(); unit dicts always hold id / pos / path (world.gd spawn_unit).
        let ev = unsafe { arr_at(units, i) };
        let id = if use_ids {
            g.uids[i] as i64
        } else {
            match unsafe { ev.dict() } { Some(d) => unsafe { dget(d, &kid).int() }, None => continue }
        };
        if !ents.contains_key(&id.to_variant()) {
            if id >= 0 {
                gone.push(id as usize);
            }
            continue;
        }
        let iu = id as usize;
        if id < 0 || iu >= tn || iu >= g.tmc.len() || iu >= g.tsp.len() || g.trad[iu] <= 0.0 {
            need.push(id as i32);
            continue;
        }
        let mi = (g.tmc[iu] & 15) as usize;
        let fl = if iu < h.mfl.len() { h.mfl[iu] } else { 0 };
        let mover = iu < h.mv.len() && h.mv[iu] & 1 != 0;
        // ground classes only (foot / vehicle): air / naval units are moved by other systems too
        let clean = mi <= 1 && fl & 1 != 0 && fl & 2 == 0 && !mover && iu < h.hpos.len();
        let d = if clean { None } else {
            match unsafe { ev.dict() } { Some(d) => Some(d), None => continue }
        };
        let p: Vector2 = match d {
            None => h.hpos[iu],   // synced, clean, not moving: the dict pos equals the mirror
            Some(d) => match unsafe { dget(d, &kpos).v2() } { Some(v) => v, None => { fallback = true; Vector2::ZERO } },
        };
        let cx = p.x.floor() as i64;
        let cy = p.y.floor() as i64;
        let bad = cx < 0 || cy < 0 || cx >= g.mw as i64 || cy >= g.mh as i64;
        if bad {
            fallback = true;
        } else if mi != 2 && mi < 6 {
            let sb = g.sols[mi];
            if sb.is_empty() || sb[(cy * g.mw as i64 + cx) as usize] != 0 {
                fallback = true; // solid under the unit (rescue / own gate) or class grid not built yet
            }
        }
        let d = match d {
            None => {
                rows.push(Row { touched: false, i, e: Variant::nil(), id, p, path: Variant::nil(), changed: false });
                continue;
            }
            Some(d) => d,
        };
        let pp = unsafe { dget(d, &kpath) };
        if unsafe { pp.ty() } != VariantType::ARRAY.ord() {
            fallback = true;
            continue;
        }
        let changed = if iu < nref {
            let rp = unsafe { arr_at(refs, iu) };
            unsafe { rp.ty() != VariantType::ARRAY.ord() || rp.ref_id() != pp.ref_id() }
        } else {
            true
        };
        let e = if changed { units.at(i) } else { Variant::nil() };
        let owed = if changed { gh(&e, &k.mv_owed).0 } else { iu < h.mv.len() && h.mv[iu] & 4 != 0 };
        if owed {
            fallback = true;
        }
        rows.push(Row { touched: true, i, e, id, p, path: Variant::nil(), changed });
    }
    let t1 = std::time::Instant::now();
    if !need.is_empty() {
        return GatherOut::NeedTables(need);
    }
    if fallback {
        return GatherOut::Fallback;
    }
    // ---- pass 2 (the GDScript loop's effects, ascending input order)
    let na = rows.len();
    let (mut pos, mut ids, mut mov, mut uix) = (Vec::with_capacity(na), Vec::with_capacity(na), Vec::with_capacity(na), Vec::with_capacity(na));
    let (mut mvi, mut spd, mut arrive) = (Vec::new(), Vec::new(), Vec::new());
    let mut paths_set: Vec<(i32, Vec<Vector2>)> = Vec::new();
    let need_n = rows.iter().map(|r| r.id as usize + 1).max().unwrap_or(0);
    // CORE10K-2 fix: grow each mirror on its own. With gather_trust off movement.gd passes an EMPTY
    // mflags (hot.pos is already long), so the old joint resize left mfl at len 0 -> panic on mfl[iu].
    if h.hpos.len() < need_n {
        h.hpos.resize(need_n, Vector2::ZERO);
    }
    if h.mfl.len() < need_n {
        h.mfl.resize(need_n, 0);
    }
    for &gi in gone.iter() {
        if gi < h.mfl.len() {
            h.mfl[gi] = 0; // left w.entities (e.g. loaded as cargo): re-read when it comes back
        }
    }
    for r in rows.iter() {
        let iu = r.id as usize;
        if r.touched {
            h.hpos[iu] = r.p;
            h.mfl[iu] = 1;
        }
        if iu >= h.pi.len() {
            let hn = (iu + 1).max(h.pi.len() * 2 + 64);
            h.pi.resize(hn, 0);
            h.st.resize(hn, 0);
            h.ps.resize(hn, 0);
            h.mv.resize(hn, 0);
        }
        let ee: &Variant = &r.e;
        if r.changed {
            let path = gn(ee, &k.path);
            let pv = match path_vec(&path) { Some(v) => v, None => return GatherOut::Fallback };
            if iu >= refs.len() {
                let hn = (iu + 1).max(refs.len() * 2 + 64);
                refs.resize(hn, &Variant::nil());
            }
            refs.set(iu, &path);
            h.ps[iu] = pv.len() as i32;
            paths_set.push((r.id as i32, pv));
            h.pi[iu] = vint(&gn(ee, &k.path_i)) as i32;
            let sv = gn(ee, &k.stuck);
            h.st[iu] = if sv.is_nil() { 0 } else { vint(&sv) as i32 };
            let mvb = gn(ee, &k.moving).booleanize();
            let (has_req, req) = gh(ee, &k.path_req);
            let preq = if has_req { vint(&req) } else { -1 };
            h.mv[iu] = (if mvb { 1 } else { 0 }) | (if preq >= 0 { 2 } else { 0 })
                | (if gh(ee, &k.mv_owed).0 { 4 } else { 0 }) | (if sv.get_type() == VariantType::INT { 0 } else { 8 });
        }
        let mut mflag: u8 = 0;
        let hm = h.mv[iu];
        if hm & 1 != 0 {
            let ps = h.ps[iu];
            if ps == 0 {
                if hm & 2 == 0 {
                    arrive.push(r.i as i32);
                } else {
                    mflag = 1;
                }
            } else if h.pi[iu] >= ps {
                arrive.push(r.i as i32);
            } else {
                mflag = 1;
                mvi.extend_from_slice(&[pos.len() as i32, 1, h.pi[iu], h.st[iu]]);
                let mut mm = 1.0f64;
                let e_own;
                let ee: &Variant = if r.changed { &r.e } else { e_own = units.at(r.i); &e_own };
                let c = gn(ee, &k.comp);
                let f = gn(ee, &k.fuel);
                let mob = if c.is_nil() { 1.0 } else {
                    let (has, m) = gh(&c, &k.mobility);
                    if has { vfloat(&m) } else { 100.0 }
                };
                if !c.is_nil() && mob <= 0.0 {
                    mm = 0.0;
                } else if !f.is_nil() && vfloat(&f) <= 0.0 {
                    mm = 0.0;
                } else if gn(ee, &k.broken).booleanize() {
                    mm = 1.2;
                } else if gn(ee, &k.pinned).booleanize() {
                    mm = 0.5;
                }
                spd.push(((g.tsp[iu] as f64) * mm) as f32);
            }
        }
        uix.push(r.i as i32);
        pos.push(r.p);
        ids.push(r.id as i32);
        mov.push(mflag);
    }
    let _ = g.tick;
    unsafe { GT[0] += (t1 - t0).as_micros() as u64; GT[1] += t1.elapsed().as_micros() as u64; GT[2] += 1; }
    GatherOut::Done { pos, ids, mov, mvi, spd, uix, arrive, paths_set }
}
