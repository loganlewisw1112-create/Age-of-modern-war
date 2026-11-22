//! G7.1 SWARMNAT71 (docs/SWARM_NATIVE71.md sections 3-4): RtsSwarmDraw, the native unit kernel of
//! presentation/view/entity_layer.gd `_refresh` for "plain" units on motion-layer frames (motion_on, not far LOD,
//! no bay crafts). It is a line-for-line port of the GDScript full path for those units: position interpolation,
//! view cull, terrain raise / height lift, fog, Motion.step (presentation/view/motion.gd), the frame choice,
//! VehAnim61.pick, the facing row with hysteresis, the drawn7 row and the item push. Float semantics follow
//! GDScript: scalars are f64, Vector2 / Color / Rect2 / PackedFloat32Array values are f32 (every Vector2 op rounds
//! to f32; a Vector2 built from f64 scalars rounds each component once).
//!
//! The kernel returns at the first unit it cannot draw exactly (before any side effect of that unit) and the GDScript
//! path draws it, so push order, sort keys and every counter stay what the GDScript path gives. Items go to native
//! buffers at the push indices the GDScript path would use; `scatter` writes them into the layer's arrays after the
//! unit loop. Motion state stays in motion.gd's `vs` Dictionary (id -> PackedFloat32Array(23)): each stepped unit's
//! array is read and written back, so a unit can move between the two paths from frame to frame with no handover.
//! Display only: nothing here touches the sim (sim hashes cannot move).

use godot::prelude::*;
use std::collections::HashMap;
use std::sync::Arc;

const ABS: i64 = -999_999; // "key absent" in a record (never equal to a frame column)

// RenderSnap flags
const F_MOVING: i32 = 1;
const F_FIRING: i32 = 2;
const F_AIR: i32 = 4;
const F_HID: i32 = 16;
const F_DEPLOYED: i32 = 32;
const F_G6: i32 = 1 << 6;
const F_S7: i32 = 1 << 7;
const F_WORK: i32 = 1 << 16;
const F_UNLOAD: i32 = 1 << 17;
const F_WOUNDED: i32 = 1 << 18;
const F_ABOARD: i32 = 1 << 19;
const F_LANDED: i32 = 1 << 20;
const F_SHIP: i32 = 1 << 21;
const F_DRONE: i32 = 1 << 22;
const F_EVAC: i32 = 1 << 23;
const F_TACTICAL: i32 = 1 << 26;
const F_SLUNG: i32 = 1 << 27;
const POSE_MASK: i32 = F_DEPLOYED | F_WORK | F_UNLOAD;
const NONPLAIN: i32 = F_AIR | F_HID | F_S7 | F_WOUNDED | F_LANDED | F_SHIP | F_EVAC | F_SLUNG;

// Motion (motion.gd)
const P_MOVING: i32 = 1;
const P_FIRING: i32 = 2;
const P_RUN: i32 = 4;
const P_PINNED: i32 = 8;
const P_SUPPRESSED: i32 = 16;
const P_WOUNDED: i32 = 32;
const P_BROKEN: i32 = 64;
const P_THROW: i32 = 128;
const RUN_SPEED: f64 = 2.3; // entity_layer.gd RUN_SPEED
const CLS_INF: i64 = 0;
const CLS_VEH: i64 = 1;
const CLS_HEAVY: i64 = 2;
const MAX_OFF: f32 = 0.3;
const TURN: [f64; 5] = [10.0, 3.2, 1.6, 3.6, 0.9];
const LAG: [f64; 5] = [0.10, 0.22, 0.30, 0.40, 0.60];
const BACK: f64 = 0.35;
const KICK_T: f64 = 0.09;
const FLINCH_T: f64 = 0.16;
const KICK_EVERY: f64 = 0.55;
const ROW_HYS: f64 = 0.12;
const SUSP_T: f64 = 0.15;
const S_FACE: usize = 0;
const S_T: usize = 1;
const S_VX: usize = 2;
const S_VY: usize = 3;
const S_OX: usize = 4;
const S_OY: usize = 5;
const S_PX: usize = 6;
const S_PY: usize = 7;
const S_KICK: usize = 8;
const S_FLINCH: usize = 9;
const S_SEED: usize = 10;
const S_CLS: usize = 11;
const S_SPD: usize = 12;
const S_FIRE: usize = 13;
const S_TURN: usize = 14;
const S_DIST: usize = 15;
const S_SX: usize = 16;
const S_SY: usize = 17;
const S_MV: usize = 18;
const S_SUSP: usize = 19;
const S_AIM: usize = 20;
const S_ROW: usize = 22;
const S_N: usize = 23;

// VehAnim61
const BANK: f64 = 0.6;
const RECOIL: f64 = 0.3;
const TRACK_PX: f64 = 6.0;
const WALK_PX: f64 = 4.0;
const PULSE_HZ: f64 = 1.5;

// entity_layer.gd
const IDX_MUL: i64 = 4194304;
const Y_OFF: i64 = 65536;

const PI: f64 = std::f64::consts::PI;

// counters (counts()): index -> entity_layer counter
// 0 gc5.aboard, 1 gc6.lifted, 2 gc61.motion, 3 gc5.tactical, 4 gc5.ramp, 5 gc6.command, 6 gc61.veh, 7 gc61.bank,
// 8 gc61.recoil, 9 gc61.track, 10 gc61.flipped, 11 units_drawn, 12 native units drawn (items pushed), 13 kernel calls,
// 14 gc61.a61 (rts_core 0.6.5)
const NC: usize = 15;

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

