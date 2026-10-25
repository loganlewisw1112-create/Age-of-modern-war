extends RefCounted
## G4bMech (owner: UNITS): mines, charges, fire spread, concealment, deploy/set-up, crush.
## CONTRACTS_G4 section 8. Runs after Combat each tick (SYSTEM_ORDER), so this tick's combat grids
## (w.cache.combat_ng native / combat_grid GDScript, FULL units) are current for neighbour queries.
##
## Unit def flags (content/g4/units_g4b.json):
##   conceal_still  sniper: e.still_since (tick it last moved), e.hid, e.spot (sorted team ids that
##                  have a unit/building within CONCEAL_RANGE). Hidden = still and not fired for
##                  CONCEAL_TICKS. Combat (and Fog via CR) treat it as concealed from teams not in spot.
##   setup_ticks    mortar: e.deployed, e.setup_left. Fires only deployed (combat _fire gate). Moving
##                  packs it at once; stopping with a target (or a `deploy` command) starts set-up.
##   crush_damage   scrap mech: while moving, enemy infantry within radius+0.3 take this per tick
##                  (weapon class "crush" through Damage.apply_hit).
##   detects_mines  (or def role "recon"): enemy mines within DETECT_RANGE join mine.seen (that team).
##   can_mine / can_charge  combat engineer: orders {type:"lay_mine", cell, t} / {type:"plant_charge",
##                  target_id, t}; walk there, work LAY_TICKS / PLANT_TICKS, then spawn the entity.
## Entities (saved in w.entities, ascending ids):
##   mine   {id, kind:"mine", def:"g4_mine", owner, pos, cell, hp, max_hp, seen:[team], layer}
##          Triggers when an enemy ground unit (of a team not in seen) is within MINE_TRIGGER of it:
##          weapon g4_mine_blast on every ground unit within its splash (falloff to 50%), then gone.
##   charge {id, kind:"charge", def:"g4_charge", owner, pos, target, fuse, hp, max_hp}
##          fuse counts down from FUSE_TICKS; at 0 weapon g4_charge (class demolition) hits target.
## Fire: w.sys_state.g4b.fires {cell index: [left, next_spread, owner]} (created on first fire).
##   Burns FIRE_BURN ticks; every FIRE_SPREAD_EVERY ticks each 4-neighbour FOREST cell catches with
##   w.rng chance FIRE_SPREAD_CHANCE (ascending cell order, seeded = deterministic); every
##   FIRE_DMG_EVERY ticks units on a burning cell take FIRE_DMG (class flame). Burnt-out cells become
##   DIRT: event TerrainChanged{cells, cause:"fire"} + Movement.on_terrain_changed (renderer rebakes).
## Events: MineLaid, MineDetected, MineTriggered, ChargePlanted, ChargeDetonated, FireStarted,
##   FireSpread, FireOut, TerrainChanged, Deployed, Packed.
##   G5 (UNITS5): every burnt-out cell is also set in w.map.burnt (saved, hashed; see _burnt_layer).
## Determinism: ascending ids / cell order, w.rng only, integer tick state. Caches never saved.

