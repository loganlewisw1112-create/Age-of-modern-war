//! RtsNav: grid navigation for the ground move classes (0 = foot, 1 = vehicle; 2 = air is
//! "every in-bounds cell"). Cell weight = 1 / terrain speed_mult, 0 = solid (impassable terrain
//! or a building footprint). Mirrors movement.gd's AStarGrid2D setup: 8-neighbour, diagonal only
//! if both orthogonal cells are open, step cost (1 or sqrt2) x weight of the cell entered,
//! octile heuristic (scaled by the minimum weight so it stays admissible on roads).
//! Flow fields: one reverse Dijkstra integration field per (goal, class), LRU cached, invalidated
//! by any passability change (version counter).

use godot::prelude::*;
use std::cmp::Ordering;
use std::collections::BinaryHeap;
pub(crate) const SQRT2: f32 = std::f32::consts::SQRT_2;

pub const DIRS: [(i32, i32); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)];

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
    pub(crate) mc: usize,
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
    pub(crate) lut: [Vec<f32>; 2],
    pub(crate) weight: [Vec<f32>; 2],
    pub(crate) min_w: [f32; 2],
    pub(crate) comp: [Vec<i32>; 2],
    pub(crate) comp_ok: [bool; 2],
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
    #[inline]
    pub fn passable(&self, mc: usize, x: i32, y: i32) -> bool {
        if !self.in_bounds(x, y) {
            return false;
        }
        mc >= 2 || self.weight[mc][(y * self.w + x) as usize] > 0.0
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
        if ax != bx && ay != by {
            return self.passable(mc, bx, ay) && self.passable(mc, ax, by);
        }
        true
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
    pub(crate) fn recompute_cell(&mut self, i: usize) {
        for mc in 0..2 {
            let sm = if self.lut[mc].len() == 256 { self.lut[mc][self.terrain[i] as usize] } else { 0.0 };
            self.weight[mc][i] = if self.blocked[i] > 0 || sm <= 0.0 { 0.0 } else { 1.0 / sm };
        }
    }
    pub(crate) fn changed(&mut self) {
        self.version += 1;
        self.comp_ok = [false, false];
        self.flows.clear();
    }
    pub(crate) fn recompute_all(&mut self) {
        let n = (self.w * self.h) as usize;
        self.weight = [vec![0.0; n], vec![0.0; n]];
        for i in 0..n {
            self.recompute_cell(i);
        }
        for mc in 0..2 {
            let m = self.weight[mc].iter().cloned().filter(|&x| x > 0.0).fold(f32::INFINITY, f32::min);
            self.min_w[mc] = if m.is_finite() { m.min(1.0) } else { 1.0 };
        }
        self.changed();
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
        o * self.min_w[mc]
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
    pub(crate) fn astar(&mut self, mc: usize, s: usize, t: usize) -> Option<Vec<usize>> {
        let gen = self.next_gen();
        let w = self.w;
        let mut heap = BinaryHeap::new();
        let mut seq = 0u32;
        self.g[s] = 0.0;
        self.stamp[s] = gen;
        self.parent[s] = -1;
        heap.push(Node { f: self.heur(mc, s, t), seq, idx: s as u32 });
        let mut found = false;
        while let Some(Node { idx, .. }) = heap.pop() {
            let u = idx as usize;
            if self.closed[u] == gen {
                continue;
            }
            self.closed[u] = gen;
            if u == t {
                found = true;
                break;
            }
            let (ux, uy) = ((u as i32) % w, (u as i32) / w);
            for (k, &(dx, dy)) in DIRS.iter().enumerate() {
                let (vx, vy) = (ux + dx, uy + dy);
                if !self.passable(mc, vx, vy) || !self.diag_ok(mc, ux, uy, dx, dy) {
                    continue;
                }
                let v = (vy * w + vx) as usize;
                if self.closed[v] == gen {
                    continue;
                }
                let step = if k < 4 { 1.0 } else { SQRT2 };
                let ng = self.g[u] + step * self.weight[mc][v];
                if self.stamp[v] != gen || ng < self.g[v] {
                    self.stamp[v] = gen;
                    self.g[v] = ng;
                    self.parent[v] = u as i32;
                    seq += 1;
                    heap.push(Node { f: ng + self.heur(mc, v, t), seq, idx: v as u32 });
                }
            }
        }
        if !found {
            return None;
        }
        let mut cells = vec![t];
        let mut c = t;
        while self.parent[c] >= 0 && c != s {
            c = self.parent[c] as usize;
            cells.push(c);
        }
        cells.reverse();
        Some(cells)
    }
    /// Cells (start first) -> waypoints at cell centres, start dropped, collinear runs merged
    /// (movement.gd _compute rule).
    pub(crate) fn simplify(&self, cells: &[usize]) -> PackedVector2Array {
        let w = self.w as usize;
        let xy = |c: usize| ((c % w) as i32, (c / w) as i32);
        let n = cells.len();
        let mut out: Vec<Vector2> = Vec::new();
        for i in 1..n {
            if i < n - 1 {
                let (a, b, c) = (xy(cells[i - 1]), xy(cells[i]), xy(cells[i + 1]));
                if b.0 - a.0 == c.0 - b.0 && b.1 - a.1 == c.1 - b.1 {
                    continue;
                }
            }
            let (x, y) = xy(cells[i]);
            out.push(Vector2::new(x as f32 + 0.5, y as f32 + 0.5));
        }
        PackedVector2Array::from(out.as_slice())
    }
}

// GDScript API lives in nav_api.rs (child module so #[godot_api] sees the derive macros).
#[path = "nav_api.rs"]
mod api;