/// Godot Math::wrapf(double)
fn wrapf(v: f64, mn: f64, mx: f64) -> f64 {
    let r = mx - mn;
    if r.abs() < 0.00001 {
        return mn;
    }
    let res = v - r * ((v - mn) / r).floor();
    if is_equal_approx(res, mx) {
        return mn;
    }
    res
}

fn lerpf(a: f64, b: f64, w: f64) -> f64 {
    a + (b - a) * w
}

fn clampf(v: f64, a: f64, b: f64) -> f64 {
    if v < a {
        a
    } else if v > b {
        b
    } else {
        v
    }
}

fn maxf(a: f64, b: f64) -> f64 {
    if a > b {
        a
    } else {
        b
    }
}

fn minf(a: f64, b: f64) -> f64 {
    if a < b {
        a
    } else {
        b
    }
}

fn posmod(a: i64, b: i64) -> i64 {
    let mut v = a % b;
    if (v < 0 && b > 0) || (v > 0 && b < 0) {
        v += b;
    }
    v
}

fn v2(x: f64, y: f64) -> Vector2 {
    Vector2::new(x as f32, y as f32)
}

fn vlen(v: Vector2) -> f32 {
    (v.x * v.x + v.y * v.y).sqrt()
}

fn vnorm(v: Vector2) -> Vector2 {
    let l = v.x * v.x + v.y * v.y;
    if l != 0.0 {
        let l = l.sqrt();
        Vector2::new(v.x / l, v.y / l)
    } else {
        v
    }
}

fn vmul(v: Vector2, s: f64) -> Vector2 {
    let s = s as f32;
    Vector2::new(v.x * s, v.y * s)
}

fn seed_of(id: i64) -> f64 {
    let h = id.wrapping_mul(2654435761) & 0xFFFFFF;
    h as f64 / 16777216.0
}

fn vint(v: &Variant) -> i64 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>(),
        VariantType::FLOAT => v.to::<f64>() as i64,
        VariantType::BOOL => v.to::<bool>() as i64,
        _ => 0,
    }
}

#[derive(Default, Clone)]
struct Rec {
    def: i32,
    owner: i32,
    pg: i32,
    src: Vector2,
    fw: i64,
    fh: i64,
    off: Vector2,
    fire: i64,
    walk: bool,
    wa: i64,
    wb: i64,
    mv: i64,
    dep: i64,
    work: i64,
    unl: i64,
    tac: i64,
    dive: i64,
    ramp: i64,
    cmd: i64,
    split: i64,
    pg_b: i32,
    tb: Vec<Vector2>,
    sz: Vec<Vector2>,
    offs: Vec<Vector2>,
    mcls: i64,
    v61: bool,
    recoil: i64,
    bank_l: i64,
    bank_r: i64,
    mvs: Vec<i64>,
    track: Vec<i64>,
    burner: i64,
    damaged: i64,
    pulse: i64,
    trk_or_mv: bool,
    dname: Variant,
    // rts_core 0.6.5: the anim61 infantry set (Motion.inf_col columns; empty sheet = a61 false) and _is_inf(dname)
    a61: bool,
    a_walk: [i64; 6],
    a_run: [i64; 6],
    a_crawl: [i64; 2],
    a_reload: [i64; 2],
    a_throw: [i64; 2],
    a_idle: [i64; 2],
    a_crouch: i64,
    a_prone: i64,
    a_fire_s: i64,
    a_fire_c: i64,
    a_fire_p: i64,
    a_wounded: i64,
    is_inf: bool,
}

#[derive(Default)]
struct Item {
    ii: i64,
    key: i64,
    page: i32,
    src: Vector2,
    size: Vector2,
    dst: Vector2,
    dsz: Vector2,
    md: Color,
}

/// Motion.step outputs
struct MOut {
    face: f64,
    off: Vector2,
    px: Vector2,
    flash: f64,
    row: i64,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsSwarmDraw {
    recs: HashMap<i32, Arc<Rec>>,
    post: HashMap<i32, (i32, bool)>,
    fat: HashMap<i32, f64>, // 0.6.5: mirror of EntityLayer._fat (REAL61 Fatigue level)
    // frame inputs
    ids: Vec<i32>,
    pos: Vec<Vector2>,
    prev: Vec<Vector2>,
    fac: Vec<f32>,
    def: Vec<i32>,
    own: Vec<i32>,
    flg: Vec<i32>,
    hp: Vec<f32>,
    sq7f: Vec<u8>,
    terr: Vec<u8>,
    raise: Vec<i32>,
    hl_t: Vec<f32>,
    rp6: Vec<u8>,
    vis: Vec<u8>,
    ally: Vec<u8>,
    n_ally: usize,
    ww: Vec<u8>,
    dfl: Vec<i32>,
    mark: Vec<u8>,
    alpha: f64,
    t: f64,
    vr: [f32; 4],
    mw: i64,
    pf: i32,
    live: bool,
    pframe: i64,
    lod: i64,
    has_g6: bool,
    has_ww: bool,
    has_cr: bool, // 0.6.5: a landed dropship this frame (bay-hide entries for infantry)
    vs: VarDictionary,
    drawn7: VarDictionary,
    // per-call state
    n: i64,
    cdt: f64,
    ck: [f64; 5],
    cb: f64,
    cache_changed: bool,
    items: Vec<Item>,
    vis_i: Vec<i32>,
    vis_sp: Vec<Vector2>,
    bay_ii: Vec<i32>, // 0.6.5: _bay_hide entries [ii, ii + 1, sp, ky] of this frame's native infantry items
    bay_sp: Vec<Vector2>,
    bay_ky: Vec<i32>,
    cnt: [i64; NC],
}

#[godot_api]
impl RtsSwarmDraw {
    /// Drops every art record and posture mirror (new world / new def table / art cache reset).
    #[func]
    fn reset(&mut self) {
        self.recs.clear();
        self.post.clear();
        self.fat.clear();
    }

