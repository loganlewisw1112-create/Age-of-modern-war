//! RtsSteer: batch separation step (movement.gd _separate), deterministic.
//! Units overlap-test only against units with the same key (owner layer, air layer) in a
//! half neighbourhood of buckets, so each pair is visited once, in ascending index order.
//! Pushes are clamped, bounded to the map and slid against the RtsNav passability grid.

use crate::nav::RtsNav;
use godot::prelude::*;
use std::collections::HashMap;

const HALF_NB: [(i32, i32); 5] = [(0, 0), (1, 0), (-1, 1), (0, 1), (1, 1)];

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsSteer {
    last_pairs: i32,
    last_moved: i32,
}

fn qpos(p: Vector2, q: f32) -> Vector2 {
    let s = Vector2::new((p.x / q + 0.5).floor() * q, (p.y / q + 0.5).floor() * q);
    if s.x.floor() == p.x.floor() && s.y.floor() == p.y.floor() { s } else { p }
}

#[godot_api]
impl RtsSteer {
    /// Inputs are parallel arrays in ascending entity-id order. mcs: 0 foot, 1 vehicle, 2 air.
    /// moving: 1 = has a path. Returns the new positions (unchanged entries are copied through).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn separate(&mut self, nav: Gd<RtsNav>, pos: PackedVector2Array, rad: PackedFloat32Array,
                moving: PackedByteArray, keys: PackedInt32Array, ids: PackedInt32Array,
                mcs: PackedByteArray, params: PackedFloat32Array) -> PackedVector2Array {
        let p = pos.as_slice();
        let n = p.len().min(rad.len()).min(moving.len()).min(keys.len()).min(ids.len()).min(mcs.len());
        let (r, mv, ky, id, mc) = (rad.as_slice(), moving.as_slice(), keys.as_slice(), ids.as_slice(), mcs.as_slice());
        let pr = params.as_slice();
        let get = |i: usize, d: f32| if i < pr.len() { pr[i] } else { d };
        let (strength, max_push, bucket, q) = (get(0, 0.5), get(1, 0.15), get(2, 1.5), get(3, 1.0 / 1024.0));
        let nav = nav.bind();
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
        PackedVector2Array::from(out.as_slice())
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
