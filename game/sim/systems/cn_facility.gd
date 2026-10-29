extends RefCounted
## G7 (CNFAC7): Counter-Nanite facility flows (master scope 6.2, 6.9; brainstorm B2, B4, B9, B11, B18).
## The facility def (`cn_facility: true`, Human A / Human B) is a 4x4 core (mission planning room + package lab) inside a
## 32x32 compound (content/g7/defs_g7_facility.json "_g7_facility", PROVISIONAL). When the core completes, the compound
## rises with it in the same order: 4 hardened towers (remote weapon station + counter-drone/interceptor CIWS), the
## armoured gate checkpoint and blast-wall perimeter, all complete, unhackable and needing no base power (backup power).
## Zones (compound-relative rects): gate, staging, decon, pad, helipad, drone_bay, range, workshop, 8 garage slots.
## Flows (tick): training queue (speed x BaseState7.training_mult) -> teams spawn inside their APCs in the garages ->
## cn_rollout: APCs pull onto the loading pad, load (load_time), roll out through the gate (staging smoke) -> released.
## cn_return: APCs drive into the decon zone, are rinsed (crew decontaminated), park in a garage (repair + restock).
## Soldiers on foot in the decon zone walk the walkway: exposure cleared, suits repaired, mimics exposed (THREAT7 hook).
## Package lab queue + 2 tier upgrades; simulation range drills (team XP) only while the base is secure.
## Breach (BaseState7 "breached"): lockdown (garages/lab/helipad sealed, pop-up turrets, counter-nanite mist in decon
## hurting Machine units); evacuation (cn_evacuate, or automatic below evac_core_frac core hp); self-repair when quiet.
## State: w.sys_state.cn_facility = {facs: {"<id>": F}, teams: {"<tid>": T}, next_team}; created only when a facility
## completes, so a match without it is hash-identical (discovery reads only).
## Commands (ORCH registers in world.gd COMMANDS): cn_train {building_id, kind}, cn_cancel_train {building_id},
## cn_rollout {team, target}, cn_return {team}, cn_lab_queue {building_id, package}, cn_lab_upgrade {building_id},
## cn_drill {team, on}, cn_evacuate {building_id}.

const SimIndex = preload("res://sim/systems/sim_index.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Transport = preload("res://sim/systems/transport.gd")
const BaseState7 = preload("res://sim/systems/base_state7.gd")
const Air = preload("res://sim/systems/air.gd")
const G5Mech = preload("res://sim/systems/g5_mech.gd")  # kamikaze extraction drones fly as G5 launched drones

const KEY := "cn_facility"
const CONF_PATH := "res://content/g7/defs_g7_facility.json"
const DISCOVER_EVERY := 10
const FLOW_EVERY := 5          # team phase checks (staggered by team id)
const ZONES := ["gate_outer", "apc_wash", "gate_inner", "decon_hall", "staging", "pad", "helipad", "drone_bay", "range", "workshop", "planning", "lab",
	"magazine", "armory", "aid_station", "barracks", "fuel_point", "runoff"]  # FACB7 (owner 13.9c-6): + special ammo magazine, armory + suit bay, aid station (+ quarantine bay), Sentinel barracks (13.9c-10, was the ready room), fuel / rearm apron, wash runoff tank  # BASE7: + mission planning room; BASE7-2: + package lab; BASE7-3 (13.9c-2): two-layer APC entry (gate_outer -> apc_wash -> gate_inner) + infantry decon hall; the old single "gate" / "decon" are code aliases only (ALIASES), no longer drawn
## BASE7-3: legacy zone names kept for callers (tests, other systems): "gate" = the outer gate layer, "decon" = the APC wash.
const ALIASES := {"gate": "gate_outer", "decon": "apc_wash"}
const PKG_KINDS := ["purge", "seed_hunter", "barrier", "core_breaker"]
const CN_PATH := "res://sim/systems/counter_nanite.gd"
const APC7_PATH := "res://sim/systems/apc7.gd"
const ENG7_PATH := "res://sim/systems/engineer7.gd"   # FACB7-3 (13.9c-11, ENG7 via ORCH): lazy, no preload cycle
const FD7_PATH := "res://sim/systems/fac_drive7.gd"   # APCMOV7 (13.9c-16): facility APC traffic controller, lazy (no preload cycle)

static var _conf: Dictionary = {}
static var _api: Dictionary = {}


static func conf() -> Dictionary:
	if _conf.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONF_PATH)) if FileAccess.file_exists(CONF_PATH) else null
		_conf = parsed["_g7_facility"] if typeof(parsed) == TYPE_DICTIONARY and parsed.has("_g7_facility") else {"compound": 32}
		for a in ALIASES:   # BASE7-3: conf().gate / conf().decon still answer (same rects as gate_outer / apc_wash)
			if not _conf.has(a) and _conf.has(ALIASES[a]):
				_conf[a] = _conf[ALIASES[a]]
	return _conf


## Guarded call into another G7 agent's script (no preload: their in-progress file must not break this one).
static func _callf(path: String, fn: String, args: Array, dflt):
	var key := path + ":" + fn
	if not _api.has(key):
		var s = load(path) if ResourceLoader.exists(path) else null
		var ok := false
		if s != null:
			for m in s.get_script_method_list():
				if String(m.name) == fn:
					ok = true
					break
		_api[key] = s if ok else null
	var sc = _api[key]
	return sc.callv(fn, args) if sc != null else dflt


static func secs(s) -> int:
	return int(round(float(s) * SimWorld.TICK_RATE))


# ================================================================ state access
static func st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {"facs": {}, "teams": {}, "next_team": 1}
	return w.sys_state[KEY]


static func active(w: SimWorld) -> bool:
	return w.sys_state.has(KEY)


static func fac(w: SimWorld, id: int) -> Dictionary:
	if not active(w):
		return {}
	return w.sys_state[KEY].facs.get(str(id), {})


static func team(w: SimWorld, tid: int) -> Dictionary:
	if not active(w):
		return {}
	return w.sys_state[KEY].teams.get(str(tid), {})


## Facility ids of side fid, ascending.
static func facilities(w: SimWorld, fid: int) -> Array:
	var out := []
	if active(w):
		for k in w.sys_state[KEY].facs:
			if int(w.sys_state[KEY].facs[k].owner) == fid:
				out.append(int(k))
	out.sort()
	return out


static func _sorted(d: Dictionary) -> Array:
	var ks := []
	for k in d:
		ks.append(int(k))
	ks.sort()
	return ks


static func origin(F: Dictionary) -> Vector2i:
	return Vector2i(int(F.origin[0]), int(F.origin[1]))


## World rect of a named zone of facility F.
static func zone(F: Dictionary, name: String) -> Rect2:
	var z: Array = conf().get(name, conf().get(ALIASES.get(name, name), [0, 0, 0, 0]))
	return Rect2(Vector2(origin(F)) + Vector2(float(z[0]), float(z[1])), Vector2(float(z[2]), float(z[3])))


## FACB7-4 (owner 13.9c-14): the gunship landing pad on the Sentinel barracks roof: {rect: Rect2 (world tiles, the TLOF),
## centre: Vector2, z: deck height in metres, heading_deg, ok: the barracks still stands}. {} when the conf has none.
static func roof_pad(w: SimWorld, F: Dictionary) -> Dictionary:
	var rp: Dictionary = conf().get("roof_pad", {})
	var r: Array = rp.get("rect", [])
	if F.is_empty() or r.size() != 4:
		return {}
	var rect := Rect2(Vector2(origin(F)) + Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]), float(r[3])))
	var b := int(F.get("bar", 0))
	return {"rect": rect, "centre": rect.get_center(), "z": float(rp.get("deck_z", 0.0)), "heading_deg": float(rp.get("heading_deg", 0.0)),
		"ok": b == 0 or w.entities.has(b)}


## Every zone of facility id as {name: Rect2} plus "garages": [Vector2] and "compound": Rect2 (render / UI).
static func zones(w: SimWorld, id: int) -> Dictionary:
	var F := fac(w, id)
	if F.is_empty():
		return {}
	var out := {}
	for n in ZONES:
		out[n] = zone(F, n)
	out["garages"] = garage_spots(F)
	var cs := int(conf().compound)
	out["compound"] = Rect2(Vector2(origin(F)), Vector2(cs, cs))
	return out


static func garage_spots(F: Dictionary) -> Array:
	var out := []
	for g in conf().get("garages", []):
		out.append(Vector2(origin(F)) + Vector2(float(g[0]) + 0.5, float(g[1]) + 0.5))
	return out