    /// Unit id left (EntityLayer.on_destroyed / BatchArt.forget): its record and posture mirror go.
    #[func]
    fn forget(&mut self, id: i64) {
        self.recs.remove(&(id as i32));
        self.post.remove(&(id as i32));
        self.fat.remove(&(id as i32));
    }

    /// rts_core 0.6.5: mirror of EntityLayer._fat[id] (written in _refresh_post).
    #[func]
    fn set_fat(&mut self, id: i64, f: f64) {
        self.fat.insert(id as i32, f);
    }

    /// rts_core 0.6.5: this frame's bay-hide entries of native infantry items: [ii PackedInt32Array, sp PackedVector2Array,
    /// ky PackedInt32Array] (the glue appends [ii, ii + 1, sp, ky] to _bay_hide; _apply_bay_hide is order-free).
    #[func]
    fn bay_out(&self) -> VarArray {
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(self.bay_ii.as_slice()).to_variant());
        out.push(&PackedVector2Array::from(self.bay_sp.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(self.bay_ky.as_slice()).to_variant());
        out
    }

    /// Mirror of EntityLayer._post[id] and (_chev[id] > 0 or _pips[id] > 0), written where those change.
    #[func]
    fn set_post(&mut self, id: i64, bits: i64, marked: bool) {
        if bits == 0 && !marked {
            self.post.remove(&(id as i32));
        } else {
            self.post.insert(id as i32, (bits as i32, marked));
        }
    }

    #[func]
    fn has_rec(&self, id: i64) -> bool {
        self.recs.contains_key(&(id as i32))
    }

    /// Registers the art record of a unit the GDScript path just drew (layout: entity_layer.gd _sw_reg).
    #[func]
    fn reg(&mut self, id: i64, r: VarArray) {
        if r.len() < 36 {
            return;
        }
        let gi = |j: usize| vint(&r.at(j));
        let gv = |j: usize| r.at(j).try_to::<Vector2>().unwrap_or(Vector2::ZERO);
        let gpv = |j: usize| r.at(j).try_to::<PackedVector2Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        let gpi = |j: usize| {
            r.at(j).try_to::<PackedInt32Array>().map(|p| p.as_slice().iter().map(|&x| x as i64).collect()).unwrap_or_default()
        };
        let rec = Rec {
            def: gi(0) as i32,
            owner: gi(1) as i32,
            pg: gi(2) as i32,
            src: gv(3),
            fw: gi(4),
            fh: gi(5),
            off: gv(6),
            fire: gi(7),
            walk: gi(8) != 0,
            wa: gi(9),
            wb: gi(10),
            mv: gi(11),
            dep: gi(12),
            work: gi(13),
            unl: gi(14),
            tac: gi(15),
            dive: gi(16),
            ramp: gi(17),
            cmd: gi(18),
            split: gi(19),
            pg_b: gi(20) as i32,
            tb: gpv(21),
            sz: gpv(22),
            offs: gpv(23),
            mcls: gi(24),
            v61: gi(25) != 0,
            recoil: gi(26),
            bank_l: gi(27),
            bank_r: gi(28),
            mvs: gpi(29),
            track: gpi(30),
            burner: gi(31),
            damaged: gi(32),
            pulse: gi(33),
            trk_or_mv: gi(34) != 0,
            dname: r.at(35),
            ..Default::default()
        };
        let mut rec = rec;
        if r.len() >= 38 {
            // 0.6.5: [36] flat anim61 columns walk6 run6 crawl2 reload2 throw2 idle2 crouch prone fire_s fire_c fire_p
            // wounded (26 ints; empty = no set), [37] _is_inf(dname)
            let a: Vec<i64> = gpi(36);
            if a.len() == 26 {
                rec.a61 = true;
                rec.a_walk.copy_from_slice(&a[0..6]);
                rec.a_run.copy_from_slice(&a[6..12]);
                rec.a_crawl.copy_from_slice(&a[12..14]);
                rec.a_reload.copy_from_slice(&a[14..16]);
                rec.a_throw.copy_from_slice(&a[16..18]);
                rec.a_idle.copy_from_slice(&a[18..20]);
                rec.a_crouch = a[20];
                rec.a_prone = a[21];
                rec.a_fire_s = a[22];
                rec.a_fire_c = a[23];
                rec.a_fire_p = a[24];
                rec.a_wounded = a[25];
            } else if !a.is_empty() {
                self.recs.remove(&(id as i32));
                return;
            }
            rec.is_inf = gi(37) != 0;
        }
        self.recs.insert(id as i32, Arc::new(rec));
    }

