extends RefCounted
## Naval (owner: NAVAL). CONTRACTS_G5 sections 3.3, 3.4, 4, 5, 6, 8. Preload it; no class_name.
##   const Naval = preload("res://sim/systems/naval.gd")
## Commands:
##   bombard {issuer, unit_ids, cell: [x, y]}: units with bombard_range fire their bombard_weapon
##     (indirect, splash) at a LAND cell within bombard_range until another order replaces it.
## Rules (content/g5/naval.json; tunables in rules.naval, PROVISIONAL):
##   - Ships move by class through Movement (naval: >= 3-wide channel; naval_small: any water).
##   - Shore buildings (def `shore`): footprint >= 2 water cells + >= 2 buildable land cells, and
##     water outside the footprint (the launch side). `near_water: N`: water within N tiles.
##     Construction.placement_error calls shore_error() (ORCH wiring, change request).
##   - Beach unloading: a carrier with `beach_unload` drops cargo only on beach_ok() cells
##     (BEACH, SHALLOW, or dry land next to SHALLOW). Transport calls unload_error()/drop_ok()
##     (AIRSYS wiring, change request).
##   - Wrecks: a ship (`naval_ship`) leaves the G2 wreck entity; Naval sees it the next tick (or the
##     same tick), and after rules.naval.sink_ticks its cell becomes SHALLOW (an obstruction for
##     naval, passable for naval_small) through Movement.on_terrain_changed (both classes rebuilt).
##   - Supply Pier (def `pier`): every pier_every ticks own naval / naval_small / amphibious units
##     within pier_radius (footprint distance) restock ammo/fuel from the faction stock.
## State (saved, hashed): w.sys_state.naval = {wrecks: [[x, y, t, wreck_id]], ver}.
## G5 entity fields (NAVAL): unit.bombard = [x, y] (active fire mission), unit.bombard_cd (ticks to
##   the next bombard shot); wreck.sinking = true (registered in sys_state.naval.wrecks).
## Runtime cache (never saved): w.cache.naval = {bombard: {id: true}} rebuilt from entity fields.
## ---- G6 (owner: NAVAL6; CONTRACTS_G6 section 11, D38/D39; tunables in rules.g6_naval, PROVISIONAL) ----
##   lay_sea_mines {issuer, unit_ids, rect: [x0, y0, x1, y1]}: mine layers whose def has
##     mine_layer.layer "sea" (b_mine_barge) sail to the rect's water cells (row-major, every
##     sea_mine_spacing-th cell) and lay one sea mine each through Mines.lay_sea (MECH6a API), one per
##     sea_mine_lay_s, while charges last (e.sea_mines, def mine_layer.charges; +1 per pier pass, costs
##     sea_mine_ammo ammo from the faction stock).
##   - Minesweepers (def mine_sweep.layer "sea", a_minesweeper) sweep passively every sweep_every ticks:
##     enemy mines within their sonar range join the team's `seen` (they never trigger on it) and enemy
##     mines within mine_sweep.width are cleared through Mines.sweep_cells at sweep_mines_per_s.
##   - Carriers (def mobile_field {slots}) are registered as mobile air fields through
##     Airfield.register_mobile_field (ECON-AIRF6) the tick they appear, with slots + carrier_research_slots
##     once the owner has g6_carrier_1 (re-checked every carrier_check_every ticks). Aircraft rebase to
##     and sortie from them with the G5 commands; the hull rearms at a Supply Pier (_piers) or a Supply
##     Ship (Supply / Support).
##   - Hover carriers (move_class hover) are never beach-only: they unload on any land (udef.beach).
##   - Submerged subs (Sonar) are skipped by the pier restock.
## G6 state (saved, hashed; keys added lazily, so G5 worlds hash as before): sys_state.naval.sea_layers =
##   [unit ids with a lay_sea order]; unit e.order {type: "lay_sea", cells: [[x, y]...], i, t},
##   e.sea_mines (charges left), e.sweep_acc (sweeper mine budget).
## G6 runtime cache: w.cache.naval6 = {next: id cursor, carriers: [ids], sweepers: [ids]} (rebuilt by a
##   rescan from id 1 after a load; registering a carrier twice is a no-op).

