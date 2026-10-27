extends RefCounted
## G7 (FISSURE7): creep fissures, canyons and growths (G7_REFERENCE master scope 13.9a, owner amendment 2026-10-26).
## Numbers: content/g7/defs_g7_fissures.json (rules.g7_fissures), all PROVISIONAL.
##
## No system slot: Creep.tick calls Fissures7.tick(w) (one marked line in creep.gd), so a match without creep never
## reaches this file and keeps its pre-G7 hash. State w.sys_state.fissures7 is created the first time creep exists.
##
## Model
##   age   one byte per creep cell (cs x cs tiles): +1 per visit while the creep value >= dense_v (big growths near the
##         cell add feed_age), -age_decay while the cell is not creep, 0 on sterile / water / burnt / barrier cells.
##         Rows are visited in stripes (row % age_stripes == step % age_stripes); rows with no creep and no age skip.
##   veins long branching lines that open the ground. A vein starts on a cell aged >= crack_age with no other vein
##         near it, then its tip walks one tile every grow_every ticks, steering toward older creep (5 candidate
##         headings, score = cell age + a hashed wobble - turn cost) and stops on young creep, protected ground or at
##         its length cap. Tips branch (depth <= branch_depth). Every point remembers its birth tick: the old part of a
##         vein widens first, so a vein reads canyon at its root, fissure behind the tip and a crack at the tip.
##   tiles ts: one byte per map tile = stage (1 crack, 2 fissure, 3 canyon, 5 span) | 8 held (capped at crack by the
##         base connectivity check) | 16 scar (purged: no growth, closes later). A point of stage S stamps a disc
##         (canyon core, fissure wall band, crack rim) into the PENDING set; never on buildings / walls / gates /
##         bridges / rail / water / rock / forest / ford, nor on sterile, water or barrier creep cells; stages >= 2 also
##         keep one tile off any building, gate or bridge.
##   commit pending tiles are written to w.map.terrain in one batch every commit_every ticks (spans and closings at
##         the next fissure tick): crack = FORD (ground slow), fissure = FOREST (vehicles blocked, infantry slow),
##         canyon = RIDGE (all ground blocked), span = BRIDGE, closed = DIRT (stage_codes). Before a batch that blocks
##         ground, each player base (its lowest-id building) must still reach connect_r tiles out for vehicles
##         (bounded outward-first DFS, connect_budget cells); otherwise the blocking tiles within connect_r are held
##         at crack. One Movement.on_terrain_changed per batch; units left on blocked tiles step to the nearest
##         free tile.
##   purge / burn / barrier (Creep hooks -> on_cleared): tiles in the area scar (growth stops, pending openings there
##         are dropped), vein points there stop widening, tips there die, big growths there are destroyed. After
##         close_after_s the scarred tiles close back to rough ground (DIRT).
##   span  command fissure_span {issuer, unit_ids (engineers), cell}: the shortest straight 2-wide run across the
##         opening through cell (<= span_max tiles, 8 headings); engineers walk to a bank and build it
##         (span_s + span_s_per_tile x length seconds, engineers stack); then the run becomes BRIDGE tiles that
##         fissures never reopen.
##   big growths: when a point opens to canyon and hash(point) % big.every == 0 (max big.max, big.spacing apart), a
##         Machine-owned 1x1 building (g7_growth_spire / g7_growth_heart) rises there: destructible, a creep source
##         (Creep makes every Machine building one) and it ages the creep cells within big.feed_cells faster.
##   scenery growths are display-only (presentation/view/fissure_layer.gd), derived from snap points and age.
## Determinism: no rng stream; every random choice is a pure hash of (seed_value, ids, tick). Sorted keys, ascending
## vein ids, building ids ascending. Events: FissuresChanged {tiles, blocking, held}, FissurePurged {pos, radius,
## tiles}, FissureSpanned {job, owner, tiles}, GrowthRisen {id, def, pos}.

const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Movement = preload("res://sim/systems/movement.gd")

const VER := 1
const ST_MASK := 7
const ST_CRACK := 1
const ST_FISSURE := 2
const ST_CANYON := 3
const ST_SPAN := 5
const B_HELD := 8
const B_SCAR := 16
const CF_NOGROW := 1 | 2 | 8   # creep flags: sterile, water, barrier
const CF_AGE0 := 1 | 2 | 4 | 8  # + burnt / cratered: age resets
const TPS := 20


static func R() -> Dictionary:
	return Content.rules().get("g7_fissures", {})


static func st(w: SimWorld):
	return w.sys_state.get("fissures7")


static func enabled(w: SimWorld) -> bool:
	return w.sys_state.has("fissures7")


static func _h(a: int, b: int, c: int = 0) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	x = ((x ^ (x >> 13)) * 1274126177) & 0xffffffff
	x = x ^ (x >> 16)
	return x & 0x7fffffff


static func _hf(a: int, b: int, c: int = 0) -> float:
	return float(_h(a, b, c) % 100003) / 100003.0


static func _enable(w: SimWorld, cst: Dictionary) -> Dictionary:
	var s = w.sys_state.get("fissures7")
	if s != null:
		return s
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var ts := PackedByteArray()
	ts.resize(mw * mh)
	ts.fill(0)
	var n := int(cst.cw) * int(cst.ch)
	var age := PackedByteArray()
	age.resize(n)
	age.fill(0)
	var vd := PackedByteArray()
	vd.resize(n)
	vd.fill(0)
	s = {"ver": VER, "ts": ts, "age": age, "vd": vd, "veins": [], "next": 1, "npts": 0, "pend": {}, "force": false,
		"last_commit": w.tick, "scars": [], "jobs": [], "next_job": 1, "big": [], "dv": 0, "pv": 0, "commits": 0,
		"rejects": 0, "opened": [0, 0, 0, 0]}
	w.sys_state["fissures7"] = s
	return s


