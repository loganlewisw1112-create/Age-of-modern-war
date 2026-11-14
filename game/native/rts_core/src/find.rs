//! G7.1 PERFSIM71-5 (rts_core 0.6.1): native Combat._find (docs/NATIVE_COMBAT71.md phase 2).
//!
//! `find(eid, radius)` returns what combat.gd `_find` returns for a FULL unit shooter of this tick's
//! mirror: the id of the picked unit or building, -1 for none, or FB (-2) = "ask the GDScript _find".
//! FB whenever a rule without a native port could decide the pick: a candidate that passes every
//! native filter but is a `hid` sniper (spot list), an unrevealed soldier on a FOREST cell
//! (Fog._spotted), an aircraft (Air.can_target), or carries a G6 visibility key (submerged / camo_net /
//! cloak_hid / garrisoned_in); a roof_out shooter; a shooter outside the mirror / grid; a def without
//! columns. Per-tick guards (WallFire7.any, a G6 test spy) stay in combat.gd (no find_setup that tick).
//!
//! Reads: tick-fixed values from the mirror (shooter / candidate pos, owner, def index, team; pos and
//! owner are fixed during Combat.tick: mirror_check), per-def columns filled once per def (combat.gd
//! _dx_of: df, dmr, dcf), and LIVE only what the act loop can change, only for the candidate being
//! decided: alive (w.entities), morale / hid / last_fired_tick / wounded / air_landed / G6 keys, the
//! Senses7 spot set of the shooter's team, fog visible cells, terrain.
//! The pick follows _find path for path: the pre-batched (or single) nearest_enemy candidate when it
//! is legal, else the first legal id of the sorted visible scan (= the (f32 distance, id) argmin of the
//! legal set), then enemy buildings by (distance, id). Float math as GDScript: f32 Vector2 distances,
//! f64 range compares. Deterministic: input order only, no hash order, no RNG, no threads.

use crate::fastdict::VP;
use crate::grid::RtsGrid;
use crate::mirror::Mirror;
use godot::prelude::*;
use godot::sys;

#[path = "act.rs"]
pub mod act;

pub const FB: i64 = -2;
pub const C_AIR: i32 = 1;
pub const C_NAVAL_SHIP: i32 = 2;
pub const C_NAVAL_ONLY: i32 = 4;
pub const C_ROOF_OUT: i32 = 8;
pub const C_INF: i32 = 16;
pub const C_UNIT: i32 = 32;

/// stats slots: 0 calls, 1 fallbacks, then fallback reasons
pub const S_GUARD: usize = 2; // no mirror row / grid index / columns / team / fog entry
pub const S_HID: usize = 3;
pub const S_FOREST: usize = 4;
pub const S_G6: usize = 5;
pub const S_AIR: usize = 6;
pub const S_ROOF: usize = 7;
pub const S_SPOT: usize = 8; // Senses7 spot set not a Dictionary / no tkey
pub const S_BG6: usize = 9; // building with a G6 key
pub const NSTATS: usize = 10;

struct FKeys {
    morale: StringName,
    hid: StringName,
    lft: StringName,
    submerged: StringName,
    camo_net: StringName,
    cloak_hid: StringName,
    garrisoned_in: StringName,
    wounded: StringName,
    air_landed: StringName,
    visible: Variant,
    terrain: Variant,
}

impl FKeys {
    fn new() -> Self {
        let n = |s: &str| StringName::from(s);
        FKeys {
            morale: n("morale"), hid: n("hid"), lft: n("last_fired_tick"), submerged: n("submerged"),
            camo_net: n("camo_net"), cloak_hid: n("cloak_hid"), garrisoned_in: n("garrisoned_in"),
            wounded: n("wounded"), air_landed: n("air_landed"),
            visible: GString::from("visible").to_variant(), terrain: GString::from("terrain").to_variant(),
        }
    }
}

