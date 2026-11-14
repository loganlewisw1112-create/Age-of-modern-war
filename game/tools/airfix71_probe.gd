extends RefCounted
## AIRFIX71 (G7.1 A1) headless repro / matrix probe. Puts one craft of each of the 4 types (helicopter, regular VTOL
## dropship, CN stealth dropship, CN Vanta) through a return trigger and logs every LOG_EVERY ticks: phase, landed,
## distance to its home pad point and to the nearest building centre. Used by tests/test_airfix71.gd.
## Triggers: "low_fuel" (fuel set to 15%), "dry" (mission complete: ammo 0 / Air._go_home for unarmed craft),
## "manual" (the player's return: rebase to home for helicopters, vanta_rtb, Air._go_home for dropships).

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Vanta7 = preload("res://sim/systems/vanta7.gd")
const Air = preload("res://sim/systems/air.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")

const TYPES := ["heli", "vtol", "cn", "vanta"]
const LOG_EVERY := 100


static func _g7() -> void:
	if Content.unit("cn_vanta_a").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


## Skirmish: a cleared 60x60 grass square with a CN facility, an a_helipad, a dropship pad and one craft of each type.
static func setup_skirmish() -> Dictionary:
	_g7()
	var c := SimWorld.default_config()
	c.sides[1].ai = false
	var w := SimWorld.new_match(c)
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(84, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if r.has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	var off: Array = CnFacility.conf().core_offset
	w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	var hp := w.spawn_building("a_helipad", 0, o + Vector2i(6, n - 8), true)
	var vp := w.spawn_building("a_g7_vtol_pad", 0, o + Vector2i(16, n - 10), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	var out := {"w": w, "pads": {"heli": hp, "vtol": vp}}
	var heli := w.spawn_unit("a_attack_heli", 0, Vector2(w.entities[hp].pos))
	var vt := w.spawn_unit("a_vtol_dropship", 0, Vector2(w.entities[vp].pos))
	w.run_ticks(1)
	Air.land_now(w, w.entities[vt])
	var F := _fac(w)
	CnFacility._finish_train(w, F, "stealth_dropship")
	var rp := Vanta7.pad_of(w, int(CnFacility.facilities(w, 0)[0]))
	var va := w.spawn_unit("cn_vanta_a", 0, Vector2(rp.centre) + Vector2(3, 3))
	w.run_ticks(2)
	out.ids = {"heli": heli, "vtol": vt, "cn": int(F.heli), "vanta": va}
	return out


## Last Protocol (real LP map + setup): the start helicopters / VTOLs / stealth dropship, plus a Vanta on the roof pad.
static func setup_lp() -> Dictionary:
	_g7()
	var w := SimWorld.new_match(LastProtocol.make_config(77, "last_protocol"))
	w.run_ticks(CnFacility.DISCOVER_EVERY + 2)
	var ids := {}
	for e in SimIndex.of(w, "unit"):
		if int(e.owner) != 0 or not Air.is_aircraft(e):
			continue
		var d := Air.adef(e)
		if not ids.has("heli") and String(d.aircraft) == "heli":
			ids.heli = int(e.id)
		elif not ids.has("vtol") and Air.regular_dropship(d):
			ids.vtol = int(e.id)
	var F := _fac(w)
	if not F.is_empty():
		ids.cn = int(F.heli)
		var rp := Vanta7.pad_of(w, int(CnFacility.facilities(w, 0)[0]))
		if not rp.is_empty():
			ids.vanta = w.spawn_unit("cn_vanta_a", 0, Vector2(rp.centre) + Vector2(3, 3))
	w.run_ticks(2)
	return {"w": w, "ids": ids}


static func _fac(w: SimWorld) -> Dictionary:
	var fs: Array = CnFacility.facilities(w, 0)
	return CnFacility.fac(w, int(fs[0])) if not fs.is_empty() else {}


static func clone(w: SimWorld) -> SimWorld:
	return SimWorld.from_dict(w.to_dict().duplicate(true))


## The craft's home pad landing point: the Pads71 home when it has one, else what each system treats as home today.
static func home_point(w: SimWorld, e: Dictionary) -> Vector2:
	var hk := Pads71.home(w, int(e.id))
	if hk != "" and Pads71.has_pad(w, hk):
		return Pads71.pos_of(w, hk)
	var d := Air.adef(e)
	if bool(d.get("cn_vanta", false)):
		var rp := Vanta7.pad_of(w, int(Vanta7.rec(w, int(e.id)).get("fac", 0)))
		return Vector2(rp.centre) if not rp.is_empty() else Vector2(-1, -1)
	if bool(d.get("cn_dropship", false)):
		for fk in CnFacility.facilities(w, int(e.owner)):
			var F := CnFacility.fac(w, int(fk))
			if int(F.get("heli", 0)) == int(e.id):
				return CnFacility.zone(F, "helipad").get_center()
	if Air.regular_dropship(d) and w.entities.has(int(e.get("vpad", -1))):
		return Vector2(w.entities[int(e.vpad)].pos)
	var h = w.entities.get(int(e.get("air_home", -1)))
	return Vector2(h.pos) if h != null else Vector2(-1, -1)


## Nearest building to p: [distance to its centre, def, contains p in its footprint].
static func near_building(w: SimWorld, p: Vector2) -> Array:
	var best := [INF, "", false]
	for b in SimIndex.of(w, "building"):
		var dd := Vector2(b.pos).distance_to(p)
		if dd < float(best[0]):
			var o: Vector2i = b.cell
			var inside := p.x >= o.x and p.y >= o.y and p.x < o.x + int(b.size) and p.y < o.y + int(b.size)
			best = [dd, String(b.def), inside]
	return best


## Lifts craft id, moves it `away` tiles from home, applies trigger, runs ticks; returns {log: [lines], end: {...}}.
static func run_case(w: SimWorld, id: int, trigger: String, ticks: int, away := Vector2(14, -10)) -> Dictionary:
	var e: Dictionary = w.entities[id]
	var home0 := home_point(w, e)
	var f: Dictionary = Air._ensure(w, e)
	if bool(e.get("air_landed", false)):
		Air._lift(w, e, f)
	e.pos = Airfield_clamp(w, Vector2(e.pos) + away)
	Movement.stop_path(e)
	e.order = {"type": "idle"}
	var d := Air.adef(e)
	match trigger:
		"low_fuel":
			e.fuel = 0.15 * float(d.get("fuel_max", 100.0))
		"dry":
			if bool(d.get("cn_vanta", false)):
				w.submit({"type": "vanta_rtb", "unit_ids": [id], "issuer": int(e.owner)})
			elif int(d.get("ammo_max", 0)) > 0:
				e.ammo = 0
			else:
				Air._go_home(w, e, f)
		"manual":
			if bool(d.get("cn_vanta", false)):
				w.submit({"type": "vanta_rtb", "unit_ids": [id], "issuer": int(e.owner)})
			elif String(d.aircraft) == "heli" and w.entities.has(int(e.get("air_home", -1))):
				w.submit({"type": "rebase", "unit_ids": [id], "building_id": int(e.air_home), "issuer": int(e.owner)})
			else:
				Air._go_home(w, e, f)
	var lines := []
	var alerts := []
	for ev in w.events:   # a return started outside a step (Air._go_home) emits before the first step
		if ["AirPadBusy", "AirNoPad", "AirPadLost"].has(String(ev.type)) and int(ev.get("id", -1)) == id:
			alerts.append(String(ev.type))
	var hover_bld := 0
	for i in ticks:
		w.step()
		if i % 10 == 0 and w.entities.has(id) and not bool(e.get("air_landed", false)) and not bool(e.moving):
			var hb := near_building(w, Vector2(e.pos))
			if float(hb[0]) <= 1.5:
				hover_bld += 1
		for ev in w.events:
			if ["AirPadBusy", "AirNoPad", "AirPadLost", "AirHolding"].has(String(ev.type)) and int(ev.get("id", -1)) == id:
				alerts.append(String(ev.type))
		if not w.entities.has(id):
			lines.append("t=%d DEAD" % i)
			return {"log": lines, "end": {"dead": true}, "alerts": alerts}
		if i % LOG_EVERY == 0 or i == ticks - 1:
			lines.append(_line(w, e, i, home0))
	var nb := near_building(w, Vector2(e.pos))
	var hp := home_point(w, e)
	var end := {"landed": bool(e.get("air_landed", false)), "phase": Air.phase(w, id), "d_home": Vector2(e.pos).distance_to(hp),
		"d_home0": Vector2(e.pos).distance_to(home0), "bld_d": float(nb[0]), "bld": String(nb[1]), "in_bld": bool(nb[2]),
		"pos": Vector2(e.pos), "fuel": float(e.get("fuel", -1.0)), "home": hp, "pad71": on_pad71(w, e), "hover_bld": hover_bld,
		"hold": Air.flight(w, id).has("hold71")}
	return {"log": lines, "end": end, "alerts": alerts}


static func Airfield_clamp(w: SimWorld, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 2.0, float(w.map.w) - 3.0), clampf(p.y, 2.0, float(w.map.h) - 3.0))


static func _line(w: SimWorld, e: Dictionary, i: int, home0: Vector2) -> String:
	var f := Air.flight(w, int(e.id))
	var nb := near_building(w, Vector2(e.pos))
	return "t=%d ph=%s landed=%s pos=(%.1f,%.1f) d_home=%.2f bld=%s d_bld=%.2f in=%s moving=%s fuel=%.0f dest=%s lc=%s pad71=%s hold=%s order=%s" % [i,
		String(f.get("phase", "?")), str(bool(e.get("air_landed", false))), e.pos.x, e.pos.y, Vector2(e.pos).distance_to(home0),
		String(nb[1]), float(nb[0]), str(nb[2]), str(bool(e.moving)), float(e.get("fuel", -1.0)), str(f.get("dest", "-")), str(f.get("land_cell", "-")),
		String(f.get("pad71", "-")), str(f.has("hold71")), str(e.order)]


## Puts the home pad of craft id into pad state st: "free" (as is), "taken" (other craft sit on every slot of it),
## "destroyed" (the building / facility carrying its home pad destroyed), "none" (every own pad it could use destroyed).
static func apply_state(w: SimWorld, id: int, st: String) -> void:
	var e: Dictionary = w.entities[id]
	var d := Air.adef(e)
	Air.sync71(w)
	var hk := Air.home71(w, e)
	var hp := home_point(w, e)
	match st:
		"taken":
			var n := int(Pads71.pad(w, hk).get("cap", 1)) if hk != "" else 1
			for i in n:
				var b := w.spawn_unit(String(e.def), int(e.owner), hp)
				w.run_ticks(1)
				var be: Dictionary = w.entities[b]
				if not bool(be.get("air_landed", false)) or Vector2(be.pos).distance_to(hp) > 0.75:
					var fb: Dictionary = Air._ensure(w, be)
					be.pos = hp
					Air._lift(w, be, fb)
					Air.land71(w, be, fb, hk)
		"destroyed":
			var ref := int(Pads71.pad(w, hk).get("ref", -1))
			if w.entities.has(ref):
				w.destroy(ref, "airfix71_test")
		"none":
			var kinds: Array = Air.PAD_KINDS71[Air.craft71(d)]
			var ks: Array = Pads71.pads(w).keys()
			ks.sort()
			for k in ks:
				var p: Dictionary = Pads71.pads(w)[k]
				if int(p.o) == int(e.owner) and kinds.has(String(p.k)) and w.entities.has(int(p.ref)):
					w.destroy(int(p.ref), "airfix71_test")
	w.run_ticks(2)


## Key of the Pads71 pad of a kind craft e can use whose landing point is within 0.75 of e ("" none).
static func on_pad71(w: SimWorld, e: Dictionary) -> String:
	var kinds: Array = Air.PAD_KINDS71[Air.craft71(Air.adef(e))]
	var ks: Array = Pads71.pads(w).keys()
	ks.sort()
	for k in ks:
		var p: Dictionary = Pads71.pads(w)[k]
		if kinds.has(String(p.k)) and Pads71.alive(w, String(k)) and Vector2(e.pos).distance_to(Vector2(float(p.x), float(p.y))) <= 0.75:
			return String(k)
	return ""