# ================================================================ queries
## Stage of a tile: 0 none, 1 crack, 2 fissure, 3 canyon, 5 span (committed terrain only).
static func stage_at(w: SimWorld, cell: Vector2i) -> int:
	var s = st(w)
	if s == null or not w.in_bounds(cell):
		return 0
	return int((s.ts as PackedByteArray)[cell.y * int(w.map.w) + cell.x]) & ST_MASK


static func is_scar(w: SimWorld, cell: Vector2i) -> bool:
	var s = st(w)
	if s == null or not w.in_bounds(cell):
		return false
	return int((s.ts as PackedByteArray)[cell.y * int(w.map.w) + cell.x]) & B_SCAR != 0


## Committed tile counts per stage [none, crack, fissure, canyon] plus spans (tests / HUD / perf probes).
static func counts(w: SimWorld) -> Dictionary:
	var s = st(w)
	var out := {"crack": 0, "fissure": 0, "canyon": 0, "span": 0, "scar": 0, "veins": 0, "points": 0, "big": 0}
	if s == null:
		return out
	var ts: PackedByteArray = s.ts
	for i in ts.size():
		var b := ts[i]
		if b == 0:
			continue
		match b & ST_MASK:
			ST_CRACK: out.crack += 1
			ST_FISSURE: out.fissure += 1
			ST_CANYON: out.canyon += 1
			ST_SPAN: out.span += 1
		if b & B_SCAR != 0:
			out.scar += 1
	out.veins = (s.veins as Array).size()
	out.points = int(s.npts)
	out.big = (s.big as Array).size()
	return out


static func creep_on() -> int:
	return int(Content.rules().get("g7_machine", {}).get("creep", {}).get("on", 64))


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var cst = w.sys_state.get("creep")
	if cst == null:
		return
	var r := R()
	if r.is_empty():
		return
	var every := maxi(int(r.get("every", 10)), 1)
	if w.tick % every != 3 % every:
		return
	var s = w.sys_state.get("fissures7")
	if s == null:
		if int(cst.get("on_n", 0)) <= 0:
			return
		s = _enable(w, cst)
	var step := w.tick / every
	var bud := {"up": int(r.get("upgrade_budget", 40)), "seed": int(r.get("seed_budget", 3))}
	_age_scan(w, s, cst, r, step, bud)
	_veins_step(w, s, cst, r, step, every, bud)
	if not (s.jobs as Array).is_empty():
		_jobs_step(w, s, r, every)
	if not (s.big as Array).is_empty():
		_big_clean(w, s)
	if not (s.scars as Array).is_empty():
		_closing(w, s, r)
	var pend: Dictionary = s.pend
	if not pend.is_empty() and (bool(s.force) or w.tick - int(s.last_commit) >= int(r.get("commit_every", 100))):
		_commit(w, s, r)


static func _age_scan(w: SimWorld, s: Dictionary, cst: Dictionary, r: Dictionary, step: int, bud: Dictionary) -> void:
	var S := maxi(int(r.get("age_stripes", 8)), 1)
	var ph := step % S
	var cw := int(cst.cw)
	var ch := int(cst.ch)
	var cs := int(cst.cs)
	var v: PackedByteArray = cst.v
	var fl: PackedByteArray = cst.fl
	var dense := int(r.get("dense_v", 190))
	var on := creep_on()
	var dec := int(r.get("age_decay", 4))
	var crack_age := int(r.get("crack_age", 40))
	var feed := {}
	var br: Dictionary = r.get("big", {})
	if not (s.big as Array).is_empty():
		var fc := int(br.get("feed_cells", 2))
		var fa := int(br.get("feed_age", 3))
		for b in s.big:
			var bx := int(b.x) / cs
			var by := int(b.y) / cs
			for oy in range(-fc, fc + 1):
				for ox in range(-fc, fc + 1):
					var x := bx + ox
					var y := by + oy
					if x >= 0 and y >= 0 and x < cw and y < ch:
						feed[y * cw + x] = fa
	var age: PackedByteArray = s.age
	var vd: PackedByteArray = s.vd
	s.age = PackedByteArray()
	var cand := []
	for row in range(ph, ch, S):
		var base := row * cw
		if v.slice(base, base + cw).count(0) == cw and age.slice(base, base + cw).count(0) == cw:
			continue
		for x in cw:
			var k := base + x
			var a := age[k]
			if fl[k] & CF_AGE0 != 0:
				if a != 0:
					age[k] = 0
				continue
			var val := v[k]
			if val >= dense:
				var na := mini(a + 1 + int(feed.get(k, 0)), 255)
				if na != a:
					age[k] = na
				if na >= crack_age and vd[k] == 0:
					cand.append(k)
			elif val < on and a > 0:
				age[k] = maxi(a - dec, 0)
	s.age = age
	var tries := int(bud.seed) * 8
	for k in cand:
		tries -= 1
		if int(bud.seed) <= 0 or tries < 0:
			break
		if _try_seed(w, s, cst, r, k):
			bud.seed = int(bud.seed) - 1


