//! G7.1 PERFSIM71-6 (rts_core 0.6.2): native act driver, phase 3a (docs/NATIVE_COMBAT71.md section 8).
//!
//! Child module of find (it uses FindCtx's per-tick inputs and `legal`). `act_run(i0, stop_id)` runs
//! combat.gd's act-loop entries i0.. of this tick (act_id / askip / atg / nores from prep, w.cache.cmb_ev
//! live) in order and returns 2*j = "stopped before entry j: an armed building with id stop_id < act_id[j]
//! acts first", 2*j + 1 = "entry j needs the GDScript body" (nothing of entry j was written), 2*n = done.
//!
//! An entry is finished natively only when its whole GDScript body (loop skips + _unit_tick) is decided by
//! ported rules and writes at most e.target and e.order.engaged = true. Every other path hands the whole
//! unit to GDScript BEFORE any write: a shot that passes _fire's cooldown gate, a chase repath, stop_path,
//! an order change, an attack order, a builder, return fire, a bk move, a possible Spread8.mark, a building
//! or structure target, a hid / marked / forest / air / G6-key / REDUCED target, find() == -2. So every
//! outcome is the GDScript outcome by construction. Per-tick guards (combat.gd): native find on, G6 RANGE /
//! LOS / VIS bits clear (_rm == 1.0, _hlos true, no visible_to), WallFire7.blocked false by its cheap exit.
//! Reads: the mirror for tick-fixed shooter / target pos, owner, dx; live Dictionary reads for every
//! volatile field. Deterministic: input order only, no RNG, no threads.

use super::*;
use crate::combat::{height_los_core, line_clear_core};

pub const A_N: usize = 18;
// stats: 0 entries, 1 finished natively, 2 delegated, then the delegation reason / native class
const D_GUARD: usize = 3;
const D_ATTACK: usize = 4; // attack order / builder / bk / return fire
const D_FIND: usize = 5;
const D_VALID: usize = 6; // current target or pick needs an unported rule (building, structure, hid, marked, ...)
const D_FIRE: usize = 7; // _fire passes the cooldown gate
const D_CHASE: usize = 8; // chase repath / min-range back-off
const D_STOP: usize = 9; // stop_path
const D_ORDER: usize = 10; // order rewrite
const D_SP8: usize = 11; // Spread8.mark possible
const D_IDLE: usize = 12; // wall-walk / CN parked idle rule present this tick
const N_SKIP: usize = 13; // dead / skip code / nores: no call
const N_FAST: usize = 14; // _unit_tick early exit, nothing written
const N_PICK: usize = 15; // decided after a pick: target (+ engaged) written
const D_RANGE: usize = 16; // G6_RANGE: _rm may be != 1.0 (raised cell, s7, wall-walk state)

pub const F_IDLE_DEL: i64 = 1;
pub const F_SP8: i64 = 2;
pub const F_G6R: i64 = 4; // G6_RANGE bit live
pub const F_WW: i64 = 8; // WallWalk7 state present (its range factor)
pub const F_G6L: i64 = 16; // G6_LOS bit live (native height_los, combat.gd checks ng.hl)
pub const AF_INDIRECT: i32 = 1;
pub const AF_A8INF: i32 = 2;

struct AKeys {
    broken: Variant, target: Variant, moving: Variant, cd_ticks: Variant, cooldown: Variant, order: Variant,
    otype: Variant, engaged: Variant, bk: Variant, last_hit: Variant, last_attacker: Variant, sp8: Variant,
    chase_goal: Variant, chase_tick: Variant, kind: Variant, marked_until: Variant, s7: Variant,
    idle: Variant, hold: Variant, attack_move: Variant, attack: Variant, unit: Variant, building: Variant,
}

impl AKeys {
    fn new() -> Self {
        let s = |x: &str| GString::from(x).to_variant();
        AKeys {
            broken: s("broken"), target: s("target"), moving: s("moving"), cd_ticks: s("cd_ticks"), cooldown: s("cooldown"),
            order: s("order"), otype: s("type"), engaged: s("engaged"), bk: s("bk"), last_hit: s("last_hit_tick"),
            last_attacker: s("last_attacker"), sp8: s("sp8"), chase_goal: s("chase_goal"), chase_tick: s("chase_tick"),
            kind: s("kind"), marked_until: s("marked_until"), s7: s("s7"),
            idle: s("idle"), hold: s("hold"), attack_move: s("attack_move"), attack: s("attack"), unit: s("unit"),
            building: s("building"),
        }
    }
}

