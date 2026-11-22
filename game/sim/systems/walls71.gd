extends RefCounted
## Walls71 (owner: BASTION71, G7.1 G3 wall tech + I2 gate defence / choke points). Last Protocol only. Numbers PROVISIONAL
## in content/g71/rules_g71_defences.json (rules.g71_defences.walls). A "wall" here is any building with Fortify.kind_of
## != "" or a CN facility part wall / tower.
##   Tiers    steel -> composite -> nanite_coat: upgrade() scales hp / max_hp by the tier ratio (no damage-path hook), charges
##            the tier cost; unlock(w, fid, tier) is the progression API (LP: all unlocked until H7). nanite_coat sets e.nres.
##   Fits     fit(w, b, kind) adds a feature to a wall: electric / overhang / firepour (anti-climb), murder / popup (gate
##            defence), port (hidden firing port / pop-out slit), choke (wall-walk choke door), lift (fast wall lift),
##            reinforce (gate reinforcement).
##   Effects  every EVERY ticks each fitted wall hits enemy ground units near it (electric: damage pulse; firepour: when
##            >= pile enemies are packed at its foot, a burst + Parts71.ignite when present; murder / popup: gate guns).
##            overhang marks adjacent enemies e.cl_block until the next pulse (climber logic reads it).
##   Choke    sealed doors block ENEMY units on the wall-walk: choke_sealed(w, cell) / passable_for(w, fid, cell) for
##            Movement; own troops always pass. A choke auto-seals while an enemy stands within r of it (choke_seal_s).
##   Lifts    lift_use moves own foot units next to the lift up onto the wall (lift_s transit).
##   Ports    port_exempt(w, shooter): a shooter next to a wall fitted with a port may fire through the wall
##            (explicit allowed case of the WallFire7 rule; WallFire7.any is untouched).
##   Dozer    (BASTION71-7, G2) berm_build {issuer, unit_ids, from, to}: own dozers (def dozer71.builds) push an earth
##            berm line (Fortify build_line of a_g71_berm, built by the dozers). doze_clear {issuer, unit_ids, at}: own
##            dozers (def dozer71.clears has "wreck") drive to at and remove the Gore71 bodies / wrecks within
##            rules doze.clear_r, one per doze.clear_s, then go idle (DozeCleared / DozeDone events). LP only.
##            dozers_near(w, fid, pos, r): the trench-fill hook for C3 sappers (wave 3) to call.
## State (saved, hashed; created on the first upgrade / fit): w.sys_state.walls71 = {ver, tier, fit, unlock, seal, cd, lift}
##   + doze {unit id: [x, y, next clear tick (0 = driving)]}, created by the first doze_clear only.
## Commands: wall_tier {building_ids, tier}, gate_reinforce {building_id}, choke_seal {building_id, sealed}, lift_use
## {unit_ids, building_id}. Determinism: ascending ids, integer ticks, no rng.
const VER := 1
const EVERY := 10
const Fortify = preload("res://sim/systems/fortify.gd")
const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Damage = preload("res://sim/systems/damage.gd")
const FITS := ["electric", "overhang", "firepour", "murder", "popup", "port", "choke", "lift", "reinforce"]
const CDK := ["e", "f", "m", "p"]


static func R() -> Dictionary:
	return Content.rules().get("g71_defences", {}).get("walls", {})


static func is_wall(b: Dictionary) -> bool:
	if b.kind != "building":
		return false
	var d := Content.building(String(b.def))
	return Fortify.is_fort(String(b.def)) or ["wall", "tower"].has(String(d.get("cn_part", "")))


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("walls71")
	if s == null:
		s = {"ver": VER, "tier": {}, "fit": {}, "unlock": {}, "seal": {}, "cd": {}, "lift": {}}
		w.sys_state["walls71"] = s
	return s


static func _tiers() -> Array:
	return R().get("tiers", [])


static func tier(w: SimWorld, b: Dictionary) -> int:
	var s = w.sys_state.get("walls71")
	return 0 if s == null else int((s.tier as Dictionary).get(int(b.id), 0))


