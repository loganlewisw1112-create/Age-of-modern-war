extends RefCounted
## G7 (CREEP7): Machine creep layer, dormant seeds, regrowth and permanent purge (master scope sections 8, 6.3, 10).
## Numbers: content/g7/rules_g7_machine.json (rules.g7_machine.creep), all PROVISIONAL.
##
## Field: a coarse grid (one creep cell = cs x cs tiles; 128 x 128 cells on a 512 x 512 map) of values 0..255.
##   Sources (Machine buildings at source_value, seeds at seed/nest value) pull a cell up; every other cell's target is
##   max(4-neighbour) - falloff, so creep reaches about source_value / falloff cells from a source and dies back
##   (decay per visit) when its sources are gone. A cell "is creep" at value >= on.
##   Cells are visited in stripes: row r is updated on ticks where tick % stripe_ticks == r % stripe_ticks, and rows
##   with no creep, no source and no creep next to them are skipped, so a map without creep costs nothing.
## Flags per cell (fl): STERILE = purged (permanent, never regrows), WATER = holds a water tile (firebreak),
##   BREAK = burnt / cratered / thermite (firebreak), BARRIER = barrier package line, CHECKED = tile check done.
## State: w.sys_state.creep, created only by enable() (cfg.creep, cfg.mode "last_protocol", a seed, a purge or a core),
##   so a match without creep keeps its pre-G7 hash. Saved and hashed (PackedByteArrays inside sys_state).
##   Packed arrays are copy-on-write: every writer takes the array out of the state dict, edits it, puts it back.
## Events: CreepPurged {kind, pos, radius, cells, lost, seeds, by}, SeedRevealed {id, pos, side},
##   SeedRegrown {id, pos, def, building}, SeedKilled {id, pos, kind}.
## Determinism: no rng; fixed row/column order; seeds in ascending id; integer values.

const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Fissures7 = preload("res://sim/systems/fissures7.gd")  # G7 FISSURE7: fissures / canyons / growths

const VER := 1
const F_STERILE := 1
const F_WATER := 2
const F_BREAK := 4
const F_BARRIER := 8
const F_CHECKED := 16
const F_BLOCK := F_STERILE | F_WATER | F_BREAK | F_BARRIER


static func R() -> Dictionary:
	return Content.rules().get("g7_machine", {})


static func RC() -> Dictionary:
	return R().get("creep", {})


static func st(w: SimWorld):
	return w.sys_state.get("creep")


static func enabled(w: SimWorld) -> bool:
	return w.sys_state.has("creep")


