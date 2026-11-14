//! G7.1 PERFSIM71-4 (rts_core 0.6.0): the packed combat entity MIRROR (docs/NATIVE_COMBAT71.md).
//!
//! `prep_mirror` is combat_prep::prep_units_ids (ids path) with the same reads, writes, outputs and
//! order, but (1) the always-present unit keys (pos, firing, target, moving, order, owner) are read
//! through pointer-level Dictionary access (fastdict, no Variant clone), optional keys through
//! variant_get_named on the element pointer (no clone of the unit or order Dictionary), and the
//! countdown writes go through dictionary_operator_index (in place, same key, same Variant types);
//! and (2) everything it read is kept in the RtsCombat object as a per-tick packed mirror (one row
//! per live FULL unit, input = ascending id order) for the later native act-loop phases, plus
//! GDScript accessors for the debug oracle (combat.gd mirror_check: mirror vs Dictionaries).
//!
//! Mirror semantics (exactness trap, see the doc): every row is the value at PREP time (after the
//! firing / cooldown countdown). pos / owner / def index / team flags are tick-fixed during
//! Combat.tick (verified by mirror_check at act end); target / moving / cd / order code / broken
//! are NOT (the act loop writes them) and a later native phase must read those live or update the
//! row on every write.
//! Deterministic: one pass in input order, no hash iteration, no RNG, no threads.

use crate::fastdict::{arr_at, dget, VP};
use godot::prelude::*;
use godot::sys;

#[derive(Default)]
pub struct Mirror {
    pub tick: i64,
    pub valid: bool,
    pub ids: Vec<i32>,
    pub pos: Vec<Vector2>,
    pub owner: Vec<i32>,
    pub tf: Vec<i32>,
    pub dx: Vec<i32>,
    pub target: Vec<i32>,
    pub moving: Vec<u8>,
    pub cd: Vec<i32>,
    /// 0 idle, 1 hold, 2 attack_move, 3 attack, 4 any other value (move, gather, nil, ...)
    pub ocode: Vec<u8>,
    pub broken: Vec<u8>,
    /// id -> row (-1: not mirrored this tick)
    pub row: Vec<i32>,
}

impl Mirror {
    fn clear(&mut self, next_id: i64) {
        self.valid = false;
        self.ids.clear();
        self.pos.clear();
        self.owner.clear();
        self.tf.clear();
        self.dx.clear();
        self.target.clear();
        self.moving.clear();
        self.cd.clear();
        self.ocode.clear();
        self.broken.clear();
        let n = (next_id.max(0) + 1) as usize;
        self.row.clear();
        self.row.resize(n, -1);
    }
}

/// GDScript int(v) for int / float / bool Variants (else 0), as combat_prep::vint.
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

/// variant_get_named on the Variant at `vp` (no clone of the container): (valid, value).
#[inline]
unsafe fn gnp(vp: VP, key: &StringName) -> (bool, Variant) {
    let mut valid: sys::GDExtensionBool = 0;
    let v = Variant::new_with_var_uninit(|ptr| {
        sys::interface_fn!(variant_get_named)(vp.0 as sys::GDExtensionConstVariantPtr, key.string_sys(), ptr, &mut valid)
    });
    if valid != 0 { (true, v) } else { (false, Variant::nil()) }
}

/// GDScript `e.key = value` on the Dictionary at d (inserts the key when absent, as set_named).
#[inline]
unsafe fn dset(d: sys::GDExtensionConstTypePtr, key: &Variant, val: Variant) {
    let p = sys::interface_fn!(dictionary_operator_index)(d as sys::GDExtensionTypePtr, key.var_sys()) as *mut Variant;
    *p = val;
}

pub struct MKeys {
    k_pos: Variant, k_firing: Variant, k_cd_ticks: Variant, k_cooldown: Variant, k_target: Variant,
    k_moving: Variant, k_order: Variant, k_owner: Variant,
    n_cd_ticks: StringName, n_cooldown: StringName, n_broken: StringName, n_last_hit: StringName,
    n_air_landed: StringName, n_type: StringName, n_engaged: StringName, n_moving: StringName,
    idle: Variant, hold: Variant, attack: Variant, attack_move: Variant,
}

impl MKeys {
    pub fn new() -> Self {
        let g = |s: &str| GString::from(s).to_variant();
        let n = |s: &str| StringName::from(s);
        // k_cd_ticks is the one key prep can ADD (a unit with cooldown but no cd_ticks): add it as a StringName like
        // GDScript's `e.cd_ticks = cd`, or var_to_bytes / state_hash differ (0.6.3 fix; lookups match either type)
        MKeys {
            k_pos: g("pos"), k_firing: g("firing"), k_cd_ticks: n("cd_ticks").to_variant(), k_cooldown: g("cooldown"),
            k_target: g("target"), k_moving: g("moving"), k_order: g("order"), k_owner: g("owner"),
            n_cd_ticks: n("cd_ticks"), n_cooldown: n("cooldown"), n_broken: n("broken"), n_last_hit: n("last_hit_tick"),
            n_air_landed: n("air_landed"), n_type: n("type"), n_engaged: n("engaged"), n_moving: n("moving"),
            idle: g("idle"), hold: g("hold"), attack: g("attack"), attack_move: g("attack_move"),
        }
    }
}