static func tier_id(w: SimWorld, b: Dictionary) -> String:
	var t := _tiers()
	var i := tier(w, b)
	return String(t[i].id) if i < t.size() else "steel"


static func unlocked(w: SimWorld, fid: int) -> int:
	if LastProtocol.active(w):
		return _tiers().size() - 1   # LP keeps research_all until H7 (roster Q5)
	var s = w.sys_state.get("walls71")
	return 0 if s == null else int((s.unlock as Dictionary).get(fid, 0))


static func unlock(w: SimWorld, fid: int, t: int) -> void:
	var s := _st(w)
	s.unlock[fid] = maxi(int((s.unlock as Dictionary).get(fid, 0)), clampi(t, 0, _tiers().size() - 1))


## Upgrades wall b to tier t (> its tier, <= unlocked). Pays the tier cost unless free. Returns "" or a reason.
static func upgrade(w: SimWorld, b: Dictionary, t: int, free := false) -> String:
	if not is_wall(b):
		return "Not a wall."
	var tiers := _tiers()
	if t <= tier(w, b) or t >= tiers.size():
		return "No such upgrade."
	if t > unlocked(w, int(b.owner)):
		return "Not researched."
	if not free and not w.spend(int(b.owner), tiers[t].get("cost", {}), "wall_tier"):
		return "Cannot afford."
	var old := float(tiers[tier(w, b)].hp_mult)
	var ratio := float(tiers[t].hp_mult) / old
	var s := _st(w)
	b.max_hp = snappedf(float(b.max_hp) * ratio, 0.01)
	b.hp = snappedf(float(b.hp) * ratio, 0.01)
	s.tier[int(b.id)] = t
	if bool(tiers[t].get("nanite_resist", false)):
		b.nres = true
	w.emit("WallTier", {"id": int(b.id), "tier": t, "owner": int(b.owner)})
	return ""


static func fit(w: SimWorld, b: Dictionary, kind: String) -> bool:
	if not is_wall(b) or not FITS.has(kind):
		return false
	var s := _st(w)
	var l: Array = (s.fit as Dictionary).get(int(b.id), [])
	if l.has(kind):
		return true
	l.append(kind)
	s.fit[int(b.id)] = l
	w.cache.erase("w71_ports")
	if kind == "reinforce":
		var m := float(R().get("gate", {}).get("reinforce_hp_mult", 1.5))
		b.max_hp = snappedf(float(b.max_hp) * m, 0.01)
		b.hp = snappedf(float(b.hp) * m, 0.01)
	return true


static func fits_of(w: SimWorld, b: Dictionary) -> Array:
	var s = w.sys_state.get("walls71")
	return [] if s == null else (s.fit as Dictionary).get(int(b.id), [])


static func has_fit(w: SimWorld, b: Dictionary, kind: String) -> bool:
	return fits_of(w, b).has(kind)


# ---------------------------------------------------------------- queries other systems call
static func _cells_of(b: Dictionary) -> Array:
	var out := []
	for y in int(b.size):
		for x in int(b.size):
			out.append(Vector2i(b.cell) + Vector2i(x, y))
	return out


static func choke_sealed(w: SimWorld, cell: Vector2i) -> bool:
	var s = w.sys_state.get("walls71")
	if s == null or (s.seal as Dictionary).is_empty():
		return false
	for id in s.seal:
		var b = w.entities.get(int(id))
		if b != null and _cells_of(b).has(cell):
			return true
	return false


## Movement hook: may a unit of side fid enter wall-walk cell? Own troops always; enemies not through a sealed choke.
static func passable_for(w: SimWorld, fid: int, cell: Vector2i) -> bool:
	var s = w.sys_state.get("walls71")
	if s == null or (s.seal as Dictionary).is_empty():
		return true
	for id in s.seal:
		var b = w.entities.get(int(id))
		if b != null and _cells_of(b).has(cell):
			return not w.is_enemy(fid, int(b.owner))
	return true