const Movement = preload("res://sim/systems/movement.gd")
const Traverse7 = preload("res://sim/systems/traverse7.gd")   # G7 TURRET7B (13.9c-30)
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Status = preload("res://sim/systems/status.gd")
const Supply = preload("res://sim/systems/supply.gd")
const Sonar = preload("res://sim/systems/sonar.gd")   # G6: sonar_range (sonar.gd preloads only sim_index)
const HotState = preload("res://sim/hot_state.gd")
## G6: Airfield (register_mobile_field) and Mines (lay_sea, sweep_cells) are reached through SimWorld at run
## time: airfield.gd and mines.gd preload construction.gd, which preloads this file (no preload cycle).

const VER := 1
const SHIP_CLASSES := ["naval", "naval_small", "amphibious"]
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static var _ud: Dictionary = {}   # unit def -> naval facts (content is immutable at runtime)


static func rules() -> Dictionary:
	return Content.rules().get("naval", {})


static func _rule(key: String, dflt):
	return rules().get(key, dflt)


## Per-def naval facts: {mc, ship, beach, brange, bweapon}.
static func udef(def_id: String) -> Dictionary:
	var v = _ud.get(def_id)
	if v == null:
		var d := Content.unit(def_id)
		v = {"mc": String(d.get("move_class", "foot")), "ship": bool(d.get("naval_ship", false)),
			"beach": bool(d.get("beach_unload", false)) and String(d.get("move_class", "")) != "hover",
			"brange": float(d.get("bombard_range", 0.0)),
			"bweapon": String(d.get("bombard_weapon", ""))}
		_ud[def_id] = v
	return v


static func is_ship(def_id: String) -> bool:
	return bool(udef(def_id).ship)


static func is_water_class(def_id: String) -> bool:
	return SHIP_CLASSES.has(String(udef(def_id).mc))