#[derive(Default)]
pub struct ActCtx {
    pub on: bool,
    ids: Vec<i32>,
    skip: Vec<u8>,
    atg: Vec<i32>,
    nores: Vec<u8>,
    ev: Option<VarDictionary>,
    terr: PackedByteArray,
    ridge: u8,
    scan_every: i64,
    scan_eng: i64,
    ret_fire: i64,
    repath: i64,
    trf: f64,
    flags: i64,
    dar: Vec<f64>,
    das: Vec<f64>,
    daf: Vec<i32>,
    vis: Vec<(i32, PackedByteArray)>,
    height: PackedByteArray,
    plain: i64,
    max_level: i32,
    keys: Option<AKeys>,
    pub stats: [i64; A_N],
}

enum Out {
    Skip,
    Fast,
    Pick,
    Del(usize),
}

enum Tg {
    Null,
    Unit(i32, usize), // id, mirror row
    Del(usize),
}

/// GDScript truthiness of a Variant (if v:).
#[inline]
fn truthy(v: &Variant) -> bool {
    v.booleanize()
}

impl FindCtx {
    /// Per-tick inputs: [act_id, askip, atg, nores, cmb_ev, SCAN_EVERY, SCAN_EVERY_ENGAGED, RETURN_FIRE_TICKS,
    /// CHASE_REPATH_TICKS, TICK_RATE (float), flags, terrain, RIDGE, dar, das, daf]. Needs this tick's find_setup.
    pub fn act_setup(&mut self, a: &VarArray) -> bool {
        self.act.on = false;
        if !self.on || a.len() < 19 {
            return false;
        }
        let c = &mut self.act;
        if c.keys.is_none() {
            c.keys = Some(AKeys::new());
        }
        let pi = |j: usize| -> Option<Vec<i32>> { a.at(j).try_to::<PackedInt32Array>().ok().map(|p| p.as_slice().to_vec()) };
        let pb = |j: usize| -> Option<Vec<u8>> { a.at(j).try_to::<PackedByteArray>().ok().map(|p| p.as_slice().to_vec()) };
        let (Some(ids), Some(skip), Some(atg), Some(nores)) = (pi(0), pb(1), pi(2), pb(3)) else { return false };
        if skip.len() != ids.len() || atg.len() != ids.len() {
            return false;
        }
        let Ok(ev) = a.at(4).try_to::<VarDictionary>() else { return false };
        let gi = |j: usize| -> Option<i64> { vint(&a.at(j)) };
        let (Some(se), Some(see), Some(rf), Some(rp), Some(fl), Some(rd)) = (gi(5), gi(6), gi(7), gi(8), gi(10), gi(12)) else {
            return false;
        };
        let Some(trf) = vfloat(&a.at(9)) else { return false };
        let Ok(terr) = a.at(11).try_to::<PackedByteArray>() else { return false };
        let pf = |j: usize| -> Option<Vec<f64>> { a.at(j).try_to::<PackedFloat64Array>().ok().map(|p| p.as_slice().to_vec()) };
        let (Some(dar), Some(das), Some(daf)) = (pf(13), pf(14), pi(15)) else { return false };
        if se <= 0 || see <= 0 || !(0..=255).contains(&rd) {
            return false;
        }
        let Ok(height) = a.at(16).try_to::<PackedByteArray>() else { return false };
        let (Some(plain), Some(ml)) = (gi(17), gi(18)) else { return false };
        c.ids = ids;
        c.skip = skip;
        c.atg = atg;
        c.nores = nores;
        c.ev = Some(ev);
        c.scan_every = se;
        c.scan_eng = see;
        c.ret_fire = rf;
        c.repath = rp;
        c.trf = trf;
        c.flags = fl;
        c.terr = terr;
        c.ridge = rd as u8;
        c.dar = dar;
        c.das = das;
        c.daf = daf;
        c.vis.clear();
        c.height = height;
        c.plain = plain;
        c.max_level = ml as i32;
        c.on = true;
        true
    }

    pub fn act_run(&mut self, m: &Mirror, i0: i64, stop_id: i64) -> i64 {
        let n = self.act.ids.len() as i64;
        if i0 < 0 || i0 >= n {
            return n * 2;
        }
        if !self.act.on || !self.on || !m.valid || m.tick != self.tick || self.ents.is_none() {
            return i0 * 2 + 1;
        }
        let ents = self.ents.clone().unwrap();
        let Some(k) = self.act.keys.take() else { return i0 * 2 + 1 };
        let r = self.act_loop(m, &ents, &k, i0, stop_id, n);
        self.act.keys = Some(k);
        r
    }