    /// Per-frame inputs (layout: entity_layer.gd _sw_begin). `vs` = motion.vs, `drawn7` = EntityLayer.drawn7.
    #[func]
    fn begin(&mut self, a: VarArray, vs: VarDictionary, drawn7: VarDictionary) -> bool {
        if a.len() < 19 {
            return false;
        }
        let pi = |j: usize| a.at(j).try_to::<PackedInt32Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        let pb = |j: usize| a.at(j).try_to::<PackedByteArray>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        let pv = |j: usize| a.at(j).try_to::<PackedVector2Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        let pf = |j: usize| a.at(j).try_to::<PackedFloat32Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        self.ids = pi(0);
        self.pos = pv(1);
        self.prev = pv(2);
        self.fac = pf(3);
        self.def = pi(4);
        self.own = pi(5);
        self.flg = pi(6);
        self.hp = pf(7);
        self.sq7f = pb(8);
        self.terr = pb(9);
        self.raise = pi(10);
        self.hl_t = pf(11);
        self.rp6 = pb(12);
        self.vis = pb(13);
        self.ally = pb(14);
        self.n_ally = vint(&a.at(15)).max(0) as usize;
        self.ww = pb(16);
        self.dfl = pi(17);
        let n = self.ids.len();
        if self.pos.len() < n || self.prev.len() < n || self.fac.len() < n || self.def.len() < n || self.own.len() < n
            || self.flg.len() < n || (self.n_ally > 0 && self.ally.len() != self.vis.len() * self.n_ally) {
            return false;
        }
        // sparse side tables (squad / g7u / air / x7 / sling ids): those units take the GDScript path
        self.mark.clear();
        self.mark.resize(n, 0);
        let keys = pi(18);
        if !keys.is_empty() {
            let sorted = self.ids.windows(2).all(|w| w[0] < w[1]);
            if sorted {
                for k in keys {
                    if let Ok(j) = self.ids.binary_search(&k) {
                        self.mark[j] = 1;
                    }
                }
            } else {
                let mut m: HashMap<i32, usize> = HashMap::with_capacity(n);
                for (j, &id) in self.ids.iter().enumerate() {
                    m.insert(id, j);
                }
                for k in keys {
                    if let Some(&j) = m.get(&k) {
                        self.mark[j] = 1;
                    }
                }
            }
        }
        let s = a.at(19).try_to::<PackedFloat64Array>().map(|p| p.as_slice().to_vec()).unwrap_or_default();
        if s.len() < 13 {
            return false;
        }
        self.alpha = s[0];
        self.t = s[1];
        self.vr = [s[2] as f32, s[3] as f32, s[4] as f32, s[5] as f32];
        self.mw = s[6] as i64;
        self.pf = s[7] as i32;
        self.live = s[8] != 0.0;
        self.pframe = s[9] as i64;
        self.lod = s[10] as i64;
        self.has_g6 = s[11] != 0.0;
        self.has_ww = s[12] != 0.0;
        self.has_cr = s.len() > 13 && s[13] != 0.0;
        self.vs = vs;
        self.drawn7 = drawn7;
        self.items.clear();
        self.bay_ii.clear();
        self.bay_sp.clear();
        self.bay_ky.clear();
        self.cnt = [0; NC];
        true
    }

    /// Draws units from index i0 at push index n0 until the first unit the kernel cannot draw exactly; returns that
    /// index (= ids.size() when it drew to the end). cdt / ck / cb = motion._cdt / _ck / _cb (the per-dt exp cache).
    #[func]
    fn run(&mut self, i0: i64, n0: i64, cdt: f64, ck: PackedFloat64Array, cb: f64) -> i64 {
        self.n = n0;
        self.cdt = cdt;
        let c = ck.as_slice();
        for k in 0..5 {
            self.ck[k] = if k < c.len() { c[k] } else { 0.0 };
        }
        self.cb = cb;
        self.cache_changed = false;
        self.vis_i.clear();
        self.vis_sp.clear();
        self.cnt[13] += 1;
        let n = self.ids.len();
        let mut i = i0.max(0) as usize;
        while i < n {
            if !self.unit(i) {
                return i as i64;
            }
            i += 1;
        }
        n as i64
    }

    #[func]
    fn n_now(&self) -> i64 {
        self.n
    }

    #[func]
    fn cache_changed(&self) -> bool {
        self.cache_changed
    }

    #[func]
    fn cdt(&self) -> f64 {
        self.cdt
    }

    #[func]
    fn ck(&self) -> PackedFloat64Array {
        PackedFloat64Array::from(&self.ck[..])
    }

    #[func]
    fn cb(&self) -> f64 {
        self.cb
    }

    /// Snapshot indices of the units the last run() drew (for vis_units / vis_sp, in order) and their vis_sp points.
    #[func]
    fn vis_idx(&self) -> PackedInt32Array {
        PackedInt32Array::from(self.vis_i.as_slice())
    }

    #[func]
    fn vis_pts(&self) -> PackedVector2Array {
        PackedVector2Array::from(self.vis_sp.as_slice())
    }

    #[func]
    fn counts(&self) -> PackedInt64Array {
        PackedInt64Array::from(&self.cnt[..])
    }