## Creates the creep state (idempotent). Water tiles mark their creep cell as a firebreak.
static func enable(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("creep")
	if s != null:
		return s
	var rc := RC()
	var cs := maxi(int(rc.get("cell", 4)), 1)
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var cw := (mw + cs - 1) / cs
	var ch := (mh + cs - 1) / cs
	var v := PackedByteArray()
	v.resize(cw * ch)
	v.fill(0)
	var fl := PackedByteArray()
	fl.resize(cw * ch)
	fl.fill(0)
	var t: PackedByteArray = w.map.terrain
	var land := cw * ch
	for y in mh:
		var row := y * mw
		var crow := (y / cs) * cw
		for x in mw:
			if Terrain.is_water(t[row + x]):
				var k := crow + x / cs
				if fl[k] & F_WATER == 0:
					fl[k] |= F_WATER
					land -= 1
	s = {"ver": VER, "cs": cs, "cw": cw, "ch": ch, "v": v, "fl": fl, "on_n": 0, "land": maxi(land, 1),
		"seeds": [], "next_seed": 1, "lost": 0, "sites": [], "hunt": [], "dv": 0}
	w.sys_state["creep"] = s
	return s


# ================================================================ queries
static func _k(s: Dictionary, cell: Vector2i) -> int:
	var cs := int(s.cs)
	return (cell.y / cs) * int(s.cw) + cell.x / cs


## Creep value of a TILE cell (0..1).
static func at(w: SimWorld, cell: Vector2i) -> float:
	var s = st(w)
	if s == null or not w.in_bounds(cell):
		return 0.0
	return float((s.v as PackedByteArray)[_k(s, cell)]) / 255.0


## True when the tile cell is creep (value >= rules on).
static func on_creep(w: SimWorld, cell: Vector2i) -> bool:
	var s = st(w)
	if s == null or not w.in_bounds(cell):
		return false
	return int((s.v as PackedByteArray)[_k(s, cell)]) >= int(RC().get("on", 64))


## Share of the land (creep cells without water) covered by creep, 0..1 (Last Protocol creep meter).
static func coverage(w: SimWorld) -> float:
	var s = st(w)
	if s == null:
		return 0.0
	return float(s.on_n) / float(s.land)


static func is_sterile(w: SimWorld, cell: Vector2i) -> bool:
	return _flag(w, cell, F_STERILE)


static func is_barrier(w: SimWorld, cell: Vector2i) -> bool:
	return _flag(w, cell, F_BARRIER)


## Firebreak, barrier or purged: creep can never enter this tile's cell.
static func is_blocked(w: SimWorld, cell: Vector2i) -> bool:
	return _flag(w, cell, F_BLOCK)


static func _flag(w: SimWorld, cell: Vector2i, bit: int) -> bool:
	var s = st(w)
	if s == null or not w.in_bounds(cell):
		return false
	return (s.fl as PackedByteArray)[_k(s, cell)] & bit != 0


## Creep-grid indices whose cell centre lies within radius tiles of center (ascending).
static func _cells_in(s: Dictionary, center: Vector2, radius: float) -> Array:
	var cs := float(s.cs)
	var cw := int(s.cw)
	var ch := int(s.ch)
	var out := []
	var r2 := radius * radius + cs * cs * 0.25
	var x0 := maxi(floori((center.x - radius) / cs), 0)
	var x1 := mini(floori((center.x + radius) / cs), cw - 1)
	var y0 := maxi(floori((center.y - radius) / cs), 0)
	var y1 := mini(floori((center.y + radius) / cs), ch - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if Vector2((cx + 0.5) * cs, (cy + 0.5) * cs).distance_squared_to(center) <= r2:
				out.append(cy * cw + cx)
	return out


## Zeroes the cells and ORs bit into their flags. Returns how many of them were creep.
static func _clear_cells(s: Dictionary, cells: Array, bit: int) -> int:
	var on := int(RC().get("on", 64))
	var v: PackedByteArray = s.v
	var fl: PackedByteArray = s.fl
	s.v = PackedByteArray()
	s.fl = PackedByteArray()
	var lost := 0
	for k in cells:
		if v[k] >= on:
			lost += 1
		if v[k] != 0:
			v[k] = 0
		fl[k] |= bit
	s.v = v
	s.fl = fl
	s.on_n = int(s.on_n) - lost
	s.dv = int(s.dv) + 1
	return lost


# ================================================================ purge / burn / crater
## Clears an area permanently. kind: "standard" (area + seeds in it), "seed_hunter" (same area; seeds and burrowed
## cores over seed_kill_mult x radius), "barrier" (a permanent line creep can't cross: a ring at radius, or a line of
## length 2 x radius through center along dir when dir is non-zero). Returns {cells, lost, seeds}.
static func purge(w: SimWorld, center: Vector2, radius: float, kind: String = "standard", by: int = -1,
		dir: Vector2 = Vector2.ZERO) -> Dictionary:
	var s := enable(w)
	var pall: Dictionary = RC().get("purge", {})
	var pr: Dictionary = pall.get(kind, pall.get("standard", {}))
	var cells := []
	var bit := F_STERILE
	if kind == "barrier":
		cells = _barrier_cells(s, center, radius, dir, int(pr.get("width_cells", 1)))
		bit = F_STERILE | F_BARRIER
	else:
		cells = _cells_in(s, center, radius)
	var lost := _clear_cells(s, cells, bit)
	s.lost = int(s.lost) + lost
	Fissures7.on_cleared(w, center, radius, kind)  # G7 FISSURE7: purge / seal stops fissures, kills growths
	var nseeds := 0
	if kind != "barrier":
		var kr := radius * float(pr.get("seed_kill_mult", 1.0))
		nseeds = _kill_seeds(w, s, center, kr, bool(pr.get("cores", false)), kind)
		if bool(pr.get("cores", false)):
			(s.hunt as Array).append({"pos": center, "r": kr})
	if by >= 0:
		var sites: Array = s.sites
		sites.append({"pos": center, "tick": w.tick, "by": by, "kind": kind})
		if sites.size() > 16:
			sites.remove_at(0)
	w.emit("CreepPurged", {"kind": kind, "pos": center, "radius": radius, "cells": cells.size(), "lost": lost,
		"seeds": nseeds, "by": by})
	return {"cells": cells.size(), "lost": lost, "seeds": nseeds}


static func _barrier_cells(s: Dictionary, center: Vector2, radius: float, dir: Vector2, width: int) -> Array:
	var cs := float(s.cs)
	var cw := int(s.cw)
	var ch := int(s.ch)
	var pts := []
	if dir == Vector2.ZERO:
		var n := maxi(ceili(TAU * radius / (cs * 0.5)), 8)
		for i in n:
			pts.append(center + Vector2.RIGHT.rotated(TAU * float(i) / float(n)) * radius)
	else:
		var d := dir.normalized()
		var steps := maxi(ceili(radius * 2.0 / (cs * 0.5)), 2)
		for i in steps + 1:
			pts.append(center - d * radius + d * (radius * 2.0 * float(i) / float(steps)))
	var seen := {}
	for p in pts:
		var cx := clampi(floori(p.x / cs), 0, cw - 1)
		var cy := clampi(floori(p.y / cs), 0, ch - 1)
		for oy in range(-(width - 1), width):
			for ox in range(-(width - 1), width):
				var x := cx + ox
				var y := cy + oy
				if x >= 0 and y >= 0 and x < cw and y < ch:
					seen[y * cw + x] = true
	var out := seen.keys()
	out.sort()
	return out


## Thermite / fire: clears creep and leaves a permanent firebreak (not counted as purged-sterile).
static func burn(w: SimWorld, center: Vector2, radius: float) -> int:
	var s := enable(w)
	var cells := _cells_in(s, center, radius)
	_clear_cells(s, cells, F_BREAK)
	Fissures7.on_cleared(w, center, radius, "burn")  # G7 FISSURE7: burning stops fissures, kills growths
	return cells.size()


## Craters (heavy shells, bombs): a firebreak creep can't cross.
static func crater(w: SimWorld, center: Vector2, radius: float) -> int:
	return burn(w, center, radius)


# ================================================================ seeds, nests, burrowed cores
## Sides of the Machine kind (rules machine_kinds), ascending. Runtime cache.
static func machine_fids(w: SimWorld) -> Array:
	var c = w.cache.get("creep_mf")
	if c != null:
		return c
	var kinds: Array = RC().get("machine_kinds", ["machine"])
	var out := []
	for fid in w.factions:
		var fd := Content.faction(String(w.factions[fid].get("faction_def", "")))
		if kinds.has(String(fd.get("kind", ""))):
			out.append(int(fid))
	out.sort()
	w.cache["creep_mf"] = out
	return out


static func is_machine(w: SimWorld, fid: int) -> bool:
	return machine_fids(w).has(fid)


## A hidden regrowth point. kind: "seed" (dormant seed), "nest" (dense, faster), "core" (burrowed core: regrows a
## doomsday core; only seed-hunter purges kill it). owner -1 = the first Machine side at regrowth time.
static func add_seed(w: SimWorld, pos: Vector2, kind: String = "seed", owner: int = -1) -> int:
	var s := enable(w)
	var id := int(s.next_seed)
	s.next_seed = id + 1
	(s.seeds as Array).append({"id": id, "pos": pos, "kind": kind, "owner": owner, "rev": [], "t": 0})
	w.cache.erase("creep_src")
	return id


## A seed nest (LPMAP7): count nest seeds in a ring of the given radius around center. Returns their ids.
static func add_nest(w: SimWorld, center: Vector2, count: int = 5, radius: float = 3.0, owner: int = -1) -> Array:
	var ids := [add_seed(w, center, "nest", owner)]
	for i in maxi(count - 1, 0):
		var p := center + Vector2.RIGHT.rotated(TAU * float(i) / float(maxi(count - 1, 1))) * radius
		ids.append(add_seed(w, p, "nest", owner))
	return ids


static func seeds(w: SimWorld) -> Array:
	var s = st(w)
	return [] if s == null else s.seeds


## Scanner sweep: seeds (and burrowed cores) within radius become visible to side. Returns how many were new.
static func reveal(w: SimWorld, center: Vector2, radius: float, side: int) -> int:
	var s = st(w)
	if s == null:
		return 0
	var n := 0
	for sd in s.seeds:
		if (sd.pos as Vector2).distance_to(center) <= radius and not (sd.rev as Array).has(side):
			(sd.rev as Array).append(side)
			n += 1
			w.emit("SeedRevealed", {"id": sd.id, "pos": sd.pos, "kind": sd.kind, "side": side})
	return n


static func _kill_seeds(w: SimWorld, s: Dictionary, center: Vector2, r: float, cores_ok: bool, how: String) -> int:
	var keep := []
	var n := 0
	for sd in s.seeds:
		if (sd.pos as Vector2).distance_to(center) <= r and (cores_ok or String(sd.kind) != "core"):
			n += 1
			w.emit("SeedKilled", {"id": sd.id, "pos": sd.pos, "kind": sd.kind, "by": how})
		else:
			keep.append(sd)
	s.seeds = keep
	if n > 0:
		w.cache.erase("creep_src")
	return n


# ================================================================ tick
static func _auto_on(w: SimWorld) -> bool:
	return bool(w.cfg.get("creep", false)) or String(w.cfg.get("mode", "")) == "last_protocol"


static func _phase_mult(w: SimWorld) -> float:
	var cst = w.sys_state.get("cores")
	if cst == null:
		return 1.0
	var n := int(cst.get("phase", 0))
	for p in R().get("phases", []):
		if int(p.get("n", -1)) == n:
			return float(p.get("creep_mult", 1.0))
	return 1.0


## Runtime source table {creep index: value}, Machine building list and source rows; rebuilt once per stripe cycle.
static func _sources(w: SimWorld, s: Dictionary) -> Dictionary:
	var rc := RC()
	var src := {}
	var rows := {}
	var blds := []
	var cs := int(s.cs)
	var cw := int(s.cw)
	var sv := int(rc.get("source_value", 255))
	var mfs := machine_fids(w)
	for e in SimIndex.of(w, "building"):  # ascending id, live this tick
		if not mfs.has(int(e.owner)) or not w.entities.has(int(e.id)):
			continue
		blds.append(e)
		var c := w.cell_of(e.pos)
		if w.in_bounds(c):
			var k := (c.y / cs) * cw + c.x / cs
			src[k] = sv
			rows[c.y / cs] = true
	for sd in s.seeds:
		var c := w.cell_of(sd.pos)
		if w.in_bounds(c):
			var k := (c.y / cs) * cw + c.x / cs
			var val := int(rc.get("nest_value", 255)) if String(sd.kind) == "nest" else int(rc.get("seed_value", 170))
			src[k] = maxi(int(src.get(k, 0)), val)
			rows[c.y / cs] = true
	var jam := {}
	if s.has("jams"):
		var keep := []
		for j in s.jams:
			if int(j.until) > w.tick:
				keep.append(j)
				for k in _cells_in(s, j.pos, float(j.r)):
					jam[k] = true
		s.jams = keep
	var out := {"src": src, "rows": rows, "blds": blds, "tick": w.tick, "jam": jam}
	w.cache["creep_src"] = out
	return out


static func tick(w: SimWorld) -> void:
	var s = st(w)
	if s == null:
		if not _auto_on(w):
			return
		s = enable(w)
	var rc := RC()
	var S := maxi(int(rc.get("stripe_ticks", 20)), 1)
	var ph := w.tick % S
	var sc = w.cache.get("creep_src")
	if sc == null or ph == 0:
		sc = _sources(w, s)
	_spread(w, s, sc, ph, S)
	if ph == 1:
		_seed_step(w, s, sc, S)
	var every := maxi(int(rc.get("repair_every_ticks", 20)), 1)
	if w.tick % every == 0:
		_repair(w, s, sc, every)
	Fissures7.tick(w)  # G7 FISSURE7: cracks -> fissures -> canyons, growths (no-op until creep ages)


## One stripe: rows r with r % S == ph. Skips rows with no creep, no source and no creep in the rows next to them.
static func _spread(w: SimWorld, s: Dictionary, sc: Dictionary, ph: int, S: int) -> void:
	var rc := RC()
	var cw := int(s.cw)
	var ch := int(s.ch)
	var cs := int(s.cs)
	var on := int(rc.get("on", 64))
	var fall := maxi(int(rc.get("falloff", 12)), 1)
	var grow := maxi(roundi(float(rc.get("grow", 8)) * _phase_mult(w)), 1)
	var decay := maxi(int(rc.get("decay", 8)), 1)
	var src: Dictionary = sc.src
	var srows: Dictionary = sc.rows
	var ra = w.cache.get("creep_rows")
	var rowany: PackedByteArray
	if ra == null or (ra as PackedByteArray).size() != ch:
		rowany = PackedByteArray()
		rowany.resize(ch)
		rowany.fill(1)
	else:
		rowany = ra
	w.cache.erase("creep_rows")
	var burnt = w.map.get("burnt")
	var jam: Dictionary = sc.get("jam", {})
	var jam_on := not jam.is_empty()
	var v: PackedByteArray = s.v
	var fl: PackedByteArray = s.fl
	s.v = PackedByteArray()
	s.fl = PackedByteArray()
	var on_n := int(s.on_n)
	var changed := false
	for r in range(ph, ch, S):
		if not srows.has(r) and rowany[r] == 0 and (r == 0 or rowany[r - 1] == 0) and (r == ch - 1 or rowany[r + 1] == 0):
			continue
		var any := 0
		var base := r * cw
		for x in cw:
			var k := base + x
			var f := fl[k]
			if f & F_BLOCK != 0:
				continue
			var cur := v[k]
			var nm := 0
			if x > 0:
				nm = v[k - 1]
			if x < cw - 1 and v[k + 1] > nm:
				nm = v[k + 1]
			if r > 0 and v[k - cw] > nm:
				nm = v[k - cw]
			if r < ch - 1 and v[k + cw] > nm:
				nm = v[k + cw]
			var tgt := maxi(int(src.get(k, 0)), nm - fall)
			var nv := cur
			if tgt > cur and jam_on and jam.has(k):
				tgt = cur   # jammed hive link: no growth here while the jam lasts
			if tgt > cur:
				if f & F_CHECKED == 0:
					fl[k] = f | F_CHECKED
					if burnt != null and _cell_burnt(w, burnt, x, r, cs):
						fl[k] = f | F_CHECKED | F_BREAK
						continue
				nv = mini(tgt, cur + grow)
			elif tgt < cur:
				nv = maxi(tgt, cur - decay)
			if nv != cur:
				if cur >= on and nv < on:
					on_n -= 1
				elif cur < on and nv >= on:
					on_n += 1
				v[k] = nv
				changed = true
			if nv > 0:
				any = 1
		rowany[r] = any
	s.v = v
	s.fl = fl
	s.on_n = on_n
	if changed:
		s.dv = int(s.dv) + 1
	w.cache["creep_rows"] = rowany


static func _cell_burnt(w: SimWorld, burnt, cx: int, cy: int, cs: int) -> bool:
	var b: PackedByteArray = burnt
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	for y in range(cy * cs, mini(cy * cs + cs, mh)):
		for x in range(cx * cs, mini(cx * cs + cs, mw)):
			var i := y * mw + x
			if i < b.size() and b[i] != 0:
				return true
	return false


## Dormant seeds regrow a structure when no Machine building stands within clear_radius for regrow_s.
static func _seed_step(w: SimWorld, s: Dictionary, sc: Dictionary, S: int) -> void:
	if (s.seeds as Array).is_empty():
		return
	var rg: Dictionary = RC().get("regrow", {})
	var cr2: float = pow(float(rg.get("clear_radius", 24.0)), 2.0)
	var mfs := machine_fids(w)
	for sd in s.seeds:
		var near := false
		for b in sc.blds:
			if w.entities.has(int(b.id)) and (b.pos as Vector2).distance_squared_to(sd.pos) <= cr2:
				near = true
				break
		if near:
			sd.t = 0
			continue
		sd.t = int(sd.t) + S
		var need := roundi(float(rg.get("nest_regrow_s" if String(sd.kind) == "nest" else "regrow_s", 90.0)) * SimWorld.TICK_RATE)
		if int(sd.t) < need:
			continue
		sd.t = 0
		var owner := int(sd.owner)
		if owner < 0:
			if mfs.is_empty():
				continue
			owner = int(mfs[0])
		var def := String(rg.get("nest_building" if String(sd.kind) == "nest" else "building", "m_hive_node"))
		if String(sd.kind) == "core":
			def = String(R().get("cores", {}).get("def", "m_core"))
		if Content.building(def).is_empty():
			continue
		var c := w.cell_of(sd.pos)
		var bid := w.spawn_building(def, owner, c, true)
		if String(sd.kind) == "core":
			var cst = w.sys_state.get("cores")
			if cst == null:
				cst = {}
				w.sys_state["cores"] = cst
			if not cst.has("pending"):
				cst["pending"] = []
			(cst.pending as Array).append(bid)
		w.emit("SeedRegrown", {"id": sd.id, "pos": sd.pos, "kind": sd.kind, "def": def, "building": bid})
		w.cache.erase("creep_src")


## Machine units and buildings on creep, out of combat, regain hp.
static func _repair(w: SimWorld, s: Dictionary, sc: Dictionary, every: int) -> void:
	var rc := RC()
	var mfs := machine_fids(w)
	if mfs.is_empty() or int(s.on_n) <= 0:
		return
	var on := int(rc.get("on", 64))
	var v: PackedByteArray = s.v
	var cs := int(s.cs)
	var cw := int(s.cw)
	var window := int(rc.get("repair_out_of_combat_ticks", 60))
	var hu := float(rc.get("repair_hp_per_sec_unit", 2.0)) * float(every) / SimWorld.TICK_RATE
	var hb := float(rc.get("repair_hp_per_sec_building", 6.0)) * float(every) / SimWorld.TICK_RATE
	var byown: Dictionary = SimIndex.units_by_owner(w)
	for fid in mfs:
		for e in byown.get(fid, []):
			_heal(w, e, v, cs, cw, on, window, hu)
	for b in sc.blds:
		if w.entities.has(int(b.id)):
			_heal(w, b, v, cs, cw, on, window, hb)


static func _heal(w: SimWorld, e: Dictionary, v: PackedByteArray, cs: int, cw: int, on: int, window: int, add: float) -> void:
	var c := w.cell_of(e.pos)
	if not w.in_bounds(c) or v[(c.y / cs) * cw + c.x / cs] < on:
		return
	var jc = w.cache.get("creep_src")
	if jc != null and (jc.jam as Dictionary).has((c.y / cs) * cw + c.x / cs):
		return
	if w.tick - int(e.get("last_hit_tick", -1000000)) < window:
		return
	var unit: bool = e.kind == "unit"
	var hp := HotState.get_hp(w, int(e.id)) if unit else float(e.hp)
	if hp <= 0.0 or hp >= float(e.max_hp):
		return
	var nv := snappedf(minf(float(e.max_hp), hp + add), 1.0 / 1024.0)
	if unit:
		HotState.set_hp(w, int(e.id), nv)
	else:
		e.hp = nv


## Machine unit or building standing on creep (powered by the network).
static func powered(w: SimWorld, e: Dictionary) -> bool:
	return is_machine(w, int(e.owner)) and on_creep(w, w.cell_of(e.pos))


## CNSIM7: EW specialists jam the local hive link: inside radius, until until_tick, creep does not grow and Machine
## units are not repaired by it. Saved in the creep state.
static func jam_link(w: SimWorld, pos: Vector2, radius: float, until_tick: int, fid: int) -> void:
	var s := enable(w)
	if not s.has("jams"):
		s["jams"] = []
	(s.jams as Array).append({"pos": pos, "r": radius, "until": until_tick, "fid": fid})
	w.cache.erase("creep_src")
	w.emit("HiveLinkJammed", {"pos": pos, "radius": radius, "until": until_tick, "fid": fid})


static func is_jammed(w: SimWorld, pos: Vector2) -> bool:
	var s = st(w)
	if s == null or not s.has("jams"):
		return false
	for j in s.jams:
		if int(j.until) > w.tick and (j.pos as Vector2).distance_to(pos) <= float(j.r):
			return true
	return false


## CNSIM7 / EMP: knocks every leech (THREAT7 sets e.leech_on = vehicle id on a latched leech) off vehicle_id.
static func detach_leeches(w: SimWorld, vehicle_id: int) -> int:
	var n := 0
	for e in SimIndex.of(w, "unit"):
		if int(e.get("leech_on", -1)) == vehicle_id and w.entities.has(int(e.id)):
			e.erase("leech_on")
			n += 1
			w.emit("LeechDetached", {"id": e.id, "vehicle": vehicle_id})
	return n


## Render-thread copy (packed arrays are copy-on-write, so this shares the buffers until the sim writes again).
## {} when the match has no creep. seeds: [{pos, kind, rev}] for the view to mark revealed seeds.
static func snap(w: SimWorld) -> Dictionary:
	var s = st(w)
	if s == null:
		return {}
	var sl := []
	for sd in s.seeds:
		if not (sd.rev as Array).is_empty():
			sl.append({"pos": sd.pos, "kind": sd.kind, "rev": (sd.rev as Array).duplicate()})
	return {"cs": s.cs, "cw": s.cw, "ch": s.ch, "v": s.v, "fl": s.fl, "dv": s.dv, "on": int(RC().get("on", 64)),
		"seeds": sl, "coverage": coverage(w), "fis": Fissures7.snap(w)}  # G7 FISSURE7: fissure field for the view


static func validate_command(_w: SimWorld, cmd: Dictionary) -> String:
	return "%s: not implemented yet" % String(cmd.get("type", ""))


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