    fn act_loop(&mut self, m: &Mirror, ents: &VarDictionary, k: &AKeys, i0: i64, stop_id: i64, n: i64) -> i64 {
        let mut i = i0 as usize;
        while (i as i64) < n {
            let eid = self.act.ids[i];
            if stop_id < eid as i64 {
                return (i as i64) * 2;
            }
            self.act.stats[0] += 1;
            let o = self.act_entry(m, ents, k, i, eid);
            match o {
                Out::Skip => {
                    self.act.stats[1] += 1;
                    self.act.stats[N_SKIP] += 1;
                }
                Out::Fast => {
                    self.act.stats[1] += 1;
                    self.act.stats[N_FAST] += 1;
                }
                Out::Pick => {
                    self.act.stats[1] += 1;
                    self.act.stats[N_PICK] += 1;
                }
                Out::Del(w) => {
                    self.act.stats[2] += 1;
                    self.act.stats[w] += 1;
                    return (i as i64) * 2 + 1;
                }
            }
            i += 1;
        }
        n * 2
    }

    /// The loop body of combat.gd's act loop for entry i (id eid) up to and including _unit_tick.
    fn act_entry(&mut self, m: &Mirror, ents: &VarDictionary, k: &AKeys, i: usize, eid: i32) -> Out {
        let ev = ents.get_or_nil(&(eid as i64).to_variant());
        if ev.is_nil() {
            return Out::Skip; // destroyed earlier this tick
        }
        let sk = self.act.skip[i];
        if sk != 0 {
            let evd = self.act.ev.as_ref().unwrap();
            if sk == 1 || evd.is_empty() {
                return Out::Skip;
            }
            if sk == 2 && !evd.contains_key(&(self.act.atg[i] as i64).to_variant()) {
                return Out::Skip;
            }
            if sk == 3 && !evd.contains_key(&(eid as i64).to_variant()) {
                return Out::Skip;
            }
        }
        let Ok(mut e) = ev.try_to::<VarDictionary>() else { return Out::Del(D_GUARD) };
        let Ok(mut order) = e.get_or_nil(&k.order).try_to::<VarDictionary>() else { return Out::Del(D_GUARD) };
        let moving = truthy(&e.get_or_nil(&k.moving));
        let has_type = order.contains_key(&k.otype);
        let otv = if has_type { order.get_or_nil(&k.otype) } else { k.idle.clone() };
        // order class as String(e.order.get("type", "idle")) compares (Variant ==, String == StringName)
        let oc: u8 = if otv == k.idle { 0 } else if otv == k.hold { 1 } else if otv == k.attack_move { 2 } else if otv == k.attack { 3 } else { 4 };
        let eng = truthy(&order.get_or_nil(&k.engaged)); // nothing writes it before the reads below
        let iu = eid as usize;
        if sk == 0 && !self.act.nores.is_empty() && self.act.atg[i] < 0 {
            let Some(&nr) = self.act.nores.get(iu) else { return Out::Del(D_GUARD) };
            if nr == 1 {
                if oc == 0 || oc == 1 {
                    return Out::Skip;
                }
                if oc == 2 && moving && !eng {
                    return Out::Skip;
                }
            }
        }
        // ---- _unit_tick
        if truthy(&e.get_or_nil(&k.broken)) {
            e.set(&k.target, &(-1i64).to_variant());
            return Out::Pick;
        }
        let Some(tgt) = vint(&e.get_or_nil(&k.target)) else { return Out::Del(D_GUARD) };
        let tick = self.tick;
        let off_slot = (tick + eid as i64) % self.act.scan_every != 0;
        if tgt >= 0 {
            let cdv = e.get_or_nil(&k.cd_ticks);
            let cdt = if cdv.is_nil() && !e.contains_key(&k.cd_ticks) { Some(0) } else { vint(&cdv) };
            let Some(cdt) = cdt else { return Out::Del(D_GUARD) };
            if !moving && cdt > 1 && ents.contains_key(&tgt.to_variant()) {
                return Out::Fast;
            }
        } else if !moving && off_slot {
            if !has_type {
                return Out::Del(D_GUARD); // e.order.type would raise in GDScript
            }
            if oc == 0 || oc == 1 {
                return Out::Fast;
            }
        }
        let row = match m.row.get(iu) { Some(&r) if r >= 0 => r as usize, _ => return Out::Del(D_GUARD) };
        let dx = m.dx[row];
        if dx < 0 || dx as usize >= self.df.len() || dx as usize >= self.act.daf.len() || dx as usize >= self.act.dar.len()
            || dx as usize >= self.act.das.len() || dx as usize >= self.dmr.len() || dx as usize >= self.dcf.len() {
            return Out::Del(D_GUARD);
        }
        let dx = dx as usize;
        let df = self.df[dx];
        if df & 2 == 0 {
            return Out::Fast; // s.weapon == ""
        }
        let builder = df & 4 != 0;
        if tgt < 0 && oc == 4 {
            let lh = e.get_or_nil(&k.last_hit);
            let lht = if lh.is_nil() && !e.contains_key(&k.last_hit) { Some(-100000) } else { vint(&lh) };
            let Some(lht) = lht else { return Out::Del(D_GUARD) };
            if tick - lht > self.act.ret_fire && !truthy(&order.get_or_nil(&k.bk)) {
                return Out::Fast;
            }
        }
        if tgt < 0 && oc == 2 && moving && !builder && off_slot && !eng {
            return Out::Fast;
        }
        if oc == 3 || builder || oc == 4 {
            return Out::Del(D_ATTACK);
        }
        // _rm(w, e, s) == 1.0 unless G6_RANGE and (s7 / wall-walk state / a raised cell under a ground weapon)
        if self.act.flags & F_G6R != 0 {
            if self.act.flags & F_WW != 0 || e.contains_key(&k.s7) {
                return Out::Del(D_RANGE);
            }
            if !self.act.height.is_empty() && self.dcf[dx] & C_AIR == 0 {
                let p = m.pos[row];
                let (x, y) = (p.x.floor() as i64, p.y.floor() as i64);
                if x >= 0 && y >= 0 && x < self.mw as i64 && y < self.mh as i64 {
                    let hi = (y * self.mw as i64 + x) as usize;
                    let Some(&h) = self.act.height.as_slice().get(hi) else { return Out::Del(D_GUARD) };
                    if h as i64 > self.act.plain {
                        return Out::Del(D_RANGE);
                    }
                }
            }
        }
        let range = self.act.dar[dx];
        let sight = self.act.das[dx];
        let indirect = self.act.daf[dx] & AF_INDIRECT != 0;
        let search_r = if indirect { sight.max(range) } else { sight }; // _search_rm with _rm == 1.0
        if oc == 0 && self.act.flags & F_IDLE_DEL != 0 {
            return Out::Del(D_IDLE);
        }
        let radius = if oc == 1 { range } else { search_r };
        let t = self.act_pick(m, ents, k, row, dx, eid, tgt, radius, range);
        match oc {
            0 => match t {
                Tg::Del(w) => Out::Del(w),
                Tg::Null => {
                    if tgt >= 0 {
                        if moving {
                            return Out::Del(D_STOP);
                        }
                        e.set(&k.target, &(-1i64).to_variant());
                        return Out::Pick;
                    }
                    Out::Fast
                }
                Tg::Unit(tid, trow) => self.act_engage(m, k, &mut e, &mut order, row, dx, tid, trow, moving, false),
            },
            1 => match t {
                Tg::Del(w) => Out::Del(w),
                Tg::Null => {
                    e.set(&k.target, &(-1i64).to_variant());
                    Out::Pick
                }
                Tg::Unit(tid, _) => {
                    // e.target = t.id; _fire(w, e, s, t): returns at its first line while _cd(e) > 0
                    match self.act_cd(k, &e) {
                        Some(cd) if cd > 0 => {
                            e.set(&k.target, &(tid as i64).to_variant());
                            Out::Pick
                        }
                        Some(_) => Out::Del(D_FIRE),
                        None => Out::Del(D_GUARD),
                    }
                }
            },
            _ => match t {
                // attack_move
                Tg::Del(w) => Out::Del(w),
                Tg::Null => {
                    if eng || !moving {
                        return Out::Del(D_ORDER);
                    }
                    e.set(&k.target, &(-1i64).to_variant());
                    Out::Pick
                }
                Tg::Unit(tid, trow) => self.act_engage(m, k, &mut e, &mut order, row, dx, tid, trow, moving, true),
            },
        }
    }