#[derive(Default)]
pub struct FindCtx {
    pub on: bool,
    pub tick: i64,
    grid: Option<Gd<RtsGrid>>,
    max_rad: f32,
    ents: Option<VarDictionary>,
    fog: Option<VarDictionary>,
    map: Option<VarDictionary>,
    spot: Option<VarDictionary>,
    fids: Vec<i32>,
    fteam: Vec<i32>,
    ftk: Vec<i64>,
    neutral: i32,
    reveal: i64,
    forest: i64,
    mw: i32,
    mh: i32,
    nidx: Vec<i32>,
    pre_at: Vec<i32>,
    pre_c: Vec<i32>,
    pre_r: Vec<f32>,
    df: Vec<i32>,
    dmr: Vec<f64>,
    dcf: Vec<i32>,
    b_id: Vec<i32>,
    b_owner: Vec<i32>,
    b_cx: Vec<i32>,
    b_cy: Vec<i32>,
    b_sz: Vec<i64>,
    b_szf: Vec<f64>,
    keys: Option<FKeys>,
    buf: Vec<(f32, i32)>,
    pub stats: [i64; NSTATS],
    /// G7.1 PERFSIM71-6: phase 3a act driver inputs (act.rs)
    pub act: act::ActCtx,
}

fn vint(v: &Variant) -> Option<i64> {
    match v.get_type() {
        VariantType::INT => Some(v.to::<i64>()),
        VariantType::FLOAT => Some(v.to::<f64>() as i64),
        VariantType::BOOL => Some(v.to::<bool>() as i64),
        _ => None,
    }
}

fn vfloat(v: &Variant) -> Option<f64> {
    match v.get_type() {
        VariantType::INT => Some(v.to::<i64>() as f64),
        VariantType::FLOAT => Some(v.to::<f64>()),
        _ => None,
    }
}

/// variant_get_named on the Variant at vp (key presence semantics for a Dictionary): (present, value).
#[inline]
unsafe fn gnp(vp: VP, key: &StringName) -> (bool, Variant) {
    let mut valid: sys::GDExtensionBool = 0;
    let v = Variant::new_with_var_uninit(|ptr| {
        sys::interface_fn!(variant_get_named)(vp.0 as sys::GDExtensionConstVariantPtr, key.string_sys(), ptr, &mut valid)
    });
    if valid != 0 { (true, v) } else { (false, Variant::nil()) }
}

#[inline]
fn vp_of(v: &Variant) -> VP {
    VP(v.var_sys() as *const u8)
}

/// Godot is_equal_approx(double, double) (CMP_EPSILON 0.00001).
#[inline]
fn is_equal_approx(a: f64, b: f64) -> bool {
    if a == b {
        return true;
    }
    let mut tol = 0.00001 * a.abs();
    if tol < 0.00001 {
        tol = 0.00001;
    }
    (a - b).abs() < tol
}

enum Leg {
    Ok,
    No,
    Fb(usize),
}

