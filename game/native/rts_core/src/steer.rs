//! RtsSteer: batch separation step (movement.gd _separate), deterministic.
//! Units overlap-test only against units with the same key (owner layer, air layer) in a
//! half neighbourhood of buckets, so each pair is visited once, in ascending index order.
//! Pushes are clamped, bounded to the map and slid against the RtsNav passability grid.
//! advance_separate(): the whole movement tick in one call (G3b N1-core-2): batch path advance for the
//! moving units (advance.rs), then separation over every unit, in ascending index order.

use crate::advance::{advance_k, qpos, AdvParams, OUT_ARRIVE};
use crate::nav::RtsNav;
use godot::prelude::*;
use std::collections::HashMap;

const HALF_NB: [(i32, i32); 5] = [(0, 0), (1, 0), (-1, 1), (0, 1), (1, 1)];

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsSteer {
    last_pairs: i32,
    last_moved: i32,
    last_adv: Vec<f32>,
    last_changed: Vec<i32>,
    /// N1-core-4: unit paths held natively, indexed by entity id (set_path); advance_held reads them.
    paths: Vec<Vec<Vector2>>,
}

/// Mover record stride in advance_separate()'s `mvi`: [unit index, k, rem, wp offset, wp count, stuck].
const MVI: usize = 6;