    /// combat.gd _cd(e).
    fn act_cd(&self, k: &AKeys, e: &VarDictionary) -> Option<i64> {
        if e.contains_key(&k.cd_ticks) {
            return vint(&e.get_or_nil(&k.cd_ticks));
        }
        let cv = e.get_or_nil(&k.cooldown);
        let c = if cv.is_nil() && !e.contains_key(&k.cooldown) { 0.0 } else { vfloat(&cv)? };
        Some(((c * self.act.trf - 1e-6).ceil() as i64).max(0))
    }

    /// fid's fog visible cells (cached per act_setup; fog is fixed during Combat.tick). None: no fog entry.
    fn act_vis(&mut self, fid: i32) -> Result<Option<PackedByteArray>, ()> {
        if let Some((_, v)) = self.act.vis.iter().find(|(f, _)| *f == fid) {
            return Ok(Some(v.clone()));
        }
        let fv = self.fog.as_ref().unwrap().get_or_nil(&(fid as i64).to_variant());
        if fv.is_nil() {
            return Ok(None);
        }
        let k = self.keys.as_ref().unwrap();
        let Ok(fd) = fv.try_to::<VarDictionary>() else { return Err(()) };
        let Ok(v) = fd.get_or_nil(&k.visible).try_to::<PackedByteArray>() else { return Err(()) };
        self.act.vis.push((fid, v.clone()));
        Ok(Some(v))
    }

