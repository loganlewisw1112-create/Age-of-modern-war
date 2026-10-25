//! RtsNav: grid navigation per move class. Cell weight = 1 / terrain speed_mult, 0 = solid
//! (impassable terrain, a building footprint, or a cell the class's `allow` mask forbids).
//! Mirrors movement.gd's AStarGrid2D setup: 8-neighbour, diagonal only if both orthogonal cells
//! are open, step cost (1 or sqrt2) x weight of the cell entered, octile heuristic (scaled by the
//! minimum weight so it stays admissible on roads).
//!
//! G4 (CONTRACTS_G4 section 3, NAT): classes 0 foot, 1 vehicle, 2 air, 3 amphibious,
//! 4 naval_small, 5 naval, 6 air_low, 7 air_high. Air classes (2, 6, 7) pass every in-bounds
//! cell. Ground classes other than foot/vehicle are added lazily (add_class) with their LUT and
//! an optional per-cell allow mask (naval: the >= 3-wide channel mask).
//! Every "mc" argument is a class KEY: class | ((team + 1) << 4); team bits 0 = no team. Gate
//! cells (set_gate) are solid for every key except the owner team's while unlocked; a gate
//! overrides the building footprint under it. Caches (components, flow fields) are keyed by the
//! normalised key: the team bits are dropped while no gate exists, so nothing changes for G3 maps.

use godot::prelude::*;
use std::cmp::Ordering;
use std::collections::BinaryHeap;
pub(crate) const SQRT2: f32 = std::f32::consts::SQRT_2;
pub(crate) const NCLS: usize = 10;   // G6: + rail 8, hover 9

pub const DIRS: [(i32, i32); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)];

#[inline]
pub fn is_air(c: usize) -> bool {
    c == 2 || c == 6 || c == 7
}

#[derive(Copy, Clone)]
pub(crate) struct Node {
    pub(crate) f: f32,
    pub(crate) seq: u32,
    pub(crate) idx: u32,
}
impl PartialEq for Node {
    fn eq(&self, o: &Self) -> bool {
        self.cmp(o) == Ordering::Equal
    }
}
impl Eq for Node {}
impl PartialOrd for Node {
    fn partial_cmp(&self, o: &Self) -> Option<Ordering> {
        Some(self.cmp(o))
    }
}
impl Ord for Node {
    // BinaryHeap is a max-heap: smallest f first, then smallest seq (FIFO among equals).
    fn cmp(&self, o: &Self) -> Ordering {
        o.f.total_cmp(&self.f).then_with(|| o.seq.cmp(&self.seq))
    }
}