#[godot_api]
impl RtsSteer {
    /// Inputs are parallel arrays in ascending entity-id order. mcs: 0 foot, 1 vehicle, 2 air.
    /// moving: 1 = has a path. Returns the new positions (unchanged entries are copied through).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn separate(&mut self, nav: Gd<RtsNav>, pos: PackedVector2Array, rad: PackedFloat32Array,
                moving: PackedByteArray, keys: PackedInt32Array, ids: PackedInt32Array,
                mcs: PackedByteArray, params: PackedFloat32Array) -> PackedVector2Array {
        let nav = nav.bind();
        let out = self.separate_core(&nav, pos.as_slice(), rad.as_slice(), moving.as_slice(), keys.as_slice(),
                                     ids.as_slice(), mcs.as_slice(), params.as_slice());
        PackedVector2Array::from(out.as_slice())
    }

    /// One movement tick for the native path. Per unit i (ascending entity id): pos[i], ids[i],
    /// moving[i] (1 = has or awaits a path). Static per-entity data comes from tables indexed by
    /// entity id: rad_tab, key_tab (separation layer), mc_tab (0 foot, 1 vehicle, 2 air).
    /// Per mover m: mvi[m*6..] = [unit index, k (PERF4 stride mult, >= 1), rem = path.size() -
    /// path_i, offset into wp, waypoint count (min(rem, 4k)), stuck]; spd[m] = speed * DT *
    /// move_mult (terrain applied here); fin[m] = the path's final waypoint. params = [sep
    /// strength, max push, bucket, q, wp_tol, seg_max, stuck_repath]. Returns every unit's new
    /// position; per-mover results via last_adv(), indices whose position changed via last_changed().
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn advance_separate(&mut self, nav: Gd<RtsNav>, pos: PackedVector2Array, ids: PackedInt32Array, moving: PackedByteArray,
            rad_tab: PackedFloat32Array, key_tab: PackedInt32Array, mc_tab: PackedByteArray,
            mvi: PackedInt32Array, spd: PackedFloat32Array, wp: PackedVector2Array, fin: PackedVector2Array,
            params: PackedFloat32Array) -> PackedVector2Array {
        let nav = nav.bind();
        let out = self.run(&nav, pos.as_slice(), ids.as_slice(), moving.as_slice(), rad_tab.as_slice(),
                           key_tab.as_slice(), mc_tab.as_slice(), mvi.as_slice(), spd.as_slice(), wp.as_slice(),
                           fin.as_slice(), params.as_slice());
        PackedVector2Array::from(out.as_slice())
    }

    /// N1-core-4: store entity `id`'s path (movement.gd pushes it whenever e.path is a new array).
    #[func]
    fn set_path(&mut self, id: i32, path: PackedVector2Array) {
        if id < 0 {
            return;
        }
        let i = id as usize;
        if i >= self.paths.len() {
            self.paths.resize_with(i + 1, Vec::new);
        }
        self.paths[i] = path.as_slice().to_vec();
    }

    /// advance_separate() with the waypoints read from the held paths (set_path): per mover
    /// mvi[m*4..] = [unit index, k, path_i, stuck]. The window (path[path_i .. path_i + k + 2]),
    /// rem and fin are built exactly as movement.gd built them, so results are bit-identical.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn advance_held(&mut self, nav: Gd<RtsNav>, pos: PackedVector2Array, ids: PackedInt32Array, moving: PackedByteArray,
            rad_tab: PackedFloat32Array, key_tab: PackedInt32Array, mc_tab: PackedByteArray,
            mvi: PackedInt32Array, spd: PackedFloat32Array, params: PackedFloat32Array) -> PackedVector2Array {
        let nav = nav.bind();
        let (mi, id) = (mvi.as_slice(), ids.as_slice());
        let nm = mi.len() / 4;
        let mut m6: Vec<i32> = Vec::with_capacity(nm * MVI);
        let mut wps: Vec<Vector2> = Vec::with_capacity(nm * 3);
        let mut fs: Vec<Vector2> = Vec::with_capacity(nm);
        let empty: Vec<Vector2> = Vec::new();
        for m in 0..nm {
            let r = &mi[m * 4..m * 4 + 4];
            let ui = r[0].max(0) as usize;
            let eid = id.get(ui).copied().unwrap_or(-1);
            let path = if eid >= 0 { self.paths.get(eid as usize).unwrap_or(&empty) } else { &empty };
            let ps = path.len() as i32;
            let pi = r[2].clamp(0, ps);
            let nw = (ps - pi).min(r[1].max(1) + 2).max(0);
            m6.extend_from_slice(&[r[0], r[1], ps - pi, wps.len() as i32, nw, r[3]]);
            wps.extend_from_slice(&path[pi as usize..(pi + nw) as usize]);
            fs.push(if ps > 0 { path[ps as usize - 1] } else { Vector2::ZERO });
        }
        let out = self.run(&nav, pos.as_slice(), id, moving.as_slice(), rad_tab.as_slice(), key_tab.as_slice(),
                           mc_tab.as_slice(), &m6, spd.as_slice(), &wps, &fs, params.as_slice());
        PackedVector2Array::from(out.as_slice())
    }

    #[allow(clippy::too_many_arguments)]
    fn run(&mut self, nav: &RtsNav, p0: &[Vector2], id: &[i32], moving: &[u8], rt: &[f32], kt: &[i32], mt: &[u8],
           mi: &[i32], sp: &[f32], wps: &[Vector2], fs: &[Vector2], pr: &[f32]) -> Vec<Vector2> {
        let get = |i: usize, d: f32| if i < pr.len() { pr[i] } else { d };
        let ap = AdvParams { q: get(3, 1.0 / 1024.0), wp_tol: get(4, 0.45), seg_max: get(5, 0.5),
                             stuck_repath: get(6, 40.0) as i32 };
        let n = p0.len().min(id.len()).min(moving.len());
        let mut r = Vec::with_capacity(n);
        let mut ky = Vec::with_capacity(n);
        let mut mc = Vec::with_capacity(n);
        for (i, &eid) in id[..n].iter().enumerate() {
            let e = eid.max(0) as usize;
            r.push(rt.get(e).copied().unwrap_or(0.3));
            // unknown ids get a unique negative layer: they never separate against anything
            ky.push(kt.get(e).copied().unwrap_or(-1 - i as i32));
            mc.push(mt.get(e).copied().unwrap_or(0));
        }
        let mut p: Vec<Vector2> = p0[..n].to_vec();
        let mut mv: Vec<u8> = moving[..n].to_vec();
        let nm = (mi.len() / MVI).min(sp.len()).min(fs.len());
        let mut res = vec![0.0f32; nm * 4];
        for m in 0..nm {
            let rr = &mi[m * MVI..m * MVI + MVI];
            let ui = rr[0] as usize;
            if ui >= n {
                continue;
            }
            let a = (rr[3].max(0) as usize).min(wps.len());
            let b = (a + rr[4].max(0) as usize).min(wps.len());
            let o = advance_k(nav, mc[ui] as usize, p[ui], sp[m], rr[1], &wps[a..b], rr[2], fs[m], rr[5], &ap);
            p[ui] = o.pos;
            if o.flags & 3 == OUT_ARRIVE {
                mv[ui] = 0;
            }
            res[m * 4] = o.dpi as f32;
            res[m * 4 + 1] = o.facing;
            res[m * 4 + 2] = o.stuck as f32;
            res[m * 4 + 3] = o.flags as f32;
        }
        self.last_adv = res;
        let out = self.separate_core(nav, &p, &r, &mv, &ky, id, &mc, pr);
        self.last_changed = (0..n).filter(|&i| out[i] != p0[i]).map(|i| i as i32).collect();
        out
    }

    /// Unit indices (ascending) whose position the last advance_separate() changed.
    #[func]
    fn last_changed(&self) -> PackedInt32Array {
        PackedInt32Array::from(self.last_changed.as_slice())
    }

    /// Per-mover results of the last advance_separate(), stride 4: [path_i delta, facing, stuck, flags]
    /// with flags & 3 = 0 none / 1 arrive / 2 repath and flags & 4 = facing was set.
    #[func]
    fn last_adv(&self) -> PackedFloat32Array {
        PackedFloat32Array::from(self.last_adv.as_slice())
    }

    /// Overlapping pairs found by the last separate() call.
    #[func]
    fn last_pairs(&self) -> i32 {
        self.last_pairs
    }

    #[func]
    fn last_moved(&self) -> i32 {
        self.last_moved
    }
}

