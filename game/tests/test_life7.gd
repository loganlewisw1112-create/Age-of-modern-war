extends "res://tests/test_base.gd"
## G7 LIFE7 (13.9c-7): the living-facility display layer (presentation/view/fac_life7.gd) and its art
## (tools/art/g7_life7.gd -> assets/art/g7_life7). Display only: the state hash is identical with the layer on / off.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
const LayerScript = preload("res://presentation/view/fac_life7.gd")
const SHEETS := ["fig_tech", "fig_guard", "fig_staff", "dog", "forklift", "fuel_truck", "tow_tractor", "drone", "radar", "cupola", "target"]


class _StubView extends Node:
	var world: SimWorld = null
	var camera = null
	var _alpha := 0.0
	func sim_busy() -> bool:
		return false


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


func _setup(seed_v := 7) -> Array:
	var w := make_world({"seed": seed_v})
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(40, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var t: PackedByteArray = w.map.terrain
	for y in range(o.y, o.y + n):
		for x in range(o.x, o.x + n):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if Rect2i(o, Vector2i(n, n)).has_point(w.cell_of(e.pos)) and e.kind != "building":
			w.entities.erase(id)
	w.cache.clear()
	var off: Array = CnFacility.conf().core_offset
	var fid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return [w, fid]


func _layer(w: SimWorld) -> Array:
	var v := _StubView.new()
	v.world = w
	var L = LayerScript.new()
	v.add_child(L)
	L.setup(v)
	return [v, L]


func _step(w: SimWorld, L, n: int) -> void:
	for i in n:
		w.run_ticks(1)
		RenderSnap.build(w)
		L.refresh(RenderSnap.latest(w))


func test_art_sheets_generated() -> void:
	var p := "res://assets/art/g7_life7/manifest.json"
	check(FileAccess.file_exists(p), "assets/art/g7_life7/manifest.json written by tools/art/g7_life7.gd")
	var man = JSON.parse_string(FileAccess.get_file_as_string(p))
	check(man is Dictionary and (man as Dictionary).has("life7"), "manifest has the life7 section")
	if not (man is Dictionary):
		return
	for id in SHEETS:
		var e: Dictionary = man.life7.get(id, {})
		check(not e.is_empty(), "sheet %s listed" % id)
		if e.is_empty():
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/g7_life7/" + String(e.file)))
		check(img != null and img.get_width() == int(e.fw) * (e.frames as Array).size() and img.get_height() == int(e.fh) * int(e.rows),
			"sheet %s is %d frames x %d rows of %dx%d" % [id, (e.frames as Array).size(), int(e.rows), int(e.fw), int(e.fh)])
	check(ArtCatalogHas("g7_life7"), "art catalog registers the g7_life7 group")


func ArtCatalogHas(grp: String) -> bool:
	var src := FileAccess.get_file_as_string("res://presentation/art/art_catalog.gd")
	return src.contains("\"%s\"" % grp)


func test_no_facility_costs_nothing() -> void:
	var w := make_world()
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 20)
	check(not L.visible and (L.life as Array).is_empty() and int(L.scans) == 0, "no facility: hidden, no layout, no snapshot scan")
	r[0].free()


func test_layout_actors_and_routes() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 3)
	check_eq((L.life as Array).size(), 1, "one facility laid out")
	var Lf: Dictionary = L.life[0]
	var kinds := {}
	for a in Lf.actors:
		kinds[String(a.kind)] = int(kinds.get(String(a.kind), 0)) + 1
	check(int(kinds.get("tech", 0)) >= 4 and int(kinds.get("forklift", 0)) == 2 and int(kinds.get("fuel", 0)) == 1
		and int(kinds.get("tug", 0)) == 1 and int(kinds.get("dog", 0)) == 1 and int(kinds.get("drone", 0)) == 1
		and int(kinds.get("gate", 0)) == 2 and int(kinds.get("staff", 0)) == 1, "actors: %s" % str(kinds))
	check(int(kinds.get("guard", 0)) == 0, "no display wall guards / patrols (13.9c-10: Sentinels are real units)")
	# every routed leg stays on the compound floor: no corner of a path inside a building footprint or garage
	var bad := 0
	var legs := 0
	for a in Lf.actors:
		for sg in a.segs:
			if not bool(sg.m):
				continue
			legs += 1
			var pts: PackedVector2Array = sg.pts
			for j in range(1, pts.size() - 1):
				for b in Lf.boxes:
					if (b.r as Rect2).grow(-0.05).has_point(pts[j]):
						bad += 1
	check(legs >= 12 and bad == 0, "%d routed legs, %d path corners inside a building" % [legs, bad])
	check((Lf.garage_door as Array).size() == (Lf.garages as Array).size() and (Lf.garages as Array).size() >= 4, "a shutter for every garage")
	r[0].free()