    /// combat.gd _valid_target(w, fid, tid, s) for a unit target with a mirror row (anything else: Del).
    fn act_valid(&mut self, m: &Mirror, ents: &VarDictionary, k: &AKeys, fid: i32, dx: usize, tid: i64) -> Tg {
        if tid < 0 {
            return Tg::Null;
        }
        let tv = ents.get_or_nil(&tid.to_variant());
        if tv.is_nil() {
            return Tg::Null;
        }
        let trow = match m.row.get(tid as usize) { Some(&r) if r >= 0 => r as usize, _ => return Tg::Del(D_VALID) };
        let Ok(t) = tv.try_to::<VarDictionary>() else { return Tg::Del(D_GUARD) };
        if !self.is_enemy(fid, m.owner[trow]) {
            return Tg::Null;
        }
        if t.contains_key(&k.marked_until) {
            return Tg::Del(D_VALID);
        }
        // Fog.enemy_visible: fid's visible cell under the target (then concealed_enemy: in legal())
        let vis = match self.act_vis(fid) { Ok(Some(v)) => v, Ok(None) => return Tg::Null, Err(()) => return Tg::Del(D_GUARD) };
        let p = m.pos[trow];
        let (cx, cy) = (p.x.floor() as i64, p.y.floor() as i64);
        if cx < 0 || cy < 0 || cx >= self.mw as i64 || cy >= self.mh as i64 {
            return Tg::Null;
        }
        let vi = (cy * self.mw as i64 + cx) as usize;
        if vi >= vis.len() {
            return Tg::Del(D_GUARD);
        }
        if vis.as_slice()[vi] != 1 {
            return Tg::Null;
        }
        let Some(fix) = self.fi(fid) else { return Tg::Del(D_GUARD) };
        let tk = self.ftk.get(fix).copied();
        let aa = self.df[dx] & 1 != 0;
        let naval_only = self.dcf[dx] & C_NAVAL_ONLY != 0;
        let mut sp: Option<Option<VarDictionary>> = None;
        let mut terr: Option<PackedByteArray> = None;
        let fk = self.keys.as_ref().unwrap();
        match self.legal(m, ents, fk, tid as i32, aa, naval_only, &mut sp, tk, &mut terr) {
            Leg::Ok => Tg::Unit(tid as i32, trow),
            Leg::No => Tg::Null,
            Leg::Fb(_) => Tg::Del(D_VALID),
        }
    }

