extends RefCounted
## G7 (LPMODE7): Last Protocol set pieces (13.3), secrets (13.8), the capture-a-core subdue (13.5) and the on-call
## commands. Site data comes from LPMAP7's map.lp (dam, bridges, power, secrets) or cfg.lp_sites (tests), copied
## into w.sys_state.lp.sites at setup:
##   {dam: {cell, flood: Rect2i, route, done}, bridges: [{id, cell, done}], power: {cell, held, held_s},
##    secrets: {cache|lost_squad|origin|mech: {cell, state hidden|done, t}}}
## Commands (LastProtocol routes them here): lp_blow_dam {issuer}, lp_drop_bridge {issuer, bridge},
##   lp_orbital_strike {issuer, cell}, lp_fire_support {issuer, cell}.

const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const HotState = preload("res://sim/hot_state.gd")
const Terrain = preload("res://sim/terrain.gd")
const Air = preload("res://sim/systems/air.gd")
const CounterNanite = preload("res://sim/systems/counter_nanite.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")
const PDATA = preload("res://sim/systems/progression_data.gd")
const MOVEMENT = preload("res://sim/systems/movement.gd")
const SECRET_KINDS := ["cache", "lost_squad", "origin", "mech"]


static func R() -> Dictionary:
	return Content.rules().get("g7_lastprotocol", {})


