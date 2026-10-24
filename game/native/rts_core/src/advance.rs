//! Per-unit path advance (movement.gd `_advance`), called in a batch by RtsSteer.step.
//! Deterministic: pure function of its inputs, plain f32 IEEE math, no hashing, no RNG.
//!
//! Semantics mirror the GDScript fallback exactly in structure:
//!   - next waypoint cell solid           -> REPATH (no movement, stuck unchanged)
//!   - speed (base * terrain mult * k) <= 0 -> nothing (immobile: keep the path)
//!   - up to 4*k segment iterations; intermediate waypoints count as reached within wp_tol;
//!     each segment is at most seg_max tiles so the cell-to-cell collision check stays exact
//!     with the PERF4 k x stride step; a refused step slides (RtsNav::try_move) and stops.
//!   - the caller passes only a window of waypoints (k + 2); reaching its end stops this tick.
//!   - all waypoints consumed -> ARRIVE
//!   - stuck counter +k when slow (< 25 % of the step) or blocked, else -k (floor 0)
//!   - crowding at the destination (last waypoint, close, stuck) -> ARRIVE
//!   - stuck >= stuck_repath -> REPATH

use crate::nav::RtsNav;
use godot::prelude::*;

pub const OUT_NONE: i32 = 0;
pub const OUT_ARRIVE: i32 = 1;
pub const OUT_REPATH: i32 = 2;
pub const FLAG_FACING: i32 = 4;

pub struct AdvParams {
    pub q: f32,
    pub wp_tol: f32,
    pub seg_max: f32,
    pub stuck_repath: i32,
}

pub struct AdvOut {
    pub pos: Vector2,
    pub dpi: i32,
    pub facing: f32,
    pub stuck: i32,
    pub flags: i32,
}

#[inline]
fn snap(v: f32, q: f32) -> f32 {
    (v / q + 0.5).floor() * q
}

/// movement.gd _qpos: quantize to q without changing the cell.
#[inline]
pub fn qpos(p: Vector2, q: f32) -> Vector2 {
    let s = Vector2::new(snap(p.x, q), snap(p.y, q));
    if s.x.floor() == p.x.floor() && s.y.floor() == p.y.floor() { s } else { p }
}

#[inline]
fn dist(a: Vector2, b: Vector2) -> f32 {
    let d = a - b;
    (d.x * d.x + d.y * d.y).sqrt()
}

/// wp = path[pi .. pi + min(rem, 4k)], rem = path.size() - pi (>= 1), fin = path[size - 1].
#[allow(clippy::too_many_arguments)]
pub fn advance_one(nav: &RtsNav, mc: usize, pos0: Vector2, spd_base: f32, k: i32, wp: &[Vector2],
                   rem: i32, fin: Vector2, stuck0: i32, pr: &AdvParams) -> AdvOut {
    let mut out = AdvOut { pos: pos0, dpi: 0, facing: 0.0, stuck: stuck0, flags: OUT_NONE };
    if wp.is_empty() || rem <= 0 {
        out.flags = OUT_ARRIVE;
        return out;
    }
    let (nx, ny) = (wp[0].x.floor() as i32, wp[0].y.floor() as i32);
    if !nav.passable(mc, nx, ny) {
        out.flags = OUT_REPATH;
        return out;
    }
    let tmult = if crate::nav::is_air(mc & 15) {
        1.0
    } else {
        let (cx, cy) = (pos0.x.floor() as i32, pos0.y.floor() as i32);
        if nav.in_bounds(cx, cy) {
            let code = nav.terrain[(cy * nav.w + cx) as usize] as usize;
            nav.lut[mc & 15].get(code).copied().unwrap_or(0.0)
        } else {
            0.0
        }
    };
    let k = k.max(1);
    let spd = spd_base * tmult * k as f32;
    if spd <= 0.0 {
        return out;
    }
    let mut remaining = spd;
    let mut pi: i32 = 0;
    let mut guard = 0;
    let mut blocked = false;
    let mut pos = pos0;
    let gmax = 4 * k;
    while remaining > 0.0001 && pi < rem && guard < gmax {
        guard += 1;
        let Some(&w) = wp.get(pi as usize) else { break };
        let d = w - pos;
        let dd = (d.x * d.x + d.y * d.y).sqrt();
        if dd > 0.0001 {
            out.facing = snap(d.y.atan2(d.x), pr.q);
            out.flags |= FLAG_FACING;
        }
        if pi < rem - 1 && dd <= pr.wp_tol {
            pi += 1;
            continue;
        }
        let step = remaining.min(pr.seg_max);
        let want = if dd <= step { w } else { pos + d / dd * step };
        let got = nav.try_move(mc, pos, want);
        if got != want {
            blocked = true;
            pos = got;
            break;
        }
        pos = want;
        if dd <= step {
            remaining -= dd;
            pi += 1;
        } else {
            remaining -= step;
        }
    }
    out.pos = qpos(pos, pr.q);
    out.dpi = pi;
    if pi >= rem {
        out.flags |= OUT_ARRIVE;
        return out;
    }
    let moved = dist(pos, pos0);
    if moved < spd * 0.25 || blocked {
        out.stuck = stuck0 + k;
    } else {
        out.stuck = (stuck0 - k).max(0);
    }
    let to_final = dist(pos, fin);
    let st = out.stuck;
    if pi == rem - 1 && ((to_final < 0.8 && st >= 6) || (to_final < 2.0 && st >= 20)) {
        out.flags |= OUT_ARRIVE;
    } else if st >= pr.stuck_repath {
        out.flags |= OUT_REPATH;
    }
    out
}

/// N1-core-4: a PERF4 stride advance of k ticks = k exact one-tick advances (each with its own
/// guard, terrain lookup, quantize and stuck +-1), no separation in between. Stops on arrive /
/// repath, and before a sub-step when the waypoint window is nearly spent (the caller passes
/// k + 2 waypoints; the rest of the path is served on the next advance). k = 1 is advance_one.
#[allow(clippy::too_many_arguments)]
pub fn advance_k(nav: &RtsNav, mc: usize, pos0: Vector2, spd_base: f32, k: i32, wp: &[Vector2],
                 rem: i32, fin: Vector2, stuck0: i32, pr: &AdvParams) -> AdvOut {
    if k <= 1 {
        return advance_one(nav, mc, pos0, spd_base, 1, wp, rem, fin, stuck0, pr);
    }
    let mut acc = AdvOut { pos: pos0, dpi: 0, facing: 0.0, stuck: stuck0, flags: OUT_NONE };
    for s in 0..k {
        let off = acc.dpi.max(0) as usize;
        let left = wp.len().saturating_sub(off);
        if left == 0 || (s > 0 && left < 2 && (rem - acc.dpi) as usize > left) {
            break;
        }
        let o = advance_one(nav, mc, acc.pos, spd_base, 1, &wp[off..], rem - acc.dpi, fin, acc.stuck, pr);
        acc.pos = o.pos;
        acc.dpi += o.dpi;
        acc.stuck = o.stuck;
        if o.flags & FLAG_FACING != 0 {
            acc.facing = o.facing;
            acc.flags |= FLAG_FACING;
        }
        if o.flags & 3 != OUT_NONE {
            acc.flags |= o.flags & 3;
            break;
        }
    }
    acc
}
