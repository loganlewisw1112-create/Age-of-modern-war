//! RtsFormation (G7 PERF7K, rts_core 0.5.4): exact port of formations7.gd `_polish_near_fast` (big-group assignment
//! polish). Same visiting order (men ascending, partners in the 3 x 3 start-cell order dy then dx, each cell list in
//! ascending man index, only partners after the man), the same per-pair tests with the same float widths as GDScript:
//! Vector2 math in f32 (Godot real_t), every scalar the script combines (products of crosses, sums of squared
//! distances, divisions in _crosses, the 0.0001 / CROSS_EPS compares) in f64 (GDScript float). The cell map is a
//! lookup only (never iterated), so the result is a pure function of the inputs.

use godot::prelude::*;
use std::collections::HashMap;

const CROSS_EPS: f64 = 0.001;

#[inline]
fn sub(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x - b.x, a.y - b.y)
}

#[inline]
fn cross(a: Vector2, b: Vector2) -> f64 {
    (a.x * b.y - a.y * b.x) as f64
}

#[inline]
fn d2(a: Vector2, b: Vector2) -> f64 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    (dx * dx + dy * dy) as f64
}

/// formations7.gd `_crosses`.
fn crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool {
    let u = sub(b, a);
    let v = sub(d, c);
    let lu = (u.x * u.x + u.y * u.y).sqrt() as f64;
    let lv = (v.x * v.x + v.y * v.y).sqrt() as f64;
    if lu < 0.0001 || lv < 0.0001 {
        return false;
    }
    let d1 = cross(u, sub(c, a)) / lu;
    let d2_ = cross(u, sub(d, a)) / lu;
    let d3 = cross(v, sub(a, c)) / lv;
    let d4 = cross(v, sub(b, c)) / lv;
    d1 * d2_ < 0.0 && d3 * d4 < 0.0 && d1.abs().min(d2_.abs()) > CROSS_EPS && d3.abs().min(d4.abs()) > CROSS_EPS
}

pub fn polish_core(st: &[Vector2], pv: &[Vector2], perm: &[i32], li: i32, cs: f64, passes: i32) -> Vec<i32> {
    let m = st.len();
    let mut pm: Vec<i32> = perm.to_vec();
    let cells: Vec<(i64, i64)> = st
        .iter()
        .map(|p| (((p.x as f64) / cs).floor() as i64, ((p.y as f64) / cs).floor() as i64))
        .collect();
    let mut grid: HashMap<(i64, i64), Vec<i32>> = HashMap::new();
    for j in 0..m {
        if j as i32 == li {
            continue;
        }
        grid.entry(cells[j]).or_default().push(j as i32);
    }
    // partners of each man in the script's order, only those after him
    let mut nb: Vec<i32> = Vec::new();
    let mut nb_off: Vec<usize> = vec![0; m + 1];
    for ja in 0..m {
        nb_off[ja] = nb.len();
        if ja as i32 == li {
            continue;
        }
        let c = cells[ja];
        for ey in -1..=1i64 {
            for ex in -1..=1i64 {
                if let Some(l) = grid.get(&(c.0 + ex, c.1 + ey)) {
                    for &jb in l {
                        if jb as usize > ja {
                            nb.push(jb);
                        }
                    }
                }
            }
        }
    }
    nb_off[m] = nb.len();
    let mut dd = vec![0f64; m];
    for j in 0..m {
        if j as i32 != li {
            dd[j] = d2(st[j], pv[pm[j] as usize]);
        }
    }
    let mut lc = vec![0i64; m];
    let mut clk: i64 = 0;
    let mut prev_start: i64 = -1;
    let mut prev_changed = true;
    for it in 0..(passes * 2) {
        let cost_too = it < passes;
        let mut changed = false;
        let start = clk;
        if prev_changed {
            for ja in 0..m {
                if ja as i32 == li {
                    continue;
                }
                let pa = st[ja];
                let mut sa = pv[pm[ja] as usize];
                let mut u = sub(sa, pa);
                let mut daa = dd[ja];
                let mut a_clean = lc[ja] <= prev_start;
                for q in nb_off[ja]..nb_off[ja + 1] {
                    let jb = nb[q] as usize;
                    if a_clean && lc[jb] <= prev_start {
                        continue;
                    }
                    let pb = st[jb];
                    let sb = pv[pm[jb] as usize];
                    let mut sw = cross(u, sub(pb, pa)) * cross(u, sub(sb, pa)) < 0.0 && crosses(pa, sa, pb, sb);
                    if !sw && cost_too && d2(pa, sb) + d2(pb, sa) < daa + dd[jb] - 0.0001 {
                        let u2 = sub(sb, pa);
                        sw = !(cross(u2, sub(pb, pa)) * cross(u2, sub(sa, pa)) < 0.0 && crosses(pa, sb, pb, sa));
                    }
                    if sw {
                        let t = pm[ja];
                        pm[ja] = pm[jb];
                        pm[jb] = t;
                        clk += 1;
                        lc[ja] = clk;
                        lc[jb] = clk;
                        changed = true;
                        sa = sb;
                        u = sub(sa, pa);
                        daa = d2(pa, sa);
                        dd[ja] = daa;
                        dd[jb] = d2(pb, pv[t as usize]);
                        a_clean = false;
                    }
                }
            }
        }
        prev_start = start;
        prev_changed = changed;
        if !changed {
            if cost_too {
                continue;
            }
            break;
        }
    }
    pm
}