impl RtsSteer {
    #[allow(clippy::too_many_arguments)]
    fn separate_core(&mut self, nav: &RtsNav, p: &[Vector2], r: &[f32], mv: &[u8], ky: &[i32], id: &[i32],
                     mc: &[u8], pr: &[f32]) -> Vec<Vector2> {
        let n = p.len().min(r.len()).min(mv.len()).min(ky.len()).min(id.len()).min(mc.len());
        let get = |i: usize, d: f32| if i < pr.len() { pr[i] } else { d };
        let (strength, max_push, bucket, q) = (get(0, 0.5), get(1, 0.15), get(2, 1.5), get(3, 1.0 / 1024.0));
        let (mw, mh) = nav.dims();
        // stable bucket order: (key, by, bx), then index
        let bxy: Vec<(i32, i32)> = (0..n).map(|i| ((p[i].x / bucket).floor() as i32, (p[i].y / bucket).floor() as i32)).collect();
        let mut order: Vec<u32> = (0..n as u32).collect();
        order.sort_by_key(|&i| { let i = i as usize; (ky[i], bxy[i].1, bxy[i].0, i) });
        let mut ranges: HashMap<(i32, i32, i32), (u32, u32)> = HashMap::with_capacity(n);
        let mut s = 0usize;
        while s < n {
            let i0 = order[s] as usize;
            let k = (ky[i0], bxy[i0].0, bxy[i0].1);
            let mut e = s + 1;
            while e < n {
                let j = order[e] as usize;
                if (ky[j], bxy[j].0, bxy[j].1) != k { break; }
                e += 1;
            }
            ranges.insert(k, (s as u32, e as u32));
            s = e;
        }
        let mut push = vec![Vector2::ZERO; n];
        let mut pairs = 0;
        for i in 0..n {
            let (bx, by) = bxy[i];
            for (nb, &(ox, oy)) in HALF_NB.iter().enumerate() {
                let Some(&(a, b)) = ranges.get(&(ky[i], bx + ox, by + oy)) else { continue };
                for &j in &order[a as usize..b as usize] {
                    let j = j as usize;
                    if nb == 0 && j <= i {
                        continue;
                    }
                    let d = p[i] - p[j];
                    let min_d = r[i] + r[j];
                    let dist2 = d.x * d.x + d.y * d.y;
                    if dist2 >= min_d * min_d {
                        continue;
                    }
                    pairs += 1;
                    let dist = dist2.sqrt();
                    let dir = if dist < 0.0001 {
                        let ang = (((id[i] as i64) * 37 + (id[j] as i64) * 17).rem_euclid(360)) as f32 * std::f32::consts::PI / 180.0;
                        Vector2::new(ang.cos(), ang.sin())
                    } else {
                        d / dist
                    };
                    let overlap = (min_d - dist) * strength;
                    let mut wa = 0.5;
                    if mv[i] != mv[j] {
                        wa = if mv[i] == 1 { 0.25 } else { 0.75 };
                    }
                    push[i] += dir * (overlap * wa);
                    push[j] -= dir * (overlap * (1.0 - wa));
                }
            }
        }
        self.last_pairs = pairs;
        let mut out: Vec<Vector2> = p[..n].to_vec();
        let mut moved = 0;
        if pairs > 0 {
            let (fw, fh) = (mw as f32 - 0.01, mh as f32 - 0.01);
            for i in 0..n {
                let mut v = push[i];
                let l = v.length();
                if l < 0.002 {
                    continue;
                }
                if l > max_push {
                    v = v / l * max_push;
                }
                let mut to = p[i] + v;
                to.x = to.x.clamp(0.01, fw);
                to.y = to.y.clamp(0.01, fh);
                let np = qpos(nav.try_move(mc[i] as usize, p[i], to), q);
                if np != p[i] {
                    moved += 1;
                }
                out[i] = np;
            }
        }
        self.last_moved = moved;
        out
    }
}