## Starts a vein in creep cell k when no vein is near and the hashed chance hits.
static func _try_seed(w: SimWorld, s: Dictionary, cst: Dictionary, r: Dictionary, k: int) -> bool:
	if (s.veins as Array).size() >= int(r.get("max_veins", 180)) or int(s.npts) >= int(r.get("max_points", 9000)):
		return false
	var sd := int(w.seed_value)
	if _hf(sd, k, w.tick) >= float(r.get("seed_chance", 0.05)):
		return false
	var cw := int(cst.cw)
	var ch := int(cst.ch)
	var cs := int(cst.cs)
	var sp := int(r.get("seed_spacing_cells", 3))
	var vd: PackedByteArray = s.vd
	var cx := k % cw
	var cy := k / cw
	for oy in range(-sp, sp + 1):
		for ox in range(-sp, sp + 1):
			var x := cx + ox
			var y := cy + oy
			if x >= 0 and y >= 0 and x < cw and y < ch and vd[y * cw + x] != 0:
				return false
	var h := _h(sd, k, w.tick + 7)
	var tile := Vector2i(cx * cs + h % cs, cy * cs + (h / cs) % cs)
	if not w.in_bounds(tile) or _cap(w, s, cst, tile.y * int(w.map.w) + tile.x, ST_CRACK) < ST_CRACK:
		return false
	var vn := {"id": int(s.next), "d": 0, "dir": float(h % 6283) / 1000.0, "alive": true,
		"lmax": int(r.get("max_len", 70)) + h % maxi(int(r.get("max_len_jitter", 40)), 1),
		"tx": float(tile.x) + 0.5, "ty": float(tile.y) + 0.5,
		"p": PackedInt32Array(), "b": PackedInt32Array(), "s": PackedByteArray(), "x": PackedByteArray()}
	s.next = int(s.next) + 1
	(s.veins as Array).append(vn)
	_add_point(w, s, cst, vn, tile)
	return true


static func _add_point(w: SimWorld, s: Dictionary, cst: Dictionary, vn: Dictionary, tile: Vector2i) -> void:
	var mw := int(w.map.w)
	var i := tile.y * mw + tile.x
	var p: PackedInt32Array = vn.p
	var b: PackedInt32Array = vn.b
	var ss: PackedByteArray = vn.s
	var xx: PackedByteArray = vn.x
	vn.p = PackedInt32Array()
	vn.b = PackedInt32Array()
	vn.s = PackedByteArray()
	vn.x = PackedByteArray()
	p.append(i)
	b.append(w.tick)
	ss.append(0)
	xx.append(0)
	vn.p = p
	vn.b = b
	vn.s = ss
	vn.x = xx
	s.npts = int(s.npts) + 1
	s.pv = int(s.pv) + 1
	var cs := int(cst.cs)
	var k := (tile.y / cs) * int(cst.cw) + tile.x / cs
	var vd: PackedByteArray = s.vd
	s.vd = PackedByteArray()
	vd[k] = mini(vd[k] + 1, 255)
	s.vd = vd
	_stamp(w, s, cst, vn, p.size() - 1, ST_CRACK)


## Highest stage tile i may open to (0 = protected).
static func _cap(w: SimWorld, s: Dictionary, cst: Dictionary, i: int, want: int = ST_CANYON) -> int:
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var tb := int((s.ts as PackedByteArray)[i])
	if tb & ST_MASK == ST_SPAN or tb & B_SCAR != 0:
		return 0
	var x := i % mw
	var y := i / mw
	var cs := int(cst.cs)
	if int((cst.fl as PackedByteArray)[(y / cs) * int(cst.cw) + x / cs]) & CF_NOGROW != 0:
		return 0
	var t: PackedByteArray = w.map.terrain
	if tb & ST_MASK == 0 and not _openable(t[i]):
		return 0
	var nav: Dictionary = w.nav if w.nav is Dictionary else {}
	var blocked = nav.get("blocked")
	var gates: Dictionary = nav.get("gates", {})
	if blocked != null and (blocked as PackedByteArray).size() == mw * mh and blocked[i] != 0:
		return 0
	if gates.has(i):
		return 0
	var cap := ST_CANYON
	if tb & B_HELD != 0 or want <= ST_CRACK:
		cap = ST_CRACK
	else:
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var nx := x + ox
				var ny := y + oy
				if nx < 0 or ny < 0 or nx >= mw or ny >= mh:
					continue
				var j := ny * mw + nx
				var c := t[j]
				if c == Terrain.BRIDGE or c == Terrain.BUILDING or c == Terrain.RAIL or gates.has(j) \
						or (blocked != null and (blocked as PackedByteArray).size() == mw * mh and blocked[j] != 0):
					return ST_CRACK
	return cap


static func _openable(code: int) -> bool:
	return code == Terrain.GRASS or code == Terrain.DIRT or code == Terrain.ROAD or code == Terrain.BEACH \
		or code == Terrain.HILL


## Radius of a point's opening for a stage (depth 0 = trunk; wobble from the point hash).
static func _radius(r: Dictionary, stage: int, depth: int, h: int) -> float:
	var rr: Dictionary = r.get("radius", {})
	var key := "canyon" if stage >= ST_CANYON else "fissure"
	var arr: Array = rr.get(key, [1.0])
	var base := float(arr[mini(depth, arr.size() - 1)])
	if stage >= ST_CANYON:
		base += float(rr.get("wobble", 0.5)) * (float(h % 1000) / 1000.0 - 0.3)
	return maxf(base, 0.5)


## Stamps point pi of vein vn at stage into the pending set (canyon core / fissure band / crack rim).
static func _stamp(w: SimWorld, s: Dictionary, cst: Dictionary, vn: Dictionary, pi: int, stage: int) -> void:
	var r := R()
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var i0: int = (vn.p as PackedInt32Array)[pi]
	var cx := i0 % mw
	var cy := i0 / mw
	var h := _h(int(w.seed_value), i0, int(vn.id))
	var rc := 0.0
	var rf := 0.0
	if stage >= ST_CANYON:
		rc = _radius(r, ST_CANYON, int(vn.d), h)
		rf = rc + 1.0
	elif stage == ST_FISSURE:
		rf = _radius(r, ST_FISSURE, int(vn.d), h)
	var rk := rf + 1.0 if stage >= ST_FISSURE else 0.0
	var ext := ceili(rk)
	var ts: PackedByteArray = s.ts
	var pend: Dictionary = s.pend
	for oy in range(-ext, ext + 1):
		for ox in range(-ext, ext + 1):
			var x := cx + ox
			var y := cy + oy
			if x < 0 or y < 0 or x >= mw or y >= mh:
				continue
			var d := sqrt(float(ox * ox + oy * oy))
			var want := 0
			if stage >= ST_CANYON and d <= rc:
				want = ST_CANYON
			elif stage >= ST_FISSURE and d <= rf:
				want = ST_FISSURE
			elif d <= rk + 0.01:
				want = ST_CRACK
			if want == 0:
				continue
			var i := y * mw + x
			var cur := int(pend.get(i, ts[i]))
			var cs := cur & ST_MASK
			if cs == ST_SPAN or cur & B_SCAR != 0 or cs >= want:
				continue
			var cap := _cap(w, s, cst, i, want)
			var ns := mini(want, cap)
			if ns <= cs:
				continue
			pend[i] = (cur & ~ST_MASK) | ns