    /// Writes this frame's native items into the layer's arrays at their push indices; returns the 7 arrays.
    #[func]
    fn scatter(&mut self, mut keys: PackedInt64Array, mut page: PackedInt32Array, mut src: PackedVector2Array,
               mut size: PackedVector2Array, mut dst: PackedVector2Array, mut dsz: PackedVector2Array,
               mut md: PackedColorArray) -> VarArray {
        {
            let (k, p, s, z, d, dz, m) = (keys.as_mut_slice(), page.as_mut_slice(), src.as_mut_slice(),
                size.as_mut_slice(), dst.as_mut_slice(), dsz.as_mut_slice(), md.as_mut_slice());
            let lim = k.len().min(p.len()).min(s.len()).min(z.len()).min(d.len()).min(dz.len()).min(m.len());
            for it in self.items.iter() {
                let j = it.ii as usize;
                if j >= lim {
                    continue;
                }
                k[j] = it.key;
                p[j] = it.page;
                s[j] = it.src;
                z[j] = it.size;
                d[j] = it.dst;
                dz[j] = it.dsz;
                m[j] = it.md;
            }
        }
        self.items.clear();
        let mut out = VarArray::new();
        out.push(&keys.to_variant());
        out.push(&page.to_variant());
        out.push(&src.to_variant());
        out.push(&size.to_variant());
        out.push(&dst.to_variant());
        out.push(&dsz.to_variant());
        out.push(&md.to_variant());
        out
    }
}

impl RtsSwarmDraw {
    /// One unit of the GDScript loop. false = not plain: nothing of this unit was done (GDScript draws it).
    fn unit(&mut self, i: usize) -> bool {
        let fl = self.flg[i];
        if fl & F_ABOARD != 0 {
            self.cnt[0] += 1;
            return true;
        }
        let id = self.ids[i];
        let ow = self.own[i];
        let raw = self.pos[i];
        let mut pos = raw;
        let pp = self.prev[i];
        let ddx = pp.x - raw.x;
        let ddy = pp.y - raw.y;
        if ((ddx * ddx + ddy * ddy) as f64) < 4.0 {
            let w = self.alpha as f32;
            pos = Vector2::new(pp.x + (raw.x - pp.x) * w, pp.y + (raw.y - pp.y) * w);
        }
        let px64 = pos.x as f64;
        let py64 = pos.y as f64;
        let mut sp = v2((px64 - py64) * 32.0, (px64 + py64) * 16.0);
        let vr = self.vr;
        if sp.x < vr[0] || sp.y < vr[1] || sp.x >= vr[0] + vr[2] || sp.y >= vr[1] + vr[3] {
            return true;
        }
        let cell = (py64.floor() as i64) * self.mw + (px64.floor() as i64);
        if !self.terr.is_empty() {
            if cell >= 0 && (cell as usize) < self.terr.len() {
                let code = self.terr[cell as usize] as usize;
                let rv = if code < self.raise.len() { self.raise[code] } else { 0 };
                sp.y = (sp.y as f64 - rv as f64) as f32;
            }
        }
        let mut hl = 0.0f64;
        let mut lifted = 0i64;
        if !self.hl_t.is_empty() {
            if cell >= 0 && (cell as usize) < self.hl_t.len() {
                hl = self.hl_t[cell as usize] as f64;
                if !self.rp6.is_empty() && self.rp6[cell as usize] != 0 {
                    return false; // ramp cell: ViewUtil.ground_lift (GDScript)
                }
                sp.y = (sp.y as f64 - hl) as f32;
                if hl != 0.0 {
                    lifted = 1;
                }
            }
        }
        if self.has_ww {
            let wc = (py64.floor() as i64) * self.mw + (px64.floor() as i64);
            if px64.floor() < 0.0 || py64.floor() < 0.0 || (px64.floor() as i64) >= self.mw
                || wc < 0 || (wc as usize) >= self.ww.len() || self.ww[wc as usize] != 0 {
                return false; // a wall-walk cell (or one the mask cannot answer)
            }
        }
        if ow != self.pf {
            let ci = (raw.y as f64).floor() as i64 * self.mw + (raw.x as f64).floor() as i64;
            if !self.vis.is_empty() {
                if ci < 0 || ci as usize >= self.vis.len() {
                    self.cnt[1] += lifted;
                    return true;
                }
                let ci = ci as usize;
                if self.vis[ci] == 0 {
                    let mut seen = false;
                    let vl = self.vis.len();
                    for a in 0..self.n_ally {
                        if self.ally[a * vl + ci] == 1 {
                            seen = true;
                            break;
                        }
                    }
                    if !seen {
                        self.cnt[1] += lifted;
                        return true;
                    }
                }
            }
        }
        // 0.6.5: the view / fog culls above have no side effect the GDScript path does differently for any unit, so a
        // marked or non-plain unit that is culled no longer stops the run (it never reached the GDScript art cache)
        if self.mark[i] != 0 || fl & NONPLAIN != 0 || (fl & F_G6 != 0 && self.has_g6) {
            return false;
        }
        let dx = self.def[i];
        let Some(rec) = self.recs.get(&id) else { return false };
        if rec.def != dx || rec.owner != ow {
            return false;
        }
        if dx < 0 || dx as usize >= self.dfl.len() || self.dfl[dx as usize] != 0 {
            return false;
        }
        let idl = id as i64;
        if self.live && (self.pframe + idl) % 8 == 0 {
            return false; // _refresh_post reads the live sim (GDScript)
        }
        let (post, marked) = self.post.get(&id).copied().unwrap_or((0, false));
        if marked && self.lod == 0 {
            return false; // rank chevron / bearer pips (_push_marks)
        }
        if i < self.sq7f.len() && self.sq7f[i] != 0 {
            return false;
        }
        if rec.mcls < 0 || rec.mcls > 4 {
            return false;
        }
        // ---- plain from here: no more returns ----
        let rec = Arc::clone(rec);
        self.cnt[1] += lifted;
        if self.live {
            self.vis_i.push(i as i32);
            self.vis_sp.push(sp);
        }
        self.cnt[11] += 1;
        let t = self.t;
        let mut bits = 0i32;
        if fl & F_MOVING != 0 {
            bits |= P_MOVING;
        }
        if fl & F_FIRING != 0 {
            bits |= P_FIRING;
        }
        bits |= post;
        let mcls = rec.mcls;
        let idv = idl.to_variant();
        let (mo, mut s, bits) = self.step(idl, &idv, mcls, pos, self.fac[i] as f64, bits, t);
        let mut mpx = mo.px;
        if rec.cmd >= 0 && fl & F_MOVING != 0 {
            let of = mo.face;
            let d = vnorm(v2(of.cos() - of.sin(), (of.cos() + of.sin()) * 0.5));
            mpx = Vector2::new(mpx.x + d.x * 2.0f32, mpx.y + d.y * 2.0f32);
        }
        let ox = mo.off.x as f64;
        let oy = mo.off.y as f64;
        let add = v2((ox - oy) * 32.0, (ox + oy) * 16.0);
        let add = Vector2::new(add.x + mpx.x, add.y + mpx.y);
        sp = Vector2::new(sp.x + add.x, sp.y + add.y);
        s[S_SX] = sp.x;
        s[S_SY] = sp.y;
        let mut md = Color::from_rgba(1.0, 1.0, 1.0, 1.0);
        if mo.flash > 0.0 {
            let fk = mo.flash;
            md = Color::from_rgba((1.0f64 * (1.0 + 0.9 * fk)) as f32, (1.0f64 * (1.0 + 0.6 * fk)) as f32,
                (1.0f64 * (1.0 + 0.5 * fk)) as f32, 1.0);
        }
        self.cnt[2] += 1;
        // frame choice (a61 empty, no G7 / air / amphibian / wounded / evac state: those are not plain)
        let mut fi: i64;
        let fat = if rec.a61 { self.fat.get(&id).copied().unwrap_or(0.0) } else { 0.0 };
        if fl & F_FIRING != 0 {
            fi = if fl & F_DRONE != 0 && rec.dive >= 0 { rec.dive } else { rec.fire };
            if rec.a61 {
                fi = Self::inf_col(&rec, bits, t, seed_of(idl), s[S_FIRE] as f64, fat);
                self.cnt[14] += 1;
            }
        } else if fl & F_TACTICAL != 0 && rec.tac >= 0 && fl & F_MOVING == 0 {
            fi = rec.tac;
            self.cnt[3] += 1;
        } else {
            fi = 0;
            let mut pz = -1i64;
            if fl & POSE_MASK != 0 {
                pz = if fl & F_DEPLOYED != 0 { rec.dep } else if fl & F_WORK != 0 { rec.work } else { rec.unl };
                if fl & F_UNLOAD != 0 && rec.ramp >= 0 && ((fl >> 8) & 0xFF) > 0 {
                    pz = rec.ramp;
                    self.cnt[4] += 1;
                }
            }
            if pz >= 0 {
                fi = pz;
            } else if rec.a61 && !(rec.cmd >= 0 && fl & F_MOVING == 0 && (bits & (P_PINNED | P_SUPPRESSED)) == 0
                && ((t * 0.5 + idl as f64 * 0.61) as i64) % 4 == 0) {
                fi = Self::inf_col(&rec, bits, t, seed_of(idl), 0.0, fat);
                self.cnt[14] += 1;
            } else if fl & F_MOVING != 0 {
                let ph = (t * 6.0 + idl as f64 * 0.37) as i64;
                if rec.walk {
                    fi = if ph % 2 == 0 { rec.wa } else { rec.wb };
                } else {
                    fi = if ph % 2 == 0 { rec.mv } else { 0 };
                }
            } else if rec.cmd >= 0 && ((t * 0.5 + idl as f64 * 0.61) as i64) % 4 == 0 {
                fi = rec.cmd;
                self.cnt[5] += 1;
            }
        }
        if fi < 0 {
            fi = 0;
        }
        if rec.v61 {
            let vmv = fl & F_MOVING != 0 && (fi == rec.mv || fi == 0);
            let vid = !vmv && fi == 0;
            let hpf = if i < self.hp.len() { self.hp[i] as f64 } else { 1.0 };
            let fb = fi;
            fi = Self::pick(&rec, fi, vid, vmv, &s, hpf, t);
            self.cnt[6] += 1;
            if fi != fb {
                if fi == rec.bank_l || fi == rec.bank_r {
                    self.cnt[7] += 1;
                } else if fi == rec.recoil {
                    self.cnt[8] += 1;
                } else if rec.trk_or_mv {
                    self.cnt[9] += 1;
                }
            }
        }
        let row = mo.row;
        s[S_ROW] = (row + 1) as f32;
        // motion state back into motion.vs (the GDScript path mutates the same array in place)
        self.vs.set(&idv, &PackedFloat32Array::from(&s[..]).to_variant());
        // drawn7[id] = [fi, row, sp, t, dname]
        let mut d7 = VarArray::new();
        d7.push(&fi.to_variant());
        d7.push(&row.to_variant());
        d7.push(&sp.to_variant());
        d7.push(&t.to_variant());
        d7.push(&rec.dname);
        self.drawn7.set(&idv, &d7.to_variant());
        // push (layer 0: air units are not plain)
        let ii = self.n;
        let ky = (sp.y as f64 + hl) as i64;
        let key = (ky + Y_OFF) * IDX_MUL + ii;
        let fsz = Vector2::new(rec.fw as f32, rec.fh as f32);
        let k61 = (fi * 8 + row) as usize;
        let tb61 = if fi < rec.split || k61 >= rec.tb.len() { Vector2::new(-1.0, -1.0) } else { rec.tb[k61] };
        let it = if tb61.x >= 0.0 && k61 < rec.sz.len() && k61 < rec.offs.len() {
            let dz = rec.sz[k61];
            let o = rec.offs[k61];
            if dz.x < 0.0 {
                self.cnt[10] += 1;
            }
            Item { ii, key, page: rec.pg_b, src: tb61, size: Vector2::new(dz.x.abs(), dz.y),
                dst: Vector2::new(sp.x + o.x, sp.y + o.y), dsz: dz, md }
        } else {
            let col = if fi < rec.split { fi } else { 0 };
            let cr = Vector2::new(col as f32 * fsz.x, row as f32 * fsz.y);
            Item { ii, key, page: rec.pg, src: Vector2::new(rec.src.x + cr.x, rec.src.y + cr.y), size: fsz,
                dst: Vector2::new(sp.x + rec.off.x, sp.y + rec.off.y), dsz: fsz, md }
        };
        self.items.push(it);
        if self.has_cr && rec.is_inf {
            // _bay_hide.append([ii, ii + 1, sp, ky]) (G7 CNFAC7-3); ky = bay_sort_y(...) = ky beyond 7.5 tiles of a
            // craft, and units within 10.5 tiles are marked for the GDScript path
            self.bay_ii.push(ii as i32);
            self.bay_sp.push(sp);
            self.bay_ky.push(ky as i32);
        }
        self.n = ii + 1;
        self.cnt[12] += 1;
        true
    }