static func state(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get("naval")
	if st == null:
		st = {"wrecks": [], "ver": VER}
		w.sys_state["naval"] = st
	return st


static func _t(w: SimWorld, c: Vector2i) -> int:
	return int(w.map.terrain[c.y * int(w.map.w) + c.x])


# ================================================================ shore rules (API)
## True when cargo may be put ashore on this cell: BEACH, SHALLOW, or dry passable land that has a
## SHALLOW 4-neighbour (CONTRACTS_G5 section 8: BEACH/SHALLOW-adjacent land).
static func beach_ok(w: SimWorld, cell: Vector2i) -> bool:
	if not w.in_bounds(cell):
		return false
	var code := _t(w, cell)
	if code == Terrain.BEACH or code == Terrain.SHALLOW:
		return true
	if Terrain.is_water(code) or not Terrain.passable(code, "foot"):
		return false
	for d in N4:
		var q: Vector2i = cell + d
		if w.in_bounds(q) and _t(w, q) == Terrain.SHALLOW:
			return true
	return false


## "" when building def_id may stand at origin as far as the shore rules go (def `shore` or
## `near_water`); otherwise the player-facing reason. Defs with neither flag always return "".
static func shore_error(w: SimWorld, def_id: String, origin: Vector2i) -> String:
	var d := Content.building(def_id)
	var size := int(d.get("size", 1))
	var nm := String(d.get("name", def_id))
	if bool(d.get("shore", false)):
		var water := 0
		var land := 0
		for dy in size:
			for dx in size:
				var c := origin + Vector2i(dx, dy)
				if not w.in_bounds(c):
					return "Outside the map."
				var code := _t(w, c)
				if Terrain.is_water(code):
					water += 1
				elif Terrain.buildable(code):
					land += 1
				else:
					return "Terrain is not buildable here."
		if water < 2 or land < 2:
			return "%s must stand on the shore: part water, part beach or land." % nm
		var outlet := false
		for c in _ring(origin, size):
			if w.in_bounds(c) and Terrain.passable(_t(w, c), "naval_small"):
				outlet = true
				break
		if not outlet:
			return "%s needs open water beside it." % nm
		return ""
	if d.has("near_water"):
		var r := int(d.near_water)
		for dy in range(-r, size + r):
			for dx in range(-r, size + r):
				var c := origin + Vector2i(dx, dy)
				if w.in_bounds(c) and Terrain.is_water(_t(w, c)):
					return ""
		return "%s must be built within %d tiles of water." % [nm, r]
	return ""


## Cells touching the footprint (margin 1), row-major.
static func _ring(origin: Vector2i, size: int) -> Array:
	var out := []
	for y in range(origin.y - 1, origin.y + size + 1):
		for x in range(origin.x - 1, origin.x + size + 1):
			if x < origin.x or y < origin.y or x >= origin.x + size or y >= origin.y + size:
				out.append(Vector2i(x, y))
	return out


## "" when carrier c may unload around `center`; else the reason. Only `beach_unload` carriers are
## restricted: they need a beach_ok cell within rules.naval.beach_drop_radius of center.
static func unload_error(w: SimWorld, c: Dictionary, center: Vector2) -> String:
	if not bool(udef(String(c.def)).beach):
		return ""
	var r := int(_rule("beach_drop_radius", 5))
	var cc := w.cell_of(center)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r and beach_ok(w, cc + Vector2i(dx, dy)):
				return ""
	return "Landing craft can only unload at a beach."


## Drop-cell filter for Transport: false when carrier c is `beach_unload` and cell is not beach_ok.
static func drop_ok(w: SimWorld, c: Dictionary, cell: Vector2i) -> bool:
	return not bool(udef(String(c.def)).beach) or beach_ok(w, cell)


## Id of the nearest own built Supply Pier whose footprint is within rules.naval.pier_radius of pos
## (ties by id), or -1.
static func pier_at(w: SimWorld, fid: int, pos: Vector2) -> int:
	var r := float(_rule("pier_radius", 3))
	var best := -1
	var bd := INF
	for b in SimIndex.of(w, "building"):
		if not SimIndex.alive(w, b) or int(b.owner) != fid or not bool(b.get("built", false)):
			continue
		if not bool(Content.building(String(b.def)).get("pier", false)):
			continue
		var dd := _fp_dist(pos, b.cell, int(b.size))
		if dd <= r and dd < bd:
			bd = dd
			best = int(b.id)
	return best


## Distance from pos to the nearest point of a size x size footprint at cell (0 inside).
static func _fp_dist(pos: Vector2, cell: Vector2i, size: int) -> float:
	var cx := clampf(pos.x, float(cell.x), float(cell.x + size))
	var cy := clampf(pos.y, float(cell.y), float(cell.y + size))
	return pos.distance_to(Vector2(cx, cy))


# ================================================================ bombard command
static func _cmd_cell(cmd: Dictionary):
	var c = cmd.get("cell")
	if c is Vector2i:
		return c
	if c is Vector2:
		return Vector2i(floori(c.x), floori(c.y))
	if typeof(c) == TYPE_ARRAY and (c as Array).size() >= 2:
		return Vector2i(int(c[0]), int(c[1]))
	return null


## Bombard weapon stats of a unit def ({} when it has none): the fields Damage.apply_hit reads.
static func bombard_stats(def_id: String) -> Dictionary:
	var u := udef(def_id)
	if float(u.brange) <= 0.0 or String(u.bweapon) == "":
		return {}
	var wd := Content.weapon(String(u.bweapon))
	if wd.is_empty():
		return {}
	return {"weapon": String(u.bweapon), "damage": float(wd.get("damage", 0)), "cls": String(wd.get("class", "artillery")),
		"splash": float(wd.get("splash", 1.0)), "accuracy": float(wd.get("accuracy", 0.5)),
		"cooldown": float(wd.get("cooldown", 5.0)), "min_range": float(wd.get("min_range", 0.0)),
		"range": float(u.brange), "indirect": true, "guided": false}


## Selected own units able to bombard `cell` from where they are now (ascending id).
static func _bombarders(w: SimWorld, cmd: Dictionary, cell: Vector2i, in_range: bool) -> Array:
	var ids := []
	for raw in cmd.get("unit_ids", []):
		if not ids.has(int(raw)):
			ids.append(int(raw))
	ids.sort()
	var out := []
	var at := Vector2(cell) + Movement.CENTER
	for id in ids:
		var e = w.entities.get(id)
		if e == null or e.kind != "unit" or int(e.owner) != int(cmd.issuer):
			continue
		var s := bombard_stats(String(e.def))
		if s.is_empty():
			continue
		var d: float = Vector2(e.pos).distance_to(at)
		if in_range and (d > float(s.range) or d < float(s.min_range)):
			continue
		out.append(e)
	return out


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) == "lay_sea_mines":
		return _validate_lay_sea(w, cmd)
	if String(cmd.get("type", "")) != "bombard":
		return "Unknown naval command."
	var cell = _cmd_cell(cmd)
	if cell == null or not w.in_bounds(cell):
		return "The bombard target is outside the map."
	if Terrain.is_water(_t(w, cell)):
		return "Bombard targets must be on land."
	if _bombarders(w, cmd, cell, false).is_empty():
		return "Select ships that can bombard."
	if _bombarders(w, cmd, cell, true).is_empty():
		return "Target out of bombard range."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if String(cmd.get("type", "")) == "lay_sea_mines":
		_apply_lay_sea(w, cmd)
		return
	var cell: Vector2i = _cmd_cell(cmd)
	var bc := _bcache(w)
	for e in _bombarders(w, cmd, cell, true):
		Movement.stop_path(e)
		e.erase("patrol")
		e.erase("guard")
		e.order = {"type": "bombard", "cell": [cell.x, cell.y]}
		e.bombard = [cell.x, cell.y]
		e.target = -1
		if not e.has("bombard_cd"):
			e.bombard_cd = 0
		bc[int(e.id)] = true
		w.emit("BombardOrdered", {"id": int(e.id), "owner": int(e.owner), "cell": cell})