static func _veins_step(w: SimWorld, s: Dictionary, cst: Dictionary, r: Dictionary, step: int, every: int,
		bud: Dictionary) -> void:
	var veins: Array = s.veins
	if veins.is_empty():
		return
	var G := maxi(int(r.get("grow_every", 40)) / every, 1)
	var n := veins.size()
	for vi in n:
		var vn: Dictionary = veins[vi]
		if (step + int(vn.id)) % G != 0:
			continue
		if bool(vn.alive):
			_grow(w, s, cst, r, vn)
		if int(bud.up) > 0 and int(vn.get("f", 0)) < (vn.p as PackedInt32Array).size():
			_upgrade(w, s, cst, r, vn, bud)


static func _grow(w: SimWorld, s: Dictionary, cst: Dictionary, r: Dictionary, vn: Dictionary) -> void:
	if int(s.npts) >= int(r.get("max_points", 9000)):
		vn.alive = false
		return
	var mw := int(w.map.w)
	var cs := int(cst.cs)
	var cw := int(cst.cw)
	var age: PackedByteArray = s.age
	var tx := float(vn.tx)
	var ty := float(vn.ty)
	var dir := float(vn.dir)
	var steer := float(r.get("steer_rad", 0.45))
	var sd := int(w.seed_value)
	var best := -1.0e9
	var best_a := dir
	for c in 5:
		var a := dir + steer * float(c - 2) * 0.5
		var nx := tx + cos(a)
		var ny := ty + sin(a)
		var tile := Vector2i(floori(nx), floori(ny))
		if not w.in_bounds(tile):
			continue
		var i := tile.y * mw + tile.x
		if _cap(w, s, cst, i, ST_CRACK) < ST_CRACK and int((s.ts as PackedByteArray)[i]) & ST_MASK == 0:
			continue
		var sc := float(age[(tile.y / cs) * cw + tile.x / cs]) + _hf(sd, int(vn.id) * 31 + c, w.tick) * 25.0 \
			- absf(float(c - 2)) * 4.0
		if sc > best:
			best = sc
			best_a = a
	if best < -1.0e8:
		vn.alive = false
		return
	var nx2 := tx + cos(best_a)
	var ny2 := ty + sin(best_a)
	var nt := Vector2i(floori(nx2), floori(ny2))
	var ck := (nt.y / cs) * cw + nt.x / cs
	if float(age[ck]) < float(r.get("crack_age", 40)) * float(r.get("stop_age_mult", 0.6)):
		vn.alive = false
		return
	vn.tx = nx2
	vn.ty = ny2
	vn.dir = best_a
	var p: PackedInt32Array = vn.p
	if p[p.size() - 1] == nt.y * mw + nt.x:
		return
	_add_point(w, s, cst, vn, nt)
	var np := (vn.p as PackedInt32Array).size()
	if np >= int(vn.lmax):
		vn.alive = false
	# branch
	if np >= int(r.get("branch_min_len", 6)) and int(vn.d) < int(r.get("branch_depth", 3)) \
			and (s.veins as Array).size() < int(r.get("max_veins", 180)) \
			and _hf(sd, int(vn.id) * 977 + np, w.tick) < float(r.get("branch_chance", 0.07)):
		var side := 1.0 if _h(sd, int(vn.id), np) % 2 == 0 else -1.0
		var ba := best_a + side * (0.7 + 0.5 * _hf(sd, np, int(vn.id)))
		var bv := {"id": int(s.next), "d": int(vn.d) + 1, "dir": ba, "alive": true,
			"lmax": maxi(int(float(vn.lmax) * 0.55), 6), "tx": nx2, "ty": ny2,
			"p": PackedInt32Array(), "b": PackedInt32Array(), "s": PackedByteArray(), "x": PackedByteArray()}
		s.next = int(s.next) + 1
		(s.veins as Array).append(bv)
		_add_point(w, s, cst, bv, nt)


