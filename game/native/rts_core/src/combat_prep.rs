//! SIM10K: combat.gd tick prep as one native batch (RtsCombat.prep_units). An exact port of the
//! GDScript prep loop in combat.gd `tick()` (native branch) plus its act-phase skip codes; the
//! GDScript loop stays the fallback and the hash oracle (native-on == native-off).
//! Deterministic: one pass in input (ascending id) order, no hashing order observable, no RNG.

use godot::prelude::*;
use godot::sys;

/// GDScript `int(v)` for the Variant kinds the sim stores (int, float, bool); anything else 0.
fn vint(v: &Variant) -> i64 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>(),
        VariantType::FLOAT => v.to::<f64>() as i64, // truncation toward zero, as GDScript int()
        VariantType::BOOL => v.to::<bool>() as i64,
        _ => 0,
    }
}

/// GDScript `float(v)` for int / float / bool Variants.
fn vfloat(v: &Variant) -> f64 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>() as f64,
        VariantType::FLOAT => v.to::<f64>(),
        VariantType::BOOL => (v.to::<bool>() as i64) as f64,
        _ => 0.0,
    }
}

struct Keys {
    id: StringName, pos: StringName, firing: StringName, cd_ticks: StringName, cooldown: StringName,
    target: StringName, broken: StringName, moving: StringName, order: StringName, typ: StringName,
    last_hit: StringName, engaged: StringName, air_landed: StringName,
    idle: Variant, hold: Variant, attack: Variant, attack_move: Variant,
}

impl Keys {
    fn new() -> Self {
        let n = |s: &str| StringName::from(s);
        let k = |s: &str| GString::from(s).to_variant();
        Keys {
            id: n("id"), pos: n("pos"), firing: n("firing"), cd_ticks: n("cd_ticks"), cooldown: n("cooldown"),
            target: n("target"), broken: n("broken"), moving: n("moving"), order: n("order"), typ: n("type"),
            last_hit: n("last_hit_tick"), engaged: n("engaged"), air_landed: n("air_landed"), idle: k("idle"), hold: k("hold"),
            attack: k("attack"), attack_move: k("attack_move"),
        }
    }
}

/// GDScript `e.key` / `e.get(key)` read: Variant::get_named, the same lookup GDScript does for a
/// Dictionary (one FFI call, no key Variant built). Missing key -> nil.
#[inline]
fn gn(e: &Variant, key: &StringName) -> Variant {
    let mut valid: sys::GDExtensionBool = 0;
    // SAFETY: e and key are live; get_named always initializes r_ret.
    let v = unsafe {
        Variant::new_with_var_uninit(|ptr| {
            sys::interface_fn!(variant_get_named)(e.var_sys(), key.string_sys(), ptr, &mut valid)
        })
    };
    if valid != 0 { v } else { Variant::nil() }
}

/// GDScript `e.key = value` write: Variant::set_named on the Variant holding the (shared) Dictionary.
#[inline]
fn sn(e: &mut Variant, key: &StringName, value: &Variant) {
    let mut valid: sys::GDExtensionBool = 0;
    // SAFETY: all pointers live for the call.
    unsafe { sys::interface_fn!(variant_set_named)(e.var_sys_mut(), key.string_sys(), value.var_sys(), &mut valid) };
}

/// e.order.get("type", "idle")
fn order_type(e: &Variant, k: &Keys) -> Variant {
    let o = gn(e, &k.order);
    if o.get_type() == VariantType::DICTIONARY {
        let t = gn(&o, &k.typ);
        if !t.is_nil() {
            return t;
        }
        if let Ok(od) = o.try_to::<VarDictionary>() {
            if od.contains_key(&k.typ.to_variant()) {
                return t;   // present but nil
            }
        }
    }
    k.idle.clone()
}

/// e.order.get("engaged", false) truthiness
fn order_engaged(e: &Variant, k: &Keys) -> bool {
    let o = gn(e, &k.order);
    if o.get_type() == VariantType::DICTIONARY { gn(&o, &k.engaged).booleanize() } else { false }
}