static func _c(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


## Site table from map.lp / cfg.lp_sites.
static func sites_from(w: SimWorld) -> Dictionary:
	var src: Dictionary = {}
	if w.cfg.get("lp_sites") is Dictionary:
		src = w.cfg.lp_sites
	elif w.map.get("lp") is Dictionary:
		src = w.map.lp
	var out := {"dam": {}, "bridges": [], "power": {}, "secrets": {}}
	var dam = src.get("dam")
	if dam is Dictionary and dam.has("cell"):
		var fr = dam.get("flood")
		out.dam = {"cell": _c(dam.cell), "flood": fr if fr is Rect2i else Rect2i(_c(dam.cell) - Vector2i(6, 6), Vector2i(13, 13)),
			"route": String(dam.get("route", "")), "done": false}
	for b in src.get("bridges", []):
		if b is Dictionary and b.has("cell"):
			(out.bridges as Array).append({"id": String(b.get("id", "b%d" % (out.bridges as Array).size())), "cell": _c(b.cell), "done": false})
	var pw = src.get("power")
	if pw is Dictionary and pw.has("cell"):
		out.power = {"cell": _c(pw.cell), "held": false, "held_s": 0.0}
	var sec = src.get("secrets")
	if sec is Dictionary:
		for k in SECRET_KINDS:
			if sec.has(k):
				var v = sec[k]
				var cell := _c(v.get("cell") if v is Dictionary else v)
				if cell.x >= 0:
					out.secrets[k] = {"cell": cell, "state": "hidden", "t": 0.0}
	return out


## Does side fid have a unit of the needed kind within r of cell? (cn | engineer | air | any)
static func near(w: SimWorld, fid: int, cell: Vector2i, r: float, need: String) -> bool:
	var p := Vector2(cell) + Vector2(0.5, 0.5)
	for e in w.units_of(fid):
		if (e.pos as Vector2).distance_to(p) > r:
			continue
		match need:
			"cn":
				if e.has("cn_team"):
					return true
			"engineer":
				if bool(Content.unit(String(e.def)).get("can_build", false)):
					return true
			"air":
				if Air.is_aircraft(e):
					return true
			_:
				return true
	return false


static func hostile_near(w: SimWorld, mfid: int, cell: Vector2i, r: float) -> bool:
	var p := Vector2(cell) + Vector2(0.5, 0.5)
	for e in w.units_of(mfid):
		if (e.pos as Vector2).distance_to(p) <= r:
			return true
	return false


## Damage every Machine unit / building within r of p by dmg (destroyed at 0 hp). Returns the count hit.
static func blast(w: SimWorld, mfid: int, by: int, p: Vector2, r: float, dmg: float, cause: String) -> int:
	var ids := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if int(e.owner) == mfid and (e.kind == "unit" or e.kind == "building") and (e.pos as Vector2).distance_to(p) <= r:
			ids.append(int(id))
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		var hp := (HotState.get_hp(w, id) if e.kind == "unit" else float(e.hp)) - dmg
		if hp <= 0.0:
			w.destroy(id, cause, by)
		elif e.kind == "unit":
			HotState.set_hp(w, id, hp)
		else:
			e.hp = hp
	return ids.size()


## Once a second: power grid hold, secrets, capture-a-core subdue.
static func tick(w: SimWorld, s: Dictionary) -> void:
	var fid := int(s.fid)
	var mfid := int(s.mfid)
	var dt := 1.0
	var sites: Dictionary = s.sites
	var sp: Dictionary = R().get("setpieces", {})
	var pw: Dictionary = sites.power
	if not pw.is_empty():
		var pr: Dictionary = sp.get("power", {})
		var held := near(w, fid, pw.cell, float(pr.get("radius", 6.0)), "any") \
			and not hostile_near(w, mfid, pw.cell, float(pr.get("hostile_radius", 9.0)))
		if held != bool(pw.held):
			pw.held = held
			w.emit("LpPowerGrid", {"held": held, "cell": pw.cell})
		if held:
			pw.held_s = float(pw.held_s) + dt
			_power_bonus(w, fid, float(pr.get("research_bonus", 0.5)), float(pr.get("production_bonus", 0.5)), dt)
	var sr: Dictionary = R().get("secrets", {})
	for k in SECRET_KINDS:
		if not (sites.secrets as Dictionary).has(k):
			continue
		var sc: Dictionary = sites.secrets[k]
		if String(sc.state) == "done":
			continue
		var kr: Dictionary = sr.get(k, {})
		if near(w, fid, sc.cell, float(sr.get("radius", 4.0)), String(kr.get("needs", "any"))):
			sc.t = float(sc.t) + dt
			if float(sc.t) >= float(kr.get("hold_s", 0.0)):
				_secret(w, s, k, sc, kr)
		else:
			sc.t = 0.0
	_capture_step(w, s, dt)


static func _power_bonus(w: SimWorld, fid: int, rb: float, pb: float, dt: float) -> void:
	var r: Dictionary = w.factions[fid].research
	if String(r.active) != "" and int(r.facility) != -1:
		var p: Dictionary = PDATA.project(String(r.active))
		r.progress = minf(float(r.progress) + rb * dt / maxf(float(p.get("time", 1)), 0.001), 0.999)
	for b in w.buildings_of(fid):
		if not (b.get("queue", []) as Array).is_empty() and bool(b.get("built", false)):
			var head: Dictionary = b.queue[0]
			var pd := Content.production(String(head.item))
			if pd.has("train_time"):
				head.progress = minf(float(head.progress) + pb * dt / maxf(float(pd.train_time), 0.001), 0.999)


static func _secret(w: SimWorld, s: Dictionary, k: String, sc: Dictionary, kr: Dictionary) -> void:
	var fid := int(s.fid)
	sc.state = "done"
	var p := Vector2(sc.cell) + Vector2(0.5, 0.5)
	var info := {"kind": k, "cell": sc.cell}
	match k:
		"cache":
			s.prototype = int(s.get("prototype", 0)) + 1
			info.prototype = String(kr.get("prototype", "orbital_designator"))
		"lost_squad":
			var res = CounterNanite.spawn_team(w, fid, String(kr.get("kind", "tactical_squad")), p + Vector2(2, 0))
			w.cache.erase("eco_pop")  # crews spawned + boarded this tick: Economy's full recount counts the cargo
			if res is Dictionary:
				for id in res.get("members", []):
					var e = w.entities.get(int(id))
					if e != null:
						e.vet = int(kr.get("vet", 3))
				info.team = int(res.get("team", 0))
		"origin":
			s.origin_found = true
		"mech":
			var def := String(kr.get("def", "a_laser_tank"))
			if not Content.unit(def).is_empty():
				var id := w.spawn_unit(def, fid, p + Vector2(1, 1))
				var e: Dictionary = w.entities[id]
				e.max_hp = float(e.max_hp) * float(kr.get("hp_mult", 3.0))
				e.hp = float(e.max_hp)
				HotState.touch(w, id)
				e.lp_mech = true
				info.id = id
	(s.secrets_found as Array).append(k)
	w.emit("LpSecret", info)


## The walking last core, EMP-held and boxed in by barrier cells for capture.hold_s, is captured (13.5).
static func _capture_step(w: SimWorld, s: Dictionary, dt: float) -> void:
	var wid := Cores.walker(w)
	if wid < 0 or bool(s.get("captured", false)):
		s.cap_t = 0.0
		return
	var e = w.entities.get(wid)
	if e == null:
		return
	var cr: Dictionary = R().get("capture", {})
	var held := MachineEW7.held(w, wid) != ""
	var cs := 4
	var cst = Creep.st(w)
	if cst != null:
		cs = int(cst.cs)
	var rad := float(cr.get("barrier_radius", 3.0))
	var n := 0
	var c0 := w.cell_of(e.pos)
	var reach := int(ceil(rad)) + cs
	for dy in range(-reach, reach + 1, cs):
		for dx in range(-reach, reach + 1, cs):
			if Creep.is_barrier(w, c0 + Vector2i(dx, dy)):
				n += 1
	if held and n >= int(cr.get("barrier_cells_min", 6)):
		s.cap_t = float(s.get("cap_t", 0.0)) + dt
		if float(s.cap_t) >= float(cr.get("hold_s", 20.0)):
			s.captured = true
			Cores.finish(w, int(e.get("core7", -1)), int(s.fid))
			w.emit("LpCoreCaptured", {"pos": e.pos, "origin_found": bool(s.get("origin_found", false))})
	else:
		s.cap_t = 0.0


# ================================================================ commands
static func validate(w: SimWorld, s: Dictionary, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	if fid != int(s.fid):
		return "Only the Last Protocol commander can do that."
	var sp: Dictionary = R().get("setpieces", {})
	match String(cmd.type):
		"lp_blow_dam":
			var d: Dictionary = s.sites.dam
			if d.is_empty() or bool(d.done):
				return "There is no dam left to blow."
			var dr: Dictionary = sp.get("dam", {})
			if not near(w, fid, d.cell, float(dr.get("radius", 5.0)), String(dr.get("needs", "cn"))):
				return "A strike team must reach the dam first."
		"lp_drop_bridge":
			var b := _bridge(s, String(cmd.get("bridge", "")))
			if b.is_empty() or bool(b.done):
				return "Unknown or already dropped bridge."
			var br: Dictionary = sp.get("bridge", {})
			if not near(w, fid, b.cell, float(br.get("radius", 4.0)), String(br.get("needs", "engineer"))):
				return "Engineers must rig the bridge first."
		"lp_orbital_strike":
			if int(s.get("prototype", 0)) <= 0:
				return "No prototype designator recovered."
			if _c(cmd.get("cell")).x < 0:
				return "Pick a target cell."
		"lp_fire_support":
			if _c(cmd.get("cell")).x < 0:
				return "Pick a target cell."
		_:
			return "Unknown Last Protocol command."
	return ""


static func _bridge(s: Dictionary, id: String) -> Dictionary:
	for b in s.sites.bridges:
		if String(b.id) == id:
			return b
	return {}


static func apply(w: SimWorld, s: Dictionary, cmd: Dictionary) -> void:
	var fid := int(s.fid)
	var mfid := int(s.mfid)
	match String(cmd.type):
		"lp_blow_dam":
			_blow_dam(w, s)
		"lp_drop_bridge":
			var b := _bridge(s, String(cmd.bridge))
			b.done = true
			var p := Vector2(b.cell) + Vector2(0.5, 0.5)
			var hit := -1
			var keys := w.entities.keys()
			keys.sort()
			for id in keys:
				var e: Dictionary = w.entities[id]
				if e.kind == "structure" and (e.pos as Vector2).distance_to(p) <= 4.0:
					hit = int(id)
					break
			if hit >= 0:
				w.destroy(hit, "lp_demolition", fid)
			blast(w, mfid, fid, p, 3.0, 99999.0, "lp_demolition")
			w.emit("LpBridgeDropped", {"bridge": b.id, "cell": b.cell, "structure": hit})
		"lp_orbital_strike":
			var sr: Dictionary = R().get("secrets", {}).get("cache", {})
			var p := Vector2(_c(cmd.cell)) + Vector2(0.5, 0.5)
			s.prototype = int(s.prototype) - 1
			var n := blast(w, mfid, fid, p, float(sr.get("strike_radius", 7.0)), float(sr.get("strike_dmg", 2500.0)), "lp_orbital")
			Creep.purge(w, p, float(sr.get("strike_radius", 7.0)), "standard", fid)
			w.emit("LpOrbitalStrike", {"pos": p, "hit": n})
		"lp_fire_support":
			var p := Vector2(_c(cmd.cell)) + Vector2(0.5, 0.5)
			var ids := []
			for e in w.units_of(fid):
				if e.has("lp_home") and Air.is_aircraft(e) and String(Content.unit(String(e.def)).get("weapon", "")) != "":
					e.lp_support_until = w.tick + roundi(float(R().get("air", {}).get("support_s", 60.0)) * SimWorld.TICK_RATE)
					ids.append(int(e.id))
			ids.sort()
			if not ids.is_empty():
				w.submit({"type": "attack_move", "issuer": fid, "unit_ids": ids, "target": p, "ai_cmd": "lp"})
			w.emit("LpFireSupport", {"pos": p, "n": ids.size()})


## Blow the dam: the valley floods (terrain to shallow water, nav rebuilt once), creep there burns into a permanent
## firebreak, Machine units in the valley drown, and the valley convoy route closes.
static func _blow_dam(w: SimWorld, s: Dictionary) -> void:
	var d: Dictionary = s.sites.dam
	d.done = true
	var fr: Rect2i = d.flood
	var t: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	var n := 0
	for y in range(maxi(fr.position.y, 0), mini(fr.end.y, int(w.map.h))):
		for x in range(maxi(fr.position.x, 0), mini(fr.end.x, mw)):
			var k := y * mw + x
			if not Terrain.is_water(int(t[k])) and int(t[k]) != Terrain.BUILDING:
				t[k] = Terrain.SHALLOW
				n += 1
	w.map.terrain = t
	if n > 0:
		MOVEMENT.rebuild_nav(w)
	Creep.burn(w, Vector2(fr.get_center()), Vector2(fr.size).length() * 0.5)
	var ids := []
	for e in w.units_of(int(s.mfid)):
		if fr.has_point(w.cell_of(e.pos)):
			ids.append(int(e.id))
	ids.sort()
	for id in ids:
		w.destroy(id, "lp_flood", int(s.fid))
	if String(d.route) != "":
		(s.routes_closed as Array).append(String(d.route))
	w.emit("LpDamBlown", {"cell": d.cell, "flooded": n, "drowned": ids.size(), "route": d.route})
