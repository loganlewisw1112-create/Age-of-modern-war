extends "res://tests/test_base.gd"
## G7 acceptance (owner: CIWS7). G7_REFERENCE 13.9c-32 + ORCH owner answers (2 mounts on opposite corners of the
## command centre roof; air first, ground too; Facility Engineers swap the empty drum):
## placement on the roof, a drone and a rocket intercepted only after the head lays, a guided missile intercepted,
## a Machine crawler inside the compound engaged (one outside is not), bursts + pauses, a dry drum goes silent and an
## Engineer walks up, swaps it and the mount fires again, destroyed with the building, hash twice-same, no facility =
## no cost.

const C7 = preload("res://sim/systems/ciws7.gd")
const CD = preload("res://sim/systems/counterdrone.gd")
const E7 = preload("res://sim/systems/engineer7.gd")
const S7 = preload("res://sim/systems/sentinels7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Traverse7 = preload("res://sim/systems/traverse7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const M := 1


func _ensure_g7() -> void:
	if Content.building("cn_ciws7").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


## Human A (fid 0) vs Machine (fid 1), both inert; whole map GRASS, no entities.
func _setup(seed_v: int = 7) -> SimWorld:
	_ensure_g7()
	var w := make_world({"seed": seed_v, "victory": "endless", "sides": [
		{"faction": "human_a", "stage": 10, "credits": 200000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 10, "credits": 50000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	t.fill(Terrain.GRASS)
	w.map.terrain = t
	w.map.erase("burnt")
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		HotState.sync(w)
	Movement.rebuild_nav(w)
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 200000
	return w


func _step(w: SimWorld) -> void:
	w.step()
	if not SimWorld.SYSTEM_ORDER.has(C7):
		C7.tick(w)


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		_step(w)


## Raises a facility for side 0 in the map centre (no Sentinel garrison: the CIWS works alone, plain to read) and
## silences every other facility weapon (towers, laser CIWS, wall turrets, drone bay). Returns the core id.
func _facility(w: SimWorld) -> int:
	var off: Array = CnFacility.conf().core_offset
	var o := Vector2i(int(w.map.w) / 2 - 14, int(w.map.h) / 2 - 14)
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(int(off[0]), int(off[1])), true)
	S7._st(w).seeded.append(id)
	_run(w, 24)
	_silence(w, id)
	return id


func _silence(w: SimWorld, fac: int) -> void:
	for bid in w.entities.keys():
		var b: Dictionary = w.entities[bid]
		if b.kind != "building" or int(b.owner) != 0 or int(bid) == fac or C7.is_mount(b):
			continue
		b.emp_until = w.tick + 1000000
		if String(SimWorld.Combat.stats(b).get("weapon", "")) != "":
			HotState.set_cd(w, int(bid), 1000000)
	var dcmd := {"type": "dronebay_auto", "on": false, "issuer": 0}
	if SimWorld.DroneBay7.validate_command(w, dcmd) == "":
		SimWorld.DroneBay7.apply_command(w, dcmd)


func _unit(w: SimWorld, def_id: String, fid: int, p: Vector2) -> int:
	return w.spawn_unit(def_id, fid, p)


func _mp(w: SimWorld, bid: int) -> Vector2:
	return Vector2(w.entities[bid].c7m)


func _rec(w: SimWorld, bid: int) -> Dictionary:
	return C7.state(w).m[str(bid)]


## Events of type ty (optionally filtered by key == val) seen while running n ticks: [[tick, ev], ...].
func _collect(w: SimWorld, n: int, ty: String, key: String = "", val = null) -> Array:
	var out := []
	for i in n:
		_step(w)
		for ev in w.events:
			if String(ev.type) == ty and (key == "" or ev.get(key) == val):
				out.append([w.tick, ev])
	return out


# ---------------------------------------------------------------- placement
func test_two_mounts_on_the_command_centre_roof() -> void:
	var w := _setup()
	var fac := _facility(w)
	var F := CnFacility.fac(w, fac)
	var ms := C7.mounts_of(w, fac)
	check_eq(ms.size(), 2, "the command centre carries 2 rotary CIWS mounts")
	var pz: Rect2 = CnFacility.zone(F, "planning")
	var ctr := pz.get_center()
	for bid in ms:
		var b: Dictionary = w.entities[bid]
		check_eq(String(b.def), "cn_ciws7", "mount def")
		check_eq(int(b.owner), 0, "owner-only: the facility owner's mount")
		check_eq(int(b.cn_fac), fac, "a part of its facility")
		check(bool(b.built) and bool(b.get("unhackable", false)), "built, unhackable")
		check(pz.has_point(Vector2(b.cell) + Vector2(0.5, 0.5)), "footprint cell inside the command centre %s" % [b.cell])
		var mp := _mp(w, bid)
		check(pz.grow(0.01).has_point(mp), "mount point %s on the roof %s" % [mp, pz])
		# corners of the roof brim (the 4-storey tower block, compound-local x 8.1..11.3, y 9.08..11.92; fact
		# facb7.zone_heights seq 4583 / g7_fac7f planning()): the zone rect also holds the low east vestibule
		var rb := Rect2(Vector2(CnFacility.origin(F)) + Vector2(8.1, 9.08), Vector2(3.2, 2.84))
		var dc := INF
		for cc in [rb.position, Vector2(rb.end.x, rb.position.y), rb.end, Vector2(rb.position.x, rb.end.y)]:
			dc = minf(dc, mp.distance_to(cc))
		check(dc <= 0.9, "mount %d stands on a roof corner (%.2f tiles from it)" % [bid, dc])
		check_eq(C7.ammo(w, bid), int(C7.cfg().drum), "starts with a full drum")
	if ms.size() == 2:
		check((_mp(w, ms[0]) - ctr).dot(_mp(w, ms[1]) - ctr) < 0.0, "opposite corners (all-round cover)")
	check(not bool(Content.building("cn_ciws7").get("buildable", true)), "not buildable elsewhere")
	check(C7.raise(w, F).is_empty(), "raised once per facility")


# ---------------------------------------------------------------- air
func test_drone_shot_down_after_laying() -> void:
	var w := _setup(11)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var a: int = ms[0]
	w.entities[ms[1]].emp_until = w.tick + 1000000   # one mount: plain to read
	var mp := _mp(w, a)
	var b0 := Traverse7.bearing(w, w.entities[a], int(w.tick))
	var did := _unit(w, "m_micro_drone", M, mp + Vector2.from_angle(b0 + PI) * 7.0)
	var need := absf(wrapf((Vector2(w.entities[did].pos) - mp).angle() - b0, -PI, PI))
	var rate: float = float(Traverse7.mount(w.entities[a])[1])
	var min_ticks := int(floor((need - deg_to_rad(6.0)) / rate))
	var t0 := int(w.tick)
	var first := -1
	var off_deg := 999.0
	var killed := false
	for i in 200:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "ShotFired" and bool(ev.get("ciws7", false)) and int(ev.shooter) == a and first < 0:
				first = int(w.tick) - t0
				off_deg = rad_to_deg(absf(wrapf((Vector2(ev.to) - mp).angle() - Traverse7.bearing(w, w.entities[a], int(w.tick)), -PI, PI)))
			if String(ev.type) == "Ciws7Kill" and int(ev.id) == did:
				killed = true
		if killed:
			break
	check(first >= 0, "the mount fired at the drone")
	check(first >= min_ticks, "it traversed before firing: first shot after %d ticks, a %.0f deg swing needs >= %d" % [first, rad_to_deg(need), min_ticks])
	check(off_deg <= 6.0, "laid on the drone when it fired (%.1f deg off)" % off_deg)
	check(killed and not w.entities.has(did), "drone shot down")
	check(C7.ammo(w, a) < int(C7.cfg().drum), "rounds came out of the drum")


# ---------------------------------------------------------------- rockets / shells / missiles
func test_rocket_intercepted_after_laying() -> void:
	var w := _setup(13)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var a: int = ms[0]
	w.entities[ms[1]].emp_until = w.tick + 1000000
	var pk: Dictionary = C7.cfg().intercept_pk
	var keep := pk.duplicate()
	for k in pk.keys():
		pk[k] = 1.0   # deterministic kill once laid (the roll itself is w.rng, PROVISIONAL Pk in the def)
	var mp := _mp(w, a)
	var b0 := Traverse7.bearing(w, w.entities[a], int(w.tick))
	var at := mp + Vector2.from_angle(b0 + PI * 0.97) * 5.0
	var a0 := C7.ammo(w, a)
	var got1 := CD.intercept_strike(w, M, at, "rocket")
	check(not got1, "a rocket from behind gets through: the head cannot swing ~175 deg inside the window")
	check_eq(C7.ammo(w, a), a0, "no rounds spent on a threat it could not lay onto")
	_run(w, 14)
	var got2 := CD.intercept_strike(w, M, at, "rocket")
	check(got2, "the next rocket on the same line is shot down (the head swung onto it)")
	var ic := 0
	for ev in w.events:
		if String(ev.type) == "Ciws7Intercept" and int(ev.ciws) == a:
			ic += 1
			check(int(ev.lay_ticks) >= 0, "intercept carries its lay time")
	check_eq(ic, 1, "one Ciws7Intercept event")
	check_eq(C7.ammo(w, a), a0 - int(C7.cfg().intercept_rounds), "an intercept burst came out of the drum")
	_run(w, 2)
	var src := {"id": -1, "owner": M, "kind": "unit", "def": "m_micro_drone", "pos": at}
	var shot := {"guided": true, "weapon": "test_missile", "cls": "missile"}
	check(CD.shot_blocked(w, src, shot, {"id": fac, "owner": 0}, mp + Vector2(1.0, 1.0)), "a guided missile into the compound is shot down")
	var a1 := C7.ammo(w, a)
	_rec(w, a).a = 0
	check(not CD.intercept_strike(w, M, mp + Vector2(1.0, 0.5), "shell"), "a dry mount intercepts nothing")
	_rec(w, a).a = a1
	for k in keep:
		pk[k] = keep[k]


# ---------------------------------------------------------------- ground
func test_machine_crawler_in_compound_engaged_outside_not() -> void:
	var w := _setup(17)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var F := CnFacility.fac(w, fac)
	var cr: Rect2 = CnFacility.compound_rect(F)
	var O := Vector2(CnFacility.origin(F))
	var outside := _unit(w, "m_breacher_crawler", M, Vector2(cr.end.x + 2.5, O.y + 10.5))   # beyond the east wall, in range
	var shots_out := _collect(w, 60, "ShotFired", "target", outside)
	var by_ciws := 0
	for s in shots_out:
		if bool(s[1].get("ciws7", false)):
			by_ciws += 1
	check_eq(by_ciws, 0, "a crawler outside the compound is not engaged (the walls and towers own it)")
	w.destroy(outside, "test", SimWorld.NEUTRAL)
	var inside := _unit(w, "m_breacher_crawler", M, O + Vector2(10.5, 17.5))   # staging yard south of the command centre
	var shots := []
	var dead := -1
	for i in 400:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "ShotFired" and bool(ev.get("ciws7", false)) and int(ev.get("target", -1)) == inside:
				shots.append(int(w.tick))
		if not w.entities.has(inside):
			dead = i
			break
	check(shots.size() > 0, "the CIWS hoses a Machine crawler inside the compound")
	check(dead >= 0, "the crawler dies")
	if not shots.is_empty():
		var ev_el := false
		for bid in ms:
			ev_el = ev_el or int(w.entities[bid].facing_i) >= 0
		check(ev_el, "frame code present")


func test_bursts_and_pauses() -> void:
	var w := _setup(19)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var a: int = ms[0]
	w.entities[ms[1]].emp_until = w.tick + 1000000
	var O := Vector2(CnFacility.origin(CnFacility.fac(w, fac)))
	var tid := _unit(w, "m_breacher_crawler", M, O + Vector2(14.5, 6.5))
	w.entities[tid].hp = 100000.0
	w.entities[tid].max_hp = 100000.0
	var fire_ticks := {}
	var codes := {}
	for i in 240:
		_step(w)
		for ev in w.events:
			if String(ev.type) == "ShotFired" and bool(ev.get("ciws7", false)) and int(ev.shooter) == a:
				fire_ticks[int(w.tick)] = int(ev.get("rounds", 0))
		codes[int(w.entities[a].facing_i) % 8] = true
	var ts: Array = fire_ticks.keys()
	ts.sort()
	check(ts.size() >= 30, "kept firing at a tough target (%d fire ticks)" % ts.size())
	var runs := []
	var cur := 0
	var gaps := []
	for i in ts.size():
		if i > 0 and int(ts[i]) != int(ts[i - 1]) + 1:
			runs.append(cur)
			gaps.append(int(ts[i]) - int(ts[i - 1]) - 1)
			cur = 0
		cur += 1
	runs.append(cur)
	var bmax := C7.ticks(float(C7.cfg().burst_max_s))
	var pause := C7.ticks(float(C7.cfg().pause_s))
	var longest := 0
	for r in runs:
		longest = maxi(longest, int(r))
	check(runs.size() >= 2, "fires in bursts (%d bursts)" % runs.size())
	check(longest <= bmax, "no burst longer than burst_max (%d <= %d ticks)" % [longest, bmax])
	for g in gaps:
		check(int(g) >= pause, "a pause of >= %d ticks between bursts (got %d)" % [pause, int(g)])
	var rsum := 0
	for k in ts:
		rsum += int(fire_ticks[k])
	var rpt := float(rsum) / maxf(float(ts.size()), 1.0)
	check(rpt >= 2.0 and rpt <= 3.0, "high rate: %.2f rounds a tick (3000 rpm = 2.5)" % rpt)
	check(codes.has(2) and codes.has(1), "display phases spin + fire seen %s" % [codes.keys()])


# ---------------------------------------------------------------- drum + engineer
func test_dry_drum_engineer_swaps_and_it_fires_again() -> void:
	var w := _setup(23)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var a: int = ms[0]
	w.entities[ms[1]].emp_until = w.tick + 1000000
	check(not E7.engineers_of(w, fac).is_empty(), "the facility has its Engineer crew")
	_rec(w, a).a = 30
	var O := Vector2(CnFacility.origin(CnFacility.fac(w, fac)))
	var tid := _unit(w, "m_breacher_crawler", M, O + Vector2(14.5, 6.5))
	w.entities[tid].hp = 100000.0
	w.entities[tid].max_hp = 100000.0
	var dry := _collect(w, 200, "Ciws7Dry", "ciws", a)
	check(not dry.is_empty(), "the drum runs dry")
	check_eq(C7.ammo(w, a), 0, "0 rounds left")
	var after := _collect(w, 60, "ShotFired", "shooter", a)
	check(after.is_empty(), "a dry mount goes silent (%d shots after dry)" % after.size())
	check_eq(int(w.entities[a].facing_i) % 8, 4, "dry frame code")
	var ext: Dictionary = S7.state(w).get("ext", {}).get(str(fac), {})
	check(ext.has(C7.job_id(a)), "an engineer job is on the facility board")
	w.destroy(tid, "test", SimWorld.NEUTRAL)
	var swap_seen := false
	var rel = null
	var t_dry := int(w.tick)
	for i in 3600:
		_step(w)
		if int(w.entities[a].facing_i) % 8 == 3:
			swap_seen = true
		for ev in w.events:
			if String(ev.type) == "Ciws7Reloaded" and int(ev.ciws) == a:
				rel = ev
		if rel != null:
			break
	check(rel != null, "the drum was swapped (%d s after going dry)" % ((int(w.tick) - t_dry) / 20))
	if rel == null:
		return
	var eng = w.entities.get(int(rel.unit))
	check(eng != null and E7.is_engineer(eng), "by a Facility Engineer")
	if eng != null:
		check(Vector2(eng.pos).distance_to(C7.stair_door(w, a)) <= 1.2, "who walked up to the command centre stair door")
	check(swap_seen, "the mount showed its drum-swap frames")
	check_eq(C7.ammo(w, a), int(C7.cfg().drum), "a full drum")
	check(not S7.state(w).get("ext", {}).get(str(fac), {}).has(C7.job_id(a)), "the job is taken down")
	var t2 := _unit(w, "m_breacher_crawler", M, O + Vector2(14.5, 6.5))
	var again := _collect(w, 120, "ShotFired", "shooter", a)
	check(not again.is_empty(), "it fires again after the swap")
	if w.entities.has(t2):
		w.destroy(t2, "test", SimWorld.NEUTRAL)


# ---------------------------------------------------------------- lifecycle
func test_destroyed_with_the_building() -> void:
	var w := _setup(29)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	check_eq(ms.size(), 2, "mounts")
	w.destroy(fac, "test", M)
	var lost := _collect(w, 40, "EntityDestroyed", "cause", "ciws7_host")
	for bid in ms:
		check(not w.entities.has(bid), "mount %d destroyed with the building" % bid)
	check_eq(lost.size(), ms.size(), "both mounts lost with cause ciws7_host")
	check((C7.state(w).m as Dictionary).is_empty(), "their state is gone")


func _scenario_hash() -> String:
	var w := _setup(31)
	var fac := _facility(w)
	var O := Vector2(CnFacility.origin(CnFacility.fac(w, fac)))
	var ms := C7.mounts_of(w, fac)
	if not ms.is_empty():
		_unit(w, "m_micro_drone", M, _mp(w, ms[0]) + Vector2(-6.0, 2.0))
	_unit(w, "m_breacher_crawler", M, O + Vector2(14.5, 6.5))
	_unit(w, "m_breacher_crawler", M, O + Vector2(9.5, 17.5))
	_run(w, 240)
	return w.state_hash()


func test_hash_twice_same() -> void:
	var h1 := _scenario_hash()
	var h2 := _scenario_hash()
	check_eq(h1, h2, "same inputs, same hash with the CIWS firing")


func test_no_facility_no_cost() -> void:
	var w := _setup(37)
	var f0 := int(C7.counters.fire)
	_unit(w, "m_breacher_crawler", M, Vector2(40.5, 40.5))
	_run(w, 60)
	check(not w.sys_state.has("ciws7"), "no facility: no CIWS state is ever created")
	check_eq(int(C7.counters.fire), f0, "no facility: nothing fires")
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		C7.tick(w)
	var us := float(Time.get_ticks_usec() - t0) / 2000.0
	check(us < 20.0, "no facility: tick costs %.2f us (two dictionary lookups)" % us)