#[allow(clippy::too_many_arguments)]
pub fn prep_units(units: VarArray, ents: VarDictionary, tick: i64, tf: PackedInt32Array, dx: PackedInt32Array,
                  d_range: PackedFloat32Array, d_search: PackedFloat32Array, d_flags: PackedInt32Array,
                  next_id: i64, trf: f64, scan_every: i64, ret_fire: i64) -> VarArray {
    prep_units_ids(units, ents, &[], tick, tf, dx, d_range, d_search, d_flags, next_id, trf, scan_every, ret_fire)
}

/// CORE10K-2 (rts_core 0.4.2): `ids` parallel to `units` (combat.gd: the FULL list's ids, cached per
/// list). With it, pass 1 (liveness + table check) reads no unit dict at all, so each unit dict is
/// touched once per tick instead of twice; the output gains a 13th entry, act_ids (the id of every act
/// entry), so the act loop needs no dict read for a skipped entry. Same results by construction:
/// ids[i] == units[i].id. An empty or mismatched `ids` gives the old (dict-read) pass 1.
#[allow(clippy::too_many_arguments)]
pub fn prep_units_ids(units: VarArray, ents: VarDictionary, ids: &[i32], tick: i64, tf: PackedInt32Array, dx: PackedInt32Array,
                  d_range: PackedFloat32Array, d_search: PackedFloat32Array, d_flags: PackedInt32Array,
                  next_id: i64, trf: f64, scan_every: i64, ret_fire: i64) -> VarArray {
    let k = Keys::new();
    let use_ids = !ids.is_empty() && ids.len() == units.len();
    let tfs = tf.as_slice();
    let dxs = dx.as_slice();
    let (dr, ds, df) = (d_range.as_slice(), d_search.as_slice(), d_flags.as_slice());
    let n = units.len();
    let mut dicts: Vec<Option<(Variant, i64)>> = Vec::with_capacity(n);
    // pass 1: ids, liveness and table check (no writes)
    let mut need: Vec<i32> = Vec::new();
    for i in 0..n {
        let (e, id) = if use_ids {
            (Variant::nil(), ids[i] as i64)   // fetched in pass 2 (only live units)
        } else {
            let e = units.at(i);
            if e.get_type() != VariantType::DICTIONARY {
                dicts.push(None);
                continue;
            }
            let id = vint(&gn(&e, &k.id));
            (e, id)
        };
        if !ents.contains_key(&id.to_variant()) {
            dicts.push(None);
            continue;
        }
        let iu = id as usize;
        if id < 0 || iu >= tfs.len() || iu >= dxs.len() || tfs[iu] == 0 || dxs[iu] < 0 || dxs[iu] as usize >= df.len() {
            need.push(id as i32);
        }
        dicts.push(Some((e, id)));
    }
    let mut out = VarArray::new();
    if !need.is_empty() {
        out.push(&PackedInt32Array::from(need.as_slice()).to_variant());
        return out;
    }
    let mut nids: Vec<i32> = Vec::with_capacity(n);
    let mut npos: Vec<Vector2> = Vec::with_capacity(n);
    let mut nteam: Vec<i32> = Vec::with_capacity(n);
    let mut nflags: Vec<i32> = Vec::with_capacity(n);
    let mut nidx: Vec<i32> = vec![-1; (next_id.max(0) + 1) as usize];
    let (mut scan_src, mut scan_r, mut scan_need, mut scan_ids) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let (mut act_idx, mut act_code, mut act_tg): (Vec<i32>, Vec<u8>, Vec<i32>) = (Vec::with_capacity(n), Vec::with_capacity(n), Vec::with_capacity(n));
    let mut act_id: Vec<i32> = Vec::with_capacity(n);
    for (i, slot) in dicts.into_iter().enumerate() {
        let (mut e, id) = match slot { Some(x) => x, None => continue };
        if use_ids {
            e = units.at(i);
        }
        let iu = id as usize;
        let tfv = tfs[iu];
        let d = dxs[iu] as usize;
        let p: Vector2 = gn(&e, &k.pos).try_to::<Vector2>().unwrap_or(Vector2::ZERO);
        let on_slot = (tick + id) % scan_every == 0;
        let mut ot: Option<Variant> = None;
        if tfv > 0 {
            let si = nids.len() as i32;
            if iu < nidx.len() {
                nidx[iu] = si;
            }
            nids.push(id as i32);
            npos.push(p);
            nteam.push((tfv >> 3) - 1);
            // CORE10K-2: a landed aircraft (e.air_landed) is air|ground (combat.gd _landed), as the GDScript prep
            nflags.push(if tfv & 2 != 0 && gn(&e, &k.air_landed).booleanize() { 3 } else { tfv & 3 });
            if tfv & 4 != 0 && on_slot {
                let o = order_type(&e, &k);
                if o == k.idle || o == k.attack_move || o == k.hold {
                    scan_src.push(si);
                    scan_r.push(if o == k.hold { dr[d] } else { ds[d] });
                    scan_need.push(if df[d] & 1 != 0 { 0 } else { 1 });
                    scan_ids.push(id as i32);
                }
                ot = Some(o);
            }
        }
        let fr = vint(&gn(&e, &k.firing));
        if fr > 0 {
            sn(&mut e, &k.firing, &(fr - 1).to_variant());
        }
        let cdv = gn(&e, &k.cd_ticks);
        let mut cd = if !cdv.is_nil() {
            vint(&cdv)
        } else {
            let c = (vfloat(&gn(&e, &k.cooldown)) * trf - 1e-6).ceil() as i64;
            c.max(0)
        };
        if cd > 0 {
            cd -= 1;
            sn(&mut e, &k.cd_ticks, &cd.to_variant());
            sn(&mut e, &k.cooldown, &((cd as f64) / trf).to_variant());
        }
        // act-phase skip code (combat.gd _unit_tick no-op exits)
        let tg = vint(&gn(&e, &k.target));
        let mut code: u8 = 0;
        if gn(&e, &k.broken).booleanize() {
            code = if tg < 0 { 1 } else { 0 };
        } else if tg >= 0 {
            if !gn(&e, &k.moving).booleanize() && cd > 1 && ents.contains_key(&tg.to_variant()) {
                code = 2;
            }
        } else {
            let mv = gn(&e, &k.moving).booleanize();
            let o = match ot { Some(o) => o, None => order_type(&e, &k) };
            if !mv && !on_slot && (o == k.idle || o == k.hold) {
                code = 1;
            } else if df[d] & 2 == 0 {
                code = 1;
            } else if o != k.attack && o != k.idle && o != k.hold && o != k.attack_move {
                let lh = gn(&e, &k.last_hit);
                let lht = if lh.is_nil() { -100000 } else { vint(&lh) };
                if tick - lht > ret_fire {
                    code = 3;
                }
            } else if o == k.attack_move && mv && df[d] & 4 == 0 && !on_slot && !order_engaged(&e, &k) {
                code = 1;
            }
        }
        if code != 1 {
            act_idx.push(i as i32);
            act_code.push(code);
            act_tg.push(tg as i32);
            act_id.push(id as i32);
        }
    }
    out.push(&PackedInt32Array::from(nids.as_slice()).to_variant());
    out.push(&PackedVector2Array::from(npos.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(nteam.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(nflags.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(nidx.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(scan_src.as_slice()).to_variant());
    out.push(&PackedFloat32Array::from(scan_r.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(scan_need.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(scan_ids.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(act_idx.as_slice()).to_variant());
    out.push(&PackedByteArray::from(act_code.as_slice()).to_variant());
    out.push(&PackedInt32Array::from(act_tg.as_slice()).to_variant());
    if use_ids {
        out.push(&PackedInt32Array::from(act_id.as_slice()).to_variant());
    }
    out
}