impl FindCtx {
    /// Per-tick inputs (combat.gd, after the RtsGrid rebuild and the scan pre-batch). false = off this tick.
    pub fn setup(&mut self, a: &VarArray) -> bool {
        self.on = false;
        if a.len() < 22 {
            return false;
        }
        if self.keys.is_none() {
            self.keys = Some(FKeys::new());
        }
        let pi = |j: usize| -> Vec<i32> { a.at(j).try_to::<PackedInt32Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default() };
        self.grid = a.at(0).try_to::<Gd<RtsGrid>>().ok();
        let Some(g) = self.grid.as_ref() else { return false };
        self.max_rad = g.bind().max_rad();
        self.ents = a.at(1).try_to::<VarDictionary>().ok();
        self.fog = a.at(2).try_to::<VarDictionary>().ok();
        self.map = a.at(3).try_to::<VarDictionary>().ok();
        self.spot = a.at(4).try_to::<VarDictionary>().ok();
        if self.ents.is_none() || self.fog.is_none() || self.map.is_none() {
            return false;
        }
        self.fids = pi(5);
        self.fteam = pi(6);
        self.ftk = a.at(7).try_to::<PackedInt64Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        if self.fteam.len() != self.fids.len() {
            return false;
        }
        let gi = |j: usize| -> Option<i64> { vint(&a.at(j)) };
        let (Some(neu), Some(tick), Some(rev), Some(fo), Some(mw), Some(mh)) = (gi(8), gi(9), gi(10), gi(11), gi(20), gi(21)) else {
            return false;
        };
        self.neutral = neu as i32;
        self.tick = tick;
        self.reveal = rev;
        self.forest = fo;
        self.mw = mw as i32;
        self.mh = mh as i32;
        self.nidx = pi(12);
        let scan_ids = pi(13);
        let res = pi(14);
        let scan_r: Vec<f32> = a.at(15).try_to::<PackedFloat32Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        self.pre_at.clear();
        self.pre_at.resize(self.nidx.len(), -1);
        self.pre_c.clear();
        self.pre_r.clear();
        if !scan_ids.is_empty() {
            if res.len() < scan_ids.len() || scan_r.len() < scan_ids.len() {
                return false;
            }
            // pre[scan_ids[i]] = Vector2(float(res[i]), scan_r[i]) (a later i overwrites an earlier one)
            for (i, &id) in scan_ids.iter().enumerate() {
                if id < 0 || id as usize >= self.pre_at.len() {
                    return false;
                }
                self.pre_at[id as usize] = self.pre_c.len() as i32;
                self.pre_c.push((res[i] as f32) as i32);
                self.pre_r.push(scan_r[i]);
            }
        }
        self.df = pi(16);
        self.dmr = a.at(17).try_to::<PackedFloat64Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        self.dcf = pi(18);
        let Ok(blds) = a.at(19).try_to::<VarArray>() else { return false };
        self.b_id.clear();
        self.b_owner.clear();
        self.b_cx.clear();
        self.b_cy.clear();
        self.b_sz.clear();
        self.b_szf.clear();
        let (k_id, k_owner, k_cell, k_size) = (GString::from("id").to_variant(), GString::from("owner").to_variant(),
                                               GString::from("cell").to_variant(), GString::from("size").to_variant());
        for i in 0..blds.len() {
            let Ok(b) = blds.at(i).try_to::<VarDictionary>() else { return false };
            let (Some(id), Some(ow)) = (vint(&b.get_or_nil(&k_id)), vint(&b.get_or_nil(&k_owner))) else { return false };
            let Ok(cell) = b.get_or_nil(&k_cell).try_to::<Vector2i>() else { return false };
            let sv = b.get_or_nil(&k_size);
            let (Some(sz), Some(szf)) = (vint(&sv), vfloat(&sv)) else { return false };
            self.b_id.push(id as i32);
            self.b_owner.push(ow as i32);
            self.b_cx.push(cell.x);
            self.b_cy.push(cell.y);
            self.b_sz.push(sz);
            self.b_szf.push(szf);
        }
        self.on = true;
        true
    }

    fn fi(&self, fid: i32) -> Option<usize> {
        self.fids.iter().position(|&f| f == fid)
    }

    /// SimWorld.is_enemy(a, b).
    fn is_enemy(&self, a: i32, b: i32) -> bool {
        if a == b || a == self.neutral || b == self.neutral {
            return false;
        }
        match (self.fi(a), self.fi(b)) {
            (Some(i), Some(j)) => self.fteam[i] != self.fteam[j],
            _ => true,
        }
    }

    pub fn find(&mut self, m: &Mirror, eid: i64, radius: f64) -> i64 {
        self.stats[0] += 1;
        let r = match self.find0(m, eid, radius) {
            Ok(r) => r,
            Err(why) => {
                self.stats[1] += 1;
                self.stats[why] += 1;
                FB
            }
        };
        r
    }