## POLISH7-2 (owner 13.9c-17): the facility only shelters / stops / goes cold on a lockdown or a breach; under fire and
## contested keep the daily life going (amber alert only).
func test_alarm_only_on_breach() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 2)
	check(not bool(L.life[0].alarm), "secure: no alarm")
	for stv in [["contested", false], ["under_fire", false], ["breached", true], ["secure", false]]:
		var F2: Dictionary = (L.facs[0] as Dictionary).duplicate()
		F2.state = stv[0]
		F2.lock = false
		L.facs = [F2]
		L._rebuild()
		check_eq(bool(L.life[0].alarm), stv[1], "state %s: staff shelter / range cold = %s" % [stv[0], str(stv[1])])
	var F3: Dictionary = (L.facs[0] as Dictionary).duplicate()
	F3.lock = true
	L.facs = [F3]
	L._rebuild()
	check(bool(L.life[0].alarm), "lockdown: alarm")
	r[0].free()


func test_occlusion_rule() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 2)
	var Lf: Dictionary = L.life[0]
	var pr: Rect2 = Lf.zones.planning
	var behind := Vector2(pr.get_center().x - 0.2, pr.position.y - 0.4)   # just north of the ops building
	var front := Vector2(pr.end.x + 0.5, pr.get_center().y)               # on the lane just east of it
	check(L._occluded(Lf, behind, 18.0), "a figure right behind the ops building is hidden by it")
	check(not L._occluded(Lf, front, 18.0), "a figure in front of the ops building is drawn")
	r[0].free()


func test_display_only_hash_identical() -> void:
	var a := _setup(11)
	var b := _setup(11)
	var wa: SimWorld = a[0]
	var wb: SimWorld = b[0]
	var r := _layer(wa)
	var L = r[1]
	_step(wa, L, 200)
	wb.run_ticks(200)
	check_eq(wa.state_hash(), wb.state_hash(), "200 ticks with the layer refreshing every tick == 200 ticks without it")
	var ev: Array = L.eval_all()
	check(ev.size() >= 10, "actors evaluated: %d" % ev.size())
	r[0].free()


func test_deterministic_from_tick() -> void:
	var a := _setup(5)
	var b := _setup(5)
	var ra := _layer(a[0])
	var rb := _layer(b[0])
	_step(a[0], ra[1], 300)
	_step(b[0], rb[1], 300)
	var ea: Array = ra[1].eval_all()
	var eb: Array = rb[1].eval_all()
	var same := ea.size() == eb.size()
	var moved := 0
	for i in mini(ea.size(), eb.size()):
		same = same and (ea[i].p as Vector2).is_equal_approx(eb[i].p) and String(ea[i].pose) == String(eb[i].pose)
	_step(a[0], ra[1], 60)
	var ec: Array = ra[1].eval_all()
	for i in mini(ea.size(), ec.size()):
		if (ea[i].p as Vector2).distance_to(ec[i].p) > 0.2:
			moved += 1
	check(same, "same ticks -> same picture (every actor's position and pose)")
	check(moved >= 3, "actors move over 3 s (%d moved)" % moved)
	ra[0].free()
	rb[0].free()


func test_vehicle_waits_for_sim_unit_and_doors() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 2)
	var Lf: Dictionary = L.life[0]
	# park a sim soldier right in front of the first forklift
	var fk: Dictionary = {}
	for a in Lf.actors:
		if String(a.kind) == "forklift":
			fk = a
			break
	var found := false
	for i in 400:   # until the forklift is driving
		_step(w, L, 1)
		L.eval_all()
		if bool(fk.moving):
			found = true
			break
	check(found, "forklift drives within 20 s")
	var ahead: Vector2 = (fk.p as Vector2) + Vector2.from_angle(float(fk.face)) * 0.8
	var uid := w.spawn_unit("rifleman", 0, ahead)
	if w.entities.has(uid):
		w.entities[uid].order = {"type": "hold"}   # Hold Position (squad_ai: never moves)
	var c0 := float(fk.clock)
	for _k in 40:   # kept on the spot: passing Sentinels' separation push drifts even a holding unit off the lane
		if w.entities.has(uid):
			w.entities[uid].pos = ahead
		_step(w, L, 1)
	check(absf(float(fk.clock) - c0) < 0.001 and int(L.waits) > 0, "forklift waits while a sim unit stands in its way (clock %.2f -> %.2f)" % [c0, float(fk.clock)])
	w.destroy(uid, "test")
	_step(w, L, 20)
	check(float(fk.clock) > c0, "and drives on when the way is clear")
	# a unit at a garage door rolls that shutter open
	var gd: Vector2 = Lf.garage_door[0]
	var u2 := w.spawn_unit("rifleman", 0, gd)
	_step(w, L, 2)
	for i in 3:
		L._update_doors(0.5)
	check(L.door_open(int(Lf.id), "g0") > 0.9, "garage 0 shutter open with a unit at its door (%.2f)" % L.door_open(int(Lf.id), "g0"))
	w.destroy(u2, "test")
	_step(w, L, 2)
	for i in 4:
		L._update_doors(0.5)
	check(L.door_open(int(Lf.id), "g0") < 0.05, "and rolls shut after it leaves")
	r[0].free()