## Runtime set of units with an active fire mission (rebuilt from entity fields after a load).
static func _bcache(w: SimWorld) -> Dictionary:
	var nc = w.cache.get("naval")
	if nc == null:
		var b := {}
		for e in SimIndex.of(w, "unit"):
			if SimIndex.alive(w, e) and e.has("bombard"):
				b[int(e.id)] = true
		nc = {"bombard": b}
		w.cache["naval"] = nc
	return nc.bombard


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st := state(w)
	_scan_wrecks(w, st)
	if not (st.wrecks as Array).is_empty():
		_sink(w, st)
	_bombard_tick(w)
	var every := int(_rule("pier_every", 20))
	if every > 0 and w.tick % every == 0:
		_piers(w)
	_g6_tick(w)


## Registers ship wrecks spawned since the previous tick (newest first, stop at older ones).
static func _scan_wrecks(w: SimWorld, st: Dictionary) -> void:
	var list: Array = SimIndex.of(w, "wreck")
	var found := []
	var i := list.size() - 1
	while i >= 0:
		var e: Dictionary = list[i]
		i -= 1
		if int(e.get("tick", 0)) < w.tick - 1:
			break
		if not SimIndex.alive(w, e) or bool(e.get("sinking", false)) or not is_ship(String(e.def)):
			continue
		var c := w.cell_of(e.pos)
		if not w.in_bounds(c) or not Terrain.is_water(_t(w, c)):
			continue
		e.sinking = true
		found.append([c.x, c.y, int(_rule("sink_ticks", 60)), int(e.id)])
	found.reverse()   # ascending wreck id
	for f in found:
		st.wrecks.append(f)
		w.emit("ShipSinking", {"wreck": int(f[3]), "cell": Vector2i(int(f[0]), int(f[1]))})


## Counts every sinking wreck down; at 0 its cell becomes SHALLOW and the nav is rebuilt.
static func _sink(w: SimWorld, st: Dictionary) -> void:
	var keep := []
	var changed := []
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	for f in st.wrecks:
		var left := int(f[2]) - 1
		if left > 0:
			keep.append([int(f[0]), int(f[1]), left, int(f[3])])
			continue
		var i := int(f[1]) * mw + int(f[0])
		if t[i] == Terrain.WATER or t[i] == Terrain.DEEP:
			t[i] = Terrain.SHALLOW
			changed.append(Vector2i(int(f[0]), int(f[1])))
		if w.entities.has(int(f[3])):
			w.destroy(int(f[3]), "sunk")
	st.wrecks = keep
	if changed.is_empty():
		return
	w.map.terrain = t
	w.emit("TerrainChanged", {"cells": changed, "cause": "wreck"})
	Movement.on_terrain_changed(w)


## Fire missions: one bombard_weapon shot per cooldown at the ordered land cell while in range.
static func _bombard_tick(w: SimWorld) -> void:
	var bc := _bcache(w)
	if bc.is_empty():
		return
	var ids := bc.keys()
	ids.sort()
	for id in ids:
		var e = w.entities.get(id)
		if e == null or e.kind != "unit":
			bc.erase(id)
			continue
		if not e.has("bombard") or String(e.order.get("type", "")) != "bombard":
			e.erase("bombard")
			bc.erase(id)
			continue
		var cd := int(e.get("bombard_cd", 0))
		if cd > 0:
			e.bombard_cd = cd - 1
			continue
		if Status.can_fire(w, e) != "" or (e.has("ammo") and int(e.ammo) <= 0):
			continue
		var s := bombard_stats(String(e.def))
		if s.is_empty():
			continue
		var at := Vector2(int(e.bombard[0]), int(e.bombard[1])) + Movement.CENTER
		var from: Vector2 = e.pos
		var d := from.distance_to(at)
		if d > float(s.range) or d < float(s.min_range):
			continue
		if not Traverse7.lay(w, e, at, float(s.cooldown), true):
			continue   # G7 TURRET7B (13.9c-30): the ship's guns lay onto the bombardment point before they fire
		e.bombard_cd = maxi(roundi(float(s.cooldown) * SimWorld.TICK_RATE), 1)
		var hit := w.rng.chance(float(s.accuracy) * Status.accuracy_mult(w, e))
		var to := at
		if not hit:
			to += Vector2(w.rng.randf_range(-1.5, 1.5), w.rng.randf_range(-1.5, 1.5))
		e.firing = 6
		e.facing = Traverse7.face(e, snappedf((to - from).angle(), Movement.Q))   # G7 TURRET7B: laid, no snap
		e.last_fired_tick = w.tick
		w.emit("ShotFired", {"shooter": int(e.id), "target": -1, "weapon": s.weapon, "hit": hit, "from": from,
			"to": to, "indirect": true, "bombard": true})
		Supply.on_shot(w, e)
		_splash(w, e, s, to)


