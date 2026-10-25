//! RtsNav searches: A*, waypoint simplification, connected components, flow fields.
//! Every `mc` here is a normalised class key (see nav.rs).

use super::*;

impl RtsNav {
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
                if !self.passable(mc, vx, vy) || !self.diag_ok(mc, ux, uy, dx, dy) || !self.edge_ok(mc, ux, uy, dx, dy) {
                    continue;
                }
                let v = (vy * w + vx) as usize;
                if self.closed[v] == gen {
                    continue;
                }
                let step = if k < 4 { 1.0 } else { SQRT2 };
                let ng = self.g[u] + step * self.wt(mc, v);
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

    /// 4-connected labels in scan order (movement.gd _comp): -1 solid, else component id.
    /// Cached per normalised key until the next passability change.
    pub(crate) fn ensure_comp(&mut self, mc: usize) {
        if self.comp[mc].is_some() {
            return;
        }
        let (w, h) = (self.w as usize, self.h as usize);
        let n = w * h;
        let mut lab = vec![-2i32; n];
        for (i, l) in lab.iter_mut().enumerate() {
            if !self.passable_i(mc, i) {
                *l = -1;
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
                if x > 0 && lab[i - 1] == -2 && self.eopen(mc, i, 4) { lab[i - 1] = next; q.push(i - 1); }
                if x < w - 1 && lab[i + 1] == -2 && self.eopen(mc, i, 1) { lab[i + 1] = next; q.push(i + 1); }
                if y > 0 && lab[i - w] == -2 && self.eopen(mc, i, 8) { lab[i - w] = next; q.push(i - w); }
                if y < h - 1 && lab[i + w] == -2 && self.eopen(mc, i, 2) { lab[i + w] = next; q.push(i + w); }
            }
            next += 1;
        }
        self.comp[mc] = Some(lab);
    }

    /// Reverse Dijkstra from goal: cost[c] = cheapest cost of walking c -> goal.
    pub(crate) fn build_flow(&self, goal: usize, mc: usize) -> Vec<f32> {
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
            let wu = self.wt(mc, u);
            for (k, &(dx, dy)) in DIRS.iter().enumerate() {
                let (vx, vy) = (ux + dx, uy + dy);
                if !self.passable(mc, vx, vy) || !self.diag_ok(mc, ux, uy, dx, dy) || !self.edge_ok(mc, ux, uy, dx, dy) {
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
    pub(crate) fn flow_next(&self, f: &Flow, c: usize) -> Option<usize> {
        if c == f.goal || !f.cost[c].is_finite() {
            return None;
        }
        let w = self.w;
        let (cx, cy) = ((c as i32) % w, (c as i32) / w);
        let mut best: Option<usize> = None;
        let mut best_v = f32::INFINITY;
        for (k, &(dx, dy)) in DIRS.iter().enumerate() {
            let (nx, ny) = (cx + dx, cy + dy);
            if !self.passable(f.mc, nx, ny) || !self.diag_ok(f.mc, cx, cy, dx, dy) || !self.edge_ok(f.mc, cx, cy, dx, dy) {
                continue;
            }
            let ni = (ny * w + nx) as usize;
            let wn = self.wt(f.mc, ni);
            let v = f.cost[ni] + (if k < 4 { 1.0 } else { SQRT2 }) * wn;
            if v < best_v && f.cost[ni] < f.cost[c] {
                best_v = v;
                best = Some(ni);
            }
        }
        best
    }

    pub(crate) fn flow_ref(&self, handle: i64) -> Option<&Flow> {
        self.flows.iter().find(|f| f.handle == handle && f.version == self.version)
    }
}