pub(crate) struct Flow {
    pub(crate) handle: i64,
    pub(crate) goal: usize,
    pub(crate) mc: usize, // normalised key
    pub(crate) version: i64,
    pub(crate) cost: Vec<f32>,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsNav {
    pub(crate) w: i32,
    pub(crate) h: i32,
    pub(crate) terrain: Vec<u8>,
    pub(crate) blocked: Vec<u8>,
    /// G6 (PERF6): per class, footprints at the cell that are passable for it (G6Hooks.passable).
    pub(crate) pblk: Vec<Vec<u8>>,
    /// G6 (PERF6): cliff edge bits per cell (1 +x, 2 +y, 4 -x, 8 -y; empty = no cliffs). Ground only.
    pub(crate) edge: Vec<u8>,
    pub(crate) gate: Vec<u8>, // 0 none, else (owner team + 1) | 0x80 when locked
    pub(crate) gate_n: usize,
    pub(crate) lut: Vec<Vec<f32>>,
    pub(crate) allow: Vec<Vec<u8>>,
    pub(crate) weight: Vec<Vec<f32>>,
    pub(crate) min_w: Vec<f32>,
    pub(crate) comp: Vec<Option<Vec<i32>>>,
    pub(crate) version: i64,
    pub(crate) g: Vec<f32>,
    pub(crate) parent: Vec<i32>,
    pub(crate) stamp: Vec<u32>,
    pub(crate) closed: Vec<u32>,
    pub(crate) gen: u32,
    pub(crate) flows: Vec<Flow>,
    pub(crate) next_handle: i64,
}

impl RtsNav {
    #[inline]
    pub fn in_bounds(&self, x: i32, y: i32) -> bool {
        x >= 0 && y >= 0 && x < self.w && y < self.h
    }
    /// Key with the team bits dropped while no gate exists (and always for air).
    #[inline]
    pub fn norm(&self, k: usize) -> usize {
        let c = k & 15;
        if is_air(c) || self.gate_n == 0 { c } else { k & 255 }
    }
    #[inline]
    pub fn passable_i(&self, k: usize, i: usize) -> bool {
        let c = k & 15;
        if is_air(c) {
            return true;
        }
        let ok = match self.weight.get(c) {
            Some(wv) => wv.get(i).copied().unwrap_or(0.0) > 0.0,
            None => false,
        };
        if !ok {
            return false;
        }
        let g = self.gate.get(i).copied().unwrap_or(0);
        if g == 0 {
            return true;
        }
        let t1 = (k >> 4) & 15;
        g & 0x80 == 0 && t1 != 0 && (g & 15) as usize == t1
    }
    #[inline]
    pub fn passable(&self, k: usize, x: i32, y: i32) -> bool {
        self.in_bounds(x, y) && self.passable_i(k, (y * self.w + x) as usize)
    }
    /// G6 (PERF6): true when edge bit `bit` of cell i is open for key k (always for air / no cliffs).
    #[inline]
    pub(crate) fn eopen(&self, k: usize, i: usize, bit: u8) -> bool {
        self.edge.is_empty() || is_air(k & 15) || self.edge.get(i).copied().unwrap_or(0) & bit == 0
    }
    /// G6 (PERF6): false when the step (x, y) -> (x + dx, y + dy) (|dx|, |dy| <= 1) crosses a cliff
    /// edge (Elevation.edge_ok, symmetric bits). A diagonal needs all four sides of its square open.
    #[inline]
    pub fn edge_ok(&self, k: usize, x: i32, y: i32, dx: i32, dy: i32) -> bool {
        if self.edge.is_empty() || is_air(k & 15) {
            return true;
        }
        let ox = |x: i32, y: i32, dx: i32| -> bool {
            if dx == 0 || !self.in_bounds(x, y) { return true; }
            self.edge[(y * self.w + x) as usize] & (if dx > 0 { 1 } else { 4 }) == 0
        };
        let oy = |x: i32, y: i32, dy: i32| -> bool {
            if dy == 0 || !self.in_bounds(x, y) { return true; }
            self.edge[(y * self.w + x) as usize] & (if dy > 0 { 2 } else { 8 }) == 0
        };
        if dx == 0 || dy == 0 {
            return ox(x, y, dx) && oy(x, y, dy);
        }
        ox(x, y, dx) && oy(x + dx, y, dy) && oy(x, y, dy) && ox(x, y + dy, dx)
    }
    /// Entry weight of cell i for key k (1 for air).
    #[inline]
    pub(crate) fn wt(&self, k: usize, i: usize) -> f32 {
        let c = k & 15;
        if is_air(c) { 1.0 } else { self.weight[c][i] }
    }
    pub fn dims(&self) -> (i32, i32) {
        (self.w, self.h)
    }
    #[inline]
    fn cell_of(p: Vector2) -> (i32, i32) {
        (p.x.floor() as i32, p.y.floor() as i32)
    }
    /// movement.gd _step_ok: same cell, or the new cell is open (and on a diagonal cell change
    /// both orthogonal cells are open too).
    pub fn step_ok(&self, mc: usize, from: Vector2, to: Vector2) -> bool {
        let (ax, ay) = Self::cell_of(from);
        let (bx, by) = Self::cell_of(to);
        if ax == bx && ay == by {
            return true;
        }
        if !self.passable(mc, bx, by) {
            return false;
        }
        if ax != bx && ay != by && !(self.passable(mc, bx, ay) && self.passable(mc, ax, by)) {
            return false;
        }
        self.edge_ok(mc, ax, ay, (bx - ax).signum(), (by - ay).signum())
    }
    /// movement.gd _try_move: full move, else slide on x, else slide on y, else stay.
    pub fn try_move(&self, mc: usize, from: Vector2, to: Vector2) -> Vector2 {
        if self.step_ok(mc, from, to) {
            return to;
        }
        let sx = Vector2::new(to.x, from.y);
        if self.step_ok(mc, from, sx) {
            return sx;
        }
        let sy = Vector2::new(from.x, to.y);
        if self.step_ok(mc, from, sy) {
            return sy;
        }
        from
    }
    pub(crate) fn has_class_i(&self, c: usize) -> bool {
        is_air(c) || self.weight.get(c).map_or(false, |v| v.len() == (self.w * self.h) as usize && !v.is_empty())
    }
    fn cell_weight(&self, c: usize, i: usize) -> f32 {
        let sm = if self.lut[c].len() == 256 { self.lut[c][self.terrain[i] as usize] } else { 0.0 };
        let allow = self.allow[c].is_empty() || self.allow[c].get(i).copied().unwrap_or(0) != 0;
        let pb = self.pblk.get(c).and_then(|v| v.get(i)).copied().unwrap_or(0);
        let blk = self.blocked[i] > pb && self.gate.get(i).copied().unwrap_or(0) == 0;
        if blk || sm <= 0.0 || !allow { 0.0 } else { 1.0 / sm }
    }
    pub(crate) fn recompute_cell(&mut self, i: usize) {
        for c in 0..NCLS {
            if !is_air(c) && self.weight[c].len() > i {
                let v = self.cell_weight(c, i);
                self.weight[c][i] = v;
            }
        }
    }
    pub(crate) fn changed(&mut self) {
        self.version += 1;
        for s in self.comp.iter_mut() {
            *s = None;
        }
        self.flows.clear();
    }
    /// (Re)computes every cell of class c (allocated), and its minimum weight.
    pub(crate) fn compute_class(&mut self, c: usize) {
        let n = (self.w * self.h) as usize;
        let mut v = vec![0.0f32; n];
        for (i, x) in v.iter_mut().enumerate() {
            *x = self.cell_weight(c, i);
        }
        let m = v.iter().cloned().filter(|&x| x > 0.0).fold(f32::INFINITY, f32::min);
        self.min_w[c] = if m.is_finite() { m.min(1.0) } else { 1.0 };
        self.weight[c] = v;
    }
    pub(crate) fn reset_tables(&mut self) {
        self.lut = vec![Vec::new(); NCLS];
        self.allow = vec![Vec::new(); NCLS];
        self.weight = vec![Vec::new(); NCLS];
        self.min_w = vec![1.0; NCLS];
        self.comp = vec![None; 256];
    }
    #[inline]
    pub(crate) fn diag_ok(&self, mc: usize, x: i32, y: i32, dx: i32, dy: i32) -> bool {
        dx == 0 || dy == 0 || (self.passable(mc, x + dx, y) && self.passable(mc, x, y + dy))
    }
    #[inline]
    pub(crate) fn heur(&self, mc: usize, a: usize, b: usize) -> f32 {
        let w = self.w as usize;
        let dx = ((a % w) as i32 - (b % w) as i32).abs() as f32;
        let dy = ((a / w) as i32 - (b / w) as i32).abs() as f32;
        let f = SQRT2 - 1.0;
        let o = if dx < dy { f * dx + dy } else { f * dy + dx };
        o * self.min_w.get(mc & 15).copied().unwrap_or(1.0)
    }
    pub(crate) fn next_gen(&mut self) -> u32 {
        let n = (self.w * self.h) as usize;
        if self.stamp.len() != n {
            self.g = vec![0.0; n];
            self.parent = vec![-1; n];
            self.stamp = vec![0; n];
            self.closed = vec![0; n];
            self.gen = 0;
        }
        self.gen = self.gen.wrapping_add(1);
        if self.gen == 0 {
            self.stamp.fill(0);
            self.closed.fill(0);
            self.gen = 1;
        }
        self.gen
    }
}

// A*, simplify, components and flow fields: nav_search.rs. GDScript API: nav_api.rs.
#[path = "nav_search.rs"]
mod search;
#[path = "nav_api.rs"]
mod api;