static func lift_of(w: SimWorld, cell: Vector2i) -> int:
	var s = w.sys_state.get("walls71")
	if s == null:
		return -1
	var ids: Array = (s.fit as Dictionary).keys()
	ids.sort()
	for id in ids:
		var b = w.entities.get(int(id))
		if b != null and has_fit(w, b, "lift") and Vector2(cell).distance_to(Vector2(b.pos)) <= float(b.size) + 2.0:
			return int(id)
	return -1


static func port_exempt(w: SimWorld, shooter: Dictionary) -> bool:
	var s = w.sys_state.get("walls71")
	if s == null or (s.fit as Dictionary).is_empty():
		return false
	# per-tick cell grid of the ported walls (BASTION71-5, ORCH port fits from the LP base: ~10 per start): one
	# dictionary lookup per call instead of a scan of every fit. Same answer as the scan: candidates per cell, then the
	# exact distance test; a wall removed this tick is skipped by the entities check; fit() drops the cache.
	var c = w.cache.get("w71_ports")
	if c == null or int(c.t) != int(w.tick):
		var g := {}
		for id in s.fit:
			var b = w.entities.get(int(id))
			if b == null or not ((s.fit[id] as Array).has("port")):
				continue
			var bp := Vector2(b.pos)
			var r := float(b.size) + 1.5
			for cx in range(floori(bp.x - r), floori(bp.x + r) + 1):
				for cy in range(floori(bp.y - r), floori(bp.y + r) + 1):
					var k := Vector3i(cx, cy, int(b.owner))
					var l: Array = g.get(k, [])
					l.append([int(id), bp, r])
					g[k] = l
		c = {"t": int(w.tick), "g": g}
		w.cache["w71_ports"] = c
	var p := Vector2(shooter.pos)
	var hit = (c.g as Dictionary).get(Vector3i(floori(p.x), floori(p.y), int(shooter.owner)))
	if hit == null:
		return false
	for rec in hit:
		if w.entities.has(int(rec[0])) and p.distance_to(rec[1]) <= float(rec[2]):
			return true
	return false


