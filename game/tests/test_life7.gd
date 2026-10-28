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


## Owner 13.9c-19: the floating ops-room inset over the command centre is gone (no staff-at-screens / map-table view,
## no zoom / hover trigger); the command centre reads as a building only. POLISH7-3 also checks FACB7-4's 4-storey
## command centre height (seq 4583: roof brim 15.5 m = 152 px) and the range training building occluder.
func test_ops_inset_removed() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 2)
	check(not L.has_method("_draw_inset"), "no ops-room inset drawer in the layer")
	check(not bool(L.inset_shown), "no ops-room inset shown (the windowed pt7_life7 checks it at zoom 2.5)")
	check_eq(float(LayerScript.ZONE_H.planning), 152.0, "the command centre occludes at its 4-storey height")
	var Lf: Dictionary = L.life[0]
	var rz: Rect2 = Lf.zones.get("range", Rect2())
	if rz.size != Vector2.ZERO:
		var b := rz.position + LayerScript.RANGE_BLD.position
		check(L._occluded(Lf, Vector2(b.x + 1.5, b.y - 0.3), 18.0), "a figure just behind the range training building is hidden")
		check(not L._occluded(Lf, Vector2(rz.position.x + LayerScript.RANGE_TARGET_X - 0.4, rz.position.y + 1.0), 18.0), "a trainee checking the targets downrange is drawn")
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
		for i in 30:   # POLISH7-4: a fixed 0.1 s step (headless get_process_delta_time() is 0: the dog only "heeled"
			L._dog_at(Lf, dog, 0.1)   # while its kennel was > 6 tiles away and it snapped; the barracks moved closer)
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


## POLISH7-4 (ORCH / owner flag "theres a forklift ontop of workshop/drone launch bay roof"): no LIFE7 ground actor
## (forklifts, fuel truck, tow tractor, technicians, staff, dog, gate guards) stands or routes on a building. Every route
## corner, leg midpoint, stop and parking spot lies off every footprint from the layout data (FACB7-5 layout75: the
## workshop [16,9,4,4] with its stacked drone-bay storey, the barracks [16,14,4,2], every other building zone, garages,
## towers, walls, the range's training building), every parking / working spot is in sight (not behind a building at its
## real height: the tug parked behind the workshop was drawn on the 11.6 m launch deck), and the drone recovers on the
## workshop's launch deck at deck height.
func test_actors_off_footprints() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 3)
	var Lf: Dictionary = L.life[0]
	var F: Dictionary = Lf.F
	var O: Vector2 = Lf.O
	var foot := []
	for b in Lf.boxes:
		foot.append(b.r)
	var floors := ["pad", "helipad", "staging", "range", "fuel_point", "runoff", "approach", "apc_wash", "gate_outer", "gate_inner"]
	for zn in (F.zones as Dictionary):
		if not floors.has(String(zn)):
			foot.append(L._r(F.zones[zn]))
	check(L._r(F.zones.get("workshop", [])) == Rect2(O + Vector2(16, 9), Vector2(4, 4)) and L._r(F.zones.get("barracks", [])) == Rect2(O + Vector2(16, 14), Vector2(4, 2)),
		"layout75: workshop [16,9,4,4] + barracks [16,14,4,2] (%s / %s)" % [str(F.zones.get("workshop")), str(F.zones.get("barracks"))])
	var wb_h := 0.0
	for b in Lf.boxes:
		if (b.r as Rect2) == L._r(F.zones.workshop):
			wb_h = maxf(wb_h, float(b.h))
	check(wb_h >= 11.6 * 9.8 - 1.0, "the workshop + drone-bay storey hides what is behind it up to its 11.6 m deck rail (box %.0f px)" % wb_h)
	var bad := []
	var hidden_spots := []
	var n := 0
	for a in Lf.actors:
		var kind := String(a.kind)
		if kind == "drone":
			continue
		var pts := []
		for sg in a.segs:
			if bool(sg.m):
				var pp: PackedVector2Array = sg.pts
				for j in pp.size():
					pts.append(pp[j])
					if j > 0:
						pts.append(pp[j - 1].lerp(pp[j], 0.5))
			else:
				pts.append(sg.p)
				var hz := 40.0 if kind == "fuel" else (24.0 if kind in ["forklift", "tug"] else 18.0)
				if String(sg.pose) != "hide" and kind != "gate" and L._occluded(Lf, sg.p, hz):
					hidden_spots.append("%s %s %s" % [kind, String(sg.pose), str((sg.p as Vector2) - O)])
		if kind == "dog":
			pts.append(a.kennel)
		if kind == "gate":
			pts.append(a.post)
		for q in pts:
			n += 1
			for fr in foot:
				if (fr as Rect2).grow(-0.02).has_point(q):
					bad.append("%s at %s in %s" % [kind, str((q as Vector2) - O), str((fr as Rect2).position - O)])
					break
	check(n > 80 and bad.is_empty(), "%d actor route points / spots checked, %d on a building: %s" % [n, bad.size(), str(bad.slice(0, 6))])
	check(hidden_spots.is_empty(), "every parking / working spot is in sight, none behind a building: %s" % str(hidden_spots))
	# the drone: recovers on the workshop launch deck (10.57 m), never low inside a footprint
	var dr: Dictionary = {}
	for a in Lf.actors:
		if String(a.kind) == "drone":
			dr = a
	var deck: Rect2 = L._r(F.zones.workshop)
	var on_deck := 0
	var low_in := []
	for k in 640:   # 4 cycles at 0.25 s: never below the top of a building / tower / wall it is over (the deck spot excepted)
		dr.clock = float(k) * 0.25
		L._drone_at(Lf, dr)
		var home := bool(dr.get("home", false)) and deck.has_point(dr.p)
		if home and float(dr.alt) >= 10.5:
			on_deck += 1
		for b in Lf.boxes:
			if (b.r as Rect2).has_point(dr.p) and float(dr.alt) * 9.8 < float(b.h) and not (home and (b.r as Rect2) == deck):
				low_in.append("t%.2f alt %.1f m in %s (%.0f px)" % [float(dr.clock), float(dr.alt), str((b.r as Rect2).position - O), float(b.h)])
				break
	check(on_deck > 40 and low_in.is_empty(), "drone home on the launch deck (%d samples on deck >= 10.5 m); never through a building: %s" % [on_deck, str(low_in.slice(0, 4))])
	r[0].free()