## Widens the vein's points whose age (and the creep's age) reached the next stage; the tip stays narrow.
static func _upgrade(w: SimWorld, s: Dictionary, cst: Dictionary, r: Dictionary, vn: Dictionary,
		bud: Dictionary) -> void:
	var p: PackedInt32Array = vn.p
	var n := p.size()
	if n == 0:
		return
	var b: PackedInt32Array = vn.b
	var ss: PackedByteArray = vn.s
	var xx: PackedByteArray = vn.x
	var mw := int(w.map.w)
	var cs := int(cst.cs)
	var cw := int(cst.cw)
	var age: PackedByteArray = s.age
	var fa := int(r.get("fissure_after_s", 60)) * TPS
	var ca := int(r.get("canyon_after_s", 180)) * TPS
	var fage := int(r.get("fissure_age", 55))
	var cage := int(r.get("canyon_age", 80))
	var tc := int(r.get("tip_crack", 3))
	var tf := int(r.get("tip_fissure", 8))
	var changed := false
	var can_ok := int(s.get("ncan", 0)) < int(r.get("max_canyon_tiles", 16000))
	var f := int(vn.get("f", 0))
	var lead := true
	for pi in range(f, n):
		var cur := ss[pi]
		if cur >= ST_CANYON or xx[pi] != 0:
			if lead:
				f = pi + 1   # finished prefix: never visited again
			continue
		lead = false
		if int(bud.up) <= 0:
			break
		var at := w.tick - b[pi]
		if at < fa:
			break   # birth ticks rise toward the tip: nothing further along is old enough
		var i := p[pi]
		var ag := int(age[((i / mw) / cs) * cw + (i % mw) / cs])
		var tipd := n - 1 - pi
		var want := ST_CRACK
		if ag >= fage and tipd >= tc:
			want = ST_FISSURE
			if at >= ca and ag >= cage and tipd >= tf and can_ok:
				want = ST_CANYON
		if want <= cur:
			continue
		ss[pi] = want
		changed = true
		bud.up = int(bud.up) - 1
		_stamp(w, s, cst, vn, pi, want)
		if want == ST_CANYON:
			_maybe_big(w, s, r, i, int(vn.id))
	vn.f = f
	if changed:
		vn.s = PackedByteArray()
		vn.s = ss
		s.pv = int(s.pv) + 1


# ================================================================ big growths
static func _maybe_big(w: SimWorld, s: Dictionary, r: Dictionary, i: int, vid: int) -> void:
	var br: Dictionary = r.get("big", {})
	var every := maxi(int(br.get("every", 11)), 1)
	var h := _h(int(w.seed_value), i, vid + 5)
	if h % every != 0:
		return
	var big: Array = s.big
	if big.size() >= int(br.get("max", 28)):
		return
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	# rises on the canyon rim (a fissure tile next to the opening), so ground units can see and shoot it
	var cell := Vector2i(-1, -1)
	var ts: PackedByteArray = s.ts
	var pend: Dictionary = s.pend
	var cx := i % mw
	var cy := i / mw
	var rot := h % 8
	for rad in range(2, 6):
		for q in 8:
			var a := TAU * float((q + rot) % 8) / 8.0
			var x := cx + roundi(cos(a) * float(rad))
			var y := cy + roundi(sin(a) * float(rad))
			if x < 0 or y < 0 or x >= mw or y >= mh:
				continue
			var j := y * mw + x
			var cur := int(pend.get(j, ts[j]))
			if cur & ST_MASK == ST_FISSURE and cur & B_SCAR == 0:
				cell = Vector2i(x, y)
				break
		if cell.x >= 0:
			break
	if cell.x < 0:
		return
	var sp := float(br.get("spacing", 12))
	for g in big:
		if Vector2(int(g.x), int(g.y)).distance_to(Vector2(cell)) < sp:
			return
	var mfs: Array = SimWorld.Creep.machine_fids(w)
	if mfs.is_empty():
		return
	var kinds: Array = br.get("kinds", ["g7_growth_spire"])
	var def_id := String(kinds[(h / every) % kinds.size()])
	if Content.building(def_id).is_empty():
		return
	var id := w.spawn_building(def_id, int(mfs[0]), cell, true)
	if id < 0 or not w.entities.has(id):
		return
	big.append({"id": id, "x": cell.x, "y": cell.y, "def": def_id, "t": w.tick})
	w.emit("GrowthRisen", {"id": id, "def": def_id, "pos": Vector2(cell) + Vector2(0.5, 0.5)})


static func _big_clean(w: SimWorld, s: Dictionary) -> void:
	var big: Array = s.big
	var keep := []
	for g in big:
		if w.entities.has(int(g.id)):
			keep.append(g)
	if keep.size() != big.size():
		s.big = keep


# ================================================================ commit (batched terrain change)
static func _code(r: Dictionary, stage: int) -> int:
	var c: Dictionary = r.get("stage_codes", {})
	match stage:
		ST_CRACK: return int(c.get("crack", Terrain.FORD))
		ST_FISSURE: return int(c.get("fissure", Terrain.FOREST))
		ST_CANYON: return int(c.get("canyon", Terrain.RIDGE))
		ST_SPAN: return int(c.get("span", Terrain.BRIDGE))
	return int(c.get("closed", Terrain.DIRT))


## Player bases: the lowest-id building of every side that is not Machine. [{cell, team, fid}]
static func _anchors(w: SimWorld) -> Array:
	var mfs: Array = SimWorld.Creep.machine_fids(w)
	var seen := {}
	var out := []
	for e in SimIndex.of(w, "building"):
		var o := int(e.owner)
		if o < 0 or seen.has(o) or mfs.has(o) or not w.entities.has(int(e.id)):
			continue
		seen[o] = true
		var team := int(w.factions.get(o, {}).get("team", o)) if w.factions.has(o) else o
		out.append({"cell": Vector2i(e.cell) + Vector2i(int(e.size) / 2, int(e.size) / 2), "team": team, "fid": o})
	return out


static func _blocks(nb: int) -> bool:
	var stg := nb & ST_MASK
	return (stg == ST_FISSURE or stg == ST_CANYON)