    /// Motion.inf_col(cols, posture, t, seed, fire_t, fat) for a record with the anim61 set (rts_core 0.6.5).
    fn inf_col(r: &Rec, posture: i32, t: f64, seed: f64, fire_t: f64, fat: f64) -> i64 {
        if posture & P_WOUNDED != 0 {
            return r.a_wounded;
        }
        let down = posture & P_PINNED != 0;
        let low = posture & P_SUPPRESSED != 0;
        if posture & P_FIRING != 0 {
            if posture & P_THROW != 0 {
                return r.a_throw[((t * 3.0 + seed * 2.0) as i64 % 2) as usize];
            }
            let mut fm = (fire_t + seed * 5.0) % 5.0; // fposmod
            if fm < 0.0 {
                fm += 5.0;
            }
            if !down && fm > 4.2 {
                return r.a_reload[((t * 3.0) as i64 % 2) as usize];
            }
            return if down { r.a_fire_p } else if low { r.a_fire_c } else { r.a_fire_s };
        }
        if posture & P_MOVING != 0 {
            if down {
                return r.a_crawl[((t * 3.0 + seed * 2.0) as i64 % 2) as usize];
            }
            if posture & (P_RUN | P_BROKEN) != 0 {
                return r.a_run[((t * 14.0 + seed * 6.0) as i64 % 6) as usize];
            }
            return r.a_walk[((t * 10.0 + seed * 6.0) as i64 % 6) as usize];
        }
        if down {
            return r.a_prone;
        }
        if low {
            return r.a_crouch;
        }
        r.a_idle[((t * (0.9 + fat * 1.6) + seed * 2.0) as i64 % 2) as usize]
    }