/// One uncross sweep of formations7.gd `_assign_exact` (`_uncross_packed`). True when it swapped.
fn uncross(p: &[Vector2], s: &[Vector2], pm: &mut [i32], free: &[usize]) -> bool {
    let mut swapped = false;
    let nf = free.len();
    for a in 0..nf {
        let ja = free[a];
        let qa = p[ja];
        for b in (a + 1)..nf {
            let jb = free[b];
            let qb = p[jb];
            let ta = s[pm[ja] as usize];
            let tb = s[pm[jb] as usize];
            let tu = sub(ta, qa);
            if cross(tu, sub(qb, qa)) * cross(tu, sub(tb, qa)) < 0.0 && crosses(qa, ta, qb, tb) {
                pm.swap(ja, jb);
                swapped = true;
            }
        }
    }
    swapped
}

/// formations7.gd `_assign_exact` after the leader pick: p = start points (m), s = slots (>= m), roles per slot,
/// ar = 1 per AR man, li = leader index or -1, passes = the twoopt pass count the script picked. None when a man
/// gets no slot (the script's -1 path; the caller then runs its own code).
pub fn assign_exact_core(p: &[Vector2], s: &[Vector2], roles: &[i32], ar: &[u8], li: i32, passes: i32) -> Option<Vec<i32>> {
    const ROLE_AR: i32 = 1;
    let m = p.len();
    let mut pm = vec![-1i32; m];
    let mut taken = vec![0u8; m.max(s.len())];
    if li >= 0 {
        pm[li as usize] = 0;
        taken[0] = 1;
    }
    for j in 0..m {
        if j as i32 == li || ar[j] == 0 {
            continue;
        }
        let mut best: i32 = -1;
        let mut bd = f64::INFINITY;
        let pj = p[j];
        for k in 0..m {
            if taken[k] != 0 || roles[k] != ROLE_AR {
                continue;
            }
            let dx = pj.x - s[k].x;
            let dy = pj.y - s[k].y;
            let d = (dx * dx + dy * dy).sqrt() as f64;
            if d < bd {
                bd = d;
                best = k as i32;
            }
        }
        if best >= 0 {
            pm[j] = best;
            taken[best as usize] = 1;
        }
    }
    let mut free: Vec<usize> = Vec::new();
    for j in 0..m {
        if pm[j] >= 0 {
            continue;
        }
        free.push(j);
        let mut best: i32 = -1;
        let mut bd = f64::INFINITY;
        let pj = p[j];
        for k in 0..m {
            if taken[k] != 0 {
                continue;
            }
            let d = d2(pj, s[k]);
            if d < bd {
                bd = d;
                best = k as i32;
            }
        }
        pm[j] = best;
        if best >= 0 {
            taken[best as usize] = 1;
        } else {
            return None;
        }
    }
    let nf = free.len();
    for _ in 0..passes {
        let mut better = false;
        for a in 0..nf {
            let ja = free[a];
            let pa = p[ja];
            for b in (a + 1)..nf {
                let jb = free[b];
                let pb = p[jb];
                let sa = s[pm[ja] as usize];
                let sb = s[pm[jb] as usize];
                if d2(pa, sb) + d2(pb, sa) < d2(pa, sa) + d2(pb, sb) - 0.0001 {
                    pm.swap(ja, jb);
                    better = true;
                }
            }
        }
        if !better {
            break;
        }
    }
    for _ in 0..(passes * 2) {
        if !uncross(p, s, &mut pm, &free) {
            break;
        }
    }
    for _ in 0..passes {
        let mut changed = false;
        for a in 0..nf {
            let ja = free[a];
            let pa = p[ja];
            for b in (a + 1)..nf {
                let jb = free[b];
                let pb = p[jb];
                let sa = s[pm[ja] as usize];
                let sb = s[pm[jb] as usize];
                let u2 = sub(sb, pa);
                if d2(pa, sb) + d2(pb, sa) < d2(pa, sa) + d2(pb, sb) - 0.0001
                    && !(cross(u2, sub(pb, pa)) * cross(u2, sub(sa, pa)) < 0.0 && crosses(pa, sb, pb, sa))
                {
                    pm.swap(ja, jb);
                    changed = true;
                }
            }
        }
        if uncross(p, s, &mut pm, &free) {
            changed = true;
        }
        if !changed {
            break;
        }
    }
    for _ in 0..(passes * 2) {
        if !uncross(p, s, &mut pm, &free) {
            break;
        }
    }
    Some(pm)
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsFormation {}

#[godot_api]
impl RtsFormation {
    /// formations7.gd `_polish_near_fast`: st = each man's start position, pts = slot points, perm = man -> slot,
    /// li = leader index (excluded), cs = polish_cell, passes = polish_passes. Returns the polished perm.
    /// Returns an empty array when the inputs are inconsistent (the caller then runs its GDScript path).
    #[func]
    fn polish_near(&self, st: PackedVector2Array, pts: PackedVector2Array, perm: PackedInt32Array, li: i32, cs: f64,
                   passes: i32) -> PackedInt32Array {
        let (s, p, pm) = (st.as_slice(), pts.as_slice(), perm.as_slice());
        if s.len() != pm.len() || pm.iter().any(|&v| v < 0 || v as usize >= p.len()) || !(cs > 0.0) {
            return PackedInt32Array::new();
        }
        let out = polish_core(s, p, pm, li, cs, passes);
        PackedInt32Array::from(out.as_slice())
    }
    /// formations7.gd `_assign_exact` (exact port). st = men's start points, pts = slots (size >= men), roles = slot
    /// roles, ar = 1 per AR man, li = leader index (-1 = no leader slot), passes = twoopt passes. Empty = use script.
    #[func]
    fn assign_exact(&self, st: PackedVector2Array, pts: PackedVector2Array, roles: PackedInt32Array, ar: PackedByteArray,
                    li: i32, passes: i32) -> PackedInt32Array {
        let (p, s, r, a) = (st.as_slice(), pts.as_slice(), roles.as_slice(), ar.as_slice());
        let m = p.len();
        if s.len() < m || r.len() < m || a.len() != m || li >= m as i32 || (li >= 0 && m == 0) {
            return PackedInt32Array::new();
        }
        match assign_exact_core(p, s, r, a, li, passes) {
            Some(out) => PackedInt32Array::from(out.as_slice()),
            None => PackedInt32Array::new(),
        }
    }
}