# ---------------------------------------------------------------- tick
static func _enemies_near(w: SimWorld, owner: int, p: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	for e in SimIndex.of(w, "unit"):
		if w.entities.has(int(e.id)) and w.is_enemy(owner, int(e.owner)) and not bool(Content.unit(String(e.def)).get("is_air", false)):
			if HotState.get_pos(w, int(e.id)).distance_squared_to(p) <= r2:
				out.append(e)
	return out


static func _hit(w: SimWorld, b: Dictionary, e: Dictionary, dmg: float, cls: String) -> void:
	Damage.apply_hit(w, b, e, {"weapon": "", "cls": cls, "damage": dmg}, true)


static func _due(w: SimWorld, s: Dictionary, id: int, k: String, secs: float) -> bool:
	var key := id * 8 + CDK.find(k) + 1
	var nxt := int((s.cd as Dictionary).get(key, 0))
	if w.tick < nxt:
		return false
	s.cd[key] = w.tick + maxi(roundi(secs * SimWorld.TICK_RATE), 1)
	return true


static func tick(w: SimWorld) -> void:
	var s = w.sys_state.get("walls71")
	if s == null:
		return
	_lifts(w, s)
	if s.has("doze"):
		_doze(w, s.doze)
	if w.tick % EVERY != 0:
		return
	var rw: Dictionary = R()
	var ac: Dictionary = rw.get("anti_climb", {})
	var gr: Dictionary = rw.get("gate", {})
	var ids: Array = (s.fit as Dictionary).keys()
	ids.sort()
	for id in ids:
		var b = w.entities.get(int(id))
		if b == null:
			(s.fit as Dictionary).erase(id)
			(s.seal as Dictionary).erase(id)
			continue
		if not bool(b.get("built", false)):
			continue
		var f: Array = s.fit[id]
		var bp := Vector2(b.pos)
		var o := int(b.owner)
		var hs := float(b.size) * 0.5
		if f.has("electric") and _due(w, s, id, "e", float(ac.get("electric_every_s", 1.0))):
			for e in _enemies_near(w, o, bp, float(ac.get("electric_r", 1.6)) + hs):
				_hit(w, b, e, float(ac.get("electric_dmg", 40)), "energy")
		if f.has("overhang"):
			for e in _enemies_near(w, o, bp, float(ac.get("overhang_r", 1.5)) + hs):
				e.cl_block = w.tick + EVERY
		if f.has("firepour") and _due(w, s, id, "f", float(ac.get("firepour_cd_s", 10.0))):
			var near := _enemies_near(w, o, bp, float(ac.get("firepour_r", 2.0)) + hs)
			if near.size() >= int(ac.get("pile", 6)):
				var P = load("res://sim/systems/parts71.gd") if ResourceLoader.exists("res://sim/systems/parts71.gd") else null
				for e in near:
					_hit(w, b, e, float(ac.get("firepour_dmg", 60)), "flame")
					if P != null and P.has_method("ignite") and w.entities.has(int(e.id)):
						P.ignite(w, e, 5.0)
				w.emit("WallFirePour", {"id": int(id), "n": near.size()})
		if f.has("murder") and _due(w, s, id, "m", float(gr.get("murder_every_s", 0.5))):
			for e in _enemies_near(w, o, bp, float(gr.get("murder_r", 3.0)) + hs):
				_hit(w, b, e, float(gr.get("murder_dmg", 30)), "small_arms")
		if f.has("popup") and _due(w, s, id, "p", float(gr.get("popup_cd_s", 6.0))):
			var near2 := _enemies_near(w, o, bp, float(gr.get("murder_r", 3.0)) + 3.0)
			if not near2.is_empty():
				near2.sort_custom(func(a, z): return int(a.id) < int(z.id))
				_hit(w, b, near2[0], float(gr.get("murder_dmg", 30)) * 4.0, "autocannon")
		if f.has("choke"):
			var close := not _enemies_near(w, o, bp, 4.0 + float(b.size)).is_empty()
			var sealed := (s.seal as Dictionary).has(id)
			if close and not sealed:
				s.seal[id] = w.tick + int(float(rw.get("choke_seal_s", 4.0)) * SimWorld.TICK_RATE)
				w.emit("ChokeSealed", {"id": int(id), "on": true})
			elif sealed and not close and w.tick >= int(s.seal[id]):
				(s.seal as Dictionary).erase(id)
				w.emit("ChokeSealed", {"id": int(id), "on": false})


static func _lifts(w: SimWorld, s: Dictionary) -> void:
	if (s.lift as Dictionary).is_empty():
		return
	var ids: Array = (s.lift as Dictionary).keys()
	ids.sort()
	for uid in ids:
		var rec: Array = s.lift[uid]
		var u = w.entities.get(int(uid))
		var b = w.entities.get(int(rec[0]))
		if u == null or b == null:
			(s.lift as Dictionary).erase(uid)
		elif w.tick >= int(rec[1]):
			var to := Vector2(b.pos) + Vector2(0.0, -0.2)
			HotState.set_pos(w, int(uid), to)
			u.pos = to
			(s.lift as Dictionary).erase(uid)
			w.emit("LiftArrived", {"unit": int(uid), "lift": int(rec[0])})


# ---------------------------------------------------------------- dozer (G2)
static func _dz(def_id: String, what: String, v: String) -> bool:
	return (Content.unit(def_id).get("dozer71", {}).get(what, []) as Array).has(v)


## Own dozers among cmd.unit_ids that can do what / v (ascending ids).
static func _dozers(w: SimWorld, cmd: Dictionary, what: String, v: String) -> Array:
	var out := []
	var ids: Array = (cmd.get("unit_ids", []) as Array).duplicate()
	ids.sort()
	for id in ids:
		var u = w.entities.get(int(id))
		if u != null and u.kind == "unit" and int(u.owner) == int(cmd.get("issuer", -2)) and _dz(String(u.def), what, v):
			out.append(u)
	return out


## Own wreck-clearing dozers within r of pos (ascending ids): the hook C3 trench filling (wave 3) calls.
static func dozers_near(w: SimWorld, fid: int, pos: Vector2, r: float) -> Array:
	var out := []
	for u in SimIndex.of(w, "unit"):
		if int(u.owner) == fid and _dz(String(u.def), "clears", "trench") and HotState.get_pos(w, int(u.id)).distance_to(pos) <= r:
			out.append(u)
	out.sort_custom(func(a, z): return int(a.id) < int(z.id))
	return out


static func _doze(w: SimWorld, dz: Dictionary) -> void:
	if dz.is_empty():
		return
	var rd: Dictionary = R().get("doze", {})
	var reach := float(rd.get("reach", 1.5))
	var ids: Array = dz.keys()
	ids.sort()
	for uid in ids:
		var u = w.entities.get(int(uid))
		if u == null or String(u.order.get("type", "")) != "doze":
			dz.erase(uid)   # dozer lost, or the player gave it another order
			continue
		var rec: Array = dz[uid]
		var at := Vector2(float(rec[0]), float(rec[1]))
		if int(rec[2]) == 0:
			var d := HotState.get_pos(w, int(uid)).distance_to(at)
			if d > reach and bool(u.get("moving", false)):
				continue
			if d > reach * 3.0:
				u.order = {"type": "idle"}
				dz.erase(uid)
				w.emit("DozeDone", {"unit": int(uid), "n": 0, "why": "unreachable"})
				continue
			rec[2] = w.tick + 1
		if w.tick < int(rec[2]):
			continue
		var near: Array = SimWorld.Gore71.bodies_near(w, at, float(rd.get("clear_r", 2.5)))
		if near.is_empty():
			u.order = {"type": "idle"}
			dz.erase(uid)
			w.emit("DozeDone", {"unit": int(uid), "n": int(u.get("dz_n", 0)), "why": "clear"})
			u.erase("dz_n")
			continue
		var bd: Dictionary = near[0]
		SimWorld.Gore71.remove(w, int(bd.id))
		u.dz_n = int(u.get("dz_n", 0)) + 1
		w.emit("DozeCleared", {"unit": int(uid), "body": int(bd.id), "kind": String(bd.get("kind", "body")), "pos": Vector2(bd.pos)})
		rec[2] = w.tick + maxi(roundi(float(rd.get("clear_s", 1.5)) * SimWorld.TICK_RATE), 1)


# ---------------------------------------------------------------- commands
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -2))
	match String(cmd.type):
		"berm_build":
			if not LastProtocol.active(w):
				return "Berms are a Last Protocol order."
			if _dozers(w, cmd, "builds", "a_g71_berm").is_empty():
				return "Select a breacher dozer."
			var bc := cmd.duplicate()
			bc.type = "build_line"
			bc.def = "a_g71_berm"
			return Fortify.validate_command(w, bc)
		"doze_clear":
			if not LastProtocol.active(w):
				return "Clearing is a Last Protocol order."
			if _dozers(w, cmd, "clears", "wreck").is_empty():
				return "Select a breacher dozer."
			var at = cmd.get("at")
			if not (at is Array) or (at as Array).size() != 2:
				return "Pick a spot to clear."
			return ""
		"wall_tier":
			for id in cmd.get("building_ids", []):
				var b = w.entities.get(int(id))
				if b == null or int(b.owner) != fid or not is_wall(b):
					return "Not your wall."
			return ""
		"gate_reinforce", "choke_seal":
			var b2 = w.entities.get(int(cmd.get("building_id", -1)))
			if b2 == null or int(b2.owner) != fid or not is_wall(b2):
				return "Not your wall."
			return ""
		"lift_use":
			var b3 = w.entities.get(int(cmd.get("building_id", -1)))
			if b3 == null or int(b3.owner) != fid or not has_fit(w, b3, "lift"):
				return "No lift there."
			return ""
	return "%s: not a wall command" % String(cmd.type)


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	match String(cmd.type):
		"berm_build":
			var bc := cmd.duplicate()
			bc.type = "build_line"
			bc.def = "a_g71_berm"
			var ids := []
			for u in _dozers(w, cmd, "builds", "a_g71_berm"):
				ids.append(int(u.id))
			bc.unit_ids = ids
			Fortify.apply_command(w, bc)
		"doze_clear":
			var s3 := _st(w)
			if not s3.has("doze"):
				s3["doze"] = {}
			var at := Vector2(snappedf(float(cmd.at[0]), 1.0 / 1024.0), snappedf(float(cmd.at[1]), 1.0 / 1024.0))
			for u in _dozers(w, cmd, "clears", "wreck"):
				SimWorld.Construction.make_idle(u)
				u.erase("patrol")
				u.erase("guard")
				u.order = {"type": "doze", "at": [at.x, at.y]}
				SimWorld.Movement.order_path(w, u, at)
				HotState.touch(w, int(u.id))
				s3.doze[int(u.id)] = [at.x, at.y, 0]
		"wall_tier":
			for id in cmd.get("building_ids", []):
				upgrade(w, w.entities[int(id)], int(cmd.get("tier", 1)))
		"gate_reinforce":
			fit(w, w.entities[int(cmd.building_id)], "reinforce")
		"choke_seal":
			var s := _st(w)
			var id := int(cmd.building_id)
			if bool(cmd.get("sealed", true)):
				s.seal[id] = w.tick + 1000000
			else:
				(s.seal as Dictionary).erase(id)
		"lift_use":
			var s2 := _st(w)
			var b: Dictionary = w.entities[int(cmd.building_id)]
			for uid in cmd.get("unit_ids", []):
				var u = w.entities.get(int(uid))
				if u != null and u.kind == "unit" and Vector2(u.pos).distance_to(Vector2(b.pos)) <= float(b.size) + 3.0:
					s2.lift[int(uid)] = [int(b.id), w.tick + int(float(R().get("lift_s", 3.0)) * SimWorld.TICK_RATE)]


