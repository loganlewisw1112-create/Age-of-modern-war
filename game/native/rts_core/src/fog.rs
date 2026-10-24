//! RtsFog: stateless circle stamping for fog.gd (G3b N1-core-3, PERF4-2 change request seq 890).
//! stamp() marks every in-bounds cell (x, y) with (x - cx)^2 + (y - cy)^2 <= sight^2 (f64 compare,
//! r = floor(sight) square scan) around each source cell, exactly the rule of fog.gd `_stamp` + its
//! Image blits. Output is a pure function of the inputs: sources are OR-ed, so input order never
//! matters. The circle offset cache is keyed by the sight's bit pattern (lookup only, never iterated).

use godot::prelude::*;
use std::collections::HashMap;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsFog {
    circles: HashMap<u64, Vec<(i32, i32)>>,
    explored_last: Vec<u8>,
}

impl RtsFog {
    fn circle(&mut self, sight: f64) -> &Vec<(i32, i32)> {
        self.circles.entry(sight.to_bits()).or_insert_with(|| {
            let r = sight.floor() as i32;
            let s2 = sight * sight;
            let mut v = Vec::new();
            for dy in -r..=r {
                for dx in -r..=r {
                    if ((dx * dx + dy * dy) as f64) <= s2 {
                        v.push((dx, dy));
                    }
                }
            }
            v
        })
    }

    /// Core of stamp(): returns vis (0/1, mw*mh) and sets explored_last = explored | vis.
    pub fn stamp_core(&mut self, mw: i32, mh: i32, cells: &[i32], sights: &[f64], explored: &[u8]) -> Vec<u8> {
        let n = (mw.max(0) as usize) * (mh.max(0) as usize);
        let mut vis = vec![0u8; n];
        if mw > 0 && mh > 0 {
            for (i, &ci) in cells.iter().enumerate() {
                let s = if i < sights.len() { sights[i] } else { 0.0 };
                if !(s > 0.0) || ci < 0 {
                    continue;
                }
                let cy = ci / mw;
                let cx = ci - cy * mw;
                let r = s.floor() as i32;
                let full_inside = cx - r >= 0 && cy - r >= 0 && cx + r < mw && cy + r < mh;
                let offs = self.circle(s);
                if full_inside {
                    for &(dx, dy) in offs.iter() {
                        vis[((cy + dy) * mw + cx + dx) as usize] = 1;
                    }
                } else {
                    for &(dx, dy) in offs.iter() {
                        let x = cx + dx;
                        let y = cy + dy;
                        if x >= 0 && y >= 0 && x < mw && y < mh {
                            vis[(y * mw + x) as usize] = 1;
                        }
                    }
                }
            }
        }
        let mut ex = vec![0u8; n];
        for i in 0..n {
            let e = if i < explored.len() { explored[i] } else { 0 };
            ex[i] = if vis[i] != 0 { 1 } else { e };
        }
        self.explored_last = ex;
        vis
    }
}

#[godot_api]
impl RtsFog {
    /// cells: source cell index y * map_w + x per source; sights: per-source sight radius in tiles
    /// (same length); explored: the team's explored bytes (0/1, map_w * map_h). Returns visible
    /// (0/1, map_w * map_h). explored_out() then returns explored OR visible.
    #[func]
    fn stamp(&mut self, map_w: i32, map_h: i32, cells: PackedInt32Array, sights: PackedFloat64Array,
             explored: PackedByteArray) -> PackedByteArray {
        let vis = self.stamp_core(map_w, map_h, cells.as_slice(), sights.as_slice(), explored.as_slice());
        PackedByteArray::from(vis.as_slice())
    }

    /// explored OR visible of the last stamp() call.
    #[func]
    fn explored_out(&self) -> PackedByteArray {
        PackedByteArray::from(self.explored_last.as_slice())
    }
}