    /// combat.gd _pick(w, e, radius, ...) (_no_search is false in the act loop; _rm == 1.0).
    #[allow(clippy::too_many_arguments)]
    fn act_pick(&mut self, m: &Mirror, ents: &VarDictionary, k: &AKeys, row: usize, dx: usize, eid: i32, tgt: i64,
                radius: f64, range: f64) -> Tg {
        let fid = m.owner[row];
        let tick = self.tick;
        let due = |p: i64| (tick + eid as i64) % p == 0;
        if self.dcf[dx] & C_ROOF_OUT != 0 {
            return Tg::Del(D_VALID); // _g5_ok roof rule (and find FBs on it)
        }
        match self.act_valid(m, ents, k, fid, dx, tgt) {
            Tg::Del(w) => return Tg::Del(w),
            Tg::Unit(tid, trow) => {
                let p = m.pos[row];
                let q = m.pos[trow];
                let (ddx, ddy) = (p.x - q.x, p.y - q.y);
                let d = ((ddx * ddx + ddy * ddy).sqrt()) as f64;
                if !(d > radius || d < self.dmr[dx]) {
                    if !due(self.act.scan_every) {
                        return Tg::Unit(tid, trow);
                    }
                    if !due(self.act.scan_eng) && d <= range {
                        return Tg::Unit(tid, trow);
                    }
                }
            }
            Tg::Null => {
                if tgt < 0 && !due(self.act.scan_every) {
                    return Tg::Null;
                }
            }
        }
        let r = self.find(m, eid as i64, radius);
        if r == FB {
            return Tg::Del(D_FIND);
        }
        if r < 0 || !ents.contains_key(&r.to_variant()) {
            return Tg::Null;
        }
        match m.row.get(r as usize) {
            Some(&tr) if tr >= 0 => Tg::Unit(r as i32, tr as usize),
            _ => Tg::Del(D_VALID), // a building pick: _engage on a building is not ported
        }
    }

    /// combat.gd _engage(w, e, s, t, true) (+ the attack_move engaged write before it) for a unit target.
    #[allow(clippy::too_many_arguments)]
    fn act_engage(&mut self, m: &Mirror, k: &AKeys, e: &mut VarDictionary, order: &mut VarDictionary, row: usize, dx: usize,
                  tid: i32, trow: usize, moving: bool, am: bool) -> Out {
        // Spread8.mark: hand over whenever its cheap preconditions hold (can_open not ported)
        if self.act.flags & F_SP8 != 0 && self.act.daf[dx] & AF_A8INF != 0 && !e.contains_key(&k.sp8) {
            return Out::Del(D_SP8);
        }
        let p = m.pos[row];
        let tp = m.pos[trow];
        let (ddx, ddy) = (p.x - tp.x, p.y - tp.y);
        let d = ((ddx * ddx + ddy * ddy).sqrt()) as f64;
        let mr = self.dmr[dx];
        let range = self.act.dar[dx];
        let indirect = self.act.daf[dx] & AF_INDIRECT != 0;
        let fire_ok = d <= range && d >= mr
            && (indirect || (line_clear_core(self.act.terr.as_slice(), self.mw, self.mh, self.act.ridge, p, tp)
                && (self.act.flags & F_G6L == 0 || self.dcf[dx] & C_AIR != 0 || self.act.height.is_empty()
                    || height_los_core(self.act.height.as_slice(), self.mw, self.mh, self.act.max_level, p, tp))));
        if fire_ok {
            if moving {
                return Out::Del(D_STOP);
            }
            match self.act_cd(k, e) {
                Some(cd) if cd > 0 => {}
                Some(_) => return Out::Del(D_FIRE),
                None => return Out::Del(D_GUARD),
            }
        } else {
            if d < mr {
                return Out::Del(D_CHASE);
            }
            if !moving {
                return Out::Del(D_CHASE);
            }
            let gv = e.get_or_nil(&k.chase_goal);
            let last_goal = if gv.is_nil() && !e.contains_key(&k.chase_goal) {
                Vector2::new(-1000.0, -1000.0)
            } else {
                match gv.try_to::<Vector2>() { Ok(v) => v, Err(_) => return Out::Del(D_GUARD) }
            };
            let cv = e.get_or_nil(&k.chase_tick);
            let ct = if cv.is_nil() && !e.contains_key(&k.chase_tick) { Some(-100000) } else { vint(&cv) };
            let Some(ct) = ct else { return Out::Del(D_GUARD) };
            let (gx, gy) = (tp.x - last_goal.x, tp.y - last_goal.y);
            let gd = ((gx * gx + gy * gy).sqrt()) as f64;
            if self.tick - ct >= self.act.repath && gd > 1.0 {
                return Out::Del(D_CHASE);
            }
        }
        if am {
            order.set(&k.engaged, &true.to_variant());
        }
        e.set(&k.target, &(tid as i64).to_variant());
        Out::Pick
    }
}
