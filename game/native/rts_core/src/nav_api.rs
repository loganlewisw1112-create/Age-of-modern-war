//! RtsNav: GDScript-facing API, connected components and flow fields.

use super::*;

const MAX_FLOWS: usize = 24;

fn mc_of(mc: i32) -> usize {
    if mc <= 0 { 0 } else if mc == 1 { 1 } else { 2 }
}

impl RtsNav {
    fn idx(&self, c: Vector2i) -> Option<usize> {
        if self.in_bounds(c.x, c.y) { Some((c.y * self.w + c.x) as usize) } else { None }
    }

    /// 4-connected labels in scan order (movement.gd _comp): -1 solid, else component id.
    fn ensure_comp(&mut self, mc: usize) {
        if self.comp_ok[mc] {
            return;
        }
        let (w, h) = (self.w as usize, self.h as usize);
        let n = w * h;
        let mut lab = vec![-2i32; n];
        for i in 0..n {
            if self.weight[mc][i] <= 0.0 {
                lab[i] = -1;
            }
        }
        let mut next = 0;
        let mut q: Vec<usize> = Vec::new();
        for s in 0..n {
            if lab[s] != -2 {
                continue;
            }
            lab[s] = next;
            q.clear();
            q.push(s);
            let mut qi = 0;
            while qi < q.len() {
                let i = q[qi];
                qi += 1;
                let (x, y) = (i % w, i / w);
                if x > 0 && lab[i - 1] == -2 { lab[i - 1] = next; q.push(i - 1); }
                if x < w - 1 && lab[i + 1] == -2 { lab[i + 1] = next; q.push(i + 1); }
                if y > 0 && lab[i - w] == -2 { lab[i - w] = next; q.push(i - w); }
                if y < h - 1 && lab[i + w] == -2 { lab[i + w] = next; q.push(i + w); }
            }
            next += 1;
        }
        self.comp[mc] = lab;
        self.comp_ok[mc] = true;
    }

    /// Reverse Dijkstra from goal: cost[c] = cheapest cost of walking c -> goal.
    fn build_flow(&self, goal: usize, mc: usize) -> Vec<f32> {
        let w = self.w;
        let n = (self.w * self.h) as usize;
        let mut cost = vec![f32::INFINITY; n];
        let mut done = vec![false; n];
        let mut heap = BinaryHeap::new();
        let mut seq = 0u32;
        cost[goal] = 0.0;
        heap.push(Node { f: 0.0, seq, idx: goal as u32 });
        while let Some(Node { idx, .. }) = heap.pop() {
            let u = idx as usize;
            if done[u] {
                continue;
            }
            done[u] = true;
            let (ux, uy) = ((u as i32) % w, (u as i32) / w);
            let wu = if mc >= 2 { 1.0 } else { self.weight[mc][u] };
            for (k, &(dx, dy)) in DIRS.iter().enumerate() {
                let (vx, vy) = (ux + dx, uy + dy);
                if !self.passable(mc, vx, vy) || !self.diag_ok(mc, ux, uy, dx, dy) {
                    continue;
                }
                let v = (vy * w + vx) as usize;
                if done[v] {
                    continue;
                }
                let nc = cost[u] + (if k < 4 { 1.0 } else { SQRT2 }) * wu;
                if nc < cost[v] {
                    cost[v] = nc;
                    seq += 1;
                    heap.push(Node { f: nc, seq, idx: v as u32 });
                }
            }
        }
        cost
    }

    /// Best next cell from c on a flow field (None at the goal / unreachable). Ties: DIRS order.
    fn flow_next(&self, f: &Flow, c: usize) -> Option<usize> {
        if c == f.goal || !f.cost[c].is_finite() {
            return None;
        }
        let w = self.w;
        let (cx, cy) = ((c as i32) % w, (c as i32) / w);
        let mut best: Option<usize> = None;
        let mut best_v = f32::INFINITY;
        for (k, &(dx, dy)) in DIRS.iter().enumerate() {
            let (nx, ny) = (cx + dx, cy + dy);
            if !self.passable(f.mc, nx, ny) || !self.diag_ok(f.mc, cx, cy, dx, dy) {
                continue;
            }
            let ni = (ny * w + nx) as usize;
            let wn = if f.mc >= 2 { 1.0 } else { self.weight[f.mc][ni] };
            let v = f.cost[ni] + (if k < 4 { 1.0 } else { SQRT2 }) * wn;
            if v < best_v && f.cost[ni] < f.cost[c] {
                best_v = v;
                best = Some(ni);
            }
        }
        best
    }

    fn flow_ref(&self, handle: i64) -> Option<&Flow> {
        self.flows.iter().find(|f| f.handle == handle && f.version == self.version)
    }
}

#[godot_api]
impl RtsNav {
    /// terrain/blocked: one byte per cell (row-major). lut_*: 256 entries, the terrain code's
    /// speed_mult for that class, 0 = impassable.
    #[func]
    fn setup(&mut self, w: i32, h: i32, terrain: PackedByteArray, blocked: PackedByteArray,
             lut_foot: PackedFloat32Array, lut_vehicle: PackedFloat32Array) {
        let n = (w.max(0) * h.max(0)) as usize;
        self.w = w.max(0);
        self.h = h.max(0);
        self.terrain = terrain.as_slice().to_vec();
        self.terrain.resize(n, 0);
        self.blocked = blocked.as_slice().to_vec();
        self.blocked.resize(n, 0);
        self.lut = [lut_foot.as_slice().to_vec(), lut_vehicle.as_slice().to_vec()];
        self.stamp.clear();
        self.recompute_all();
    }