    /// Legality of unit candidate cid for shooter (fid, aa, naval_only): every filter of _cand_ok /
    /// the _find scan (all pure predicates, so their order only changes which FB is reported).
    #[allow(clippy::too_many_arguments)]
    fn legal(&self, m: &Mirror, ents: &VarDictionary, k: &FKeys, cid: i32, aa: bool, naval_only: bool,
             sp: &mut Option<Option<VarDictionary>>, tk: Option<i64>, terr: &mut Option<PackedByteArray>) -> Leg {
        let cv = ents.get_or_nil(&(cid as i64).to_variant());
        if cv.is_nil() {
            return Leg::No; // dead this tick
        }
        if cv.get_type() != VariantType::DICTIONARY {
            return Leg::Fb(S_GUARD);
        }
        let cu = cid as usize;
        let crow = match m.row.get(cu) { Some(&r) if r >= 0 => r as usize, _ => return Leg::Fb(S_GUARD) };
        let cdx = m.dx[crow];
        if cdx < 0 || cdx as usize >= self.dcf.len() {
            return Leg::Fb(S_GUARD);
        }
        let ccf = self.dcf[cdx as usize];
        if ccf & C_UNIT == 0 {
            return Leg::Fb(S_GUARD);
        }
        let vp = vp_of(&cv);
        let mut fb: usize = 0;
        // air rule + _g5_ok
        if ccf & C_AIR != 0 {
            let landed = unsafe { gnp(vp, &k.air_landed) }.1.booleanize();
            if !aa && !landed {
                return Leg::No;
            }
            fb = S_AIR; // _g5_ok: Air.can_target
        }
        if naval_only && ccf & C_NAVAL_SHIP == 0 {
            return Leg::No;
        }
        if unsafe { gnp(vp, &k.wounded) }.1.booleanize() {
            return Leg::No;
        }
        // Fog.concealed / concealed_enemy + G4bMech.hidden_from
        let (_, hv) = unsafe { gnp(vp, &k.hid) };
        let hid = hv.booleanize();
        if hid {
            if fb == 0 {
                fb = S_HID;
            }
        } else if unsafe { gnp(vp, &k.morale) }.0 {
            let (lp, lv) = unsafe { gnp(vp, &k.lft) };
            let lft = if lp { vint(&lv).unwrap_or(0) } else { -9999 };
            if self.tick - lft >= self.reveal {
                // Senses7.hidden(w, fid, e): spot set of the shooter's team, is_inf_target
                if let Some(spot) = self.spot.as_ref() {
                    if sp.is_none() {
                        let Some(t) = tk else { return Leg::Fb(S_SPOT) };
                        let sv = spot.get_or_nil(&t.to_variant());
                        if sv.is_nil() {
                            *sp = Some(None);
                        } else if let Ok(d) = sv.try_to::<VarDictionary>() {
                            *sp = Some(Some(d));
                        } else {
                            return Leg::Fb(S_SPOT);
                        }
                    }
                    if let Some(Some(d)) = sp.as_ref() {
                        if ccf & C_INF != 0 && !d.contains_key(&(cid as i64).to_variant()) {
                            return Leg::No;
                        }
                    }
                }
                // FOREST cell: concealed unless spotted (Fog._spotted: not ported)
                let cp = m.pos[crow];
                let (x, y) = (cp.x.floor() as i64, cp.y.floor() as i64);
                if x >= 0 && y >= 0 && x < self.mw as i64 && y < self.mh as i64 {
                    if terr.is_none() {
                        let tv = self.map.as_ref().unwrap().get_or_nil(&k.terrain);
                        let Ok(t) = tv.try_to::<PackedByteArray>() else { return Leg::Fb(S_GUARD) };
                        *terr = Some(t);
                    }
                    let t = terr.as_ref().unwrap();
                    let ti = (y * self.mw as i64 + x) as usize;
                    if ti >= t.len() {
                        return Leg::Fb(S_GUARD);
                    }
                    if t.as_slice()[ti] as i64 == self.forest && fb == 0 {
                        fb = S_FOREST;
                    }
                }
            }
        }
        // _g6_hidden: G6Hooks.visible_to = Sonar x Fieldworks camo x MachineG6 cloak x Garrison
        if fb == 0 {
            let g6 = unsafe { gnp(vp, &k.submerged) }.0
                || unsafe { gnp(vp, &k.camo_net) }.0
                || unsafe { gnp(vp, &k.cloak_hid) }.1.booleanize()
                || unsafe { gnp(vp, &k.garrisoned_in) }.0;
            if g6 {
                fb = S_G6;
            }
        }
        if fb != 0 { Leg::Fb(fb) } else { Leg::Ok }
    }

