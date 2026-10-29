//! RtsSpot: exact port of senses7.gd's spot pass core (G7 PERF7L, 0.5.5): `_spotted_any` ring search over the
//! observer bucket index + `_sees` for the no-smoke case. Vector math in f32 like Godot's Vector2, scalar products
//! in f64 like GDScript floats, same evaluation order. The caller precomputes everything that reads Dictionaries
//! (observer position, profile code / range, flags, view direction Vector2.from_angle(head)).

use godot::prelude::*;
use std::collections::HashMap;

const P_INF: i32 = 0;
const P_AIR: i32 = 2;
const P_BLD: i32 = 3;
const P_MACH: i32 = 4;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsSpot {}

struct Obs<'a> {
    pos: &'a [Vector2],
    code: &'a [i32],
    rr: &'a [f64],
    flags: &'a [i32],
    dir: &'a [Vector2],
}

/// senses7.gd `_sees` without smoke clouds. flags: 1 = wunc, 2 = thermal (pr[3] / nvg / thermal), 4 = optics
/// (pr[2] / optics). k = the _K tunables 0..12 as f64.
fn sees(o: &Obs, i: usize, tp: Vector2, sil: f64, moving: bool, k: &[f64], light: f64) -> bool {
    let op = o.pos[i];
    let dx = op.x - tp.x;
    let dy = op.y - tp.y;
    let d32 = (dx * dx + dy * dy).sqrt();
    let d = d32 as f64;
    let fl = o.flags[i];
    if d <= k[0] {
        return fl & 1 == 0;
    }
    let code = o.code[i];
    let r = o.rr[i];
    if code == P_MACH {
        return d <= r;
    }
    if fl & 1 != 0 {
        return false;
    }
    let mut s = sil;
    if moving {
        let m = s * k[1];
        s = if 1.0 < m { 1.0 } else { m };
    }
    if fl & 2 == 0 {
        s *= light;
    }
    if code == P_INF {
        let tx = (tp.x - op.x) / d32;
        let ty = (tp.y - op.y) / d32;
        let hv = o.dir[i];
        let cosa = (hv.x * tx + hv.y * ty) as f64;
        if fl & 4 != 0 && cosa >= k[2] && d <= r * k[3] * s {
            return true;
        }
        if cosa >= k[4] {
            return d <= r * s;
        }
        if cosa >= k[5] {
            return moving && d <= r * s * k[6];
        }
        return false;
    }
    let mut m = k[7];
    if code == P_AIR {
        m = k[8];
    } else if code == P_BLD {
        m = k[9];
    }
    d <= r * s * m
}

#[godot_api]
impl RtsSpot {
    /// For each target (pos, sil = _sil_k, moving) 1 when `_spotted_any` would return true. Observers are given in the
    /// order the script inserts them into its bucket index (key floor(x / b) + floor(y / b) * kst). Empty return on
    /// inconsistent input (the caller then runs its GDScript path).
    #[func]
    fn spotted(&self, opos: PackedVector2Array, ocode: PackedInt32Array, orr: PackedFloat64Array, oflags: PackedInt32Array,
               odir: PackedVector2Array, tpos: PackedVector2Array, tsil: PackedFloat64Array, tmov: PackedByteArray,
               k: PackedFloat64Array, light: f64, b: f64, kst: i64, maxc: i64) -> PackedByteArray {
        let n = opos.len();
        let nt = tpos.len();
        let ks = k.as_slice();
        if ocode.len() != n || orr.len() != n || oflags.len() != n || odir.len() != n || tsil.len() != nt
            || tmov.len() != nt || ks.len() < 14 || !(b > 0.0) {
            return PackedByteArray::new();
        }
        let o = Obs { pos: opos.as_slice(), code: ocode.as_slice(), rr: orr.as_slice(), flags: oflags.as_slice(), dir: odir.as_slice() };
        let mut idx: HashMap<i64, Vec<u32>> = HashMap::new();
        for i in 0..n {
            let p = o.pos[i];
            let key = ((p.x as f64) / b).floor() as i64 + ((p.y as f64) / b).floor() as i64 * kst;
            idx.entry(key).or_default().push(i as u32);
        }
        let kmax = (ks[13] / b).ceil() as i64;
        let (tp_s, ts, tm) = (tpos.as_slice(), tsil.as_slice(), tmov.as_slice());
        let mut out = vec![0u8; nt];
        for j in 0..nt {
            let p = tp_s[j];
            let sil = ts[j];
            let moving = tm[j] != 0;
            let bx = ((p.x as f64) / b).floor() as i64;
            let by = ((p.y as f64) / b).floor() as i64;
            let mut cnt: i64 = 0;
            let mut hit = false;
            'ring: for kk in 0..=kmax {
                for yy in (by - kk)..=(by + kk) {
                    let step = if kk == 0 || yy == by - kk || yy == by + kk { 1 } else { 2 * kk };
                    let mut xx = bx - kk;
                    while xx <= bx + kk {
                        if let Some(a) = idx.get(&(xx + yy * kst)) {
                            for &oi in a {
                                if sees(&o, oi as usize, p, sil, moving, ks, light) {
                                    hit = true;
                                    break 'ring;
                                }
                                cnt += 1;
                                if cnt >= maxc {
                                    hit = true;
                                    break 'ring;
                                }
                            }
                        }
                        xx += step;
                    }
                }
            }
            out[j] = hit as u8;
        }
        PackedByteArray::from(out.as_slice())
    }
}