    /// Building footprint added (solid) or removed: per-cell block counts like movement.gd.
    #[func]
    fn apply_footprint(&mut self, ox: i32, oy: i32, size: i32, solid: bool) {
        for y in oy..oy + size {
            for x in ox..ox + size {
                if !self.in_bounds(x, y) {
                    continue;
                }
                let i = (y * self.w + x) as usize;
                self.blocked[i] = if solid { self.blocked[i].saturating_add(1) } else { self.blocked[i].saturating_sub(1) };
                self.recompute_cell(i);
            }
        }
        self.changed();
    }

    #[func]
    fn is_solid(&self, mc: i32, cell: Vector2i) -> bool {
        !self.passable(mc_of(mc), cell.x, cell.y)
    }

    /// One byte per cell, 1 = solid, for class mc (0 foot, 1 vehicle).
    #[func]
    fn solid_bytes(&self, mc: i32) -> PackedByteArray {
        let m = mc_of(mc).min(1);
        let v: Vec<u8> = self.weight[m].iter().map(|&x| if x > 0.0 { 0 } else { 1 }).collect();
        PackedByteArray::from(v.as_slice())
    }

    #[func]
    fn components(&mut self, mc: i32) -> PackedInt32Array {
        let m = mc_of(mc).min(1);
        self.ensure_comp(m);
        PackedInt32Array::from(self.comp[m].as_slice())
    }

    #[func]
    fn version(&self) -> i64 {
        self.version
    }

    /// A* from start to goal. Waypoints are cell centres, start excluded, collinear runs merged.
    /// Empty if either end is solid or no path exists.
    #[func]
    fn find_path(&mut self, start: Vector2i, goal: Vector2i, mc: i32) -> PackedVector2Array {
        let m = mc_of(mc).min(1);
        let (s, t) = match (self.idx(start), self.idx(goal)) {
            (Some(s), Some(t)) => (s, t),
            _ => return PackedVector2Array::new(),
        };
        if self.weight[m][s] <= 0.0 || self.weight[m][t] <= 0.0 {
            return PackedVector2Array::new();
        }
        match self.astar(m, s, t) {
            Some(cells) => self.simplify(&cells),
            None => PackedVector2Array::new(),
        }
    }

    /// movement.gd _line_clear: straight segment sampled every 0.3 tiles; false beyond max_len.
    #[func]
    fn line_clear(&self, mc: i32, a: Vector2, b: Vector2, max_len: f32) -> bool {
        let m = mc_of(mc);
        let d = b - a;
        let l = d.length();
        if l > max_len {
            return false;
        }
        let n = (l / 0.3).ceil() as i32;
        let mut prev = a;
        for i in 1..=n {
            let q = a + d * (i as f32 / n as f32);
            if !self.step_ok(m, prev, q) {
                return false;
            }
            prev = q;
        }
        true
    }

    /// Flow field toward goal for class mc. Returns a handle (valid until the next passability
    /// change), or -1 if the goal cell is solid. LRU cached by (goal, class).
    #[func]
    fn flow(&mut self, goal: Vector2i, mc: i32) -> i64 {
        let m = mc_of(mc).min(1);
        let gi = match self.idx(goal) {
            Some(i) if self.weight[m][i] > 0.0 => i,
            _ => return -1,
        };
        let ver = self.version;
        self.flows.retain(|f| f.version == ver);
        if let Some(p) = self.flows.iter().position(|f| f.goal == gi && f.mc == m) {
            let f = self.flows.remove(p);
            let h = f.handle;
            self.flows.push(f);
            return h;
        }
        let cost = self.build_flow(gi, m);
        self.next_handle += 1;
        let h = self.next_handle;
        if self.flows.len() >= MAX_FLOWS {
            self.flows.remove(0);
        }
        self.flows.push(Flow { handle: h, goal: gi, mc: m, version: ver, cost });
        h
    }

    /// Unit direction to the next cell on the flow field (zero at the goal or if unreachable).
    #[func]
    fn flow_dir(&self, handle: i64, cell: Vector2i) -> Vector2 {
        let (Some(f), Some(c)) = (self.flow_ref(handle), self.idx(cell)) else { return Vector2::ZERO };
        match self.flow_next(f, c) {
            Some(n) => {
                let w = self.w as usize;
                Vector2::new((n % w) as f32 - (c % w) as f32, (n / w) as f32 - (c / w) as f32).normalized()
            }
            None => Vector2::ZERO,
        }
    }

    /// Integration cost cell -> goal (INF if unreachable or stale handle).
    #[func]
    fn flow_cost(&self, handle: i64, cell: Vector2i) -> f32 {
        match (self.flow_ref(handle), self.idx(cell)) {
            (Some(f), Some(c)) => f.cost[c],
            _ => f32::INFINITY,
        }
    }

    /// Descends the flow field from start to its goal and returns waypoints like find_path.
    /// Empty if start is unreachable (or the handle is stale).
    #[func]
    fn flow_path(&self, handle: i64, start: Vector2i) -> PackedVector2Array {
        let (Some(f), Some(s)) = (self.flow_ref(handle), self.idx(start)) else { return PackedVector2Array::new() };
        if !f.cost[s].is_finite() {
            return PackedVector2Array::new();
        }
        let mut cells = vec![s];
        let mut c = s;
        let cap = (self.w * self.h) as usize;
        while let Some(n) = self.flow_next(f, c) {
            cells.push(n);
            c = n;
            if cells.len() > cap {
                break;
            }
        }
        self.simplify(&cells)
    }
}