## Shell impact: every ground unit and building within s.splash of `at` takes
## damage x (1 - 0.5 d / splash) through Damage.apply_hit, ascending id (same law as Combat).
static func _splash(w: SimWorld, e: Dictionary, s: Dictionary, at: Vector2) -> void:
	var rad: float = maxf(float(s.splash), 0.01)
	var hits := {}
	for c in SimIndex.of(w, "unit"):
		if not SimIndex.alive(w, c) or Terrain.is_air(String(udef(String(c.def)).mc)):
			continue
		var d := at.distance_to(Vector2(c.pos))
		if d <= rad:
			hits[int(c.id)] = d
	for b in SimIndex.of(w, "building"):
		if not SimIndex.alive(w, b):
			continue
		var d := _fp_dist(at, b.cell, int(b.size))
		if d <= rad:
			hits[int(b.id)] = d
	if hits.is_empty():
		var sup: Dictionary = Content.rules().get("suppression", {})
		Damage.near_miss(w, int(e.owner), at, float(sup.get("per_near_miss", 8)))
		return
	var ids := hits.keys()
	ids.sort()
	for id in ids:
		var v = w.entities.get(id)
		if v == null:
			continue
		var s2 := s.duplicate()
		s2.damage = float(s.damage) * (1.0 - 0.5 * float(hits[id]) / rad)
		Damage.apply_hit(w, e, v, s2, true)


## Supply Piers: own naval / naval_small / amphibious units within pier_radius restock ammo and fuel
## (energy units: ammo only; their charge comes from `recharge`) from the faction stock.
static func _piers(w: SimWorld) -> void:
	var piers := {}   # fid -> [[cell, size, id]]
	for b in SimIndex.of(w, "building"):
		if not SimIndex.alive(w, b) or not bool(b.get("built", false)) or not w.factions.has(int(b.owner)):
			continue
		if bool(Content.building(String(b.def)).get("pier", false)):
			if not piers.has(int(b.owner)):
				piers[int(b.owner)] = []
			piers[int(b.owner)].append([b.cell, int(b.size), int(b.id)])
	if piers.is_empty():
		return
	var r := float(_rule("pier_radius", 3))
	var refill: Dictionary = _rule("pier_refill", {})
	var ammo_rate := int(refill.get("ammo", 8))
	var fuel_rate := int(refill.get("fuel", 12))
	for e in SimIndex.of(w, "unit"):
		var fid := int(e.owner)
		if not piers.has(fid) or not SimIndex.alive(w, e) or not is_water_class(String(e.def)) or e.has("submerged"):
			continue
		var pid := -1
		for p in piers[fid]:
			if _fp_dist(e.pos, p[0], int(p[1])) <= r:
				pid = int(p[2])
				break
		if pid < 0:
			continue
		var d := Content.unit(String(e.def))
		var got := 0
		if e.has("ammo"):
			var want := mini(maxi(0, int(d.get("ammo_max", 0)) - int(e.ammo)), ammo_rate)
			var n := _draw(w, fid, "ammo", want)
			e.ammo = int(e.ammo) + n
			got += n
		if e.has("fuel") and not bool(d.get("energy", false)):
			var wantf := mini(maxi(0, int(ceil(float(d.get("fuel_max", 0)) - float(e.fuel)))), fuel_rate)
			var nf := _draw(w, fid, "fuel", wantf)
			e.fuel = minf(float(d.get("fuel_max", 0)), float(e.fuel) + float(nf))
			got += nf
		got += _recharge_layer(w, e, d)
		if got > 0:
			w.emit("PierRestock", {"id": int(e.id), "pier": pid, "owner": fid})