## Bounded outward-first DFS: can a vehicle leave the base (reach connect_r tiles from it)? pend blocks too.
static func _escapes(w: SimWorld, a: Dictionary, pend: Dictionary, use_pend: bool, r: Dictionary) -> bool:
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var R2 := pow(float(r.get("connect_r", 110)), 2.0)
	var budget := int(r.get("connect_budget", 40000))
	var team := int(a.team)
	var c0: Vector2i = a.cell
	var start := Movement.nearest_free_cell(w, c0, "vehicle", team)
	if not w.in_bounds(start) or not Movement.is_passable(w, start, "vehicle", team):
		return true
	var seen := PackedByteArray()
	seen.resize(mw * mh)
	seen.fill(0)
	var stack := PackedInt32Array([start.y * mw + start.x])
	seen[start.y * mw + start.x] = 1
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var n := 0
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		n += 1
		if n > budget:
			return false
		var x := i % mw
		var y := i / mw
		var dx := x - c0.x
		var dy := y - c0.y
		if float(dx * dx + dy * dy) >= R2 or x == 0 or y == 0 or x == mw - 1 or y == mh - 1:
			return true   # out to connect_r (or the map edge on small maps): the base reaches the map
		# push the least outward first so the most outward pops next
		var order := [0, 1, 2, 3]
		order.sort_custom(func(p, q): return dirs[p].x * dx + dirs[p].y * dy < dirs[q].x * dx + dirs[q].y * dy)
		for o in order:
			var nx: int = x + dirs[o].x
			var ny: int = y + dirs[o].y
			if nx < 0 or ny < 0 or nx >= mw or ny >= mh:
				continue
			var j := ny * mw + nx
			if seen[j] != 0:
				continue
			seen[j] = 1
			if use_pend and pend.has(j) and _blocks(int(pend[j])):
				continue
			if not Movement.is_passable(w, Vector2i(nx, ny), "vehicle", team):
				continue
			stack.append(j)
	return false


static func _commit(w: SimWorld, s: Dictionary, r: Dictionary) -> void:
	var pend: Dictionary = s.pend
	var keys := pend.keys()
	keys.sort()
	var mw := int(w.map.w)
	var ts: PackedByteArray = s.ts
	var blocking := []
	for i in keys:
		var ps: int = int(pend[i]) & ST_MASK
		var os: int = ts[i] & ST_MASK
		if (ps == ST_FISSURE or ps == ST_CANYON) and os != ST_FISSURE and os != ST_CANYON:
			blocking.append(i)
	var held := 0
	if not blocking.is_empty():
		var cr := float(r.get("connect_r", 110)) + 2.0
		for a in _anchors(w):
			var c0: Vector2i = a.cell
			var near := false
			for i in blocking:
				if Vector2(int(i) % mw, int(i) / mw).distance_squared_to(Vector2(c0)) <= cr * cr:
					near = true
					break
			if not near:
				continue
			if _escapes(w, a, pend, true, r) or not _escapes(w, a, pend, false, r):
				continue
			# this batch would cut the base off: hold the blocking tiles near it at crack
			for i in blocking:
				if Vector2(int(i) % mw, int(i) / mw).distance_squared_to(Vector2(c0)) <= cr * cr:
					pend[i] = (int(pend[i]) & ~ST_MASK) | ST_CRACK | B_HELD
					held += 1
			s.rejects = int(s.rejects) + 1
	var t: PackedByteArray = w.map.terrain
	s.ts = PackedByteArray()
	var nblock := 0
	var newly := {}
	var opened: Array = s.opened
	var codes := PackedByteArray([_code(r, 0), _code(r, 1), _code(r, 2), _code(r, 3), _code(r, 0), _code(r, 5), 0, 0])
	for i in keys:
		var nb: int = pend[i]
		var stg := nb & ST_MASK
		var old := ts[i]
		if nb == old:
			continue
		ts[i] = nb
		var code := codes[stg]
		if t[i] != code:
			t[i] = code
		if stg == ST_FISSURE or stg == ST_CANYON:
			nblock += 1
			newly[i] = true
		if stg < opened.size() and (old & ST_MASK) != stg:
			opened[stg] = int(opened[stg]) + 1
			if stg == ST_CANYON:
				s.ncan = int(s.get("ncan", 0)) + 1
			elif old & ST_MASK == ST_CANYON:
				s.ncan = int(s.get("ncan", 0)) - 1
	w.map.terrain = t
	s.ts = ts
	s.pend = {}
	s.force = false
	s.last_commit = w.tick
	s.dv = int(s.dv) + 1
	s.commits = int(s.commits) + 1
	Movement.on_terrain_changed(w)
	if not newly.is_empty():
		for u in SimIndex.of(w, "unit"):
			if not SimIndex.alive(w, u):
				continue
			var cell := w.cell_of(u.pos)
			if not w.in_bounds(cell) or not newly.has(cell.y * mw + cell.x):
				continue
			var mc := Movement.move_class(u)
			if Movement.is_passable(w, cell, mc):
				continue
			var free := Movement.nearest_free_cell(w, cell, mc)
			u.pos = Vector2(free) + Movement.CENTER
			HotState.touch(w, int(u.id))
	w.emit("FissuresChanged", {"tiles": keys.size(), "blocking": nblock, "held": held})


# ================================================================ purge / burn / barrier, closing
## Creep hook (purge, burn, crater, barrier): stops fissure growth in the area, scars it, kills its growths.
static func on_cleared(w: SimWorld, center: Vector2, radius: float, kind: String = "purge") -> void:
	var s = st(w)
	if s == null:
		return
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var rr := radius + 1.0
	var r2 := rr * rr
	var x0 := maxi(floori(center.x - rr), 0)
	var x1 := mini(ceili(center.x + rr), mw - 1)
	var y0 := maxi(floori(center.y - rr), 0)
	var y1 := mini(ceili(center.y + rr), mh - 1)
	var ts: PackedByteArray = s.ts
	s.ts = PackedByteArray()
	var pend: Dictionary = s.pend
	var n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(center) > r2:
				continue
			var i := y * mw + x
			if pend.has(i):
				pend.erase(i)
			var b := ts[i]
			if b & ST_MASK != 0 and b & ST_MASK != ST_SPAN and b & B_SCAR == 0:
				ts[i] = b | B_SCAR
				n += 1
	s.ts = ts
	for vn in s.veins:
		var p: PackedInt32Array = vn.p
		var xx: PackedByteArray = vn.x
		var hit := false
		for pi in p.size():
			var i := p[pi]
			if xx[pi] == 0 and Vector2(i % mw + 0.5, i / mw + 0.5).distance_squared_to(center) <= r2:
				xx[pi] = 1
				hit = true
		if hit:
			vn.x = PackedByteArray()
			vn.x = xx
			if Vector2(float(vn.tx), float(vn.ty)).distance_squared_to(center) <= r2:
				vn.alive = false
	var big: Array = s.big
	var kill := []
	for g in big:
		if Vector2(int(g.x) + 0.5, int(g.y) + 0.5).distance_squared_to(center) <= r2:
			kill.append(int(g.id))
	for id in kill:
		if w.entities.has(id):
			w.destroy(id, "purged", SimWorld.NEUTRAL)
	_big_clean(w, s)
	(s.scars as Array).append({"t": w.tick, "x": center.x, "y": center.y, "r": rr, "kind": kind})
	s.dv = int(s.dv) + 1
	s.pv = int(s.pv) + 1
	w.emit("FissurePurged", {"pos": center, "radius": radius, "tiles": n, "growths": kill.size(), "kind": kind})