/// e.order.get("type", "idle") as combat_prep::order_type, from the order Variant pointer.
#[inline]
unsafe fn order_type(ovp: VP, k: &MKeys) -> Variant {
    if ovp.ty() != VariantType::DICTIONARY.ord() {
        return k.idle.clone();
    }
    let (ok, t) = gnp(ovp, &k.n_type);
    if ok { t } else { k.idle.clone() }
}

#[inline]
fn ocode_of(o: &Variant, k: &MKeys) -> u8 {
    if *o == k.idle { 0 } else if *o == k.hold { 1 } else if *o == k.attack_move { 2 } else if *o == k.attack { 3 } else { 4 }
}

#[allow(clippy::too_many_arguments)]
pub fn prep_mirror(m: &mut Mirror, units: &VarArray, ents: &VarDictionary, ids: &[i32], tick: i64, tfs: &[i32], dxs: &[i32],
                   dr: &[f32], ds: &[f32], df: &[i32], next_id: i64, trf: f64, scan_every: i64, ret_fire: i64) -> VarArray {
    let k = MKeys::new();
    let n = units.len();
    m.clear(next_id);
    m.tick = tick;
    let mut out = VarArray::new();
    if ids.len() != n {
        out.push(&PackedInt32Array::new().to_variant());   // caller falls back (never sent: combat.gd passes matching ids)
        out.push(&false.to_variant());
        return out;
    }
    // pass 1: liveness + table check from ids only (no dict read, no writes), as prep_units_ids
    let mut live: Vec<bool> = Vec::with_capacity(n);
    let mut need: Vec<i32> = Vec::new();
    for &id32 in ids.iter() {
        let id = id32 as i64;
        if !ents.contains_key(&id.to_variant()) {
            live.push(false);
            continue;
        }
        let iu = id as usize;
        if id < 0 || iu >= tfs.len() || iu >= dxs.len() || tfs[iu] == 0 || dxs[iu] < 0 || dxs[iu] as usize >= df.len() {
            need.push(id as i32);
        }
        live.push(true);
    }
    if !need.is_empty() {
        out.push(&PackedInt32Array::from(need.as_slice()).to_variant());
        return out;
    }
    let mut nids: Vec<i32> = Vec::with_capacity(n);
    let mut npos: Vec<Vector2> = Vec::with_capacity(n);
    let mut nteam: Vec<i32> = Vec::with_capacity(n);
    let mut nflags: Vec<i32> = Vec::with_capacity(n);
    let mut nidx: Vec<i32> = vec![-1; (next_id.max(0) + 1) as usize];
    let (mut scan_src, mut scan_r, mut scan_need, mut scan_ids): (Vec<i32>, Vec<f32>, Vec<i32>, Vec<i32>) = (Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let (mut act_idx, mut act_code, mut act_tg, mut act_id): (Vec<i32>, Vec<u8>, Vec<i32>, Vec<i32>) =
        (Vec::with_capacity(n), Vec::with_capacity(n), Vec::with_capacity(n), Vec::with_capacity(n));
    for i in 0..n {
        if !live[i] {
            continue;
        }
        let id = ids[i] as i64;
        let iu = id as usize;
        // SAFETY: i < units.len(); the element is checked to be a Dictionary; pos / firing / target /
        // moving / order / owner are set at spawn (world.gd spawn_unit) and never erased.
        let ev = unsafe { arr_at(units, i) };
        let d = match unsafe { ev.dict() } {
            Some(d) => d,
            None => continue, // unreachable for a live FULL unit (prep_units_ids would read nil fields)
        };
        let tfv = tfs[iu];
        let dxi = dxs[iu] as usize;
        let p: Vector2 = unsafe { dget(d, &k.k_pos).v2() }.unwrap_or(Vector2::ZERO);
        let on_slot = (tick + id) % scan_every == 0;
        let ovp = unsafe { dget(d, &k.k_order) };
        let mut ot: Option<Variant> = None;
        if tfv > 0 {
            let si = nids.len() as i32;
            if iu < nidx.len() {
                nidx[iu] = si;
            }
            nids.push(id as i32);
            npos.push(p);
            nteam.push((tfv >> 3) - 1);
            nflags.push(if tfv & 2 != 0 && unsafe { gnp(ev, &k.n_air_landed).1 }.booleanize() { 3 } else { tfv & 3 });
            if tfv & 4 != 0 && on_slot {
                let o = unsafe { order_type(ovp, &k) };
                if o == k.idle || o == k.attack_move || o == k.hold {
                    scan_src.push(si);
                    scan_r.push(if o == k.hold { dr[dxi] } else { ds[dxi] });
                    scan_need.push(if df[dxi] & 1 != 0 { 0 } else { 1 });
                    scan_ids.push(id as i32);
                }
                ot = Some(o);
            }
        }
        let fr = unsafe { dget(d, &k.k_firing).int() };
        if fr > 0 {
            unsafe { dset(d, &k.k_firing, (fr - 1).to_variant()) };
        }
        let (_, cdv) = unsafe { gnp(ev, &k.n_cd_ticks) };
        let mut cd = if !cdv.is_nil() {
            vint(&cdv)
        } else {
            let c = (vfloat(&unsafe { gnp(ev, &k.n_cooldown) }.1) * trf - 1e-6).ceil() as i64;
            c.max(0)
        };
        if cd > 0 {
            cd -= 1;
            unsafe {
                dset(d, &k.k_cd_ticks, cd.to_variant());
                dset(d, &k.k_cooldown, ((cd as f64) / trf).to_variant());
            }
        }
        let tg = unsafe { dget(d, &k.k_target).int() };
        let brk = unsafe { gnp(ev, &k.n_broken).1 }.booleanize();
        // e.moving is a bool (spawn: false); any other Variant type takes the generic truthiness read
        let mv = unsafe { dget(d, &k.k_moving) };
        let mvb = if unsafe { mv.ty() } == VariantType::BOOL.ord() {
            (unsafe { mv.int() }) != 0
        } else {
            unsafe { gnp(ev, &k.n_moving).1 }.booleanize()
        };
        let mut code: u8 = 0;
        let o_all: Variant;
        if brk {
            code = if tg < 0 { 1 } else { 0 };
            o_all = match ot.take() { Some(o) => o, None => unsafe { order_type(ovp, &k) } };
        } else if tg >= 0 {
            if !mvb && cd > 1 && ents.contains_key(&tg.to_variant()) {
                code = 2;
            }
            o_all = match ot.take() { Some(o) => o, None => unsafe { order_type(ovp, &k) } };
        } else {
            let o = match ot.take() { Some(o) => o, None => unsafe { order_type(ovp, &k) } };
            if !mvb && !on_slot && (o == k.idle || o == k.hold) {
                code = 1;
            } else if df[dxi] & 2 == 0 {
                code = 1;
            } else if o != k.attack && o != k.idle && o != k.hold && o != k.attack_move {
                let lh = unsafe { gnp(ev, &k.n_last_hit).1 };
                let lht = if lh.is_nil() { -100000 } else { vint(&lh) };
                if tick - lht > ret_fire {
                    code = 3;
                }
            } else if o == k.attack_move && mvb && df[dxi] & 4 == 0 && !on_slot
                && !(unsafe { ovp.ty() } == VariantType::DICTIONARY.ord() && unsafe { gnp(ovp, &k.n_engaged).1 }.booleanize()) {
                code = 1;
            }
            o_all = o;
        }
        if code != 1 {
            act_idx.push(i as i32);
            act_code.push(code);
            act_tg.push(tg as i32);
            act_id.push(id as i32);
        }
        // mirror row (prep-time values, after the countdown)
        if iu < m.row.len() {
            m.row[iu] = m.ids.len() as i32;
        }
        m.ids.push(id as i32);
        m.pos.push(p);
        m.owner.push(unsafe { dget(d, &k.k_owner).int() } as i32);
        m.tf.push(tfv);
        m.dx.push(dxi as i32);
        m.target.push(tg as i32);
        m.moving.push(mvb as u8);
        m.cd.push(cd as i32);
        m.ocode.push(ocode_of(&o_all, &k));
        m.broken.push(brk as u8);
    }
    m.valid = true;
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
    out.push(&PackedInt32Array::from(act_id.as_slice()).to_variant());
    out
}

/// The mirror as GDScript arrays: [tick, ids, pos, owner, tf, dx, target, moving, cd, ocode, broken].
pub fn mirror_arrays(m: &Mirror) -> VarArray {
    let mut a = VarArray::new();
    if !m.valid {
        return a;
    }
    a.push(&m.tick.to_variant());
    a.push(&PackedInt32Array::from(m.ids.as_slice()).to_variant());
    a.push(&PackedVector2Array::from(m.pos.as_slice()).to_variant());
    a.push(&PackedInt32Array::from(m.owner.as_slice()).to_variant());
    a.push(&PackedInt32Array::from(m.tf.as_slice()).to_variant());
    a.push(&PackedInt32Array::from(m.dx.as_slice()).to_variant());
    a.push(&PackedInt32Array::from(m.target.as_slice()).to_variant());
    a.push(&PackedByteArray::from(m.moving.as_slice()).to_variant());
    a.push(&PackedInt32Array::from(m.cd.as_slice()).to_variant());
    a.push(&PackedByteArray::from(m.ocode.as_slice()).to_variant());
    a.push(&PackedByteArray::from(m.broken.as_slice()).to_variant());
    a
}