const Movement = preload("res://sim/systems/movement.gd")
const Damage = preload("res://sim/systems/damage.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const CONCEAL_TICKS := 60
const CONCEAL_RANGE := 3.0
const DETECT_RANGE := 4.0
const MINE_TRIGGER := 0.6
const MAX_MINES := 4          # active mines per engineer
const LAY_TICKS := 20
const PLANT_TICKS := 20
const FUSE_TICKS := 100
const REACH := 1.6            # engineer work distance to a charge target
const FIRE_BURN := 300
const FIRE_SPREAD_EVERY := 40
const FIRE_SPREAD_CHANCE := 0.35
const FIRE_DMG_EVERY := 10
const FIRE_DMG := 12.0
const FOREST := 3
const DIRT := 1
const N4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BUCKET := 2.0           # combat.gd grid layout
const GRID_STRIDE := 1024

const M_CONCEAL := 1
const M_SETUP := 2
const M_CRUSH := 4
const M_DETECT := 8
const M_ENGINEER := 16


# ================================================================ unit subset (cache, never saved)
static func _mask(st: Dictionary, def_id: String) -> int:
	var m = st.defs.get(def_id)
	if m != null:
		return int(m)
	var d := Content.unit(def_id)
	var v := 0
	if bool(d.get("conceal_still", false)):
		v |= M_CONCEAL
	if int(d.get("setup_ticks", 0)) > 0:
		v |= M_SETUP
	if float(d.get("crush_damage", 0)) > 0.0:
		v |= M_CRUSH
	if bool(d.get("detects_mines", false)) or String(d.get("role", "")) == "recon":
		v |= M_DETECT
	if bool(d.get("can_mine", false)) or bool(d.get("can_charge", false)):
		v |= M_ENGINEER
	st.defs[def_id] = v
	return v


static func _add(st: Dictionary, e: Dictionary) -> void:
	if _mask(st, String(e.def)) != 0:
		(st.ids as Array).append(int(e.id))


## Ids of every unit whose def has a mechanic, ascending. Never compacted: a unit in a carrier's
## cargo (TRANS) leaves w.entities and comes back with the same id, so dead ids are only skipped.
static func _state(w: SimWorld) -> Dictionary:
	var st = w.cache.get("g4b_sub")
	var nid := int(w.next_id)
	if st == null:
		st = {"next_id": nid, "defs": {}, "ids": []}
		var all := []
		for e in SimIndex.of(w, "unit"):
			all.append(e)
			for c in e.get("cargo", []):
				all.append(c)
		all.sort_custom(func(a, b): return int(a.id) < int(b.id))
		for e in all:
			_add(st, e)
		w.cache["g4b_sub"] = st
		return st
	var from := int(st.next_id)
	if nid > from:
		for id in range(from, nid):
			var e = w.entities.get(id)
			if e != null and e.kind == "unit":
				_add(st, e)
		st.next_id = nid
	return st


static func mask_of(w: SimWorld, def_id: String) -> int:
	return _mask(_state(w), def_id)


static func team_of(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st := _state(w)
	var ents: Dictionary = w.entities
	var detectors := []
	for id in st.ids:
		var e = ents.get(id)
		if e == null:
			continue
		var m: int = st.defs[String(e.def)]
		if m & M_CONCEAL:
			_conceal_step(w, e)
		if m & M_SETUP:
			_setup_step(w, e)
		if m & M_CRUSH and bool(e.moving):
			_crush_step(w, e)
		if m & M_ENGINEER:
			_engineer_step(w, e)
		if m & M_DETECT:
			detectors.append(e)
	var mines: Array = SimIndex.of(w, "mine")
	var charges: Array = SimIndex.of(w, "charge")
	if not mines.is_empty():
		_detect(w, mines, detectors)
	if not charges.is_empty():
		_charges_step(w, charges)
	var fs = w.sys_state.get("g4b")
	var fires: Dictionary = fs.fires if fs != null else {}
	if not mines.is_empty() or (not fires.is_empty() and w.tick % FIRE_DMG_EVERY == 0):
		_ground_pass(w, mines, fires)
	if not fires.is_empty():
		_fire_step(w, fs)


# ---------------------------------------------------------------- concealment (sniper)
static func _conceal_step(w: SimWorld, e: Dictionary) -> void:
	if bool(e.moving) or not e.has("still_since"):
		e.still_since = w.tick
	var quiet := w.tick - maxi(int(e.still_since), int(e.get("last_fired_tick", -100000)))
	if quiet >= CONCEAL_TICKS:
		e.hid = true
		e.spot = _spot_teams(w, e)
	elif bool(e.get("hid", false)) or not e.has("hid"):
		e.hid = false
		e.spot = []


## Sorted team ids (other than e's) with a unit or building within CONCEAL_RANGE of e.
static func _spot_teams(w: SimWorld, e: Dictionary) -> Array:
	var my := team_of(w, int(e.owner))
	var p: Vector2 = e.pos
	var out := []
	for c in near_units(w, p, CONCEAL_RANGE):
		var tm := team_of(w, int(c.owner))
		if tm != my and int(c.owner) != SimWorld.NEUTRAL and not out.has(tm):
			out.append(tm)
	for b in w.cache.get("combat_blds", []):
		var tb := team_of(w, int(b.owner))
		if tb == my or out.has(tb) or not w.entities.has(int(b.id)):
			continue
		var o: Vector2i = b.cell
		var sz := float(b.size)
		var q := Vector2(clampf(p.x, float(o.x), float(o.x) + sz), clampf(p.y, float(o.y), float(o.y) + sz))
		if p.distance_to(q) <= CONCEAL_RANGE:
			out.append(tb)
	out.sort()
	return out


## Is unit e (conceal_still) hidden from faction fid right now? Used by combat (and fog via CR).
static func hidden_from(w: SimWorld, fid: int, e: Dictionary) -> bool:
	if not bool(e.get("hid", false)) or int(e.owner) == fid or w.is_ally(fid, int(e.owner)):
		return false
	return not (e.spot as Array).has(team_of(w, fid))


# ---------------------------------------------------------------- deploy (mortar)
static func _setup_step(w: SimWorld, e: Dictionary) -> void:
	if bool(e.moving):
		if bool(e.get("deployed", false)) or int(e.get("setup_left", 0)) > 0:
			e.deployed = false
			e.setup_left = 0
			w.emit("Packed", {"id": int(e.id), "owner": int(e.owner)})
		return
	if bool(e.get("deployed", false)):
		return
	var left := int(e.get("setup_left", 0))
	if left > 0:
		left -= 1
		e.setup_left = left
		if left == 0:
			e.deployed = true
			w.emit("Deployed", {"id": int(e.id), "owner": int(e.owner)})
		return
	if int(e.target) >= 0 and not bool(e.get("broken", false)):
		_start_setup(e)   # stopped with a target: set up automatically


static func _start_setup(e: Dictionary) -> void:
	e.deployed = false
	e.setup_left = maxi(int(Content.unit(String(e.def)).get("setup_ticks", 0)), 1)


# ---------------------------------------------------------------- crush (scrap mech)
static func _crush_step(w: SimWorld, e: Dictionary) -> void:
	var d := Content.unit(String(e.def))
	var r := float(d.get("radius", 0.5)) + 0.3
	var s := {"damage": float(d.get("crush_damage", 0)), "cls": "crush", "weapon": "crush"}
	for c in near_units(w, e.pos, r):
		if c.has("morale") and w.is_enemy(int(e.owner), int(c.owner)) and w.entities.has(int(c.id)) \
				and not _is_air(c):
			Damage.apply_hit(w, e, c, s, true)


static func _is_air(e: Dictionary) -> bool:
	var d := Content.unit(String(e.def))
	return bool(d.get("is_air", false)) or String(d.get("move_class", "")).begins_with("air")


## Units within r of p from this tick's combat grids (FULL units: by the Tiers contact bound every
## unit within any contact radius of another team's unit is FULL), ascending id.
static func near_units(w: SimWorld, p: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	var ng = w.cache.get("combat_ng")
	if ng != null:
		for cid in ng.grid.query_radius(p, r + 0.05):
			var c = w.entities.get(cid)
			if c != null and c.kind == "unit" and p.distance_squared_to(Vector2(c.pos)) <= r2:
				out.append(c)
	else:
		var grid: Dictionary = w.cache.get("combat_grid", {})
		var x0 := floori((p.x - r) / BUCKET)
		var x1 := floori((p.x + r) / BUCKET)
		var y0 := floori((p.y - r) / BUCKET)
		var y1 := floori((p.y + r) / BUCKET)
		for o in grid:
			var g: Dictionary = grid[o]
			for yy in range(y0, y1 + 1):
				for xx in range(x0, x1 + 1):
					var arr = g.get(xx + yy * GRID_STRIDE)
					if arr == null:
						continue
					for c in arr:
						if w.entities.has(int(c.id)) and p.distance_squared_to(Vector2(c.pos)) <= r2:
							out.append(c)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


# ---------------------------------------------------------------- engineers: mines and charges
static func _engineer_step(w: SimWorld, e: Dictionary) -> void:
	var o: Dictionary = e.order
	var ot := String(o.get("type", ""))
	if ot != "lay_mine" and ot != "plant_charge":
		return
	var t = null
	var goal := Vector2.ZERO
	var dist := 0.0
	var reach := MINE_TRIGGER
	if ot == "lay_mine":
		var cell: Vector2i = o.cell
		goal = Vector2(cell) + Vector2(0.5, 0.5)
		dist = Vector2(e.pos).distance_to(goal)
	else:
		t = w.entities.get(int(o.get("target_id", -1)))
		if t == null or charge_target_error(w, int(e.owner), t) != "":
			e.order = {"type": "idle"}
			Movement.stop_path(e)
			return
		goal = _approach(e, t)
		dist = _dist_to(e.pos, t)
		reach = REACH
	if dist > reach:
		if not bool(e.moving):
			o.tries = int(o.get("tries", 0)) + 1
			if int(o.tries) > 3 or not Movement.order_path(w, e, goal):
				e.order = {"type": "idle"}
		return
	if bool(e.moving):
		Movement.stop_path(e)
	o.t = int(o.get("t", 0)) + 1
	if ot == "lay_mine":
		if int(o.t) >= LAY_TICKS:
			e.order = {"type": "idle"}
			var c: Vector2i = o.cell
			if mine_error(w, int(e.owner), c) == "" and _mines_of(w, int(e.id)) < MAX_MINES:
				_spawn_mine(w, e, c)
	elif int(o.t) >= PLANT_TICKS:
		e.order = {"type": "idle"}
		_spawn_charge(w, e, t)


## Distance from p to target t: building footprint, bridge cells, else centre.
static func _dist_to(p: Vector2, t: Dictionary) -> float:
	if t.kind == "building":
		var o: Vector2i = t.cell
		var sz := float(t.size)
		return p.distance_to(Vector2(clampf(p.x, float(o.x), float(o.x) + sz), clampf(p.y, float(o.y), float(o.y) + sz)))
	if t.kind == "structure":
		var best := INF
		for c in t.get("cells", []):
			best = minf(best, p.distance_to(Vector2(c) + Vector2(0.5, 0.5)) - 0.5)
		return maxf(best, 0.0)
	return p.distance_to(Vector2(t.pos))


## Where an engineer walks to reach t (just outside a building, the nearest bridge cell).
static func _approach(e: Dictionary, t: Dictionary) -> Vector2:
	var p: Vector2 = e.pos
	if t.kind == "building":
		var o: Vector2i = t.cell
		var sz := float(t.size)
		return Vector2(clampf(p.x, float(o.x) - 0.6, float(o.x) + sz + 0.6), clampf(p.y, float(o.y) - 0.6, float(o.y) + sz + 0.6))
	if t.kind == "structure":
		var best := Vector2(t.pos)
		var bd := INF
		for c in t.get("cells", []):
			var q := Vector2(c) + Vector2(0.5, 0.5)
			if p.distance_to(q) < bd:
				bd = p.distance_to(q)
				best = q
		return best
	return Vector2(t.pos)


static func _mines_of(w: SimWorld, eng_id: int) -> int:
	var n := 0
	for m in SimIndex.of(w, "mine"):
		if w.entities.has(int(m.id)) and int(m.get("layer", -1)) == eng_id:
			n += 1
	return n


static func mine_error(w: SimWorld, _fid: int, cell: Vector2i) -> String:
	if not w.in_bounds(cell):
		return "Outside the map."
	if not Movement.is_passable(w, cell, "foot"):
		return "Mines need open ground."
	for m in SimIndex.of(w, "mine"):
		if w.entities.has(int(m.id)) and Vector2i(m.cell) == cell:
			return "A mine is already there."
	return ""


static func charge_target_error(w: SimWorld, fid: int, t: Dictionary) -> String:
	if t.kind == "structure":
		return "The bridge is already destroyed." if String(t.get("state", "")) == "ruined" else ""
	if t.kind != "building":
		return "Charges go on buildings, walls or bridges."
	if int(t.owner) == fid or w.is_ally(fid, int(t.owner)):
		return "Cannot demolish a friendly building."
	return ""


static func _spawn_mine(w: SimWorld, e: Dictionary, cell: Vector2i) -> void:
	var id: int = w._new_id()
	w.entities[id] = {"id": id, "kind": "mine", "def": "g4_mine", "owner": int(e.owner),
		"pos": Vector2(cell) + Vector2(0.5, 0.5), "cell": cell, "hp": 1.0, "max_hp": 1.0,
		"seen": [], "layer": int(e.id)}
	w.emit("MineLaid", {"id": id, "owner": int(e.owner), "cell": cell, "by": int(e.id)})


static func _spawn_charge(w: SimWorld, e: Dictionary, t: Dictionary) -> void:
	var id: int = w._new_id()
	w.entities[id] = {"id": id, "kind": "charge", "def": "g4_charge", "owner": int(e.owner),
		"pos": Vector2(e.pos), "target": int(t.id), "fuse": FUSE_TICKS, "hp": 1.0, "max_hp": 1.0}
	w.emit("ChargePlanted", {"id": id, "owner": int(e.owner), "target": int(t.id), "fuse": FUSE_TICKS, "by": int(e.id)})


static func _wpn(id: String) -> Dictionary:
	var wd := Content.weapon(id)
	return {"weapon": id, "damage": float(wd.get("damage", 0)), "cls": String(wd.get("class", "")),
		"splash": float(wd.get("splash", 0))}


static func _detect(w: SimWorld, mines: Array, detectors: Array) -> void:
	for m in mines:
		if not w.entities.has(int(m.id)):
			continue
		var mp: Vector2 = m.pos
		for d in detectors:
			if not w.entities.has(int(d.id)) or not w.is_enemy(int(m.owner), int(d.owner)):
				continue
			if Vector2(d.pos).distance_to(mp) > DETECT_RANGE:
				continue
			var tm := team_of(w, int(d.owner))
			var seen: Array = m.seen
			if not seen.has(tm):
				seen.append(tm)
				seen.sort()
				w.emit("MineDetected", {"id": int(m.id), "team": tm, "by": int(d.id), "cell": m.cell})


## Mine (or charge) visible to fid: own/allied, or (mines) detected by fid's team. Renderer/AI helper.
static func visible_to(w: SimWorld, fid: int, m: Dictionary) -> bool:
	if int(m.owner) == fid or w.is_ally(fid, int(m.owner)):
		return true
	return m.kind == "mine" and (m.get("seen", []) as Array).has(team_of(w, fid))


static func _charges_step(w: SimWorld, charges: Array) -> void:
	for c in charges:
		var cid := int(c.id)
		if not w.entities.has(cid):
			continue
		c.fuse = int(c.fuse) - 1
		if int(c.fuse) > 0:
			continue
		w.entities.erase(cid)
		var t = w.entities.get(int(c.target))
		w.emit("ChargeDetonated", {"id": cid, "owner": int(c.owner), "target": int(c.target), "pos": c.pos})
		if t != null and (t.kind != "structure" or String(t.get("state", "")) != "ruined"):
			Damage.apply_hit(w, c, t, _wpn("g4_charge"), true)


# ---------------------------------------------------------------- mines trigger + units in fire
## One pass over the units, only when mines exist or on a fire-damage tick: collects units on a
## cell next to a mine (3x3) or on a burning cell. Covers REDUCED-tier units too (a mine is not a
## Tiers contact, so a lone column walking into a minefield may be REDUCED).
static func _ground_pass(w: SimWorld, mines: Array, fires: Dictionary) -> void:
	var mw := int(w.map.w)
	var watch := {}
	for m in mines:
		if not w.entities.has(int(m.id)):
			continue
		var c: Vector2i = m.cell
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cc := c + Vector2i(dx, dy)
				if w.in_bounds(cc):
					var k := cc.y * mw + cc.x
					watch[k] = int(watch.get(k, 0)) | 1
	if w.tick % FIRE_DMG_EVERY == 0:
		for k in fires:
			watch[int(k)] = int(watch.get(int(k), 0)) | 2
	if watch.is_empty():
		return
	var near := []
	var burning := []
	for u in SimIndex.of(w, "unit"):
		var p: Vector2 = u.pos
		var v = watch.get(floori(p.y) * mw + floori(p.x))
		if v == null or not w.entities.has(int(u.id)):
			continue
		if int(v) & 1:
			near.append(u)
		if int(v) & 2:
			burning.append(u)
	for m in mines:
		if not w.entities.has(int(m.id)):
			continue
		var mp: Vector2 = m.pos
		for u in near:
			if w.entities.has(int(u.id)) and w.is_enemy(int(m.owner), int(u.owner)) and not _is_air(u) \
					and not (m.seen as Array).has(team_of(w, int(u.owner))) and mp.distance_to(u.pos) <= MINE_TRIGGER:
				_blast(w, m, near, int(u.id))
				break
	for u in burning:
		if not w.entities.has(int(u.id)) or _is_air(u):
			continue
		var p: Vector2 = u.pos
		var f = fires.get(floori(p.y) * mw + floori(p.x))
		if f == null:
			continue
		var src := {"id": -1, "kind": "fire", "owner": int(f[2]), "pos": Vector2(floorf(p.x) + 0.5, floorf(p.y) + 0.5)}
		Damage.apply_hit(w, src, u, {"weapon": "fire", "damage": FIRE_DMG, "cls": "flame"}, true)


static func _blast(w: SimWorld, m: Dictionary, near: Array, by: int) -> void:
	var s := _wpn("g4_mine_blast")
	var rad := maxf(float(s.splash), 0.01)
	var mp: Vector2 = m.pos
	w.entities.erase(int(m.id))
	w.emit("MineTriggered", {"id": int(m.id), "owner": int(m.owner), "cell": m.cell, "by": by})
	for u in near:
		if not w.entities.has(int(u.id)) or _is_air(u):
			continue
		var d := mp.distance_to(u.pos)
		if d > rad:
			continue
		var s2 := s.duplicate()
		s2.damage = float(s.damage) * (1.0 - 0.5 * d / rad)
		Damage.apply_hit(w, m, u, s2, true)


# ---------------------------------------------------------------- fire
## Starts a fire on a FOREST cell (flamer shot landing there, combat.gd hook). True if new.
static func ignite(w: SimWorld, cell: Vector2i, owner: int) -> bool:
	if not w.in_bounds(cell) or w.terrain_at(cell) != FOREST:
		return false
	var fs = w.sys_state.get("g4b")
	if fs == null:
		fs = {"fires": {}}
		w.sys_state["g4b"] = fs
	var ci := cell.y * int(w.map.w) + cell.x
	if (fs.fires as Dictionary).has(ci):
		return false
	fs.fires[ci] = [FIRE_BURN, FIRE_SPREAD_EVERY, owner]
	w.emit("FireStarted", {"cell": cell, "owner": owner})
	return true


static func is_burning(w: SimWorld, cell: Vector2i) -> bool:
	var fs = w.sys_state.get("g4b")
	return fs != null and w.in_bounds(cell) and (fs.fires as Dictionary).has(cell.y * int(w.map.w) + cell.x)


## G5 (UNITS5, CONTRACTS_G5 section 9): w.map.burnt is a PackedByteArray (w x h, 1 = burnt-out
## forest), created at the first burn-out so maps without fire keep their G4 state hash. It is part of
## w.map, so it is saved, loaded and hashed with the map; the render snapshot reads it.
static func _burnt_layer(w: SimWorld) -> PackedByteArray:
	var n := int(w.map.w) * int(w.map.h)
	var b = w.map.get("burnt")
	if b == null or typeof(b) != TYPE_PACKED_BYTE_ARRAY or (b as PackedByteArray).size() != n:
		var nb := PackedByteArray()
		nb.resize(n)
		nb.fill(0)
		return nb
	return b


static func is_burnt(w: SimWorld, cell: Vector2i) -> bool:
	var b = w.map.get("burnt")
	if b == null or not w.in_bounds(cell):
		return false
	var k := cell.y * int(w.map.w) + cell.x
	return k < (b as PackedByteArray).size() and int(b[k]) != 0


static func _cell_of_index(k: int, mw: int) -> Vector2i:
	return Vector2i(k % mw, floori(float(k) / float(mw)))


static func _fire_step(w: SimWorld, fs: Dictionary) -> void:
	var fires: Dictionary = fs.fires
	var mw := int(w.map.w)
	var keys := fires.keys()
	keys.sort()
	var spread := []
	var spread_owner := []
	var out := []
	for k in keys:
		var f: Array = fires[k]
		f[0] = int(f[0]) - 1
		f[1] = int(f[1]) - 1
		if int(f[1]) <= 0:
			f[1] = FIRE_SPREAD_EVERY
			var c := _cell_of_index(int(k), mw)
			for dv in N4:
				var n: Vector2i = c + dv
				if not w.in_bounds(n):
					continue
				var ni := n.y * mw + n.x
				if fires.has(ni) or spread.has(ni) or w.terrain_at(n) != FOREST:
					continue
				if w.rng.chance(FIRE_SPREAD_CHANCE):
					spread.append(ni)
					spread_owner.append(int(f[2]))
		if int(f[0]) <= 0:
			out.append(int(k))
	for i in spread.size():
		var ni: int = spread[i]
		fires[ni] = [FIRE_BURN, FIRE_SPREAD_EVERY, spread_owner[i]]
		w.emit("FireSpread", {"cell": _cell_of_index(ni, mw), "owner": spread_owner[i]})
	if out.is_empty():
		return
	var t: PackedByteArray = w.map.terrain
	var burnt := _burnt_layer(w)
	var cells := []
	for k in out:
		fires.erase(k)
		t[k] = DIRT
		burnt[k] = 1
		var c := _cell_of_index(k, mw)
		cells.append(c)
		w.emit("FireOut", {"cell": c})
	w.map.terrain = t
	w.map.burnt = burnt
	w.emit("TerrainChanged", {"cells": cells, "cause": "fire"})
	Movement.on_terrain_changed(w)


# ================================================================ commands
## Selected units whose def has `flag` ("setup_ticks" means setup_ticks > 0), ascending id.
static func _capable(w: SimWorld, cmd: Dictionary, flag: String) -> Array:
	var out := []
	for id in cmd.get("unit_ids", []):
		var e = w.entities.get(int(id))
		if e == null or e.kind != "unit":
			continue
		var d := Content.unit(String(e.def))
		var ok := int(d.get("setup_ticks", 0)) > 0 if flag == "setup_ticks" else bool(d.get(flag, false))
		if ok:
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


static func _cell_arg(v):
	if typeof(v) == TYPE_VECTOR2I:
		return v
	if typeof(v) == TYPE_VECTOR2:
		return Vector2i(floori(v.x), floori(v.y))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return null


## deploy {issuer, unit_ids, pack?:bool}; lay_mine {issuer, unit_ids, cell:[x,y]};
## plant_charge {issuer, unit_ids, target_id} (enemy/neutral building or wall, or a bridge).
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	match String(cmd.get("type", "")):
		"deploy":
			return "" if not _capable(w, cmd, "setup_ticks").is_empty() else "Only mortar teams deploy."
		"lay_mine":
			if _capable(w, cmd, "can_mine").is_empty():
				return "Only combat engineers lay mines."
			var c = _cell_arg(cmd.get("cell"))
			if c == null:
				return "No cell given."
			return mine_error(w, fid, c)
		"plant_charge":
			if _capable(w, cmd, "can_charge").is_empty():
				return "Only combat engineers plant charges."
			var t = w.entities.get(int(cmd.get("target_id", -1)))
			if t == null:
				return "No target."
			return charge_target_error(w, fid, t)
	return "Unknown command."


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var ty := String(cmd.type)
	if ty == "deploy":
		var pack := bool(cmd.get("pack", false))
		for e in _capable(w, cmd, "setup_ticks"):
			e.erase("patrol")
			e.erase("guard")
			if pack:
				if bool(e.get("deployed", false)) or int(e.get("setup_left", 0)) > 0:
					w.emit("Packed", {"id": int(e.id), "owner": int(e.owner)})
				e.deployed = false
				e.setup_left = 0
				e.order = {"type": "idle"}
			else:
				Movement.stop_path(e)
				e.order = {"type": "hold"}
				if not bool(e.get("deployed", false)) and int(e.get("setup_left", 0)) <= 0:
					_start_setup(e)
		return
	var list := _capable(w, cmd, "can_mine" if ty == "lay_mine" else "can_charge")
	if list.is_empty():
		return
	var e: Dictionary = list[0]   # one engineer does the job
	e.erase("patrol")
	e.erase("guard")
	e.target = -1
	var goal := Vector2.ZERO
	if ty == "lay_mine":
		var c: Vector2i = _cell_arg(cmd.cell)
		e.order = {"type": "lay_mine", "cell": c, "t": 0, "tries": 0}
		goal = Vector2(c) + Vector2(0.5, 0.5)
	else:
		var t: Dictionary = w.entities[int(cmd.target_id)]
		e.order = {"type": "plant_charge", "target_id": int(t.id), "t": 0, "tries": 0}
		goal = _approach(e, t)
	if Vector2(e.pos).distance_to(goal) > 0.3 and not Movement.order_path(w, e, goal):
		e.order = {"type": "idle"}