    /// VehAnim61.pick on the state this frame's step left.
    fn pick(r: &Rec, base: i64, idle: bool, moving: bool, st: &[f32; S_N], hp: f64, t: f64) -> i64 {
        let recoil = st[S_KICK] as f64 / KICK_T;
        if r.recoil != ABS && recoil > RECOIL && (idle || moving || r.bank_l == ABS) {
            return r.recoil;
        }
        if r.bank_l != ABS && r.bank_r != ABS && (idle || moving) {
            let tr = st[S_TURN] as f64;
            if tr.abs() > BANK {
                return if tr < 0.0 { r.bank_l } else { r.bank_r };
            }
        }
        if moving {
            let ph = st[S_DIST] as f64;
            if !r.mvs.is_empty() {
                return r.mvs[posmod((ph * WALK_PX).floor() as i64, r.mvs.len() as i64) as usize];
            }
            if !r.track.is_empty() {
                return r.track[posmod((ph * TRACK_PX).floor() as i64, r.track.len() as i64) as usize];
            }
            if r.burner != ABS && posmod((t * 10.0).floor() as i64, 2) == 1 {
                return r.burner;
            }
            return base;
        }
        if idle {
            if r.damaged != ABS && hp < 0.5 {
                return r.damaged;
            }
            if r.pulse != ABS && posmod((t * PULSE_HZ * 2.0).floor() as i64, 2) == 1 {
                return r.pulse;
            }
        }
        base
    }