    fn find0(&mut self, m: &Mirror, eid: i64, radius: f64) -> Result<i64, usize> {
        if !self.on || !m.valid || m.tick != self.tick || eid < 0 {
            return Err(S_GUARD);
        }
        let iu = eid as usize;
        let row = match m.row.get(iu) { Some(&r) if r >= 0 => r as usize, _ => return Err(S_GUARD) };
        let si = match self.nidx.get(iu) { Some(&s) if s >= 0 => s as usize, _ => return Err(S_GUARD) };
        if m.tf[row] <= 0 {
            return Err(S_GUARD);
        }
        let dxi = m.dx[row];
        if dxi < 0 || dxi as usize >= self.df.len() || dxi as usize >= self.dmr.len() || dxi as usize >= self.dcf.len() {
            return Err(S_GUARD);
        }
        let dx = dxi as usize;
        let scf = self.dcf[dx];
        if scf & C_ROOF_OUT != 0 {
            return Err(S_ROOF);
        }
        let aa = self.df[dx] & 1 != 0;
        let naval_only = scf & C_NAVAL_ONLY != 0;
        let mr = self.dmr[dx];
        let mr2 = mr * mr;
        let r2 = radius * radius;
        let fid = m.owner[row];
        let p = m.pos[row];
        let Some(fix) = self.fi(fid) else { return Err(S_GUARD) };
        let mt = self.fteam[fix];
        let tk = self.ftk.get(fix).copied();
        let k = self.keys.as_ref().unwrap();
        let ents = self.ents.as_ref().unwrap();
        // fid's visible cells (w.fog[fid].visible; empty when fog has no fid)
        let fv = self.fog.as_ref().unwrap().get_or_nil(&(fid as i64).to_variant());
        let vis: PackedByteArray = if fv.is_nil() {
            PackedByteArray::new()
        } else {
            let Ok(fd) = fv.try_to::<VarDictionary>() else { return Err(S_GUARD) };
            let Ok(v) = fd.get_or_nil(&k.visible).try_to::<PackedByteArray>() else { return Err(S_GUARD) };
            v
        };
        let vs = vis.as_slice();
        let nvis = vs.len() as i64;
        let mw = self.mw as i64;
        let mut sp: Option<Option<VarDictionary>> = None;
        let mut terr: Option<PackedByteArray> = None;
        let mut best_d = f64::INFINITY;
        let mut best_id: i64 = 0;
        let mut have = false;
        // ---- units: the nearest raw candidate (pre-batched or one nearest query), else the sorted scan
        let pa = self.pre_at.get(iu).copied().unwrap_or(-1);
        let grid = self.grid.as_ref().unwrap().bind();
        let cand: i32 = if pa >= 0 && is_equal_approx(self.pre_r[pa as usize] as f64, radius) {
            self.pre_c[pa as usize]
        } else {
            grid.nearest_one(si, radius as f32, if aa { 0 } else { 1 }, self.max_rad)
        };
        if cand >= 0 {
            let mut took = false;
            // every grid item is a mirror row; a dead candidate is rejected inside legal() (alive test)
            let cr = match m.row.get(cand as usize) { Some(&r) if r >= 0 => r as usize, _ => return Err(S_GUARD) };
            let cp = m.pos[cr];
            let (ex, ey) = (p.x - cp.x, p.y - cp.y);
            let d2 = (ex * ex + ey * ey) as f64;
            let vi = (cp.y.floor() as i64) * mw + (cp.x.floor() as i64);
            if !(d2 > r2 || d2 < mr2) && vi >= 0 && vi < nvis && vs[vi as usize] == 1 {
                match self.legal(m, ents, k, cand, aa, naval_only, &mut sp, tk, &mut terr) {
                    Leg::Ok => {
                        best_d = d2;
                        best_id = cand as i64;
                        have = true;
                        took = true;
                    }
                    Leg::No => {}
                    Leg::Fb(w) => return Err(w),
                }
            }
            if !took {
                let mut buf = std::mem::take(&mut self.buf);
                grid.scan_sorted_buf(p, radius as f32, mt, vs, self.mw, &mut buf);
                let mut res: Result<(), usize> = Ok(());
                for &(dd32, cid) in buf.iter() {
                    let dd = dd32 as f64;
                    if dd > r2 || dd < mr2 {
                        continue;
                    }
                    match self.legal(m, ents, k, cid, aa, naval_only, &mut sp, tk, &mut terr) {
                        Leg::Ok => {
                            best_d = dd;
                            best_id = cid as i64;
                            have = true;
                            break;
                        }
                        Leg::No => {}
                        Leg::Fb(w) => {
                            res = Err(w);
                            break;
                        }
                    }
                }
                self.buf = buf;
                res?;
            }
        }
        drop(grid);
        // ---- enemy buildings of fid: (distance to the footprint, id) against the unit pick
        let (px, py) = (p.x as f64, p.y as f64);
        for j in 0..self.b_id.len() {
            if !self.is_enemy(fid, self.b_owner[j]) {
                continue;
            }
            let x0 = self.b_cx[j] as f64;
            let y0 = self.b_cy[j] as f64;
            let x1 = x0 + self.b_szf[j];
            let y1 = y0 + self.b_szf[j];
            let qx = if px < x0 { x0 } else if px > x1 { x1 } else { px };
            let qy = if py < y0 { y0 } else if py > y1 { y1 } else { py };
            let (ddx, ddy) = (p.x - qx as f32, p.y - qy as f32);
            let d = ((ddx * ddx + ddy * ddy).sqrt()) as f64;
            let d2b = d * d;
            if d2b > r2 || d2b < mr2 {
                continue;
            }
            let bid = self.b_id[j] as i64;
            if d2b > best_d || (d2b == best_d && bid > best_id) {
                continue;
            }
            let bv = ents.get_or_nil(&bid.to_variant());
            if bv.is_nil() {
                continue;
            }
            // Fog.entity_visible -> _building_seen (any footprint cell visible to fid)
            if fv.is_nil() {
                continue;
            }
            let (cx, cy, s) = (self.b_cx[j] as i64, self.b_cy[j] as i64, self.b_sz[j]);
            let mut seen = false;
            'cells: for y in cy..cy + s {
                for x in cx..cx + s {
                    if x >= 0 && y >= 0 && x < mw && y < self.mh as i64 {
                        let vi = y * mw + x;
                        if vi >= nvis {
                            return Err(S_GUARD); // GDScript would index out of range
                        }
                        if vs[vi as usize] == 1 {
                            seen = true;
                            break 'cells;
                        }
                    }
                }
            }
            if !seen {
                continue;
            }
            if bv.get_type() != VariantType::DICTIONARY {
                return Err(S_GUARD);
            }
            let vp = vp_of(&bv);
            let g6 = unsafe { gnp(vp, &k.submerged) }.0
                || unsafe { gnp(vp, &k.camo_net) }.0
                || unsafe { gnp(vp, &k.cloak_hid) }.1.booleanize()
                || unsafe { gnp(vp, &k.garrisoned_in) }.0;
            if g6 {
                return Err(S_BG6);
            }
            best_d = d2b;
            best_id = bid;
            have = true;
        }
        Ok(if have { best_id } else { -1 })
    }
}