static func compound_rect(F: Dictionary) -> Rect2:
	var cs := float(conf().compound)
	return Rect2(Vector2(origin(F)), Vector2(cs, cs))


static func base_key(id: int) -> String:
	return "cnf_%d" % id


## secure | contested | under_fire | breached for facility id.
static func secure_state(w: SimWorld, id: int) -> String:
	var s := BaseState7.state_of(w, base_key(id))
	return s if s != "" else "secure"


# ================================================================ public API for CNSIM7 / UI / LPMODE7
## Packages drawn from the lab stockpiles of side fid (lowest facility id first). Returns how many were taken.
static func take_packages(w: SimWorld, fid: int, kind: String, n: int) -> int:
	var got := 0
	for id in facilities(w, fid):
		var stock: Dictionary = fac(w, id).stock
		var take := mini(n - got, int(stock.get(kind, 0)))
		stock[kind] = int(stock.get(kind, 0)) - take
		got += take
		if got >= n:
			break
	return got


static func stock(w: SimWorld, fid: int, kind: String) -> int:
	var n := 0
	for id in facilities(w, fid):
		n += int(fac(w, id).stock.get(kind, 0))
	return n


## Lab tier 0..2 of side fid (best facility).
static func package_tier(w: SimWorld, fid: int, _kind: String = "") -> int:
	var t := 0
	for id in facilities(w, fid):
		t = maxi(t, int(fac(w, id).lab.tier))
	return t


static func team_xp(w: SimWorld, tid: int) -> int:
	var T := team(w, tid)
	return int(floor(float(T.get("xp", 0.0))))


static func team_level(w: SimWorld, tid: int) -> int:
	var xp := team_xp(w, tid)
	var lv := 0
	var lvls: Array = conf().get("team_levels", [0])
	for i in lvls.size():
		if xp >= int(lvls[i]):
			lv = i
	return lv


## Render entries (LOOK7 copies them into the snapshot; display only): one per facility,
## {id, owner, zones {name: [x,y,w,h]}, garages [[x,y]...], garage_team [tid|0], lock, evac, state, heli}. [] when none.
static func render_entries(w: SimWorld) -> Array:
	var out := []
	if not active(w):
		return out
	for id in _sorted(w.sys_state[KEY].facs):
		var F: Dictionary = w.sys_state[KEY].facs[str(id)]
		var zs := {}
		for n in ZONES:
			var r := zone(F, n)
			zs[n] = [r.position.x, r.position.y, r.size.x, r.size.y]
		var gs := []
		var gr := []
		var gz: Array = conf().get("garage_size", [3, 3])
		for g in garage_spots(F):
			gs.append([g.x, g.y])
			gr.append([g.x - float(gz[0]) * 0.5, g.y - float(gz[1]) * 0.5, float(gz[0]), float(gz[1])])  # CNFAC7-2: 3x3 garages
		var ln := []  # BASE7: concrete lanes between the zones (display: baseprops_layer)
		var o := Vector2(origin(F))
		for l in conf().get("lanes", []):
			ln.append([o.x + float(l[0]), o.y + float(l[1]), float(l[2]), float(l[3])])
		var cs := float(conf().compound)
		var rpd := roof_pad(w, F)
		out.append({"roof_pad": [] if rpd.is_empty() else [rpd.rect.position.x, rpd.rect.position.y, rpd.rect.size.x, rpd.rect.size.y, rpd.z, rpd.heading_deg, rpd.ok],
			"id": id, "owner": int(F.owner), "zones": zs, "garages": gs, "garage_rects": gr, "garage_team": (F.garages as Array).duplicate(),
			"lanes": ln, "compound": [o.x, o.y, cs, cs], "links": _local_rects(o, conf().get("link_walls", [])),
			"mantrap": _mantrap_state(w, F), "mag": int(F.get("mag", 0)) == 0 or w.entities.has(int(F.get("mag", 0))),
				"cp": int(F.get("cp", 0)), "bar": int(F.get("bar", 0)) == 0 or w.entities.has(int(F.get("bar", 0))),
				"faces": conf().get("faces", {}),
				"stacked": conf().get("stacked", {}),   # FACB7-5 (13.9c-18): upper-storey zones drawn by their host's art
			"gates": _callf(FD7_PATH, "gate_view", [F], ["open", "open", false]),   # APCMOV7-2 (13.9c-22): [outer, inner, hardened]
			"lock": bool(F.lock), "evac": bool(F.evac), "state": secure_state(w, id), "heli": int(F.heli)})
	return out


static func _local_rects(o: Vector2, rs: Array) -> Array:
	var out := []
	for l in rs:
		out.append([o.x + float(l[0]), o.y + float(l[1]), float(l[2]), float(l[3])])
	return out