func test_cupola_tracks_enemy_and_dog_heels() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 2)
	var Lf: Dictionary = L.life[0]
	var tp: Vector2 = Lf.towers[0]
	var cr: Rect2 = Lf.cr
	var out := (tp - cr.get_center()).normalized()
	var ep := tp + out.rotated(0.6) * 6.0
	# a vehicle target: infantry die of lethal wounds whatever their hp (WOUND7), so a rifleman lasted ~1 s under the
	# facility's real guns and the cupola went back to its sweep before the check
	var foe := w.spawn_unit("mbt", 1, ep)
	if w.entities.has(foe):
		w.entities[foe].order = {"type": "hold"}
		w.entities[foe].hp = 1.0e9   # the tower's real weapon must not kill the test target
		w.entities[foe].max_hp = 1.0e9
	_step(w, L, 60)
	var want := (ep - tp).angle()
	var got := float(Lf.aims.get(0, 99.0))
	check(absf(wrapf(got - want, -PI, PI)) < 0.25, "tower 0 cupola turned onto the enemy (want %.2f got %.2f)" % [want, got])
	check(w.entities.has(foe), "the test target is still alive (else the check below tests nothing)")
	check(bool(Lf.aims.get("t0", false)), "tower 0 reports tracking")
	# guard dog: kennel with no Sentinel; heels beside a unit whose def id contains "sentinel" when one exists
	var dog: Dictionary = {}
	for a in Lf.actors:
		if String(a.kind) == "dog":
			dog = a
	# the facility now starts with a real Sentinel garrison (SENT7, 13.9c-10): clear it for the kennel case
	var cleared := 0
	for id in w.entities.keys():
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and Content.unit(String(e.def)).has("sentinel"):
			w.destroy(id, "test")
			cleared += 1
	if w.entities.has(foe):
		w.destroy(foe, "test")   # the foe put the facility under fire; a state change re-lays the actors out
	_step(w, L, 31)
	Lf = L.life[0]
	for a in Lf.actors:
		if String(a.kind) == "dog":
			dog = a
	L.eval_all()
	check(String(dog.pose) == "kennel", "dog at its kennel with no Sentinel inside (%d garrison Sentinels cleared, pose %s)" % [cleared, String(dog.pose)])
	var sdef := ""
	for d in Content.ids("units"):   # SENT7 defs (g7_sent_*) carry a "sentinel" type field
		var ud: Dictionary = Content.unit(String(d))
		if ud.has("sentinel") and String(ud.sentinel) != "bearer":
			sdef = String(d)
			break
	if sdef == "":
		check(false, "no Sentinel def in content (SENT7 defs_g7_sentinels.json): the heel check cannot run")
	else:
		var sp := cr.get_center() + Vector2(0.5, 3.5)
		var sid := w.spawn_unit(sdef, 0, sp)
		_step(w, L, 4)
		for i in 30:
			L._dog_at(Lf, dog)
		check((dog.p as Vector2).distance_to(w.entities[sid].pos) < 1.4, "dog heels beside the Sentinel")
	r[0].free()


## 13.9c-11 hook (fact life7.engineer_hook): a Facility Engineer driving a forklift / the fuel truck carries the display
## vehicle with it (ENG7 emits Eng7Job {unit, job}); when the job ends the vehicle goes back to its own route.
func test_engineer_hook_attaches_vehicles() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 2)
	var Lf: Dictionary = L.life[0]
	var cr: Rect2 = Lf.cr
	var p1 := cr.get_center() + Vector2(-3.5, 6.5)
	var p2 := cr.get_center() + Vector2(4.5, 6.5)
	var e1 := w.spawn_unit("rifleman", int(Lf.owner), p1)   # stand-ins for the Facility Engineer unit (ENG7)
	var e2 := w.spawn_unit("rifleman", int(Lf.owner), p2)
	L.on_events([{"type": "Eng7Job", "unit": e1, "job": "forklift"}, {"type": "Eng7Job", "unit": e2, "job": "fuel"}])
	_step(w, L, 3)
	L.eval_all()
	var fk: Dictionary = {}
	var fu: Dictionary = {}
	for a in Lf.actors:
		if String(a.kind) == "forklift" and fk.is_empty():
			fk = a
		elif String(a.kind) == "fuel":
			fu = a
	check((fk.p as Vector2).distance_to(w.entities[e1].pos) < 0.3 and bool(fk.load) and int(fk.driver) == e1,
		"forklift 0 carried by engineer %d (at %s, unit at %s, loaded %s)" % [e1, str(fk.p), str(w.entities[e1].pos), str(fk.load)])
	check((fu.p as Vector2).distance_to(w.entities[e2].pos) < 0.3 and int(fu.driver) == e2, "fuel truck carried by engineer %d" % e2)
	L.on_events([{"type": "Eng7Job", "unit": e1, "job": ""}])
	w.destroy(e2, "test")
	L.on_events([{"type": "EntityDestroyed", "id": e2}])
	_step(w, L, 2)
	L.eval_all()
	check(int(fk.driver) == -1 and int(fu.driver) == -1, "job ended / engineer gone: both vehicles back on their own routes")
	r[0].free()