    /// motion.gd step(id, cls, pos, facing, flags, t) for cls != CLS_INF; returns the outputs and the new state.
    fn step(&mut self, id: i64, idv: &Variant, cls: i64, pos: Vector2, facing: f64, flags: i32, t: f64) -> (MOut, [f32; S_N], i32) {
        let mut flags = flags;
        let mut s = [0.0f32; S_N];
        let mut have = false;
        let sv = self.vs.get_or_nil(idv);
        if let Ok(arr) = sv.try_to::<PackedFloat32Array>() {
            let a = arr.as_slice();
            if a.len() == S_N {
                s.copy_from_slice(a);
                have = true;
            }
        }
        // entity_layer: infantry run when motion.speed(id) (the state before this step) >= RUN_SPEED
        if cls == CLS_INF && have && s[S_SPD] as f64 >= RUN_SPEED {
            flags |= P_RUN;
        }
        let fresh = if have {
            let dx = s[S_PX] - pos.x;
            let dy = s[S_PY] - pos.y;
            t - s[S_T] as f64 > 0.5 || ((dx * dx + dy * dy) as f64) > 4.0
        } else {
            true
        };
        if fresh {
            let dist = if have { s[S_DIST] } else { 0.0 };
            s = [0.0f32; S_N];
            s[S_FACE] = facing as f32;
            s[S_T] = t as f32;
            s[S_PX] = pos.x;
            s[S_PY] = pos.y;
            s[S_SEED] = seed_of(id) as f32;
            s[S_DIST] = dist;
            s[S_AIM] = -1.0;
        }
        s[S_CLS] = cls as f32;
        let c = cls as usize;
        let dt = clampf(t - s[S_T] as f64, 0.0, 0.1);
        let cur = s[S_FACE] as f64;
        let d = wrapf(facing - cur, -PI, PI);
        let mx = TURN[c] * dt;
        let stp = clampf(d, -mx, mx);
        s[S_FACE] = wrapf(cur + stp, -PI, PI) as f32;
        if dt > 0.0 {
            s[S_TURN] = lerpf(s[S_TURN] as f64, stp / maxf(dt, 0.001), 0.25) as f32;
            if dt != self.cdt {
                self.cdt = dt;
                for k in 0..5 {
                    self.ck[k] = 1.0 - (-dt / LAG[k]).exp();
                }
                self.cb = (-dt / BACK).exp();
                self.cache_changed = true;
            }
            let dtf = dt as f32;
            let vsim = Vector2::new((pos.x - s[S_PX]) / dtf, (pos.y - s[S_PY]) / dtf);
            let k = self.ck[c];
            let vx = lerpf(s[S_VX] as f64, vsim.x as f64, k);
            let vy = lerpf(s[S_VY] as f64, vsim.y as f64, k);
            let o = v2(s[S_OX] as f64 + (vx - vsim.x as f64) * dt, s[S_OY] as f64 + (vy - vsim.y as f64) * dt);
            let mut off = vmul(o, self.cb);
            let l = vlen(off);
            if l > 0.0 && MAX_OFF < l {
                off = Vector2::new(off.x / l, off.y / l);
                off = Vector2::new(off.x * MAX_OFF, off.y * MAX_OFF);
            }
            s[S_VX] = vx as f32;
            s[S_VY] = vy as f32;
            s[S_OX] = off.x;
            s[S_OY] = off.y;
            s[S_SPD] = vlen(v2(vx, vy));
            s[S_DIST] = ((s[S_DIST] as f64 + vlen(vsim) as f64 * dt) % 1024.0) as f32;
            let mut kick = maxf(0.0, s[S_KICK] as f64 - dt);
            s[S_FLINCH] = maxf(0.0, s[S_FLINCH] as f64 - dt) as f32;
            let f0 = s[S_FIRE] as f64;
            if flags & P_FIRING != 0 {
                s[S_FIRE] = (f0 + dt) as f32;
                let sd = s[S_SEED] as f64;
                if ((f0 + sd) / KICK_EVERY).floor() as i64 != ((f0 + dt + sd) / KICK_EVERY).floor() as i64 {
                    kick = KICK_T;
                }
            } else {
                s[S_FIRE] = 0.0;
            }
            s[S_KICK] = kick as f32;
            let mvg = if flags & P_MOVING != 0 { 1.0f64 } else { 0.0 };
            if mvg != s[S_MV] as f64 && cls != CLS_INF {
                s[S_SUSP] = (if mvg > 0.0 { -SUSP_T } else { SUSP_T }) as f32;
            }
            s[S_MV] = mvg as f32;
            let su = s[S_SUSP] as f64;
            if su != 0.0 {
                s[S_SUSP] = (if su > 0.0 { maxf(0.0, su - dt) } else { minf(0.0, su + dt) }) as f32;
            }
        }
        s[S_PX] = pos.x;
        s[S_PY] = pos.y;
        s[S_T] = t as f32;
        let face = s[S_FACE] as f64;
        let off = Vector2::new(s[S_OX], s[S_OY]);
        let mut rr = (s[S_ROW] as f64) as i64 - 1;
        if rr < 0 || wrapf(face - rr as f64 * (PI / 4.0), -PI, PI).abs() >= PI / 8.0 + ROW_HYS {
            rr = posmod((face * (4.0 / PI)).round() as i64, 8);
        }
        let kk = s[S_KICK] as f64 / KICK_T;
        let fk = s[S_FLINCH] as f64 / FLINCH_T;
        let su2 = if cls == CLS_VEH || cls == CLS_HEAVY { s[S_SUSP] as f64 } else { 0.0 };
        let mut px = Vector2::ZERO;
        let mv_inf = cls == CLS_INF && flags & P_MOVING != 0 && flags & P_PINNED == 0;
        if !(kk <= 0.0 && fk <= 0.0 && su2 == 0.0 && !mv_inf) {
            let seed = s[S_SEED] as f64;
            let dir = vnorm(v2(face.cos() - face.sin(), (face.cos() + face.sin()) * 0.5));
            if mv_inf {
                // walking bob / running sway
                let run = flags & P_RUN != 0;
                let ph = t * (if run { 2.4 } else { 1.7 }) + seed;
                px.y = (px.y as f64 - (ph * PI).sin().abs() * (if run { 1.5 } else { 1.0 })) as f32;
                if run {
                    px.x = (px.x as f64 + (ph * PI).sin() * 0.6) as f32;
                }
            }
            if kk > 0.0 {
                let q = vmul(vmul(dir, kk), if cls == CLS_INF { 1.2 } else { 2.2 });
                px = Vector2::new(px.x - q.x, px.y - q.y);
                if cls == CLS_VEH || cls == CLS_HEAVY {
                    px.y = (px.y as f64 + 1.0) as f32;
                }
            }
            if su2 != 0.0 {
                px.y = (px.y as f64 + if su2 < 0.0 { -1.0 } else { 1.0 }) as f32;
            }
            if fk > 0.0 {
                let side = if seed > 0.5 { 1.0 } else { -1.0 };
                let a = vmul(vmul(vmul(Vector2::new(-dir.y, dir.x), side), fk), 1.5);
                let b = vmul(vmul(dir, fk), 0.8);
                let q = Vector2::new(a.x - b.x, a.y - b.y);
                px = Vector2::new(px.x + q.x, px.y + q.y);
            }
        }
        (MOut { face, off, px, flash: fk, row: rr }, s, flags)
    }
}
