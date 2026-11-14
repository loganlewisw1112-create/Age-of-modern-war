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

    /// G7.1 PERFSIM71-5: largest item radius (the nearest_enemy_batch query margin).
    pub(crate) fn max_rad(&self) -> f32 {
        self.rad.iter().cloned().fold(0.0f32, f32::max)
    }

    /// One nearest_enemy_batch entry (moved here unchanged so RtsCombat.find shares it): the id of the
    /// nearest item of another team within range (+ its radius), flags sharing a bit with need when
    /// need != 0; ties: lower id; -1 if none or si out of range.
    pub(crate) fn nearest_one(&self, si: usize, range: f32, need: i32, max_rad: f32) -> i32 {
        if si >= self.ids.len() {
            return -1;
        }
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
        best_id
    }

    /// scan_vis_sorted into a reusable buffer (moved here unchanged): items of another team within r
    /// on a visible cell (v[cell] == 1), as (f32 distance_squared, id) sorted by distance then id.
    pub(crate) fn scan_sorted_buf(&self, center: Vector2, r: f32, my_team: i32, v: &[u8], mw: i32, out: &mut Vec<(f32, i32)>) {
        out.clear();
        let r2 = r * r;
        let nv = v.len() as i64;
        if nv == 0 {
            return;
        }
        self.for_each_near(center, r, |i| {
            if self.team[i] == my_team {
                return;
            }
            let p = self.pos[i];
            let d = p - center;
            if d.x * d.x + d.y * d.y > r2 {
                return;
            }
            let vi = (p.y.floor() as i64) * (mw as i64) + (p.x.floor() as i64);
            if vi < 0 || vi >= nv || v[vi as usize] != 1 {
                return;
            }
            let ex = center.x - p.x;
            let ey = center.y - p.y;
            out.push((ex * ex + ey * ey, self.ids[i]));
        });
        out.sort_unstable_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal).then(a.1.cmp(&b.1)));
    }

    fn capsule_items(&self, from: Vector2, dir: Vector2, u0: f32, ln: f32, off: f32) -> Vec<(f32, i32)> {
        let mut out: Vec<(f32, i32)> = Vec::new();
        if self.gw <= 0 || self.items.is_empty() || ln < u0 {
            return out;
        }
        let a = from + dir * u0;
        let b = from + dir * ln;
        let (x0, y0) = self.bucket_xy(Vector2::new(a.x.min(b.x) - off, a.y.min(b.y) - off));
        let (x1, y1) = self.bucket_xy(Vector2::new(a.x.max(b.x) + off, a.y.max(b.y) + off));
        let half = self.cell * 0.5;
        let hd = half * std::f32::consts::SQRT_2 + off + 0.01;
        for by in y0..=y1 {
            for bx in x0..=x1 {
                // bucket rejection: the bucket centre's distance to the segment [a, b] exceeds half-diagonal + off
                let c = Vector2::new((bx as f32) * self.cell + half, (by as f32) * self.cell + half);
                let rc = c - from;
                let t = rc.dot(dir).clamp(u0, ln);
                let q = from + dir * t;
                let dq = c - q;
                let edge = bx == 0 || by == 0 || bx == self.gw - 1 || by == self.gh - 1;   // clamped buckets may hold off-map items
                if !edge && dq.x * dq.x + dq.y * dq.y > hd * hd {
                    continue;
                }
                for &it in self.bucket_range(bx, by) {
                    let i = it as usize;
                    let rp = self.pos[i] - from;
                    let cu = rp.x * dir.x + rp.y * dir.y;
                    if cu < u0 || cu > ln {
                        continue;
                    }
                    let cr = rp.x * dir.y - rp.y * dir.x;
                    if cr.abs() > off {
                        continue;
                    }
                    out.push((cu, self.ids[i]));
                }
            }
        }
        out
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

    /// G7 INTEG7 (perf): the ids query_radius(center, r) would return, keeping only items of another team whose
    /// cell (floor(y) * mw + floor(x)) is visible (vis[cell] == 1). Combat's exact enemy scan then walks only these
    /// (it repeats the same team / distance / visibility tests, so its legal set and argmin are unchanged).
    #[func]
    fn scan_vis(&self, center: Vector2, r: f32, my_team: i32, vis: PackedByteArray, mw: i32) -> PackedInt32Array {
        let r2 = r * r;
        let v = vis.as_slice();
        let nv = v.len() as i64;
        let mut out: Vec<i32> = Vec::new();
        if nv == 0 {
            return PackedInt32Array::from(out.as_slice());
        }
        self.for_each_near(center, r, |i| {
            if self.team[i] == my_team {
                return;
            }
            let p = self.pos[i];
            let d = p - center;
            if d.x * d.x + d.y * d.y > r2 {
                return;
            }
            let vi = (p.y.floor() as i64) * (mw as i64) + (p.x.floor() as i64);
            if vi < 0 || vi >= nv || v[vi as usize] != 1 {
                return;
            }
            out.push(self.ids[i]);
        });
        PackedInt32Array::from(out.as_slice())
    }

    /// G7 PERF7L: the ids scan_vis(center, r, my_team, vis, mw) returns, sorted ascending by (d2, id) where
    /// d2 = (cx - x) * (cx - x) + (cy - y) * (cy - y) in f32, the exact value GDScript's
    /// center.distance_squared_to(pos) gives. Combat's exact scan walks them in that order and stops at the first
    /// legal one, which is the (distance, id) argmin of the legal set.
    #[func]
    fn scan_vis_sorted(&self, center: Vector2, r: f32, my_team: i32, vis: PackedByteArray, mw: i32) -> PackedInt32Array {
        let mut out: Vec<(f32, i32)> = Vec::new();
        self.scan_sorted_buf(center, r, my_team, vis.as_slice(), mw, &mut out);
        let ids: Vec<i32> = out.iter().map(|q| q.1).collect();
        PackedInt32Array::from(ids.as_slice())
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

    /// G7 PERF8B (perf): ids (ascending) of the items whose centre p satisfies u0 <= (p - from).dot(dir) <= ln and
    /// |(p - from).cross(dir)| <= off (a capsule along a unit direction; dir must be normalised). Callers pass a small
    /// slack and repeat their exact tests, so the set they act on is unchanged; it replaces a chain of query_radius
    /// discs along a line of fire (Stray8 scan / fire-discipline check).
    #[func]
    fn query_capsule(&self, from: Vector2, dir: Vector2, u0: f32, ln: f32, off: f32) -> PackedInt32Array {
        let mut v = self.capsule_items(from, dir, u0, ln, off);
        v.sort_unstable_by_key(|x| x.1);
        let out: Vec<i32> = v.iter().map(|x| x.1).collect();
        PackedInt32Array::from(out.as_slice())
    }

    /// query_capsule ordered by the along-line distance (p - from).dot(dir) ascending, then id.
    #[func]
    fn query_capsule_along(&self, from: Vector2, dir: Vector2, u0: f32, ln: f32, off: f32) -> PackedInt32Array {
        let mut v = self.capsule_items(from, dir, u0, ln, off);
        v.sort_unstable_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal).then(a.1.cmp(&b.1)));
        let out: Vec<i32> = v.iter().map(|x| x.1).collect();
        PackedInt32Array::from(out.as_slice())
    }

    /// G7.1 PERFSIM71 (exact): stray8._sidestep's collect prefilter in one call. The ids query_radius(center, r)
    /// returns (ascending), each put through the same packed-npos box test GDScript runs (PERF8 in _sidestep):
    /// rp = npos[nix[id]] - from (f32), la = |rp.dot(nrm)|, lo = rp.dot(dir) (f32 dots, as Vector2.dot), then in f64
    /// dla = max(la - omax, 0), dlo = max(max(fmin - lo, lo - fmax), 0), far when dla^2 + dlo^2 > rb2. Near ids (and
    /// ids with no packed slot, which GDScript also passes through) come back as id; far ids as -id - 1 when keep_far,
    /// else dropped (GDScript `continue`s them when no retarget is possible). Input order is kept.
    #[func]
    fn ss_split(
        &self,
        center: Vector2,
        r: f32,
        from: Vector2,
        dir: Vector2,
        nrm: Vector2,
        omax: f64,
        fmin: f64,
        fmax: f64,
        rb2: f64,
        keep_far: bool,
        nix: PackedInt32Array,
        npos: PackedVector2Array,
    ) -> PackedInt32Array {
        let r2 = r * r;
        let mut ids: Vec<i32> = Vec::new();
        self.for_each_near(center, r, |i| {
            let d = self.pos[i] - center;
            if d.x * d.x + d.y * d.y <= r2 {
                ids.push(self.ids[i]);
            }
        });
        ids.sort_unstable();
        let nx = nix.as_slice();
        let np = npos.as_slice();
        let mut out: Vec<i32> = Vec::with_capacity(ids.len());
        for &cv in ids.iter() {
            let ci = if cv >= 0 && (cv as usize) < nx.len() { nx[cv as usize] } else { -1 };
            if ci >= 0 && (ci as usize) < np.len() {
                let rp = np[ci as usize] - from;
                let la = ((rp.x * nrm.x + rp.y * nrm.y) as f64).abs();
                let lo = (rp.x * dir.x + rp.y * dir.y) as f64;
                let dla = (la - omax).max(0.0);
                let dlo = (fmin - lo).max(lo - fmax).max(0.0);
                if dla * dla + dlo * dlo > rb2 {
                    if keep_far {
                        out.push(-cv - 1);
                    }
                    continue;
                }
            }
            out.push(cv);
        }
        PackedInt32Array::from(out.as_slice())
    }

    /// G7.1 PERFSIM71 (exact): stray8._muzzle_blocked's candidate prefilter in one call. The ids
    /// query_capsule(from, dir, u0 - 0.01, ln + 0.01, co + 0.01) returns (ascending), keeping those GDScript's loop
    /// would not skip before a Dictionary read: an id with no packed slot passes; a packed one passes when its npos
    /// satisfies u0 <= (npos - from).dot(dir) <= ln and |(npos - from).cross(dir)| <= co (f32 dot / cross, f64
    /// compares, as GDScript) AND its packed team nteam[ci] equals my_team (the loop only counts the shooter's own men,
    /// owner == shooter owner, and same owner means the same packed team: combat.gd builds both from one teams map).
    #[func]
    fn mz_cands(
        &self,
        from: Vector2,
        dir: Vector2,
        u0: f64,
        ln: f64,
        co: f64,
        my_team: i32,
        nix: PackedInt32Array,
        npos: PackedVector2Array,
        nteam: PackedInt32Array,
    ) -> PackedInt32Array {
        let mut v = self.capsule_items(from, dir, (u0 - 0.01) as f32, (ln + 0.01) as f32, (co + 0.01) as f32);
        v.sort_unstable_by_key(|x| x.1);
        let nx = nix.as_slice();
        let np = npos.as_slice();
        let nt = nteam.as_slice();
        let mut out: Vec<i32> = Vec::with_capacity(v.len());
        for &(_, cv) in v.iter() {
            let ci = if cv >= 0 && (cv as usize) < nx.len() { nx[cv as usize] } else { -1 };
            if ci >= 0 && (ci as usize) < np.len() {
                let rp = np[ci as usize] - from;
                let cp = (rp.x * dir.x + rp.y * dir.y) as f64;
                let cr = ((rp.x * dir.y - rp.y * dir.x) as f64).abs();
                if cp < u0 || cp > ln || cr > co {
                    continue;
                }
                if (ci as usize) < nt.len() && nt[ci as usize] != my_team {
                    continue;
                }
            }
            out.push(cv);
        }
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
        let max_rad = self.max_rad();
        for (k, &si) in src.iter().enumerate() {
            let range = if k < rs.len() { rs[k] } else { 0.0 };
            let need = if k < nf.len() { nf[k] } else { 0 };
            out.push(self.nearest_one(si as usize, range, need, max_rad));
        }
        PackedInt32Array::from(out.as_slice())
    }
}