## POLISH7-4 (owner 13.9c-21): the fuel bowser has ONE marked parking bay inside the facility (Engineer7.BOWSER_BAY),
## out of every lane, pad, APC bay, route and footprint; LIFE7's display truck parks there whenever it is not refuelling
## (idle -> parked; working -> leaves; done -> back in the bay).
func test_fuel_bowser_bay_display() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var r := _layer(w)
	var L = r[1]
	_step(w, L, 3)
	var Lf: Dictionary = L.life[0]
	var F: Dictionary = Lf.F
	var O: Vector2 = Lf.O
	var bay: Rect2 = Lf.fuel_bay
	check(bay == Rect2(O + L.Engineer7.bay_local().position, L.Engineer7.bay_local().size), "LIFE7 bay = Engineer7.BOWSER_BAY (one bay for the sim and the display)")
	var c: Dictionary = CnFacility.conf()
	var clash := []
	for l in F.get("lanes", []):
		if L._r(l).intersects(bay):
			clash.append("lane %s" % str(l))
	for zn in (F.zones as Dictionary):
		if L._r(F.zones[zn]).intersects(bay):
			clash.append("zone %s" % String(zn))
	for b in Lf.boxes:
		if (b.r as Rect2).intersects(bay):
			clash.append("footprint %s" % str((b.r as Rect2).position - O))
	var FD = load("res://sim/systems/fac_drive7.gd")
	for q in FD.bays(c):
		if Rect2(O + (q[0] as Vector2) - Vector2(1.0, 1.0), Vector2(2.0, 2.0)).intersects(bay):
			clash.append("APC bay %s" % str(q[0]))
	check(clash.is_empty(), "bowser bay %s clear of every lane / pad / zone / footprint / APC bay: %s" % [str(bay.position - O), str(clash)])
	var fu: Dictionary = {}
	var others_in := []
	for a in Lf.actors:
		if String(a.kind) == "fuel":
			fu = a
			continue
		for sg in a.segs:
			var pts: Array = Array(sg.pts) if bool(sg.m) else [sg.p]
			for q in pts:
				if bay.grow(0.1).has_point(q):
					others_in.append(String(a.kind))
	check(others_in.is_empty(), "no other actor's route or stop enters the bay: %s" % str(others_in))
	var parks := 0
	var park_ok := 0
	for sg in fu.segs:
		if not bool(sg.m) and String(sg.pose) == "park":
			parks += 1
			if (sg.p as Vector2).distance_to(bay.get_center()) < 0.01:
				park_ok += 1
	check(parks >= 2 and park_ok == parks, "every park stop of the display truck is the bay centre (%d of %d)" % [park_ok, parks])
	# idle: nothing to refuel -> it stays parked in the bay (the dwell holds, it never drives off on its own)
	_step(w, L, 900)
	L.eval_all()
	check((fu.p as Vector2).distance_to(bay.get_center()) < 0.05 and String(fu.pose) == "park" and not bool(fu.moving),
		"idle 45 s: parked in the bay (at %s, pose %s)" % [str((fu.p as Vector2) - O), String(fu.pose)])
	# a vehicle to refuel on the pad: the hold lets go; past the dwell it drives out of the bay
	var padr: Rect2 = L._r(F.zones.pad)
	fu.clock = float(fu.segs[0].t1) - 0.02
	L._vehs = []
	check(L._bay_hold(Lf, fu, 1), "end of the bay dwell with no vehicle on the pad: holds (stays parked)")
	L._vehs = [[padr.get_center(), int(Lf.owner)]]
	check(not L._bay_hold(Lf, fu, 1), "an own vehicle on the pad: the bowser leaves for it")
	L._vehs = [[padr.get_center(), int(Lf.owner) + 1]]
	check(L._bay_hold(Lf, fu, 1), "an enemy vehicle on the pad is not refuelled")
	fu.clock = float(fu.segs[0].t1) + 3.0
	L._eval(Lf, fu)
	check(not bay.has_point(fu.p) and bool(fu.moving), "working: drove out of the bay (at %s)" % str((fu.p as Vector2) - O))
	# every hose job ends back in the bay: the next dwell after each hose dwell is a park in the bay
	var dw := []
	for sg in fu.segs:
		if not bool(sg.m):
			dw.append(sg)
	var back := 0
	var hoses := 0
	for i in dw.size():
		if String(dw[i].pose) == "hose":
			hoses += 1
			var nx: Dictionary = dw[(i + 1) % dw.size()]
			if String(nx.pose) == "park" and (nx.p as Vector2).distance_to(bay.get_center()) < 0.01:
				back += 1
	check(hoses >= 2 and back == hoses, "done: after each refuelling the truck returns to the bay (%d of %d)" % [back, hoses])
	# an engineer's real refuelling run carries the truck; when it ends the truck is drawn parked in the bay again
	var e2 := w.spawn_unit("rifleman", int(Lf.owner), padr.get_center() + Vector2(0, 1.5))
	L.on_events([{"type": "Eng7Job", "unit": e2, "job": "fuel"}])
	_step(w, L, 3)
	L.eval_all()
	check(int(fu.driver) == e2 and not bay.has_point(fu.p), "engineer run: the truck is where the engineer drives it")
	L.on_events([{"type": "Eng7Job", "unit": e2, "job": ""}])
	fu.clock = 0.0
	_step(w, L, 3)
	L.eval_all()
	check(int(fu.driver) == -1 and (fu.p as Vector2).distance_to(bay.get_center()) < 0.05, "job ended: parked in the bay (at %s)" % str((fu.p as Vector2) - O))
	r[0].free()