# ================================================================ render snapshot provider (RenderSnap.register_g71)
## {"w": [[id, x, y, size, tier, fitbits, sealed]]} for every wall with a tier > 0 or a fit (ascending id), read by
## presentation/view/turret71_look.gd. fitbits = 1 << FITS.find(kind). Read-only: never creates state.
static func snap(w: SimWorld, _snap: Dictionary) -> Dictionary:
	var s = w.sys_state.get("walls71")
	if s == null:
		return {}
	var ids := {}
	for id in (s.tier as Dictionary).keys():
		ids[int(id)] = true
	for id in (s.fit as Dictionary).keys():
		ids[int(id)] = true
	var arr: Array = ids.keys()
	arr.sort()
	var out := []
	for id in arr:
		var b = w.entities.get(id)
		if b == null:
			continue
		var bits := 0
		for k in (s.fit as Dictionary).get(id, []):
			bits |= 1 << maxi(FITS.find(String(k)), 0)
		var sealed := 1 if (s.seal as Dictionary).has(id) else 0
		out.append([id, float(b.pos.x), float(b.pos.y), int(b.size), int((s.tier as Dictionary).get(id, 0)), bits, sealed])
	return {"w": out}


# ================================================================ nanite-resistant coating (G3 tier 3; BASTION71-7)
## Damage multiplier for a hit on wall b: a nanite_coat wall (e.nres, set by upgrade()) takes walls.nanite_resist_mult
## (PROVISIONAL 0.6) of the damage from Machine-owned shooters (nanite disassembly, claws, acid); 1.0 otherwise. Pure
## read, no state. DAMAGE71 calls it from Damage.apply_hit for building targets with nres (CR change_request.damage).
static func nres_mult(w: SimWorld, shooter: Dictionary, b: Dictionary) -> float:
	if not b.has("nres") or shooter == null or not shooter.has("owner"):
		return 1.0
	var o := int(shooter.owner)
	if not w.factions.has(o) or String(w.factions[o].faction_def) != "machine":
		return 1.0
	return float(R().get("nanite_resist_mult", 0.6))