## Scars older than close_after_s close back to rough ground (pending DIRT; committed at the next fissure tick).
static func _closing(w: SimWorld, s: Dictionary, r: Dictionary) -> void:
	var after := int(r.get("close_after_s", 180)) * TPS
	var scars: Array = s.scars
	var keep := []
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var ts: PackedByteArray = s.ts
	var pend: Dictionary = s.pend
	var closed := false
	for sc in scars:
		if w.tick - int(sc.t) < after:
			keep.append(sc)
			continue
		var c := Vector2(float(sc.x), float(sc.y))
		var rr := float(sc.r)
		for y in range(maxi(floori(c.y - rr), 0), mini(ceili(c.y + rr), mh - 1) + 1):
			for x in range(maxi(floori(c.x - rr), 0), mini(ceili(c.x + rr), mw - 1) + 1):
				var i := y * mw + x
				var b := ts[i]
				if b & B_SCAR != 0 and Vector2(x + 0.5, y + 0.5).distance_squared_to(c) <= rr * rr:
					pend[i] = 0
					closed = true
		# drop the scarred vein points there
		for vn in s.veins:
			var p: PackedInt32Array = vn.p
			var xx: PackedByteArray = vn.x
			var drop := false
			for pi in p.size():
				if xx[pi] != 0 and Vector2(p[pi] % mw + 0.5, p[pi] / mw + 0.5).distance_squared_to(c) <= rr * rr:
					drop = true
					break
			if drop:
				_drop_points(w, s, vn, c, rr)
	if closed:
		s.force = true
	if keep.size() != scars.size():
		s.scars = keep
		var vk := []
		for vn in s.veins:
			if not (vn.p as PackedInt32Array).is_empty():
				vk.append(vn)
		s.veins = vk


static func _drop_points(w: SimWorld, s: Dictionary, vn: Dictionary, c: Vector2, rr: float) -> void:
	var mw := int(w.map.w)
	var cst = w.sys_state.get("creep")
	var p: PackedInt32Array = vn.p
	var b: PackedInt32Array = vn.b
	var ss: PackedByteArray = vn.s
	var xx: PackedByteArray = vn.x
	var np := PackedInt32Array()
	var nb := PackedInt32Array()
	var ns := PackedByteArray()
	var nx := PackedByteArray()
	var vd: PackedByteArray = s.vd
	s.vd = PackedByteArray()
	for pi in p.size():
		if xx[pi] != 0 and Vector2(p[pi] % mw + 0.5, p[pi] / mw + 0.5).distance_squared_to(c) <= rr * rr:
			s.npts = int(s.npts) - 1
			if cst != null:
				var cs := int(cst.cs)
				var k := ((p[pi] / mw) / cs) * int(cst.cw) + (p[pi] % mw) / cs
				vd[k] = maxi(vd[k] - 1, 0)
			continue
		np.append(p[pi])
		nb.append(b[pi])
		ns.append(ss[pi])
		nx.append(xx[pi])
	s.vd = vd
	vn.p = np
	vn.b = nb
	vn.s = ns
	vn.x = nx
	vn.f = 0
	vn.alive = false
	s.pv = int(s.pv) + 1


# ================================================================ engineer span
static func is_engineer(e: Dictionary) -> bool:
	if e.kind != "unit":
		return false
	var d := Content.unit(e.def)
	return bool(d.get("can_build", false)) or bool(d.get("can_repair", false))


static func _cell_arg(v) -> Vector2i:
	if typeof(v) == TYPE_VECTOR2I:
		return v
	if typeof(v) == TYPE_VECTOR2:
		return Vector2i(floori(v.x), floori(v.y))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


static func _is_open(s: Dictionary, i: int) -> bool:
	var stg := int((s.ts as PackedByteArray)[i]) & ST_MASK
	return stg == ST_FISSURE or stg == ST_CANYON