## POLISH7-4 (owner 13.9c-21): the Facility Engineer's SIM bowser: the engineer takes it from its bay (Eng7Job fuel
## starts at the bay), leaves the bay to refuel (working), and drives it back into the bay to park (job ends there).
func test_sim_bowser_parks_in_its_bay() -> void:
	var E7 = load("res://sim/systems/engineer7.gd")
	var S7 = load("res://sim/systems/sentinels7.gd")
	var w := make_world()
	_ensure_g7()
	Content._link_fragment_production()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var nn := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - nn / 2, mh / 2 - nn / 2)
	var ar := Rect2i(o, Vector2i(nn, nn))
	var t: PackedByteArray = w.map.terrain
	for y in range(ar.position.y, ar.end.y):
		for x in range(ar.position.x, ar.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		if ar.has_point(w.cell_of(w.entities[id].pos)):
			w.entities.erase(id)
	w.cache.clear()
	var Mv = load("res://sim/systems/movement.gd")
	Mv.rebuild_nav(w)
	w.factions[0].credits = 200000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	var off: Array = CnFacility.conf().core_offset
	var fbid := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	S7._st(w).seeded.append(fbid)
	var tick := func() -> void:
		w.step()
		if not SimWorld.SYSTEM_ORDER.has(E7):
			E7.tick(w)
	for i in CnFacility.DISCOVER_EVERY + 6:
		tick.call()
	var cn = w.sys_state.get("cn_facility")
	var fac := -1
	for k in cn.facs:
		fac = int(k)
		break
	var F := CnFacility.fac(w, fac)
	var bay: Rect2 = E7.bowser_bay(F)
	var ids: Array = E7.engineers_of(w, fac)
	check(ids.size() >= 1, "the facility has a Facility Engineer (%d)" % ids.size())
	for i in range(1, ids.size()):
		w.entities.erase(int(ids[i]))
	w.cache.clear()
	if ids.is_empty():
		return
	var eng := int(ids[0])
	var st: Rect2 = CnFacility.zone(F, "staging")
	var cc: Vector2i = Mv.nearest_free_cell(w, w.cell_of(st.get_center()), "vehicle", 0)
	var apc := w.spawn_unit("g7_cn_strike_apc", 0, Vector2(cc) + Vector2(0.5, 0.5))
	w.entities[apc].fuel = 60.0
	var took := Vector2(-999, -999)
	var left := false
	var ended := Vector2(-999, -999)
	var pumped := false
	for i in 4000:
		tick.call()
		for ev in w.events:
			if String(ev.type) == "Eng7Job" and int(ev.unit) == eng:
				if String(ev.job) == "fuel" and took.x < -900:
					took = w.entities[eng].pos
				elif String(ev.job) == "" and took.x > -900:
					ended = w.entities[eng].pos
			elif String(ev.type) == "Eng7Pump" and bool(ev.on):
				pumped = true
		if took.x > -900 and w.entities.has(eng) and not bay.grow(0.5).has_point(w.entities[eng].pos):
			left = true
		if ended.x > -900:
			break
	check(took.x > -900 and bay.grow(0.25).has_point(took), "idle bowser taken from its bay (engineer at %s, bay %s)" % [str(took - bay.position), str(bay.size)])
	check(left and pumped, "working: the bowser left the bay and pumped the APC")
	check(ended.x > -900 and bay.grow(0.25).has_point(ended), "done: driven back and parked in the bay (at %s rel. bay)" % str(ended - bay.position))



## POLISH7-5 (owner 13.9c-21a: "fuel tanker marked parking bay should not be placed in front of any door, garage, etc
## its placement HAS to make sense"): the bowser bay (Engineer7.BOWSER_BAY, compound-local) checked against every door /
## garage door / gate / pad edge / lane mouth / bay of the layout, all read from content/g7/defs_g7_facility.json:
## a lay-by off a lane (it touches a lane on its drive-out side and lies on none), nothing opens onto it, no fac_drive7
## route crosses it, and the truck's drawn size (measured from its sprite) fits inside it. Same rule for the dog kennel.
func test_fuel_bay_makes_sense() -> void:
	_ensure_g7()
	var E7 = load("res://sim/systems/engineer7.gd")
	var FD = load("res://sim/systems/fac_drive7.gd")
	var c: Dictionary = CnFacility.conf()
	var cs := float(c.compound)
	var bay: Rect2 = E7.bay_local()
	var d := Vector2.from_angle(float(E7.bay_heading())).round()
	var R4 := func(a) -> Rect2: return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	var cell := func(q) -> Rect2: return Rect2(float(q[0]), float(q[1]), 1.0, 1.0)
	# building footprints by name (core block, zones; a stacked zone is a storey of its host)
	var fp := {}
	var co: Array = c.get("core_offset", [3, 3])
	var csz := float(Content.building("a_cn_facility").get("size", 4))
	fp["core"] = Rect2(float(co[0]), float(co[1]), csz, csz)
	for zn in CnFacility.ZONES:
		if c.has(zn) and c[zn] is Array and (c[zn] as Array).size() == 4:
			fp[zn] = R4.call(c[zn])
	for zn in (c.get("stacked", {}) as Dictionary):
		fp[zn] = fp.get(String(c.stacked[zn]), fp.get(zn, Rect2()))
	var keep := []   # [label, rect]: the bay may not overlap any
	# 1. every door: its cell grown 1 all round, plus 2 tiles straight out of the building
	for zn in (c.doors as Dictionary):
		for q in c.doors[zn]:
			var dc: Rect2 = cell.call(q)
			var out := Vector2.ZERO
			if fp.has(zn):
				var b: Rect2 = fp[zn]
				var m := dc.get_center()
				out = Vector2(1, 0) if m.x >= b.end.x else (Vector2(-1, 0) if m.x <= b.position.x else (Vector2(0, 1) if m.y >= b.end.y else Vector2(0, -1)))
			keep.append(["door %s %s" % [zn, str(q)], dc.grow(1.0).merge(Rect2(dc.position + out * 2.0, Vector2.ONE))])
			keep.append(["door front %s %s" % [zn, str(q)], dc.merge(Rect2(dc.position + out * 2.0, Vector2.ONE))])
	# 2. every garage and its door front: 2 tiles deep in front of the door face, the garage's width + 1 tile each side
	var gz: Array = c.get("garage_size", [3, 3])
	for i in (c.garages as Array).size():
		var gp: Vector2 = FD.garage_park(c, i)
		var go: Vector2 = FD.garage_out(c, i)
		var gr := Rect2(gp - Vector2(float(gz[0]), float(gz[1])) * 0.5, Vector2(float(gz[0]), float(gz[1])))
		keep.append(["garage %d" % i, gr])
		var face_x := gr.end.x if go.x > 0.0 else gr.position.x - 2.0
		keep.append(["garage %d door front" % i, Rect2(face_x, gr.position.y - 1.0, 2.0, gr.size.y + 2.0)])
	# 3. gates, the wash, the decon hall, pads, the helipad, the fuel point, the staging yard, the approach: grown 1
	for zn in ["gate_outer", "apc_wash", "gate_inner", "pad", "helipad", "fuel_point", "staging", "decon_hall", "approach"]:
		if fp.has(zn):
			keep.append([zn + " (+1 edge margin)", (fp[zn] as Rect2).grow(1.0)])
	for q in c.get("mantrap", []):
		keep.append(["mantrap door %s" % str(q), (cell.call(q) as Rect2).grow(1.0)])
	if (c.get("checkpoint", []) as Array).size() == 2:
		keep.append(["checkpoint", Rect2(float(c.checkpoint[0]), float(c.checkpoint[1]), 2, 2).grow(1.0)])
	# 4. other bays: the APC staging bays (2x2 around their park point, +1)
	for q in FD.bays(c):
		keep.append(["APC bay %s" % str(q[0]), Rect2((q[0] as Vector2) - Vector2(2, 2), Vector2(4, 4))])
	# 5. lane mouths: where a lane meets another lane, the junction cells grown 1
	var lanes: Array = c.lanes
	for i in lanes.size():
		for j in lanes.size():
			var A: Rect2 = R4.call(lanes[i])
			var B: Rect2 = R4.call(lanes[j])
			if i != j and A.grow(0.01).intersects(B):
				keep.append(["lane mouth %s x %s" % [str(lanes[i]), str(lanes[j])], A.grow(1.0).intersection(B).grow(1.0)])
	# 6. footprints, lanes, towers, lockers, pop-ups, baffles, link walls, the wall ring: not on any
	for zn in fp:
		if (fp[zn] as Rect2).size != Vector2.ZERO:
			keep.append(["footprint " + String(zn), fp[zn]])
	for l in lanes:
		keep.append(["lane %s" % str(l), R4.call(l)])
	for t in c.towers:
		keep.append(["tower %s" % str(t), Rect2(float(t[0]), float(t[1]), 2, 2)])
	for k in ["lockers", "popups", "baffles"]:
		for q in c.get(k, []):
			keep.append([k + " %s" % str(q), cell.call(q)])
	for r0 in c.get("link_walls", []):
		keep.append(["link wall", R4.call(r0)])
	keep.append(["wall ring", Rect2(0, 0, cs, 2)])
	keep.append(["wall ring", Rect2(0, cs - 2, cs, 2)])
	keep.append(["wall ring", Rect2(0, 0, 2, cs)])
	keep.append(["wall ring", Rect2(cs - 2, 0, 2, cs)])
	var hits := []
	for kr in keep:
		# 13.9c-21b authority record (owner choice, bay beside the dropship helipad): the helipad's +1 edge margin does
		# not apply to this one bay on the helipad's apron (west) side; the helipad itself, the loading pad +1 and every
		# other margin still do
		if String(kr[0]) == "helipad (+1 edge margin)" and fp.has("helipad") and bay.end.x <= (fp.helipad as Rect2).position.x:
			continue
		if (kr[1] as Rect2).intersects(bay):
			hits.append(String(kr[0]))
	check(hits.is_empty(), "fuel bay %s: nothing opens onto it (doors, garage doors, gates, pad / helipad edges, lane mouths, bays) and it stands on nothing: %s" % [str(bay), str(hits)])
	# a lay-by: the strip just past its mouth (the side the parked truck's nose points at) is a lane
	var L := absf(d.x) * bay.size.x + absf(d.y) * bay.size.y
	var pn := Vector2(-d.y, d.x)
	var W := absf(pn.x) * bay.size.x + absf(pn.y) * bay.size.y
	var mouth := Rect2(bay.get_center() + d * (L * 0.5 + 0.15), Vector2.ZERO).grow(0.1)
	var on_lane := false
	for l in lanes:
		on_lane = on_lane or (R4.call(l) as Rect2).encloses(mouth)
	# or a parallel lay-by: one long side opens onto a lane along its whole length, and the ground just past the nose is
	# clear (a lane, a vehicle yard or open paving: no building / tower / wall / locker / pop-up there), so the truck
	# pulls forward and out onto the lane
	var yard := true
	for kr in keep:
		var lab := String(kr[0])
		if lab.begins_with("footprint") or lab.begins_with("tower") or lab.begins_with("wall") or lab.begins_with("lockers") 				or lab.begins_with("popups") or lab.begins_with("baffles") or lab.begins_with("link") or (lab.begins_with("garage") and not lab.ends_with("front")):
			if (kr[1] as Rect2).intersects(mouth):
				yard = false
	var along := false
	for sg in [-1.0, 1.0]:
		var c0: Vector2 = bay.get_center() + Vector2(-d.y, d.x) * sg * (0.5 * (absf(d.y) * bay.size.x + absf(d.x) * bay.size.y) + 0.15)
		var strip := Rect2(c0, Vector2.ZERO).grow_individual(absf(d.x) * (bay.size.x * 0.5 - 0.05), absf(d.y) * (bay.size.y * 0.5 - 0.05),
			absf(d.x) * (bay.size.x * 0.5 - 0.05), absf(d.y) * (bay.size.y * 0.5 - 0.05)).grow(0.05)
		for l in lanes:
			along = along or (R4.call(l) as Rect2).encloses(strip)
	check(on_lane or (along and yard), "the bay's drive-out opens onto a lane (nose side on a lane %s, or long side on a lane %s with the nose onto a lane / yard %s; heading %.0f deg)" % [on_lane, along, yard, rad_to_deg(float(E7.bay_heading()))])
	var side := false   # against a building side or the wall's inner face along its length
	for sg in [-1.0, 1.0]:
		var q: Vector2 = bay.get_center() + pn * sg * (W * 0.5 + 0.2)
		for zn in fp:
			side = side or (fp[zn] as Rect2).has_point(q)
		side = side or q.x < 2.0 or q.y < 2.0 or q.x > cs - 2.0 or q.y > cs - 2.0
	check(side, "the bay lies along a building side / the wall's inner face")
	# every tower still has a free stair cell beside it (the bay takes none of them)
	var stairless := []
	for t in c.towers:
		var free := 0
		var tr := Rect2i(int(t[0]) - 1, int(t[1]) - 1, 4, 4)
		for y in range(tr.position.y, tr.end.y):
			for x in range(tr.position.x, tr.end.x):
				if x >= 2 and y >= 2 and x < int(cs) - 2 and y < int(cs) - 2 and not Rect2(x, y, 1, 1).intersects(bay):
					free += 1
		if free == 0:
			stairless.append(t)
	check(stairless.is_empty(), "every tower keeps a stair cell: %s" % str(stairless))
	# no fac_drive7 route (garages / staging bays / wash / gates) puts an APC body within 0.3 tiles of the bay
	var G = FD.graph()
	var pairs := []
	for i in (c.garages as Array).size():
		pairs.append(["g%d" % i, "x", i])
		for j in (G.bay as Array).size():
			pairs.append(["g%d" % i, "b%d" % j, i])
		pairs.append(["w0", "g%d" % i, i])
		pairs.append(["e", "w0", i])
	for j in (G.bay as Array).size():
		pairs.append(["b%d" % j, "x", -1])
	var w := make_world()
	var near := []
	var routes := 0
	for pr in pairs:
		var legs: Array = FD.plan(String(pr[0]), String(pr[1]), int(pr[2]),
			PackedVector2Array([Vector2(G.pos[int(G.entry)]) + Vector2(0, 1.6), Vector2(G.pos[int(G.entry)]) + Vector2(0, 0.4)]) if String(pr[0]) == "e" else PackedVector2Array())
		if legs.is_empty():
			continue
		routes += 1
		var V := {"id": -1, "legs": [], "gar": int(pr[2]), "rv": 1}
		for l in legs:
			V.legs.append([int(l[0]), FD._flat(l[1])])
		var Rt: Dictionary = FD._route(w, V)
		var s := 0.0
		while s <= float(Rt.len):
			var pp: Array = FD.pose_at(Rt, s)
			var fx := Vector2.from_angle(float(pp[1]))
			var fy := Vector2(-fx.y, fx.x)
			for a in [-FD.HL, 0.0, FD.HL]:
				for b in [-FD.HW, FD.HW]:
					if bay.grow(0.3).has_point((pp[0] as Vector2) + fx * a + fy * b):
						near.append("%s->%s" % [pr[0], pr[1]])
			s += 0.1
	check(routes >= 10 and near.is_empty(), "no fac_drive7 route comes within 0.3 tiles of the bay (%d routes): %s" % [routes, str(near.slice(0, 6))])
	# the truck's drawn size (opaque pixels of its sprite) fits inside the bay: at a 45-degree row the opaque width is
	# 32*sqrt(2) px per tile of truck width; at an axis row it is 32 px per tile of (length + width)
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/g7_life7/manifest.json"))
	var e: Dictionary = man.life7.fuel_truck
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/g7_life7/" + String(e.file)))
	var opaque_w := func(row: int) -> int:
		var lo := 9999
		var hi := -1
		for y in range(row * int(e.fh), (row + 1) * int(e.fh)):
			for x in int(e.fw):
				if img.get_pixel(x, y).a > 0.6:
					lo = mini(lo, x)
					hi = maxi(hi, x)
		return hi - lo + 1
	var tw := float(opaque_w.call(1)) / (32.0 * sqrt(2.0))
	var tl := float(opaque_w.call(0)) / 32.0 - tw
	check(tl <= L - 0.1 and tw <= W - 0.1, "truck drawn %.2f x %.2f tiles (%.1f x %.1f m) fits inside the %.2f x %.2f bay with room" % [tl, tw, tl * 4.0, tw * 4.0, L, W])
	check(bay.grow(-0.02).has_point(bay.get_center() + d * tl * 0.5) and bay.grow(-0.02).has_point(bay.get_center() - d * tl * 0.5),
		"parked on the bay centre, the truck's nose and tail are inside the bay")
	# the dog kennel (barracks): off every lane, door front (the door cell + 2 tiles out), garage + its door front,
	# footprint and the fuel bay (+0.2), same rule
	var s2 := _setup()
	var r := _layer(s2[0])
	var Ly = r[1]
	_step(s2[0], Ly, 3)
	var Lf: Dictionary = Ly.life[0]
	var O: Vector2 = Lf.O
	var kn := Vector2.ZERO
	for a in Lf.actors:
		if String(a.kind) == "dog":
			kn = (a.kennel as Vector2) - O
	var kr2 := Rect2(kn - Vector2(0.3, 0.3), Vector2(0.6, 0.6))
	var khits := []
	for k3 in keep:
		var lab := String(k3[0])
		if (k3[1] as Rect2).intersects(kr2) and (lab.begins_with("lane") or lab.begins_with("door front") or lab.begins_with("garage") or lab.begins_with("footprint")):
			khits.append(lab)
	if kr2.intersects(bay.grow(0.2)):
		khits.append("fuel bay")
	check(kn != Vector2.ZERO and khits.is_empty(), "dog kennel at %s (compound-local) is off every lane / door front / footprint / the fuel bay: %s" % [str(kn), str(khits)])
	r[0].free()