static func _draw(w: SimWorld, fid: int, res: String, want: int) -> int:
	if want <= 0:
		return 0
	var n := mini(want, int(w.factions[fid].stock.get(res, 0)))
	if n <= 0 or not w.spend(fid, {res: n}, "resupply"):
		return 0
	return n


# ================================================================ G6 (NAVAL6): carriers, sea mines, sweepers
static func g6r() -> Dictionary:
	return Content.rules().get("g6_naval", {})


static func _g6(key: String, dflt):
	return g6r().get(key, dflt)


static func _team(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid


## Runtime lists of carriers / sweepers: a cursor scan over ids created since the last call (a load
## rescans from id 1). Ships are never cargo, so every one is in w.entities when it is scanned.
static func _g6_cache(w: SimWorld) -> Dictionary:
	var c = w.cache.get("naval6")
	if c == null:
		c = {"next": 1, "carriers": [], "sweepers": []}
		w.cache["naval6"] = c
	var from := int(c.next)
	if from < w.next_id:
		for id in range(from, w.next_id):
			var e = w.entities.get(id)
			if e == null or e.kind != "unit":
				continue
			var d := Content.unit(String(e.def))
			if typeof(d.get("mobile_field")) == TYPE_DICTIONARY:
				c.carriers.append(id)
			var ms = d.get("mine_sweep")
			if typeof(ms) == TYPE_DICTIONARY and String(ms.get("layer", "sea")) == "sea":
				c.sweepers.append(id)
		c.next = w.next_id
	return c


static func _g6_tick(w: SimWorld) -> void:
	var c := _g6_cache(w)
	if not (c.carriers as Array).is_empty():
		_carriers(w, c)
	if not (c.sweepers as Array).is_empty():
		var every := maxi(1, int(_g6("sweep_every", 5)))
		if w.tick % every == 0:
			_sweep(w, c, every)
	var st = w.sys_state.get("naval")
	if st != null and st.has("sea_layers") and not (st.sea_layers as Array).is_empty():
		_lay_tick(w, st)


# ---------------------------------------------------------------- carriers (D39)
## Hangar slots of carrier e: def mobile_field.slots (+ g6_carrier_1 research value).
static func carrier_slots(w: SimWorld, e: Dictionary) -> int:
	var mf = Content.unit(String(e.def)).get("mobile_field")
	var n := int(_g6("carrier_slots", 4))
	if typeof(mf) == TYPE_DICTIONARY:
		n = int(mf.get("slots", n))
	var fid := int(e.owner)
	if w.factions.has(fid) and (w.factions[fid].research.done as Array).has("g6_carrier_1"):
		n += int(Content.research("g6_carrier_1").get("value", _g6("carrier_research_slots", 2)))
	return n


static func _carriers(w: SimWorld, c: Dictionary) -> void:
	var af = SimWorld.Airfield
	var every := maxi(1, int(_g6("carrier_check_every", 20)))
	var live := []
	for cid in c.carriers:
		var e = w.entities.get(int(cid))
		if e == null or e.kind != "unit":
			continue
		live.append(int(cid))
		var want := carrier_slots(w, e)
		if not af.fields(w).has(int(cid)):
			af.register_mobile_field(w, int(cid), want)
			w.emit("CarrierDeckReady", {"id": int(cid), "owner": int(e.owner), "slots": want})
		elif (w.tick + int(cid)) % every == 0 and int(af.slot_cap(w, int(cid))) != want:
			af.register_mobile_field(w, int(cid), want)
	c.carriers = live


# ---------------------------------------------------------------- minesweepers
static func _sweep(w: SimWorld, c: Dictionary, every: int) -> void:
	var mines: Array = SimIndex.of(w, "mine")
	var live := []
	for sid in c.sweepers:
		var e = w.entities.get(int(sid))
		if e == null or e.kind != "unit":
			continue
		live.append(int(sid))
		if not mines.is_empty() and SimIndex.alive(w, e):
			_sweep_one(w, e, mines, every)
	c.sweepers = live


## Probe (sonar range) then clear (mine_sweep.width) enemy sea mines around sweeper e.
static func _sweep_one(w: SimWorld, e: Dictionary, mines: Array, every: int) -> void:
	var ms: Dictionary = Content.unit(String(e.def)).mine_sweep
	var width := float(ms.get("width", _g6("sweep_width", 2)))
	var probe := maxf(width, Sonar.sonar_range(w, e))
	var fid := int(e.owner)
	var tm := _team(w, fid)
	var p: Vector2 = e.pos
	var reach := []
	for m in mines:
		if not w.entities.has(int(m.id)) or String(m.get("layer", "land")) != "sea" or not w.is_enemy(int(m.owner), fid):
			continue
		var dist := Vector2(m.pos).distance_to(p)
		if dist > probe:
			continue
		if not m.has("seen"):
			m["seen"] = []
		if not (m.seen as Array).has(tm):
			m.seen.append(tm)
			m.seen.sort()
			w.emit("MineDetected", {"id": int(m.id), "team": tm, "by": int(e.id), "cell": m.cell})
		if dist <= width + 0.5:
			reach.append(m)
	if reach.is_empty():
		e.erase("sweep_acc")
		return
	var acc := float(e.get("sweep_acc", 0.0)) + float(ms.get("mines_per_s", _g6("sweep_mines_per_s", 2.0))) * float(every) * SimWorld.DT
	var cells := []
	for m in reach:
		if acc < 1.0:
			break
		acc -= 1.0
		cells.append(Vector2i(m.cell))
	if not cells.is_empty():
		SimWorld.Mines.sweep_cells(w, fid, cells, int(e.id), "sweep")
	e.sweep_acc = snappedf(acc, 0.0001)


# ---------------------------------------------------------------- sea mines (Mines API, MECH6a)
## mine_layer dict of a sea mine layer def ({} for any other def).
static func _layer_def(def_id: String) -> Dictionary:
	var ml = Content.unit(def_id).get("mine_layer")
	if typeof(ml) == TYPE_DICTIONARY and String(ml.get("layer", "land")) == "sea":
		return ml
	return {}


## Sea mines left aboard e (def mine_layer.charges until the first lay).
static func sea_charges(e: Dictionary) -> int:
	if e.has("sea_mines"):
		return int(e.sea_mines)
	var ml := _layer_def(String(e.def))
	return int(ml.get("charges", _g6("sea_mine_charges", 8))) if not ml.is_empty() else 0


static func _layers_of(w: SimWorld, cmd: Dictionary) -> Array:
	var ids := []
	for raw in cmd.get("unit_ids", []):
		if not ids.has(int(raw)):
			ids.append(int(raw))
	ids.sort()
	var out := []
	for id in ids:
		var e = w.entities.get(id)
		if e != null and e.kind == "unit" and int(e.owner) == int(cmd.get("issuer", -1)) \
				and not _layer_def(String(e.def)).is_empty() and SimIndex.alive(w, e):
			out.append(e)
	return out


static func _sea_rect(v):
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 4:
		return null
	var x0 := mini(int(v[0]), int(v[2]))
	var x1 := maxi(int(v[0]), int(v[2]))
	var y0 := mini(int(v[1]), int(v[3]))
	var y1 := maxi(int(v[1]), int(v[3]))
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## Water cells of rect r that get a mine: row-major, every sea_mine_spacing-th column and row.
static func sea_cells(w: SimWorld, r: Rect2i) -> Array:
	var sp := maxi(1, int(_g6("sea_mine_spacing", 2)))
	var out := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if (x - r.position.x) % sp != 0 or (y - r.position.y) % sp != 0:
				continue
			var c := Vector2i(x, y)
			if w.in_bounds(c) and Terrain.is_water(_t(w, c)):
				out.append([x, y])
	return out


static func _validate_lay_sea(w: SimWorld, cmd: Dictionary) -> String:
	var list := _layers_of(w, cmd)
	if list.is_empty():
		return "Only mine barges lay sea mines."
	var r = _sea_rect(cmd.get("rect"))
	if r == null:
		return "A sea minefield needs a rectangle [x0, y0, x1, y1]."
	var mx := int(_g6("sea_mine_max_rect", 8))
	if r.size.x > mx or r.size.y > mx:
		return "Rectangle too large (max %dx%d)." % [mx, mx]
	if not w.in_bounds(r.position) or not w.in_bounds(r.end - Vector2i.ONE):
		return "Outside the map."
	if sea_cells(w, r).is_empty():
		return "Sea mines go on water."
	for e in list:
		if sea_charges(e) > 0:
			return ""
	return "No sea mines left: restock at a Supply Pier."


## Splits the rect's mine cells round-robin over the listed layers that still carry mines.
static func _apply_lay_sea(w: SimWorld, cmd: Dictionary) -> void:
	var cells := sea_cells(w, _sea_rect(cmd.rect))
	var list := []
	for e in _layers_of(w, cmd):
		if sea_charges(e) > 0:
			list.append(e)
	if list.is_empty() or cells.is_empty():
		return
	var st := state(w)
	if not st.has("sea_layers"):
		st["sea_layers"] = []
	var n := list.size()
	for k in n:
		var e: Dictionary = list[k]
		var mine := []
		for i in cells.size():
			if i % n == k:
				mine.append(cells[i])
		Movement.stop_path(e)
		e.erase("patrol")
		e.erase("guard")
		e.target = -1
		e.sea_mines = sea_charges(e)
		e.order = {"type": "lay_sea", "cells": mine, "i": 0, "t": 0, "tries": 0}
		HotState.touch(w, int(e.id))
		if not (st.sea_layers as Array).has(int(e.id)):
			st.sea_layers.append(int(e.id))
		w.emit("SeaMinesOrdered", {"id": int(e.id), "owner": int(e.owner), "cells": mine.size()})
	(st.sea_layers as Array).sort()


static func _lay_tick(w: SimWorld, st: Dictionary) -> void:
	var keep := []
	var reach := float(_g6("sea_mine_reach", 1.6))
	var lay_t := maxi(1, int(round(float(_g6("sea_mine_lay_s", 1.0)) * float(SimWorld.TICK_RATE))))
	for uid in st.sea_layers:
		var e = w.entities.get(int(uid))
		if e == null or e.kind != "unit" or String((e.order as Dictionary).get("type", "")) != "lay_sea":
			continue
		var o: Dictionary = e.order
		var cells: Array = o.cells
		if int(o.i) >= cells.size() or sea_charges(e) <= 0:
			_lay_done(w, e)
			continue
		keep.append(int(uid))
		var cv: Array = cells[int(o.i)]
		var cell := Vector2i(int(cv[0]), int(cv[1]))
		var goal := Vector2(cell) + Vector2(0.5, 0.5)
		if Vector2(e.pos).distance_to(goal) > reach:
			o.t = 0
			_approach(w, e, o, goal)
			continue
		if bool(e.moving):
			Movement.stop_path(e)
			HotState.touch(w, int(e.id))
		o.t = int(o.t) + 1
		if int(o.t) < lay_t:
			continue
		o.t = 0
		o.i = int(o.i) + 1
		o.tries = 0
		if int(SimWorld.Mines.lay_sea(w, int(e.owner), cell)) >= 0:
			e.sea_mines = sea_charges(e) - 1
	st.sea_layers = keep


## Path toward the current mine cell (re-ordered every 10 ticks while stopped short; a cell that cannot
## be reached after 4 tries, or has no path at all, is skipped).
static func _approach(w: SimWorld, e: Dictionary, o: Dictionary, goal: Vector2) -> void:
	var key := 4000000 + int(o.i)
	var wait := int(e.get("nav_wait", 0))
	if int(e.get("nav_for", -1)) != key or (not bool(e.moving) and wait <= 0):
		e.nav_for = key
		e.nav_wait = 10
		o.tries = int(o.get("tries", 0)) + 1
		if int(o.tries) > 4 or not Movement.order_path(w, e, goal):
			o.i = int(o.i) + 1
			o.tries = 0
		HotState.touch(w, int(e.id))
	elif wait > 0:
		e.nav_wait = wait - 1


static func _lay_done(w: SimWorld, e: Dictionary) -> void:
	if bool(e.moving):
		Movement.stop_path(e)
	e.order = {"type": "idle"}
	e.erase("nav_for")
	e.erase("nav_wait")
	HotState.touch(w, int(e.id))
	w.emit("SeaMinesDone", {"id": int(e.id), "owner": int(e.owner), "left": sea_charges(e)})


## Pier pass: a sea mine layer below its charges takes one mine for sea_mine_ammo ammo. Returns 1 if so.
static func _recharge_layer(w: SimWorld, e: Dictionary, d: Dictionary) -> int:
	var ml = d.get("mine_layer")
	if typeof(ml) != TYPE_DICTIONARY or String(ml.get("layer", "land")) != "sea":
		return 0
	var cap := int(ml.get("charges", _g6("sea_mine_charges", 8)))
	if sea_charges(e) >= cap:
		return 0
	var fid := int(e.owner)
	var cost := int(_g6("sea_mine_ammo", 10))
	if cost > 0:
		if int(w.factions[fid].stock.get("ammo", 0)) < cost or _draw(w, fid, "ammo", cost) < cost:
			return 0
	e.sea_mines = sea_charges(e) + 1
	return 1
