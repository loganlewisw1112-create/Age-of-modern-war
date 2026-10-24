//! RtsNav: GDScript-facing API. Every `mc` argument is a class key (nav.rs): the class index
//! (0 foot, 1 vehicle, 2 air, 3 amphibious, 4 naval_small, 5 naval, 6 air_low, 7 air_high)
//! plus (team + 1) << 4 when the caller knows the entity's team (gates).

use super::*;

const MAX_FLOWS: usize = 24;

fn key_of(mc: i32) -> usize {
    (mc.max(0) as usize) & 255
}

impl RtsNav {
    fn idx(&self, c: Vector2i) -> Option<usize> {
        if self.in_bounds(c.x, c.y) { Some((c.y * self.w + c.x) as usize) } else { None }
    }
}

#[godot_api]
impl RtsNav {
    /// terrain/blocked: one byte per cell (row-major). lut_*: 256 entries, the terrain code's
    /// speed_mult for that class, 0 = impassable. Adds classes 0 (foot) and 1 (vehicle); clears gates.
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
        self.gate = vec![0; n];
        self.gate_n = 0;
        self.reset_tables();
        self.lut[0] = lut_foot.as_slice().to_vec();
        self.lut[1] = lut_vehicle.as_slice().to_vec();
        self.stamp.clear();
        self.compute_class(0);
        self.compute_class(1);
        self.changed();
    }

    /// G4: adds (or replaces) ground class c (3..5, or 0/1) with its 256-entry LUT and an optional
    /// per-cell allow mask (empty = every cell; 0 = solid for this class). No-op for air classes.
    /// Does not bump version(): other classes' passability is unchanged.
    #[func]
    fn add_class(&mut self, c: i32, lut: PackedFloat32Array, allow: PackedByteArray) {
        let c = (c.max(0) as usize) & 15;
        if c >= NCLS || is_air(c) || self.weight.len() != NCLS {
            return;
        }
        self.lut[c] = lut.as_slice().to_vec();
        self.allow[c] = allow.as_slice().to_vec();
        self.compute_class(c);
        for k in 0..256usize {
            if k & 15 == c {
                self.comp[k] = None;
            }
        }
        let ver = self.version;
        self.flows.retain(|f| f.version == ver && f.mc & 15 != c);
    }

    #[func]
    fn has_class(&self, c: i32) -> bool {
        self.has_class_i((c.max(0) as usize) & 15)
    }

    /// G4 gates: code 0 removes the gate at each cell; else (owner_team + 1) | 0x80 if locked.
    #[func]
    fn set_gate(&mut self, cells: PackedInt32Array, code: i32) {
        let n = self.gate.len();
        let code = (code.clamp(0, 255)) as u8;
        for &ci in cells.as_slice() {
            if ci < 0 || ci as usize >= n {
                continue;
            }
            let i = ci as usize;
            if (self.gate[i] == 0) != (code == 0) {
                if code == 0 { self.gate_n -= 1 } else { self.gate_n += 1 }
            }
            self.gate[i] = code;
            self.recompute_cell(i);
            for c in 0..NCLS {
                if !is_air(c) && self.weight[c].len() > i && self.weight[c][i] > 0.0 {
                    self.min_w[c] = self.min_w[c].min(self.weight[c][i]);
                }
            }
        }
        self.changed();
    }

    #[func]
    fn gate_count(&self) -> i32 {
        self.gate_n as i32
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
        !self.passable(key_of(mc), cell.x, cell.y)
    }

    /// One byte per cell, 1 = solid, for key mc (team bits honoured: a gate is solid for team 0 bits).
    #[func]
    fn solid_bytes(&self, mc: i32) -> PackedByteArray {
        let k = key_of(mc);
        let n = (self.w * self.h) as usize;
        let v: Vec<u8> = (0..n).map(|i| if self.passable_i(k, i) { 0 } else { 1 }).collect();
        PackedByteArray::from(v.as_slice())
    }

    #[func]
    fn components(&mut self, mc: i32) -> PackedInt32Array {
        let k = self.norm(key_of(mc));
        self.ensure_comp(k);
        match &self.comp[k] {
            Some(v) => PackedInt32Array::from(v.as_slice()),
            None => PackedInt32Array::new(),
        }
    }

    #[func]
    fn version(&self) -> i64 {
        self.version
    }

    /// A* from start to goal. Waypoints are cell centres, start excluded, collinear runs merged.
    /// Empty if either end is solid or no path exists.
    #[func]
    fn find_path(&mut self, start: Vector2i, goal: Vector2i, mc: i32) -> PackedVector2Array {
        let k = self.norm(key_of(mc));
        let (s, t) = match (self.idx(start), self.idx(goal)) {
            (Some(s), Some(t)) => (s, t),
            _ => return PackedVector2Array::new(),
        };
        if !self.passable_i(k, s) || !self.passable_i(k, t) {
            return PackedVector2Array::new();
        }
        match self.astar(k, s, t) {
            Some(cells) => self.simplify(&cells),
            None => PackedVector2Array::new(),
        }
    }

    /// movement.gd _line_clear: straight segment sampled every 0.3 tiles; false beyond max_len.
    #[func]
    fn line_clear(&self, mc: i32, a: Vector2, b: Vector2, max_len: f32) -> bool {
        let m = key_of(mc);
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

    /// Flow field toward goal for key mc. Returns a handle (valid until the next passability
    /// change), or -1 if the goal cell is solid. LRU cached by (goal, normalised key).
    #[func]
    fn flow(&mut self, goal: Vector2i, mc: i32) -> i64 {
        let m = self.norm(key_of(mc));
        let gi = match self.idx(goal) {
            Some(i) if self.passable_i(m, i) => i,
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