## FACB7 (13.9c-8): display state of the foot-entry mantrap: [outer door open, inner door open, sealed]. Only one door is
## shown open at a time (airlock): the inner one while an owner soldier stands on the inner cell, else the outer one
## while someone is on the outer cell, else both shut. Display only (the sim gates are open for the owner either way).
static func _mantrap_state(w: SimWorld, F: Dictionary) -> Array:
	var mt: Array = conf().get("mantrap", [])
	if mt.size() < 2:
		return []
	if bool(F.lock):
		return [false, false, true]
	var o := origin(F)
	var occ := [false, false]
	var c0 := o + Vector2i(int(mt[0][0]), int(mt[0][1]))
	var c1 := o + Vector2i(int(mt[1][0]), int(mt[1][1]))
	var box := Rect2(Vector2(c0).min(Vector2(c1)), (Vector2(c0) - Vector2(c1)).abs() + Vector2.ONE)
	for e in SimIndex.of(w, "unit"):
		if not w.entities.has(int(e.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
			continue
		if box.has_point(e.pos) and int(e.owner) == int(F.owner):
			var c := w.cell_of(e.pos)
			occ[0] = occ[0] or c == c0
			occ[1] = occ[1] or c == c1
	return [occ[0] and not occ[1], occ[1], false]


## Team id of a unit spawned by the facility (APC or crew), or 0.
static func team_of(e) -> int:
	return int(e.get("cn_team", 0)) if e != null else 0


# ================================================================ system hooks
static func tick(w: SimWorld) -> void:
	var tq := Time.get_ticks_usec() if SimIndex.profiling else 0   # bench only (PERF7F); never touches state
	Transport.hold_bays(w)  # G7 (CNFAC7-2): dropships in a ramp sequence stay on the ground (runs before Movement / Air)
	if SimIndex.profiling:
		tq = SimIndex.pt("cnf.hold_bays", tq)
	if w.tick % DISCOVER_EVERY == 0:
		_discover(w)
	if SimIndex.profiling:
		tq = SimIndex.pt("cnf.discover", tq)
	if not active(w):
		return
	var S: Dictionary = w.sys_state[KEY]
	if S.has("drones") and w.tick % SimWorld.TICK_RATE == 0:
		for did in _sorted(S.drones):
			if w.tick >= int(S.drones[str(did)]) or not w.entities.has(did):
				S.drones.erase(str(did))
				if w.entities.has(did):
					w.destroy(did, "drone_expired", SimWorld.NEUTRAL)
	for id in _sorted(S.facs):
		var F: Dictionary = S.facs[str(id)]
		if not w.entities.has(id):
			_on_lost(w, F)
			continue
		_tick_fac(w, F)
	if SimIndex.profiling:
		tq = SimIndex.pt("cnf.tick_fac", tq)
	for tid in _sorted(S.teams):
		_tick_team(w, S.teams[str(tid)])
	if SimIndex.profiling:
		SimIndex.pt("cnf.tick_team", tq)


static func _discover(w: SimWorld) -> void:
	for b in SimIndex.of(w, "building"):
		if not w.entities.has(int(b.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
			continue
		if not bool(b.get("built", false)) or not bool(Content.building(String(b.def)).get("cn_facility", false)):
			continue
		if active(w) and w.sys_state[KEY].facs.has(str(int(b.id))):
			continue
		_raise(w, b)


## The core completed: the whole compound rises with it (towers, checkpoint, blast walls), complete, unhackable.
static func _raise(w: SimWorld, b: Dictionary) -> void:
	var c := conf()
	var cs := int(c.compound)
	var O: Vector2i = Vector2i(b.cell) - Vector2i(int(c.core_offset[0]), int(c.core_offset[1]))
	var area := Rect2i(O, Vector2i(cs, cs))
	var occ := {}
	for o in SimIndex.of(w, "building"):
		if not w.entities.has(int(o.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
			continue
		var oc := Vector2i(o.cell)
		var sz := int(o.size)
		if Rect2i(oc, Vector2i(sz, sz)).intersects(area):
			for x in sz:
				for y in sz:
					occ[oc + Vector2i(x, y)] = true
	var id := int(b.id)
	var owner := int(b.owner)
	b.unhackable = true
	var parts := []
	var site := area
	var apr: Array = c.get("approach", [])
	if apr.size() == 4:   # FACB7-4: the gate apron + foot-entry approach (a cleared glacis outside the south wall) too
		site = area.merge(Rect2i(O + Vector2i(int(apr[0]), int(apr[1])), Vector2i(int(apr[2]), int(apr[3]))))
	_clear_site(w, site)   # BASE7-3 (ORCH): the compound stands on flat, cleared ground in every match (one TerrainChanged)
	var reserved := [_crect(c.gate_outer)]
	for t in c.towers:
		reserved.append(Rect2i(Vector2i(int(t[0]), int(t[1])), Vector2i(2, 2)))
	reserved.append(Rect2i(Vector2i(int(c.checkpoint[0]), int(c.checkpoint[1])), Vector2i(2, 2)))
	for t in c.towers:
		_part(w, parts, occ, "cn_tower", O + Vector2i(int(t[0]), int(t[1])), owner, id)
	_part(w, parts, occ, "cn_checkpoint", O + Vector2i(int(c.checkpoint[0]), int(c.checkpoint[1])), owner, id)
	var ring := []
	for x in range(0, cs, 2):
		ring.append(Vector2i(x, 0))
		ring.append(Vector2i(x, cs - 2))
	for y in range(2, cs - 2, 2):
		ring.append(Vector2i(0, y))
		ring.append(Vector2i(cs - 2, y))
	for r in ring:
		var rr := Rect2i(r, Vector2i(2, 2))
		var clash := false
		for res in reserved:
			if rr.intersects(res):
				clash = true
				break
		if not clash:
			_part(w, parts, occ, "cn_blast_wall", O + r, owner, id)
	# BASE7-3 (owner 13.9c-4): small sentry turrets on the inner face of every wall run, facing outward (they fire over
	# the wall; walls do not block fire). Real turrets of the facility owner (turrets7 runs them like any t7 turret).
	var sdef := String(c.get("sentry_def", ""))
	if sdef != "" and not Content.building(sdef).is_empty():
		for q in c.get("sentries", []):
			var sc := Vector2i(int(q[0]), int(q[1]))
			var n0 := parts.size()
			_part(w, parts, occ, sdef, O + sc, owner, id)
			if parts.size() > n0:
				var se: Dictionary = w.entities[int(parts[parts.size() - 1])]
				var ov := Vector2(-1, 0) if sc.x <= 2 else (Vector2(1, 0) if sc.x >= cs - 3 else (Vector2(0, -1) if sc.y <= 2 else Vector2(0, 1)))
				se.facing = ov.angle()
				se.cn_sentry = true
	# FACB7 (owner 13.9c-9): hardened link walls on both sides of the APC wash (outer gate -> enclosed wash -> inner gate)
	var ldef := String(c.get("link_def", ""))
	if ldef != "" and not Content.building(ldef).is_empty():
		for l in c.get("link_walls", []):
			for yy in int(l[3]):
				for xx in int(l[2]):
					_part(w, parts, occ, ldef, O + Vector2i(int(l[0]) + xx, int(l[1]) + yy), owner, id)
	# FACB7 (owner 13.9c-6): the magazine's armoured cell is a real building (priority target, cooks off)
	var mag := 0
	var mp: Array = c.get("magazine_part", [])
	if mp.size() == 2 and not Content.building("cn_magazine").is_empty():
		var n1 := parts.size()
		_part(w, parts, occ, "cn_magazine", O + Vector2i(int(mp[0]), int(mp[1])), owner, id)
		if parts.size() > n1:
			mag = int(parts[parts.size() - 1])
	# FACB7-2 (13.9c-10/-11, -8): SENT7's Sentinel Barracks on the barracks zone, ready-ammo lockers at the tower bases /
	# stairs / entry walkway, and the T-wall baffles of the serpentine approach outside the foot entry
	var bar := 0
	var bp: Array = c.get("barracks_part", [])
	var bdef := String(c.get("barracks_def", ""))
	if bp.size() == 2 and bdef != "" and not Content.building(bdef).is_empty():
		var n2 := parts.size()
		_part(w, parts, occ, bdef, O + Vector2i(int(bp[0]), int(bp[1])), owner, id)
		if parts.size() > n2:
			bar = int(parts[parts.size() - 1])
	for kk in [["locker_def", "lockers"], ["baffle_def", "baffles"]]:
		var dd := String(c.get(kk[0], ""))
		if dd != "" and not Content.building(dd).is_empty():
			for q in c.get(kk[1], []):
				_part(w, parts, occ, dd, O + Vector2i(int(q[0]), int(q[1])), owner, id)
	# EXO7 (13.9c-20): the armory + suit bay is a real part on the armory zone (zone art draws it): it builds the
	# counter-nanite armoured suits (content/g7/defs_g7_cnsuits.json, production facility cn_armory). Spawned last.
	var ap: Array = c.get("armory_part", [])
	var adef := String(c.get("armory_def", ""))
	if ap.size() == 2 and adef != "" and not Content.building(adef).is_empty():
		var na := parts.size()
		_part(w, parts, occ, adef, O + Vector2i(int(ap[0]), int(ap[1])), owner, id)
		# FACB7-6 (13.9c-20c): the Suit Foundry rolls its ~4 m suits out of its east bay doors onto the vehicle lane
		# (armory_exit, compound-local): the production rally, so a new suit appears on the bay floor by the doors
		var ax: Array = c.get("armory_exit", [])
		if parts.size() > na and ax.size() == 2:
			w.entities[int(parts[parts.size() - 1])].rally = Vector2(O) + Vector2(float(ax[0]), float(ax[1]))
	var cp := 0
	for pid in parts:
		if String(w.entities[int(pid)].def) == "cn_checkpoint":
			cp = int(pid)
	var F := {"id": id, "owner": owner, "origin": [O.x, O.y], "parts": parts, "queue": [], "mag": mag, "cp": cp, "bar": bar,
		"garages": [], "lab": {"queue": [], "tier": 0, "up": -1.0}, "stock": {}, "lock": false, "popups": [],
		"evac": false, "heli": 0, "quiet": w.tick}
	for g in (c.get("garages", []) as Array):
		F.garages.append(0)
	for k in PKG_KINDS:
		F.stock[k] = 0
	st(w).facs[str(id)] = F
	if cp != 0:   # FACB7 (13.9c-8): the foot-entry mantrap doors are team gates through the gatehouse (owner only)
		_mantrap(w, F, false)
	_foot_hall(w, F)   # FACB7-7 (13.9c-20c): the decon hall is foot only (no CN suits)
	BaseState7.register(w, base_key(id), owner, area)
	w.emit("CnFacilityRaised", {"id": id, "owner": owner, "origin": Vector2(O), "parts": parts.duplicate()})


## BASE7-3 (ORCH, ART7F-2 shots: a grassy hill + cliff inside the NW corner, a boulder on the staging yard): every cell of
## the compound becomes paved ROAD at plain height (no ramps), and map decor whose footprint touches it is removed;
## resource nodes / deposits and salvage wrecks inside it are removed too (owner 13.9c-5).
## Movement re-reads only the changed cells (a full nav rebuild only when the height changed); TerrainChanged
## {cells, cause "cn_facility"} lets the display re-bake those chunks and drop their terrain decor.
static func _clear_site(w: SimWorld, area: Rect2i) -> void:
	var mw := int(w.map.w)
	var t: PackedByteArray = w.map.terrain
	var hg: PackedByteArray = w.map.get("height", PackedByteArray())
	var rp: PackedByteArray = w.map.get("ramps", PackedByteArray())
	var chg := []
	var cells := []
	var hchg := false
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if not w.in_bounds(c):
				continue
			var i := y * mw + x
			var dirty := false
			if t[i] != Terrain.ROAD:
				t[i] = Terrain.ROAD
				dirty = true
			if i < hg.size() and hg[i] != 1:
				hg[i] = 1
				hchg = true
				dirty = true
			if i < rp.size() and rp[i] != 0:
				rp[i] = 0
				hchg = true
				dirty = true
			if dirty:
				chg.append(i)
				cells.append(c)
	# BASE7-3 (owner 13.9c-5): no ore / salvage / other resource deposit, node or pickup inside the compound, any map
	var gone_ids := []
	for e in w.entities.values():
		if (e.kind == "resource" or e.kind == "wreck") and area.has_point(w.cell_of(e.pos)):
			gone_ids.append(int(e.id))
	gone_ids.sort()
	for gid in gone_ids:
		w.entities.erase(gid)
	if not gone_ids.is_empty():
		w.cache.erase("sim_index")
		w.cache.erase("unit_subsets")
	if w.map.has("resources"):
		var rk := []
		for r in w.map.resources:
			if not area.has_point(Vector2i(r.cell)):
				rk.append(r)
		if rk.size() != (w.map.resources as Array).size():
			w.map.resources = rk
	if chg.is_empty() and not w.map.has("decor"):
		return
	w.map.terrain = t
	if hchg:
		w.map.height = hg
		if not rp.is_empty():
			w.map.ramps = rp
	var keep := []
	var gone := 0
	for d in w.map.get("decor", []):
		var dc: Array = [int(d.cell[0]), int(d.cell[1])] if d.cell is Array else [int(d.cell.x), int(d.cell.y)]
		var sz = d.get("size", [1, 1])
		var ds := Vector2i(int(sz[0]), int(sz[1])) if sz is Array else Vector2i(sz)
		if Rect2i(Vector2i(dc[0], dc[1]), ds.max(Vector2i.ONE)).intersects(area):
			gone += 1
		else:
			keep.append(d)
	if gone > 0:
		w.map.decor = keep
	if chg.is_empty():
		return
	if hchg:
		Movement.on_terrain_changed(w)
	else:
		Movement.on_cells_changed(w, chg)
	w.emit("TerrainChanged", {"cells": cells, "cause": "cn_facility"})


## FACB7 (13.9c-8): sets the two mantrap door cells as gates of the owner's team (locked = sealed), or removes them.
static func _mantrap(w: SimWorld, F: Dictionary, locked: bool, remove: bool = false) -> void:
	var cells := []
	for m in conf().get("mantrap", []):
		cells.append(origin(F) + Vector2i(int(m[0]), int(m[1])))
	if cells.is_empty():
		return
	var f = w.factions.get(int(F.owner))
	var tm := -1 if remove else (int(f.get("team", int(F.owner))) if f != null else int(F.owner))
	_foot_gate(w, cells, tm, locked)   # FACB7-7 (13.9c-20c): foot only (the owner's CN suits never enter the mantrap)


## FACB7-7 (owner 13.9c-20c: CN suits "never the infantry mantrap / decon hall"): the decon hall cells are foot-only
## gates of the owner's team (never locked: lockdown seals the mantrap doors, not the hall). The owner's soldiers walk
## the hall as before; suits / vehicles of every team and enemy soldiers cannot stand in it.
static func _foot_hall(w: SimWorld, F: Dictionary) -> void:
	if not _foot_gates_ok():
		return
	var r := zone(F, "decon_hall")
	var cells := []
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			cells.append(Vector2i(x, y))
	var f = w.factions.get(int(F.owner))
	_foot_gate(w, cells, int(f.get("team", int(F.owner))) if f != null else int(F.owner), false)


## FACB7-7: Movement.set_gate with its foot-only flag (6th argument, movement.gd change_request to ORCH) once the
## loaded movement.gd has it; until then the plain team gate (the old behaviour).
static var _fo_ok = null


static func _foot_gates_ok() -> bool:
	if _fo_ok == null:
		_fo_ok = false
		var mv: Object = Movement
		for m in mv.get_script_method_list():
			if String(m.get("name", "")) == "set_gate" and (m.get("args", []) as Array).size() >= 6:
				_fo_ok = true
	return bool(_fo_ok)


static func _foot_gate(w: SimWorld, cells: Array, tm: int, locked: bool) -> void:
	if tm >= 0 and _foot_gates_ok():
		var mv: Object = Movement   # runtime dispatch: compiles against the current 5-argument set_gate
		mv.callv("set_gate", [w, cells, tm, locked, false, true])
	else:
		Movement.set_gate(w, cells, tm, locked)


static func _crect(a: Array) -> Rect2i:
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


static func _part(w: SimWorld, parts: Array, occ: Dictionary, def_id: String, at: Vector2i, owner: int, fid: int) -> void:
	var sz := int(Content.building(def_id).get("size", 1))
	for x in sz:
		for y in sz:
			var cc := at + Vector2i(x, y)
			if occ.has(cc) or not w.in_bounds(cc):
				return
	var pid := w.spawn_building(def_id, owner, at, true)
	var e: Dictionary = w.entities[pid]
	e.unhackable = true
	e.cn_fac = fid
	parts.append(pid)
	for x in sz:
		for y in sz:
			occ[at + Vector2i(x, y)] = true


## The core is gone: the base perimeter unregisters; surviving parts stay as ordinary structures.
static func _on_lost(w: SimWorld, F: Dictionary) -> void:
	var id := int(F.id)
	BaseState7.unregister(w, base_key(id))
	st(w).facs.erase(str(id))
	w.emit("CnFacilityLost", {"id": id, "owner": int(F.owner)})


static func _tick_fac(w: SimWorld, F: Dictionary) -> void:
	var id := int(F.id)
	var sstate := secure_state(w, id)
	var mult := BaseState7.mult_for(sstate)
	if sstate != "secure":
		F.quiet = w.tick
	if not (F.queue as Array).is_empty():
		var q: Dictionary = F.queue[0]
		q.left = float(q.left) - mult
		if float(q.left) <= 0.0 and _finish_train(w, F, String(q.kind)):
			F.queue.pop_front()
	var lab: Dictionary = F.lab
	if not (lab.queue as Array).is_empty():
		var lq: Dictionary = lab.queue[0]
		lq.left = float(lq.left) - mult
		if float(lq.left) <= 0.0:
			F.stock[String(lq.pkg)] = int(F.stock.get(String(lq.pkg), 0)) + 1
			lab.queue.pop_front()
			w.emit("CnPackageReady", {"fac": id, "owner": int(F.owner), "package": String(lq.pkg), "stock": int(F.stock[String(lq.pkg)])})
	if float(lab.up) >= 0.0:
		lab.up = float(lab.up) - mult
		if float(lab.up) < 0.0:
			lab.up = -1.0
			lab.tier = int(lab.tier) + 1
			w.emit("CnLabTier", {"fac": id, "owner": int(F.owner), "tier": int(lab.tier)})
	if sstate == "breached" and not bool(F.lock):
		_lockdown(w, F, true)
	elif bool(F.lock) and (sstate == "secure" or sstate == "contested"):
		_lockdown(w, F, false)
	if bool(F.lock):
		var core = w.entities.get(id)
		if not bool(F.evac) and core != null and float(core.hp) < float(conf().get("evac_core_frac", 0.35)) * float(core.max_hp):
			evacuate(w, F)
		_hold_seals(w, F)
	if (w.tick + id) % 10 == 0:
		_parts_lost(w, F)
		_sweep_zone(w, F)
		var ds = w.entities.get(int(F.heli))
		if ds != null:
			extraction_drones(w, ds, F)
	var emp: Dictionary = conf().get("emp_field", {})
	if not emp.is_empty() and (w.tick + id) % maxi(1, int(emp.every)) == 0:
		_emp_field(w, F, emp)
	if sstate == "secure" and w.tick - int(F.quiet) >= int(conf().get("self_repair_quiet", 200)) and (w.tick + id) % SimWorld.TICK_RATE == 0:
		_self_repair(w, F)


## Spawns a finished queue item. False (item waits at 100%) when its garages / helipad are not free.
static func _finish_train(w: SimWorld, F: Dictionary, kind: String) -> bool:
	var tc: Dictionary = conf().train.get(kind, {})
	if tc.has("unit"):
		if int(F.heli) != 0 and w.entities.has(int(F.heli)):
			return false
		var hp := zone(F, "helipad").get_center()
		var did := w.spawn_unit(String(tc.unit), int(F.owner), hp)
		var d: Dictionary = w.entities[did]
		d.facing = deg_to_rad(float((conf().get("helipad_craft", {}) as Dictionary).get("facing_deg", 0)))  # CNFAC7-2: ramp toward the compound
		d.cn_fac = int(F.id)
		d.unhackable = true
		Air.land_now(w, d)  # parked on its helipad: vehicles and squads can board it
		if bool(d.get("air_landed", false)) and Vector2(d.pos) != hp:
			d.pos = hp  # CNFAC7-2: centred on the 6x6 pad (its centre is a tile corner; land_now snaps to a tile centre)
			Air._ensure(w, d).pin = hp
		F.heli = did
		w.emit("CnDropshipReady", {"fac": int(F.id), "owner": int(F.owner), "id": did})
		return true
	return spawn_team(w, F, kind) > 0


## A trained team appears inside its APC(s), parked in free garages. Returns the team id, or 0 (no free garages).
## CNSIM7's CounterNanite.spawn_team(w, fid, kind, pos) -> {team, apcs} builds the crews when it exists; else the
## provisional fallback roster (content "_g7_facility".fallback_roster).
static func spawn_team(w: SimWorld, F: Dictionary, kind: String) -> int:
	var need := int((conf().train.get(kind, {}) as Dictionary).get("garages", 1))
	var slots := []
	for i in (F.garages as Array).size():
		if int(F.garages[i]) == 0:
			slots.append(i)
		if slots.size() >= need:
			break
	if slots.size() < need:
		return 0
	var spots := garage_spots(F)
	var owner := int(F.owner)
	var apcs := []
	var ext := 0
	var res = _callf(CN_PATH, "spawn_team", [w, owner, kind, spots[slots[0]]], null)
	if res != null:
		if typeof(res) != TYPE_DICTIONARY or (res.get("apcs", []) as Array).is_empty():
			return 0  # CNSIM7 refused (e.g. the tactical cap): the item waits at 100%
		ext = int(res.get("team", 0))
		for a in res.apcs:
			apcs.append(int(a))
	else:
		var tc := Transport._cache(w)
		for r in conf().get("fallback_roster", {}).get(kind, []):
			var aid := w.spawn_unit(String(r.apc), owner, spots[slots[mini(apcs.size(), slots.size() - 1)]])
			for d in r.crew:
				var uid := w.spawn_unit(String(d), owner, w.entities[aid].pos)
				Transport._load(w, tc, w.entities[aid], w.entities[uid])
			apcs.append(aid)
	apcs.sort()
	var S := st(w)
	var tid := int(S.next_team)
	S.next_team = tid + 1
	for i in apcs.size():
		var a = w.entities.get(int(apcs[i]))
		if a == null:
			continue
		if i < slots.size():
			a.pos = spots[slots[i]]
		a.cn_team = tid
		a.cn_fac = int(F.id)
		for u in a.get("cargo", []):
			u.cn_team = tid
	var used := slots.slice(0, mini(slots.size(), apcs.size()))
	for i in used:
		F.garages[i] = tid
	# G7 (LPMODE7-3): the crews were spawned and boarded in this same tick, so their new ids are already gone from
	# w.entities and Economy's carried pop count (cache eco_pop: new ids still alive + a size check) never sees them.
	# Drop the carried count so the next Economy pass does its full recount (which adds every carrier's cargo).
	w.cache.erase("eco_pop")
	S.teams[str(tid)] = {"id": tid, "fac": int(F.id), "owner": owner, "kind": kind, "apcs": apcs, "slots": used,
		"phase": "garage", "t": 0, "xp": 0.0, "drill": false, "target": [], "ext": ext}
	w.emit("CnTeamReady", {"team": tid, "fac": int(F.id), "owner": owner, "kind": kind, "apcs": apcs.duplicate()})
	return tid


static func _lockdown(w: SimWorld, F: Dictionary, on: bool) -> void:
	F.lock = on
	var owner := int(F.owner)
	if int(F.get("cp", 0)) != 0 and w.entities.has(int(F.cp)):
		_mantrap(w, F, on)   # FACB7 (13.9c-8): lockdown seals both mantrap doors (even the owner's own soldiers)
	if on:
		var occ := {}
		for p in conf().get("popups", []):
			_part(w, F.popups, occ, "cn_popup", origin(F) + Vector2i(int(p[0]), int(p[1])), owner, int(F.id))
		for tid in _teams_of(w, int(F.id)):
			var T := team(w, tid)
			if String(T.phase) == "garage":
				for aid in T.apcs:
					var a = w.entities.get(int(aid))
					if a != null:
						a.cn_sealed = true
						a.cn_seal_hp = float(a.hp)
	else:
		for pid in F.popups:
			var p = w.entities.get(int(pid))
			if p != null:
				w.entities.erase(int(pid))
				Movement.on_footprint_changed(w, Vector2i(p.cell), int(p.size), false)
		F.popups = []
		w.cache.erase("sim_index")
		w.cache.erase("unit_subsets")
		for tid in _teams_of(w, int(F.id)):
			for aid in team(w, tid).apcs:
				var a = w.entities.get(int(aid))
				if a != null:
					a.erase("cn_sealed")
					a.erase("cn_seal_hp")
	w.emit("CnLockdown", {"fac": int(F.id), "owner": owner, "on": on, "popups": (F.popups as Array).duplicate()})


## Blast doors: an APC sealed in its garage takes no lasting damage.
static func _hold_seals(w: SimWorld, F: Dictionary) -> void:
	for tid in _teams_of(w, int(F.id)):
		for aid in team(w, tid).apcs:
			var a = w.entities.get(int(aid))
			if a != null and a.has("cn_seal_hp") and float(a.hp) < float(a.cn_seal_hp):
				a.hp = float(a.cn_seal_hp)


static func _teams_of(w: SimWorld, fid: int) -> Array:
	var out := []
	for tid in _sorted(st(w).teams):
		if int(st(w).teams[str(tid)].fac) == fid:
			out.append(tid)
	return out


## Decon zone (every 10 ticks): friendly soldiers walk the walkway, stopped APCs are rinsed, mimics are exposed;
## during lockdown the zone floods with counter-nanite mist that hurts Machine units.
static func _sweep_zone(w: SimWorld, F: Dictionary) -> void:
	var rect := zone(F, "apc_wash")   # BASE7-3 (13.9c-2): APCs are rinsed between the two gate layers ...
	var hall := zone(F, "decon_hall")   # ... and the infantry walk their own decon hall (foot only)
	var owner := int(F.owner)
	var walk := secs(conf().get("walk_time", 3))
	var rinse := secs(conf().get("rinse_time", 5))
	var mist := float(conf().get("mist_dps", 0.0)) * 0.5 if bool(F.lock) else 0.0
	var mach := String(conf().get("machine_faction", "machine"))
	var dead := []
	var SV := _svc_rects(w, F)
	for e in SimIndex.of(w, "unit"):
		if not w.entities.has(int(e.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
			continue
		var p: Vector2 = e.pos
		if not SV.is_empty() and int(e.owner) == owner and SV.box.has_point(p):
			_service(w, F, e, p, SV)
		var in_hall := hall.has_point(p)
		if not in_hall and e.has("cn_dwh"):
			# FLOWC7 (facint7; 6.2 / 13.9c-7 "walk the decon hall and come out clean"): walking through the 4x3 hall takes
			# ~1 s, under walk_time, so a soldier who walked straight through was never cleaned. One who walked the hall
			# and stepped out into the compound has done the walkway: clean now. Backing out of the hall (outside the
			# compound) does not count.
			e.erase("cn_dwh")
			e.erase("cn_dw")
			if int(e.owner) == owner and compound_rect(F).has_point(p):
				_clean(w, e)
				e.cn_rinsed = w.tick
				w.emit("CnDecon", {"id": int(e.id), "fac": int(F.id), "kind": "walkway"})
			continue
		if not in_hall and not rect.has_point(p):
			continue
		var o := int(e.owner)
		if o != owner:
			if mist > 0.0 and w.factions.has(o) and String(w.factions[o].faction_def) == mach:
				e.hp = float(e.hp) - mist
				if float(e.hp) <= 0.0:
					dead.append([int(e.id), o])
			continue
		if bool(e.get("mimic", false)) and not bool(e.get("mimic_exposed", false)):
			e.mimic_exposed = true
			w.emit("MimicExposed", {"id": int(e.id), "fac": int(F.id), "owner": owner})
		var foot := Transport.cargo_class_of(String(e.def)) == "foot"
		if in_hall and not foot and not rect.has_point(p):
			continue
		var k := "cn_dw" if foot else "cn_rinse"
		if not foot and bool(e.get("moving", false)):
			continue
		e[k] = int(e.get(k, 0)) + 10
		if foot and in_hall:
			e.cn_dwh = true   # FLOWC7: walked into the hall (finished on the way out, see above)
		if int(e[k]) >= (walk if foot else rinse):
			e.erase(k)
			e.erase("cn_dwh")
			_clean(w, e)
			for u in e.get("cargo", []):
				_clean(w, u)
			e.cn_rinsed = w.tick
			w.emit("CnDecon", {"id": int(e.id), "fac": int(F.id), "kind": "walkway" if foot else "rinse"})
	for d in dead:
		w.destroy(int(d[0]), "cn_mist", owner)


# ================================================================ FACB7 (owner 13.9c-6): facility services
## Service areas of facility F (world rects; {} when the conf has none of them). box = their union (one cheap test).
static func _svc_rects(w: SimWorld, F: Dictionary) -> Dictionary:
	if not conf().has("armory"):
		return {}
	var c := conf()
	var o := Vector2(origin(F))
	var cp: Array = c.get("checkpoint", [0, 0])
	var SV := {"arm": zone(F, "armory"), "aid": zone(F, "aid_station"), "mag": zone(F, "magazine").grow(1.5),
		"gh": Rect2(o + Vector2(float(cp[0]), float(cp[1])), Vector2(2, 2)),
		"air": [zone(F, "helipad"), zone(F, "pad"), zone(F, "fuel_point")], "mag_ok": mag_ok(w, F), "sv": c.get("services", {})}
	var rpd := roof_pad(w, F)
	if not rpd.is_empty() and bool(rpd.ok):   # FACB7-4: the barracks roof pad refuels / rearms a landed aircraft too
		(SV.air as Array).append(rpd.rect)
	var box: Rect2 = SV.arm.merge(SV.aid).merge(SV.mag).merge(SV.gh)
	for r in SV.air:
		box = box.merge(r)
	SV.box = box
	return SV


## The magazine still stands (true for a facility raised before the magazine existed).
static func mag_ok(w: SimWorld, F: Dictionary) -> bool:
	var m := int(F.get("mag", 0))
	return m == 0 or (m > 0 and w.entities.has(m))


## One owner unit inside a service area (every 10 ticks): armory / suit bay, aid station + quarantine, magazine,
## fuel / rearm apron, gatehouse ID scan. Deterministic, saved entity fields (cn_sb, cn_quar, cn_magrs).
static func _service(w: SimWorld, F: Dictionary, e: Dictionary, p: Vector2, SV: Dictionary) -> void:
	var sv: Dictionary = SV.sv
	var dt := 10.0 / float(SimWorld.TICK_RATE)
	var d := Content.unit(String(e.def))
	if bool(d.get("is_air", false)):
		if not bool(e.get("air_landed", false)):
			return
		for r in SV.air:
			if (r as Rect2).has_point(p):
				var did := false
				# FACB7-3 (13.9c-11): the Facility Engineers refuel with the bowser while the facility is staffed; the pad
				# refuels by itself only when no engineer of this facility is alive (the old behaviour)
				if e.has("fuel") and float(e.fuel) < float(d.get("fuel_max", 0.0)) and not bool(_callf(ENG7_PATH, "staffed", [w, F], false)):
					e.fuel = minf(float(d.get("fuel_max", 0.0)), float(e.fuel) + float(sv.get("fuel_s", 40.0)) * dt)
					did = true
				if int(d.get("ammo_max", 0)) > 0 and int(e.get("ammo", 0)) < int(d.ammo_max):
					e.ammo = int(d.ammo_max)
					did = true
				if int(e.get("cn_drone_ready", 0)) > w.tick and SV.mag_ok:   # drone racks re-armed on the pad
					e.cn_drone_ready = w.tick
					did = true
				if did:
					w.emit("CnRefuel", {"id": int(e.id), "fac": int(F.id), "fuel": float(e.get("fuel", 0.0))})
				return
		return
	var foot := Transport.cargo_class_of(String(e.def)) == "foot"
	if not foot:
		if e.has("a7") and SV.mag_ok and SV.mag.has_point(p) and not bool(e.get("moving", false)) and w.tick >= int(e.get("cn_magrs", 0)):
			e.cn_magrs = w.tick + secs(30)
			_callf(APC7_PATH, "restock", [w, e], null)
			w.emit("CnMagazineIssue", {"id": int(e.id), "fac": int(F.id), "kind": "apc"})
		return
	if SV.mag_ok and SV.mag.has_point(p) and e.has("lim_n"):
		e.erase("lim_n")   # limpets / special charges drawn back to the full carry
		w.emit("CnMagazineIssue", {"id": int(e.id), "fac": int(F.id), "kind": "foot"})
	if SV.arm.has_point(p):   # armory + suit bay: weapons issue, punctured suit resealed after suit_s
		if bool(e.get("wpunct", false)):
			e.cn_sb = int(e.get("cn_sb", 0)) + 10
			if int(e.cn_sb) >= secs(sv.get("suit_s", 3)):
				e.erase("cn_sb")
				e.erase("wpunct")
				_callf(CN_PATH, "_render", [w, e], null)
				w.emit("CnSuitRepaired", {"id": int(e.id), "fac": int(F.id)})
		if SV.mag_ok and e.has("lim_n"):
			e.erase("lim_n")
	elif SV.aid.has_point(p):   # aid station: bleeding stopped, hp restored, nanite exposure treated; quarantine bay
		var hit := false
		if float(e.get("wb", 0.0)) > 0.0 and not bool(e.get("wstab", false)):
			e.wstab = true
			hit = true
		var mh := float(e.get("max_hp", d.get("hp", 100)))
		if float(e.hp) < mh:
			e.hp = minf(mh, float(e.hp) + float(sv.get("aid_hp_s", 6.0)) * dt)
			hit = true
		var x := float(e.get("cn_exp", 0.0))
		if x >= float(sv.get("quarantine_exp", 0.5)) and not e.has("cn_quar"):
			e.cn_quar = w.tick + secs(sv.get("quarantine_s", 12))
			if bool(e.get("mimic", false)) and not bool(e.get("mimic_exposed", false)):
				e.mimic_exposed = true
				w.emit("MimicExposed", {"id": int(e.id), "fac": int(F.id), "owner": int(F.owner)})
			w.emit("CnQuarantine", {"id": int(e.id), "fac": int(F.id), "on": true})
		if x > 0.0:
			x -= float(sv.get("aid_exp_s", 0.25)) * dt
			if x <= 0.0:
				e.erase("cn_exp")
				e.erase("cn_slow")
				_callf(CN_PATH, "_render", [w, e], null)
			else:
				e.cn_exp = snappedf(x, 1.0 / 1024.0)
			hit = true
		if e.has("cn_quar") and w.tick >= int(e.cn_quar) and float(e.get("cn_exp", 0.0)) <= 0.0:
			e.erase("cn_quar")
			w.emit("CnQuarantine", {"id": int(e.id), "fac": int(F.id), "on": false})
		if hit:
			e.cn_aid = w.tick
	elif SV.gh.has_point(p) and bool(e.get("mimic", false)) and not bool(e.get("mimic_exposed", false)):
		e.mimic_exposed = true   # gatehouse ID / scan station
		w.emit("MimicExposed", {"id": int(e.id), "fac": int(F.id), "owner": int(F.owner)})


## FACB7: the gatehouse fell (its mantrap gates go with it) / the magazine was destroyed (it cooks off, resupply stops).
static func _parts_lost(w: SimWorld, F: Dictionary) -> void:
	var cp := int(F.get("cp", 0))
	if cp > 0 and not w.entities.has(cp):
		F.cp = -1
		_mantrap(w, F, false, true)
		w.emit("CnEntryBreached", {"fac": int(F.id), "owner": int(F.owner)})
	var mg := int(F.get("mag", 0))
	if mg > 0 and not w.entities.has(mg):
		F.mag = -1
		var mp: Array = conf().get("magazine_part", [0, 0])
		var at := Vector2(origin(F)) + Vector2(float(mp[0]) + 1.0, float(mp[1]) + 1.0)
		var ck: Dictionary = conf().get("services", {}).get("cookoff", {})
		var r := float(ck.get("radius", 4.0))
		var dmg := float(ck.get("dmg", 900.0))
		var dead := []
		for kind in ["unit", "building"]:
			for e in SimIndex.of(w, kind):
				var dd := Vector2(e.pos).distance_to(at)
				if dd <= r and w.entities.has(int(e.id)):
					e.hp = float(e.hp) - dmg * (1.0 - 0.6 * dd / r)
					if float(e.hp) <= 0.0:
						dead.append(int(e.id))
		dead.sort()
		for id in dead:
			if w.entities.has(id):
				w.destroy(id, "cn_cookoff", SimWorld.NEUTRAL)
		w.emit("CnMagazineLost", {"fac": int(F.id), "owner": int(F.owner), "at": at, "killed": dead.size()})


## Clears exposure and repairs a punctured suit (CNSIM7's CounterNanite.decontaminate when it exists).
static func _clean(w: SimWorld, e: Dictionary) -> void:
	_callf(CN_PATH, "decontaminate", [w, e], null)
	for k in ["exposure", "cn_exposure"]:
		if e.has(k):
			e[k] = 0.0
	for k in ["suit_breached", "suit_punctured", "punctured"]:
		if e.has(k):
			e[k] = false


## Short-range EMP field: hostile Machine units within 2 tiles of the compound are stunned (emp_until).
static func _emp_field(w: SimWorld, F: Dictionary, emp: Dictionary) -> void:
	var r := compound_rect(F).grow(2.0)
	var mach := String(conf().get("machine_faction", "machine"))
	var owner := int(F.owner)
	for e in SimIndex.of(w, "unit"):
		var o := int(e.owner)
		if o == owner or not w.is_enemy(owner, o) or not r.has_point(e.pos) or not w.entities.has(int(e.id)):
			continue
		if bool(emp.get("machine_only", true)) and String(w.factions[o].faction_def) != mach:
			continue
		e.emp_until = maxi(int(e.get("emp_until", -1)), w.tick + int(emp.stun))


## Facility engineers repair the core, towers and walls between attacks (once a second while quiet and secure).
static func _self_repair(w: SimWorld, F: Dictionary) -> void:
	var frac := float(conf().get("self_repair_frac_s", 0.004))
	var ids := [int(F.id)]
	ids.append_array(F.parts)
	for pid in ids:
		var p = w.entities.get(int(pid))
		if p != null and float(p.hp) < float(p.max_hp):
			p.hp = minf(float(p.max_hp), float(p.hp) + frac * float(p.max_hp))


## Emergency evacuation: every team still inside rolls out at once, the dropship lifts off the helipad.
static func evacuate(w: SimWorld, F: Dictionary) -> void:
	F.evac = true
	var out := evac_point(F)
	for tid in _teams_of(w, int(F.id)):
		var T := team(w, tid)
		if ["garage", "to_pad", "loading", "returning", "to_garage"].has(String(T.phase)):
			T.target = [out.x, out.y]
			_start_rollout(w, T)
	var ds = w.entities.get(int(F.heli))
	if ds != null:
		Movement.order_move(w, ds, out + Vector2(4, 0))
	w.emit("CnEvacuation", {"fac": int(F.id), "owner": int(F.owner), "to": out})


## Stealth dropship extraction defence: landed / hovering away from its helipad with hostiles within radius, it
## launches its drones (3 kamikaze, 2 machine-gun; def extract_drones) at the nearest threats, then a long cooldown.
## Returns the launched drone ids.
static func extraction_drones(w: SimWorld, ds: Dictionary, F: Dictionary = {}) -> Array:
	var launched := []
	var ed: Dictionary = Content.unit(String(ds.def)).get("extract_drones", {})
	if ed.is_empty() or w.tick < int(ds.get("cn_drone_ready", 0)) or bool(ds.get("moving", false)):
		return launched
	if not F.is_empty() and zone(F, "helipad").has_point(ds.pos):
		return launched
	var owner := int(ds.owner)
	var r := float(ed.get("radius", 12))
	var p0: Vector2 = ds.pos
	var near := []
	for e in SimIndex.of(w, "unit"):
		if w.is_enemy(owner, int(e.owner)) and p0.distance_to(e.pos) <= r and w.entities.has(int(e.id)):   # DET7 CR 6999: skip destroyed entries still in the SimIndex (a loaded world's index has none)
			near.append(e)
	if near.is_empty():
		return launched
	near.sort_custom(func(a, b) -> bool:
		var da := p0.distance_squared_to(a.pos)
		var db := p0.distance_squared_to(b.pos)
		return da < db if da != db else int(a.id) < int(b.id))
	var i := 0
	var kz = ed.get("kamikaze")
	if typeof(kz) == TYPE_ARRAY:  # kamikaze: G5 launched strike drones (they fly to the target and detonate)
		ds.drone_charges = int(kz[1]) + 1
		for n in int(kz[1]):
			var tg: Dictionary = near[i % near.size()]
			i += 1
			launched.append(G5Mech._launch(w, ds, String(kz[0]), int(tg.id), Vector2(tg.pos)))
		ds.erase("drone_charges")
		ds.erase("dmode")
	var gun = ed.get("gun")
	if typeof(gun) == TYPE_ARRAY and not Content.unit(String(gun[0])).is_empty():
		var S := st(w)
		if not S.has("drones"):
			S.drones = {}
		for n in int(gun[1]):
			var did := w.spawn_unit(String(gun[0]), owner, p0)
			var d: Dictionary = w.entities[did]
			var tp: Vector2 = near[i % near.size()].pos
			i += 1
			Movement.order_move(w, d, tp)
			d.order = {"type": "attack_move", "target": tp, "engaged": false}
			d.cn_escort = int(ds.id)
			S.drones[str(did)] = w.tick + secs(ed.get("gun_life_s", 60))
			launched.append(did)
	ds.cn_drone_ready = w.tick + int(ed.get("cooldown", 3600))
	w.emit("CnExtractionDrones", {"dropship": int(ds.id), "owner": owner, "drones": launched.duplicate()})
	return launched


static func evac_point(F: Dictionary) -> Vector2:
	var g := zone(F, "gate_outer")  # BASE7: staging moved inside the compound; the evacuation point stays outside the gate
	return g.get_center() + Vector2(0, 6)


static func _start_rollout(w: SimWorld, T: Dictionary) -> void:
	for a in _apcs(w, T):
		a.erase("cn_sealed")
		a.erase("cn_seal_hp")
	T.phase = "to_pad"
	T.t = 0
	_order_slots(w, T, "pad")


static func _apcs(w: SimWorld, T: Dictionary) -> Array:
	var out := []
	for aid in T.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			out.append(a)
	return out


## Orders the team's APCs to their slot in a zone ("pad" spread in a row, "garage" = own slots).
static func _order_slots(w: SimWorld, T: Dictionary, where: String) -> void:
	var F := fac(w, int(T.fac))
	if F.is_empty():
		return
	var aps := _apcs(w, T)
	if _callf(FD7_PATH, "order_team", [w, T, aps, where], false) == true:
		return   # APCMOV7 (13.9c-16): the facility traffic controller drives them on the lanes (smooth, no overlaps)
	for i in aps.size():
		Movement.order_move(w, aps[i], _slot_pos(F, T, where, i))


static func _slot_pos(F: Dictionary, T: Dictionary, where: String, i: int) -> Vector2:
	match where:
		"pad":
			var r := zone(F, "pad")
			return r.get_center() + Vector2((float(i) - 0.5 * float(maxi(0, (T.apcs as Array).size() - 1))) * 3.0, 0.0)
		"gate":
			return zone(F, "staging").get_center() + Vector2(float(i) * 2.0 - 1.0, 0.0)
		"decon":   # BASE7-3: the APCs stop nose to tail in the wash lane between the two gate layers
			var n := maxi(1, (T.apcs as Array).size())
			return zone(F, "apc_wash").get_center() + Vector2(0.0, (float(i) - 0.5 * float(n - 1)) * 2.0)
		"inner":
			var n := maxi(1, (T.apcs as Array).size())
			return zone(F, "gate_inner").get_center() + Vector2(0.0, (float(i) - 0.5 * float(n - 1)) * 1.0)
	var spots := garage_spots(F)
	var sl: Array = T.slots
	return spots[int(sl[mini(i, sl.size() - 1)])] if not sl.is_empty() else zone(F, "pad").get_center()


## Team phases: garage -> to_pad -> loading -> to_gate -> out; out -> returning -> (rinse) -> to_garage -> garage.
static func _tick_team(w: SimWorld, T: Dictionary) -> void:
	var tid := int(T.id)
	if (w.tick + tid) % FLOW_EVERY != 0:
		return
	var aps := _apcs(w, T)
	if aps.is_empty():
		var aboard := false
		for aid in T.apcs:
			if Transport.in_cargo(w, int(aid)):
				aboard = true
		if not aboard:
			_drop_team(w, T)
			return
	var F := fac(w, int(T.fac))
	var ph := String(T.phase)
	match ph:
		"garage":
			if bool(T.drill) and not F.is_empty() and secure_state(w, int(F.id)) == "secure":
				T.xp = float(T.xp) + float(conf().get("drill_xp_s", 2.0)) * float(FLOW_EVERY) / SimWorld.TICK_RATE
			var rep := float(conf().get("repair_hp_s", 25)) * float(FLOW_EVERY) / SimWorld.TICK_RATE
			for a in aps:
				if float(a.hp) < float(a.max_hp) and not bool(a.get("moving", false)):
					a.hp = minf(float(a.max_hp), float(a.hp) + rep)
		"to_pad":
			if _arrived(w, T, aps, "pad", 1.6):
				T.phase = "loading"
				T.t = secs(conf().get("load_time", 6))
				w.emit("CnLoading", {"team": tid, "fac": int(T.fac), "owner": int(T.owner)})
		"loading":
			T.t = int(T.t) - FLOW_EVERY
			if int(T.t) <= 0:
				T.phase = "to_gate"
				_order_slots(w, T, "gate")
				if not F.is_empty():
					w.emit("CnRollout", {"team": tid, "fac": int(T.fac), "owner": int(T.owner), "smoke": zone(F, "staging").get_center()})
		"to_gate":
			if _arrived(w, T, aps, "gate", 2.5):
				T.phase = "out"
				var tg: Array = T.target
				if tg.size() == 2:
					for a in aps:
						Movement.order_move(w, a, Vector2(float(tg[0]), float(tg[1])))
				w.emit("CnTeamOut", {"team": tid, "fac": int(T.fac), "owner": int(T.owner)})
		"returning":
			var all_clean := true
			for a in aps:
				if int(a.get("cn_rinsed", -1)) < int(T.t):
					all_clean = false
			if all_clean:   # BASE7-3 (13.9c-2): rinsed in the wash -> through the inner gate layer -> garage
				T.phase = "to_inner"
				_order_slots(w, T, "inner")
		"to_inner":
			if _arrived(w, T, aps, "inner", 1.6):
				T.phase = "to_garage"
				_order_slots(w, T, "garage")
		"to_garage":
			if _arrived(w, T, aps, "garage", 1.2):
				T.phase = "garage"
				for a in aps:
					if mag_ok(w, F):   # FACB7: special rounds come from the magazine; none once it is destroyed
						_callf(APC7_PATH, "restock", [w, a], null)
				w.emit("CnTeamParked", {"team": tid, "fac": int(T.fac), "owner": int(T.owner)})


## True when every APC of T stands at its slot of `where` (or stopped trying to get there).
static func _arrived(w: SimWorld, T: Dictionary, aps: Array, where: String, tol: float) -> bool:
	var F := fac(w, int(T.fac))
	if F.is_empty():
		return true
	for i in aps.size():
		var a: Dictionary = aps[i]
		var p: Vector2 = a.pos
		if p.distance_to(_slot_pos(F, T, where, i)) > tol and String(a.order.get("type", "")) == "move":
			return false
	return true


static func _drop_team(w: SimWorld, T: Dictionary) -> void:
	var F := fac(w, int(T.fac))
	if not F.is_empty():
		for i in (F.garages as Array).size():
			if int(F.garages[i]) == int(T.id):
				F.garages[i] = 0
	st(w).teams.erase(str(int(T.id)))
	w.emit("CnTeamLost", {"team": int(T.id), "owner": int(T.owner)})


# ================================================================ commands
static func _cmd_fac(w: SimWorld, cmd: Dictionary) -> Dictionary:
	return fac(w, int(cmd.get("building_id", -1)))


static func _cmd_team(w: SimWorld, cmd: Dictionary) -> Dictionary:
	var T := team(w, int(cmd.get("team", -1)))
	return T if not T.is_empty() and int(T.owner) == int(cmd.issuer) else {}


static func _count_kind(w: SimWorld, fid: int, kind: String) -> int:
	var n := 0
	if not active(w):
		return 0
	for k in w.sys_state[KEY].teams:
		var T: Dictionary = w.sys_state[KEY].teams[k]
		if int(T.owner) == fid and String(T.kind) == kind:
			n += 1
	for k in w.sys_state[KEY].facs:
		var F: Dictionary = w.sys_state[KEY].facs[k]
		if int(F.owner) == fid:
			for q in F.queue:
				if String(q.kind) == kind:
					n += 1
	return n


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	match t:
		"cn_train", "cn_cancel_train", "cn_lab_queue", "cn_lab_upgrade", "cn_evacuate":
			var F := _cmd_fac(w, cmd)
			if F.is_empty():
				return "That is not a Counter-Nanite facility."
			match t:
				"cn_train":
					var kind := String(cmd.get("kind", ""))
					var tc = conf().train.get(kind)
					if tc == null:
						return "Unknown training order."
					var cap := int(w.cfg.get("cn_cap_" + kind, int(tc.get("cap", 0))))
					if kind == "stealth_dropship":
						var busy := int(F.heli) != 0 and w.entities.has(int(F.heli))
						for q in F.queue:
							busy = busy or String(q.kind) == kind
						if busy:
							return "The helipad already has its dropship."
					elif cap > 0 and _count_kind(w, int(cmd.issuer), kind) >= cap:
						return "At most %d of these." % cap
					if kind == "tactical_squad":
						var why = _callf(CN_PATH, "tac_reason", [w, int(cmd.issuer)], "")
						if typeof(why) == TYPE_STRING and why != "":
							return why
					return w.can_afford(int(cmd.issuer), tc.get("cost", {}))
				"cn_cancel_train":
					return "Nothing in training." if (F.queue as Array).is_empty() else ""
				"cn_lab_queue":
					var pk = conf().packages.get(String(cmd.get("package", "")))
					if pk == null:
						return "Unknown package."
					return w.can_afford(int(cmd.issuer), pk.get("cost", {}))
				"cn_lab_upgrade":
					var tiers: Array = conf().get("lab_tiers", [])
					if int(F.lab.tier) >= tiers.size() or float(F.lab.up) >= 0.0:
						return "No lab upgrade available."
					return w.can_afford(int(cmd.issuer), tiers[int(F.lab.tier)].get("cost", {}))
				"cn_evacuate":
					return "Already evacuating." if bool(F.evac) else ""
		"cn_rollout", "cn_drill":
			var T := _cmd_team(w, cmd)
			if T.is_empty():
				return "Not your team."
			return "" if String(T.phase) == "garage" else "The team is not in its garage."
		"cn_return":
			var T := _cmd_team(w, cmd)
			if T.is_empty():
				return "Not your team."
			return "" if String(T.phase) == "out" and not fac(w, int(T.fac)).is_empty() else "The team cannot return now."
	return "%s: not a facility command" % t


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var t := String(cmd.get("type", ""))
	var fid := int(cmd.issuer)
	match t:
		"cn_train":
			var F := _cmd_fac(w, cmd)
			var kind := String(cmd.kind)
			var tc: Dictionary = conf().train[kind]
			if w.spend(fid, tc.get("cost", {}), "cn_train"):
				F.queue.append({"kind": kind, "left": float(secs(tc.time)), "total": secs(tc.time), "paid": tc.get("cost", {}).duplicate()})
		"cn_cancel_train":
			var F := _cmd_fac(w, cmd)
			var q: Dictionary = F.queue.pop_back()
			w.credit(fid, q.get("paid", {}), "cn_cancel_train")
		"cn_lab_queue":
			var F := _cmd_fac(w, cmd)
			var pk: Dictionary = conf().packages[String(cmd.package)]
			if w.spend(fid, pk.get("cost", {}), "cn_lab"):
				F.lab.queue.append({"pkg": String(cmd.package), "left": float(secs(pk.time))})
		"cn_lab_upgrade":
			var F := _cmd_fac(w, cmd)
			var tier: Dictionary = conf().lab_tiers[int(F.lab.tier)]
			if w.spend(fid, tier.get("cost", {}), "cn_lab_upgrade"):
				F.lab.up = float(secs(tier.time))
		"cn_evacuate":
			evacuate(w, _cmd_fac(w, cmd))
		"cn_rollout":
			var T := _cmd_team(w, cmd)
			var tg = cmd.get("target")
			T.target = [float(tg.x), float(tg.y)] if typeof(tg) == TYPE_VECTOR2 else ([float(tg[0]), float(tg[1])] if typeof(tg) == TYPE_ARRAY and tg.size() == 2 else [])
			T.drill = false
			_start_rollout(w, T)
		"cn_drill":
			var T := _cmd_team(w, cmd)
			T.drill = bool(cmd.get("on", true))
		"cn_return":
			var T := _cmd_team(w, cmd)
			T.phase = "returning"
			T.t = w.tick
			_order_slots(w, T, "decon")