## Shortest straight 2-wide run across the opening through cell: {tiles, a, b} or {} (too wide / not an opening).
static func span_plan(w: SimWorld, cell: Vector2i) -> Dictionary:
	var s = st(w)
	if s == null or not w.in_bounds(cell):
		return {}
	var mw := int(w.map.w)
	if not _is_open(s, cell.y * mw + cell.x):
		return {}
	var smax := int(R().get("span_max", 16))
	var best := {}
	var best_n := 1 << 30
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var run := [cell]
		var ends := []
		var ok := true
		for sgn in [1, -1]:
			var c: Vector2i = cell
			while true:
				c += d * sgn
				if not w.in_bounds(c):
					ok = false
					break
				if _is_open(s, c.y * mw + c.x):
					run.append(c)
					if run.size() > smax:
						ok = false
						break
					continue
				if not Movement.is_passable(w, c, "foot"):
					ok = false
				ends.append(c)
				break
			if not ok:
				break
		if not ok or ends.size() != 2 or run.size() >= best_n:
			continue
		best_n = run.size()
		var side := Vector2i(0, 1) if d.y == 0 else Vector2i(1, 0)
		var tiles := {}
		for c in run:
			tiles[c.y * mw + c.x] = true
			var c2: Vector2i = c + side
			if w.in_bounds(c2) and _is_open(s, c2.y * mw + c2.x):
				tiles[c2.y * mw + c2.x] = true
		var tl := tiles.keys()
		tl.sort()
		best = {"tiles": tl, "a": ends[0], "b": ends[1]}
	return best


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "fissure_span":
		return "%s: unknown fissure command" % String(cmd.get("type", ""))
	var s = st(w)
	if s == null:
		return "No fissures on this map."
	var cell := _cell_arg(cmd.get("cell"))
	if not w.in_bounds(cell):
		return "Outside the map."
	var issuer := int(cmd.get("issuer", -1))
	var any := false
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and int(e.owner) == issuer and is_engineer(e):
			any = true
	if not any:
		return "Needs an engineer."
	if span_plan(w, cell).is_empty():
		return "No fissure to span here (or too wide)."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var s = st(w)
	var cell := _cell_arg(cmd.get("cell"))
	var plan := span_plan(w, cell)
	if s == null or plan.is_empty():
		return
	var r := R()
	var issuer := int(cmd.get("issuer", -1))
	var units := []
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e != null and int(e.owner) == issuer and is_engineer(e):
			units.append(int(id))
	units.sort()
	var a: Vector2i = plan.a
	var b: Vector2i = plan.b
	var L := (plan.tiles as Array).size()
	var need := roundi((float(r.get("span_s", 12)) + float(r.get("span_s_per_tile", 1.5)) * float(L)) * TPS)
	var job := {"id": int(s.next_job), "owner": issuer, "units": units, "tiles": plan.tiles, "ax": a.x, "ay": a.y,
		"bx": b.x, "by": b.y, "need": need, "prog": 0}
	s.next_job = int(s.next_job) + 1
	(s.jobs as Array).append(job)
	for id in units:
		var e: Dictionary = w.entities[id]
		var pa := Vector2(a) + Vector2(0.5, 0.5)
		var pb := Vector2(b) + Vector2(0.5, 0.5)
		var goal := pa if Vector2(e.pos).distance_squared_to(pa) <= Vector2(e.pos).distance_squared_to(pb) else pb
		e.target = -1
		e.order = {"type": "move", "target": goal}
		if not Movement.order_path(w, e, goal):
			e.order = {"type": "idle"}
	w.emit("FissureSpanStarted", {"job": int(job.id), "owner": issuer, "tiles": L})


static func _jobs_step(w: SimWorld, s: Dictionary, r: Dictionary, every: int) -> void:
	var keep := []
	var reach := float(r.get("span_reach", 3.0))
	for job in s.jobs:
		var pa := Vector2(int(job.ax), int(job.ay)) + Vector2(0.5, 0.5)
		var pb := Vector2(int(job.bx), int(job.by)) + Vector2(0.5, 0.5)
		var alive := 0
		var at := 0
		for id in job.units:
			var e = w.entities.get(int(id))
			if e == null or int(e.owner) != int(job.owner):
				continue
			alive += 1
			var p := Vector2(e.pos)
			if p.distance_to(pa) <= reach or p.distance_to(pb) <= reach:
				at += 1
		if alive == 0:
			continue
		job.prog = int(job.prog) + at * every
		if int(job.prog) < int(job.need):
			keep.append(job)
			continue
		var pend: Dictionary = s.pend
		for i in job.tiles:
			pend[int(i)] = ST_SPAN
		s.force = true
		w.emit("FissureSpanned", {"job": int(job.id), "owner": int(job.owner), "tiles": (job.tiles as Array).size()})
	s.jobs = keep


# ================================================================ snapshot (presentation)
## {} without fissures. Arrays are shared copy-on-write. pts = [tile, birth, stage | depth << 3 | scar << 6] x n,
## rebuilt at most every 40 ticks (runtime cache only).
static func snap(w: SimWorld) -> Dictionary:
	var s = st(w)
	if s == null:
		return {}
	var key := int(s.dv) * 1000003 + int(s.pv) * 7 + (s.big as Array).size() * 131 + w.tick / 40
	var c = w.cache.get("fis_snap")
	if c != null and int(c.key) == key:
		return c.out
	var pts := PackedInt32Array()
	pts.resize(int(s.npts) * 3 + 3 * 8)
	var n := 0
	for vn in s.veins:
		var p: PackedInt32Array = vn.p
		var b: PackedInt32Array = vn.b
		var ss: PackedByteArray = vn.s
		var xx: PackedByteArray = vn.x
		var d := int(vn.d)
		for pi in p.size():
			if n + 3 > pts.size():
				pts.resize(pts.size() * 2)
			pts[n] = p[pi]
			pts[n + 1] = b[pi]
			pts[n + 2] = int(ss[pi]) | (d << 3) | (int(xx[pi]) << 6)
			n += 3
	pts.resize(n)
	var big := []
	for g in s.big:
		big.append([int(g.id), int(g.x), int(g.y), String(g.def), int(g.t)])
	var jobs := []
	for j in s.jobs:
		jobs.append([int(j.ax), int(j.ay), int(j.bx), int(j.by), float(j.prog) / maxf(float(j.need), 1.0)])
	var cst = w.sys_state.get("creep")
	var out := {"w": int(w.map.w), "h": int(w.map.h), "dv": int(s.dv), "ts": s.ts, "pts": pts, "big": big,
		"jobs": jobs, "age": s.age, "cs": int(cst.cs) if cst != null else 4, "cw": int(cst.cw) if cst != null else 0,
		"tick": w.tick, "seed": int(w.seed_value)}
	w.cache["fis_snap"] = {"key": key, "out": out}
	return out
