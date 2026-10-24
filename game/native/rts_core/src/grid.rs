//! RtsGrid: uniform spatial hash over entity positions (for combat target queries).
//! Items are bucketed with a stable counting sort, so inside a bucket they keep input order
//! (ascending entity id when the caller iterates w.entities). Queries are pure functions of the
//! last rebuild; ties break on lower id.

use godot::prelude::*;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsGrid {
    cell: f32,
    gw: i32,
    gh: i32,
    ids: Vec<i32>,
    pos: Vec<Vector2>,
    team: Vec<i32>,
    rad: Vec<f32>,
    flags: Vec<i32>,
    start: Vec<u32>, // bucket b holds items[start[b]..start[b+1]]
    items: Vec<u32>,
}

impl RtsGrid {
    fn bucket_xy(&self, p: Vector2) -> (i32, i32) {
        let bx = ((p.x / self.cell).floor() as i32).clamp(0, self.gw - 1);
        let by = ((p.y / self.cell).floor() as i32).clamp(0, self.gh - 1);
        (bx, by)
    }

    fn bucket_range(&self, bx: i32, by: i32) -> &[u32] {
        let b = (by * self.gw + bx) as usize;
        &self.items[self.start[b] as usize..self.start[b + 1] as usize]
    }

    /// Visits every item index in buckets overlapping the square [c-r, c+r], bucket rows then
    /// columns ascending (deterministic).
    fn for_each_near<F: FnMut(usize)>(&self, c: Vector2, r: f32, mut f: F) {
        if self.gw <= 0 || self.items.is_empty() {
            return;
        }
        let (x0, y0) = self.bucket_xy(Vector2::new(c.x - r, c.y - r));
        let (x1, y1) = self.bucket_xy(Vector2::new(c.x + r, c.y + r));
        for by in y0..=y1 {
            for bx in x0..=x1 {
                for &it in self.bucket_range(bx, by) {
                    f(it as usize);
                }
            }
        }
    }
}

#[godot_api]
impl RtsGrid {
    /// Sets the world size (cells) and bucket size (world units). Call before rebuild.
    #[func]
    fn setup(&mut self, map_w: i32, map_h: i32, cell_size: f32) {
        self.cell = if cell_size > 0.01 { cell_size } else { 4.0 };
        self.gw = ((map_w as f32 / self.cell).ceil() as i32).max(1);
        self.gh = ((map_h as f32 / self.cell).ceil() as i32).max(1);
    }

    /// Replaces all items. Arrays are parallel; pass them in ascending id order.
    #[func]
    fn rebuild(
        &mut self,
        ids: PackedInt32Array,
        pos: PackedVector2Array,
        team: PackedInt32Array,
        radius: PackedFloat32Array,
    ) {
        if self.gw <= 0 {
            self.setup(256, 256, 4.0);
        }
        let n = ids.len().min(pos.len()).min(team.len()).min(radius.len());
        self.ids = ids.as_slice()[..n].to_vec();
        self.pos = pos.as_slice()[..n].to_vec();
        self.team = team.as_slice()[..n].to_vec();
        self.rad = radius.as_slice()[..n].to_vec();
        self.flags = vec![0; n];
        let nb = (self.gw * self.gh) as usize;
        let mut count = vec![0u32; nb + 1];
        let mut bucket = Vec::with_capacity(n);
        for i in 0..n {
            let (bx, by) = self.bucket_xy(self.pos[i]);
            let b = (by * self.gw + bx) as usize;
            bucket.push(b as u32);
            count[b + 1] += 1;
        }
        for b in 0..nb {
            count[b + 1] += count[b];
        }
        self.start = count.clone();
        let mut fill = count;
        self.items = vec![0; n];
        for i in 0..n {
            let b = bucket[i] as usize;
            self.items[fill[b] as usize] = i as u32;
            fill[b] += 1;
        }
    }

    /// Optional per-item flag bits (parallel to the last rebuild), used by nearest_enemy_batch.
    #[func]
    fn set_flags(&mut self, flags: PackedInt32Array) {
        let s = flags.as_slice();
        for i in 0..self.flags.len().min(s.len()) {
            self.flags[i] = s[i];
        }
    }

    #[func]
    fn size(&self) -> i32 {
        self.ids.len() as i32
    }

    /// Ids of items whose centre is within r of center, ascending.
    #[func]
    fn query_radius(&self, center: Vector2, r: f32) -> PackedInt32Array {
        let r2 = r * r;
        let mut out: Vec<i32> = Vec::new();
        self.for_each_near(center, r, |i| {
            let d = self.pos[i] - center;
            if d.x * d.x + d.y * d.y <= r2 {
                out.push(self.ids[i]);
            }
        });
        out.sort_unstable();
        PackedInt32Array::from(out.as_slice())
    }

    /// For each source item index s (into the last rebuild), the id of the nearest item with a
    /// different team whose centre is within ranges[k] (+ the target's radius), and, when
    /// need_flags[k] != 0, whose flags share a bit with it. -1 if none. Ties: lower id.
    #[func]
    fn nearest_enemy_batch(
        &self,
        src_idx: PackedInt32Array,
        ranges: PackedFloat32Array,
        need_flags: PackedInt32Array,
    ) -> PackedInt32Array {
        let src = src_idx.as_slice();
        let rs = ranges.as_slice();
        let nf = need_flags.as_slice();
        let mut out: Vec<i32> = Vec::with_capacity(src.len());
        let max_rad = self.rad.iter().cloned().fold(0.0f32, f32::max);
        for (k, &si) in src.iter().enumerate() {
            let si = si as usize;
            if si >= self.ids.len() {
                out.push(-1);
                continue;
            }
            let range = if k < rs.len() { rs[k] } else { 0.0 };
            let need = if k < nf.len() { nf[k] } else { 0 };
            let c = self.pos[si];
            let my_team = self.team[si];
            let mut best_id = -1i32;
            let mut best_d2 = f32::INFINITY;
            self.for_each_near(c, range + max_rad, |j| {
                if self.team[j] == my_team || (need != 0 && (self.flags[j] & need) == 0) {
                    return;
                }
                let d = self.pos[j] - c;
                let d2 = d.x * d.x + d.y * d.y;
                let lim = range + self.rad[j];
                if d2 > lim * lim {
                    return;
                }
                if d2 < best_d2 || (d2 == best_d2 && self.ids[j] < best_id) {
                    best_d2 = d2;
                    best_id = self.ids[j];
                }
            });
            out.push(best_id);
        }
        PackedInt32Array::from(out.as_slice())
    }
}
