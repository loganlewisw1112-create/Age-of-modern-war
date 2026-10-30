extends "res://tests/test_base.gd"
## G7 acceptance (owner: CIWS7). G7_REFERENCE 13.9c-32 + ORCH owner answers (2 mounts on opposite corners of the
## command centre roof; air first, ground too; Facility Engineers swap the empty drum):
## placement on the roof, a drone and a rocket intercepted only after the head lays, a guided missile intercepted,
## a Machine crawler inside the compound engaged (one outside is not), bursts + pauses, a dry drum goes silent and an
## Engineer walks up, swaps it and the mount fires again, destroyed with the building, hash twice-same, no facility =
## no cost. CIWS7-6 (13.9c-32b, owner "Realistic: ~25 deg limit"): the mounts cannot depress below -25 deg, so a ground
## target inside the blind ring (~8.63 tiles round a mount) is never engaged, one just outside it is, and no band the
## art draws or the sim shows is below the limit. Ground fire in the tests below is therefore placed outside the ring.

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


## CIWS7-6: one tick with unit tid held at p first (an idle crawler drifts, and the ring edge is only 0.1-0.3 tiles from the
## cases that need a crawler to stay put).
func _step_pinned(w: SimWorld, tid: int, p: Vector2) -> void:
	if w.entities.has(tid):
		HotState.set_pos(w, tid, p)
	_step(w)


## CIWS7-6: a point `dist` tiles east of mount bid's mount point (inside the 28-tile compound for dist <= 16; the blind ring
## of one mount is ~8.63 tiles, so dist >= 9.5 is engageable ground).
func _east(w: SimWorld, bid: int, dist: float) -> Vector2:
	return _mp(w, bid) + Vector2(dist, 0.0)


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
	# CIWS7-6: a crawler in the staging yard right under the command centre is inside the blind ring of both mounts: never engaged
	var ring_pt := O + Vector2(10.5, 17.5)
	check(C7.blind(C7.cfg(), _mp(w, ms[0]).distance_to(ring_pt)) and C7.blind(C7.cfg(), _mp(w, ms[1]).distance_to(ring_pt)),
		"the staging yard spot is inside the blind ring of both mounts (%.2f / %.2f tiles)" % [_mp(w, ms[0]).distance_to(ring_pt), _mp(w, ms[1]).distance_to(ring_pt)])
	var ringed := _unit(w, "m_breacher_crawler", M, ring_pt)
	w.entities[ringed].hp = 100000.0
	w.entities[ringed].max_hp = 100000.0
	var ring_ciws := 0
	for i in 100:
		_step_pinned(w, ringed, ring_pt)
		for ev in w.events:
			if String(ev.type) == "ShotFired" and bool(ev.get("ciws7", false)) and int(ev.get("target", -1)) == ringed:
				ring_ciws += 1
	check_eq(ring_ciws, 0, "a crawler in the blind ring right under the command centre is not engaged by the CIWS")
	w.destroy(ringed, "test", SimWorld.NEUTRAL)
	# beyond the ring (south end of the staging yard, 12.9 tiles from mount 1): engaged and killed
	_silence(w, fac)   # G7 LETHAL8D: re-silence: lockdown pop-up guns (cn_facility) spawn after the first _silence() (setup only)
	var inside := _unit(w, "m_breacher_crawler", M, O + Vector2(8.5, 24.5))
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
	check(shots.size() > 0, "the CIWS hoses a Machine crawler inside the compound, outside the blind ring")
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
	var p0 := _east(w, a, 9.7)
	var tid := _unit(w, "m_breacher_crawler", M, p0)   # CIWS7-6: outside the ~8.63-tile blind ring
	w.entities[tid].hp = 100000.0
	w.entities[tid].max_hp = 100000.0
	var fire_ticks := {}
	var codes := {}
	for i in 240:
		_step_pinned(w, tid, p0)   # FACFLOW8C (ORCH ruling, board need seq 18716, 13.9c-50): crawler pinned like the ring sub-tests (it drifted into the blind ring)
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
	var p0 := _east(w, a, 9.7)
	var tid := _unit(w, "m_breacher_crawler", M, p0)   # CIWS7-6: outside the ~8.63-tile blind ring
	w.entities[tid].hp = 100000.0
	w.entities[tid].max_hp = 100000.0
	var dry := []
	for i in 400:   # CIWS7-6: until the drum runs dry (the mount first lays onto the crawler 9.7 tiles out), then 60 ticks of silence
		_step_pinned(w, tid, p0)   # FACFLOW8C (ORCH ruling, board need seq 18716, 13.9c-50): crawler pinned like the ring sub-tests (it drifted into the blind ring)
		for ev in w.events:
			if String(ev.type) == "Ciws7Dry" and int(ev.get("ciws", -1)) == a:
				dry.append(ev)
		if not dry.is_empty():
			break
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
	var p2 := _east(w, a, 9.7)
	var t2 := _unit(w, "m_breacher_crawler", M, p2)
	var again := []
	for i in 120:   # FACFLOW8C (ORCH ruling, board need seq 18716, 13.9c-50): crawler pinned like the ring sub-tests (it drifted into the blind ring)
		_step_pinned(w, t2, p2)
		for ev in w.events:
			if String(ev.type) == "ShotFired" and int(ev.get("shooter", -1)) == a:
				again.append([int(w.tick), ev])
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
	_unit(w, "m_breacher_crawler", M, _east(w, ms[0], 9.7))
	_unit(w, "m_breacher_crawler", M, O + Vector2(8.5, 24.5))
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


# ---------------------------------------------------------------- CIWS7-5 (13.9c-32a): spread with range, straight stream
## The cone's hit share at the 3 ranges of the CIWS7-4 rule (crawler r 0.45, 80 mrad): ~1.00 at 3 tiles, ~0.64 at 7,
## ~0.16 at 14, strictly falling; a full-share kill chance stays certain. Then in play: one mount, a crawler ~9.6 tiles
## out (just outside the blind ring, CIWS7-6; was 3) vs one ~14 tiles out: the near burst's ShotFired.sh and the crawler's hp loss per fire tick are higher; every
## ciws7 ShotFired carries brg == Traverse7.bearing of the mount at its tick (the rounds fly along the barrel) and sd.
func test_hit_share_falls_with_range() -> void:
	_ensure_g7()
	var c := C7.cfg()
	var half := C7.half_angle(c)
	var want := {3.0: 1.0, 7.0: 0.64, 14.0: 0.16}
	var prev := 2.0
	for d in [3.0, 7.0, 14.0]:
		var s := C7.cone_share(d, 0.45, half)
		check(absf(s - float(want[d])) <= 0.02, "share at %.0f tiles %.3f ~ %.2f" % [d, s, float(want[d])])
		check(s < prev, "share falls with range (%.3f < %.3f at %.0f tiles)" % [s, prev, d])
		prev = s
	check(is_equal_approx(C7.p_share(1.0, 0.3), 1.0), "a certain kill stays certain at any share > 0")
	var near := _range_burst(9.6)    # CIWS7-6: just outside the ~8.63-tile blind ring (was 3.0)
	var far := _range_burst(14.0)
	if not check(not near.is_empty() and not far.is_empty(), "both crawlers engaged (near %s, far %s)" % [str(near.get("d")), str(far.get("d"))]):
		return
	check(float(near.d) < 11.0 and float(near.d) > C7.blind_radius(C7.cfg(), false) and float(far.d) > 13.0, "ranges near %.2f / far %.2f tiles" % [float(near.d), float(far.d)])
	check(float(near.sh) > float(far.sh), "hit share near %.3f > far %.3f" % [float(near.sh), float(far.sh)])
	check(float(near.loss) > float(far.loss), "hp lost per fire tick near %.1f > far %.1f" % [float(near.loss), float(far.loss)])
	check(int(near.brg_ok) == int(near.n) and int(far.brg_ok) == int(far.n) and int(near.n) > 0,
		"every ShotFired brg == the mount's Traverse7 bearing at its tick (near %d/%d, far %d/%d)" % [int(near.brg_ok), int(near.n), int(far.brg_ok), int(far.n)])


## One mount (the other silenced), one tough crawler at range r from it toward the staging yard (shrunk until inside
## the compound): {d, sh, loss (hp per fire tick, first 6 fire ticks), n events, brg_ok} or {} when never engaged.
func _range_burst(r: float) -> Dictionary:
	var w := _setup(23)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if ms.size() != 2:
		return {}
	w.entities[ms[1]].emp_until = w.tick + 1000000
	var bid := int(ms[0])
	var mp := _mp(w, bid)
	var F := CnFacility.fac(w, fac)
	var O := Vector2(CnFacility.origin(F))
	var cr: Rect2 = CnFacility.compound_rect(F).grow(-1.5)
	var dir := (O + Vector2(10.5, 17.5) - mp).normalized()
	var rr := r
	while rr > 2.0 and not cr.has_point(mp + dir * rr):
		rr -= 0.5
	var tid := _unit(w, "m_breacher_crawler", M, mp + dir * rr)
	w.entities[tid].hp = 100000.0
	w.entities[tid].max_hp = 100000.0
	var out := {"n": 0, "brg_ok": 0, "loss": 0.0, "sh": 0.0, "d": 0.0}
	var fired := 0
	for i in 400:
		var hp0 := HotState.get_hp(w, tid)
		_step(w)
		var got := false
		for ev in w.events:
			if String(ev.type) != "ShotFired" or not bool(ev.get("ciws7", false)) or int(ev.get("shooter", -1)) != bid:
				continue
			got = true
			out.n = int(out.n) + 1
			var t := (int(ev.get("sd", -1)) - bid * 131) / 977
			if ev.has("brg") and ev.has("sd") and absf(float(ev.brg) - Traverse7.bearing(w, w.entities[bid], t)) < 1e-6:
				out.brg_ok = int(out.brg_ok) + 1
			out.sh = float(ev.sh)
			out.d = float(ev.d)
		if got:
			fired += 1
			out.loss = float(out.loss) + (hp0 - HotState.get_hp(w, tid))
			if fired >= 6:
				break
	if fired == 0:
		return {}
	out.loss = float(out.loss) / float(fired)
	return out


## 13.9c-32a "wherever the barrel is point" + 13.9c-32b (depression limit): for every bearing (1 deg steps) and range the
## mount engages, the frame the picker shows (32 yaws x 6 bands, band = sim el_band) has its drawn barrel within MAX_ANG3
## deg (3D) of the stream fx_layer draws from the measured muzzle of that frame to the bore point, and within MAX_ANG deg
## on screen wherever the barrel is drawn at least 6 px per metre (15 px) long (seen nearly end-on the drawn stub has no
## clear screen direction). CIWS7-6: ground targets only OUTSIDE the blind ring (blind_radius + 0.01 .. 15 tiles), air
## targets tracked outside their ring (~8.42 .. 15; the mount fires out to air_radius 10), intercepts 2-10 (the high
## band, unaffected by the limit). Air targets INSIDE the ring are still engaged (13.9c-32b: everything in the air stays
## covered) but the barrel cannot point down the line to them: those cases are laid at the lowest band (asserted) and their
## angle is only printed, not bounded. Both bounds are regression guards set from the CIWS7-6 measurement (see the
## constants); the CIWS7-5 layout (bands -60..-21) measured 9.26 deg 3D / 16.09 deg screen over ground 2.5-15.
const MAX_ANG3 := 7.0    # CIWS7-6: measured 6.57 (was 9.26 with 13 deg band steps; now the yaw step of 11.25 deg dominates) - tightened from 9.5
const MAX_ANG := 8.5     # CIWS7-6: measured 7.95 for barrels drawn >= 6 px/m (was 16.09) - tightened from 16.5
const FXL = preload("res://presentation/view/fx_layer.gd")
const VUT = preload("res://presentation/view/view_util.gd")
const G5A = preload("res://presentation/art/g5_art.gd")
const MZG = preload("res://presentation/art/muzzle_g61.gd")


func _sweep_ranges(kind: String, c: Dictionary) -> Array:
	var ds: Array = []
	if kind == "icpt":
		var d := 2.0
		while d <= 10.001:
			ds.append(d)
			d += 0.5
		return ds
	var r0 := C7.blind_radius(c, kind == "air")
	ds.append(r0 + 0.01)   # the ring edge: the barrel at exactly the limit
	var d2 := ceilf((r0 + 0.01) * 2.0) / 2.0
	while d2 <= 15.001:
		if d2 > r0 + 0.02:
			ds.append(d2)
		d2 += 0.5
	return ds


func test_drawn_barrel_matches_stream() -> void:
	_ensure_g7()
	var b: Dictionary = ArtCatalog.manifest().get("buildings", {}).get("cn_ciws7", {})
	if not check(not b.is_empty() and int((b.get("g7", {}) as Dictionary).get("yaws", 0)) >= 16, "CIWS art has >= 16 yaw frames"):
		return
	var g7: Dictionary = b.g7
	check(int(g7.yaws) >= 16 and (g7.bands_deg as Array).size() >= 5, "%d yaws x %d elevation bands" % [int(g7.yaws), (g7.bands_deg as Array).size()])
	check(int(g7.bytes) <= int(g7.budget), "art %d bytes <= turret budget %d" % [int(g7.bytes), int(g7.budget)])
	var c := C7.cfg()
	var roof := float(c.get("roof_z", 15.5))
	var from := Vector2(60.0, 60.0)
	var anchor: Vector2 = VUT.iso(from + Vector2(0.6, 0.6))
	var mx := Vector2.ZERO          # max (screen, 3D) over the bounded cases
	var worst := ""
	var worst_s := ""
	var scr := [0.0, 0.0, 0.0]      # max screen angle for barrels drawn >= 4 / 6 / 8 px per metre
	var by_kind := {"ground": 0.0, "air": 0.0, "icpt": 0.0, "air_in_ring": 0.0}   # max 3D per kind
	var old3 := 0.0
	var n := 0
	var missing := 0
	var clamped_bad := 0
	var below := 0
	var lim := C7.depress_min(c)
	var bands: Array = g7.bands_deg
	for kind in ["ground", "air", "icpt", "air_in_ring"]:
		var ds: Array = []
		if kind == "air_in_ring":
			var d3 := 2.0
			while d3 < C7.blind_radius(c, true) - 0.01:
				ds.append(d3)
				d3 += 0.5
		else:
			ds = _sweep_ranges(kind, c)
		for deg in 360:
			var brg := deg_to_rad(float(deg))
			for dd in ds:
				var air_k: bool = kind == "air" or kind == "air_in_ring"
				var el: int = C7.EL_HIGH if kind == "icpt" else C7.el_band(c, dd, air_k)
				if kind != "icpt" and float(bands[el]) < lim - 0.001:
					below += 1
				if kind == "air_in_ring" and el != 0:
					clamped_bad += 1
				var st := G5A.building_state(b.states, {"facing_i": el * 8 + 2, "hp": 1.0, "built": true, "firing": 1, "tb": brg}, "rot")
				var sd: Dictionary = b.states.get(st, {})
				var tips: Array = MZG.building_tips("cn_ciws7", st, 0)
				if sd.is_empty() or tips.is_empty() or not sd.has("ax3"):
					missing += 1
					continue
				var a: Vector2 = anchor + tips[0]
				var aim: Vector2 = from + Vector2.from_angle(brg) * float(dd)
				var ht := 7.4 if kind == "ground" else 18.0
				if kind == "icpt":
					var m3 := Vector3(float(sd.mz3[0]), float(sd.mz3[1]), float(sd.mz3[2]))
					var hz := maxf((aim - (from + Vector2(m3.x, m3.y) / 4.0)).length() * 4.0, 0.5)
					ht = (roof + m3.z) * 9.8 + hz * tan(asin(clampf(float(sd.ax3[2]), -1.0, 1.0))) * 9.8
				var bp: Vector2 = VUT.iso(aim) - Vector2(0, ht)
				var ang: Vector2 = FXL.ciws7_angles(sd, a, bp, from, aim, ht, roof)
				by_kind[kind] = maxf(float(by_kind[kind]), ang.y)
				if kind == "air_in_ring":
					continue   # laid at the limit, the line to the target is steeper: printed, not bounded
				n += 1
				if ang.y > mx.y:
					mx.y = ang.y
					worst = "%s brg %d d %.2f -> %s" % [kind, deg, dd, st]
				var axl := Vector2(float(sd.ax[0]), float(sd.ax[1])).length()
				for ti in 3:
					if axl >= [4.0, 6.0, 8.0][ti]:
						scr[ti] = maxf(float(scr[ti]), absf(rad_to_deg(Vector2(float(sd.ax[0]), float(sd.ax[1])).angle_to(bp - a))))
				if ang.x > mx.x:
					mx.x = ang.x
					worst_s = "%s brg %d d %.2f -> %s ax %s a-anchor %s bp-a %s" % [kind, deg, dd, st, str(sd.ax), str(a - anchor), str(bp - a)]
				old3 = maxf(old3, _old_layout_angle(brg, dd, kind, roof))
	print("CIWS7-6 barrel vs stream over %d cases (ground %.2f..15 tiles, air %.2f..15, intercepts 2..10): max 3D %.2f deg, max screen %.2f deg (worst 3D: %s; worst screen: %s); max 3D by kind: ground %.2f / air %.2f / icpt %.2f; screen max by drawn barrel length >= 4 / 6 / 8 px/m: %.2f / %.2f / %.2f deg; air INSIDE the ring (laid at the %.0f deg limit, not bounded): max 3D %.2f deg; old 8 yaws x 3 bands: max 3D %.2f deg" % [n, C7.blind_radius(c, false), C7.blind_radius(c, true), mx.y, mx.x, worst, worst_s, by_kind.ground, by_kind.air, by_kind.icpt, scr[0], scr[1], scr[2], lim, by_kind.air_in_ring, old3])
	check_eq(missing, 0, "every case has a frame with a measured muzzle and an analytic barrel")
	check_eq(below, 0, "no ground / air case is shown a band below the depression limit %.0f deg" % lim)
	check_eq(clamped_bad, 0, "an air target inside the ring is laid at the lowest band (0)")
	check(mx.y <= MAX_ANG3, "max 3D angle drawn barrel vs stream %.2f <= %.1f deg (old layout %.2f)" % [mx.y, MAX_ANG3, old3])
	check(float(scr[1]) <= MAX_ANG, "max screen angle drawn barrel (>= 6 px/m) vs stream %.2f <= %.1f deg" % [float(scr[1]), MAX_ANG])


## The pre-CIWS7-5 layout (8 yaws, bands -29 / +10 / +46 deg; el 0 ground, air 2 within 6 tiles else 1, intercept 2;
## the old intercept stream climbed 0.6 x 28 px per tile), same mount geometry (trunnion 1.54 m up, 0.14 m forward,
## muzzle 2.54 m out along the bore) and the same target heights: 3D angle, deg.
func _old_layout_angle(brg: float, d: float, kind: String, roof: float) -> float:
	var pit: float = [-29.0, 10.0, 46.0][0 if kind == "ground" else (2 if (kind == "icpt" or d < 6.0) else 1)]
	var y := roundi(brg / (PI / 4.0)) * (PI / 4.0)
	var p := deg_to_rad(pit)
	var ax := Vector3(cos(p) * cos(y), cos(p) * sin(y), sin(p))
	var mz := Vector3(0.14 * cos(y), 0.14 * sin(y), 1.54) + ax * 2.54
	var hz_m := 7.4 / 9.8 if kind == "ground" else 18.0 / 9.8
	if kind == "icpt":
		hz_m = roof + mz.z + d * 0.6 * 28.0 / 9.8
	var v := Vector3(d * 4.0 * cos(brg) - mz.x, d * 4.0 * sin(brg) - mz.y, hz_m - (roof + mz.z))
	return rad_to_deg(ax.angle_to(v))


# ---------------------------------------------------------------- CIWS7-6 (13.9c-32b): depression limit ~-25 deg, blind ring
## Pitch (deg) of the line from the muzzle of a barrel pitched p_deg (trunnion roof_z + trunnion_m up, trunnion_fwd_m
## forward, barrel_m out along the bore) to a target at horizontal range d tiles and height gz m: the independent
## re-derivation the blind radius is checked against.
func _line_pitch_deg(c: Dictionary, p_deg: float, d: float, gz: float) -> float:
	var E: Dictionary = c.elev
	var tz := float(c.roof_z) + float(E.trunnion_m)
	var p := deg_to_rad(p_deg)
	var bl := float(E.barrel_m)
	return rad_to_deg(atan2(gz - (tz + bl * sin(p)), d * float(E.tile_m) - float(E.trunnion_fwd_m) - bl * cos(p)))


func test_depression_limit_content_and_art() -> void:
	_ensure_g7()
	var c := C7.cfg()
	var lim := C7.depress_min(c)
	check(lim <= -23.0 and lim >= -27.0, "depression limit %.1f deg is about -25 (owner: Realistic, ~25 deg limit)" % lim)
	var bands: Array = c.elev.bands_deg
	var low := 0
	for i in bands.size():
		if float(bands[i]) < lim - 0.001:
			low += 1
	check_eq(low, 0, "no content band is below the limit (bands %s)" % str(bands))
	check(absf(float(bands[0]) - lim) <= 0.001, "the lowest aim band IS the limit (%.1f)" % float(bands[0]))
	for i in 3:
		check(float(bands[i]) < float(bands[i + 1]), "aim bands rise (%.1f < %.1f)" % [float(bands[i]), float(bands[i + 1])])
	var b: Dictionary = ArtCatalog.manifest().get("buildings", {}).get("cn_ciws7", {})
	if not check(not b.is_empty() and b.has("g7"), "CIWS art in the manifest"):
		return
	var same := (b.g7.bands_deg as Array).size() == bands.size()
	for i in mini((b.g7.bands_deg as Array).size(), bands.size()):
		same = same and absf(float(b.g7.bands_deg[i]) - float(bands[i])) < 0.001
	check(same, "the art was generated at the content bands (art %s, content %s)" % [str(b.g7.bands_deg), str(bands)])
	# every drawn barrel (all states carrying an analytic bore) points no lower than the limit
	var minp := 90.0
	var worst := ""
	var nb := 0
	for nm in b.states:
		var sd: Dictionary = b.states[nm]
		if not (sd.get("ax3") is Array):
			continue
		nb += 1
		var pdeg := rad_to_deg(asin(clampf(float(sd.ax3[2]), -1.0, 1.0)))
		if pdeg < minp:
			minp = pdeg
			worst = String(nm)
	check(nb >= 300, "%d drawn barrel states carry their bore" % nb)
	check(minp >= lim - 0.05, "lowest drawn barrel %.2f deg (%s) >= limit %.1f" % [minp, worst, lim])
	print("CIWS7-6 art: bands %s, %d barrel states, lowest drawn bore %.2f deg (%s)" % [str(bands), nb, minp, worst])


func test_blind_ring_geometry_and_bands() -> void:
	_ensure_g7()
	var c := C7.cfg()
	var lim := C7.depress_min(c)
	for air in [false, true]:
		var gz := float(c.elev.tz_air_m) if air else float(c.elev.tz_ground_m)
		var R := C7.blind_radius(c, air)
		check(R > 8.0 and R < 9.0, "%s blind radius %.3f tiles (owner: about 8-9 tiles round the building)" % ["air" if air else "ground", R])
		# independent check: nearer than R the line to the target is steeper than the limit, farther out it is shallower
		var inner := _line_pitch_deg(c, lim, R - 0.02, gz)
		var outer := _line_pitch_deg(c, lim, R + 0.02, gz)
		check(inner < lim and outer > lim, "the line from the limit muzzle to the target crosses the limit at R (%.2f < %.1f < %.2f deg)" % [inner, lim, outer])
		check(C7.blind(c, R - 0.01, air) and not C7.blind(c, R + 0.01, air), "blind() flips at R")
	# band choice: ground targets from the ring edge out to 15 tiles use the aim bands in order, never below the limit
	var seen := {}
	var prev := -1
	var d := C7.blind_radius(c, false) + 0.01
	var bad_order := 0
	var bad_low := 0
	while d <= 15.0:
		var el := C7.el_band(c, d, false)
		seen[el] = true
		if el < prev:
			bad_order += 1
		prev = el
		if float(c.elev.bands_deg[el]) < lim - 0.001:
			bad_low += 1
		d += 0.05
	check_eq(bad_order, 0, "the band never falls back as the target moves out")
	check_eq(bad_low, 0, "no ground band 8.6-15 tiles out is below the limit")
	check_eq(seen.keys().size(), 4, "all four aim bands are used by ground targets 8.6-15 tiles out (%s)" % str(seen.keys()))
	# any range at all (including the whole ring and a target under the muzzle): never a band below the limit or the rest band
	var worst_el := 0
	for air in [false, true]:
		var dd := 0.0
		while dd <= 20.0:
			var el2 := C7.el_band(c, dd, air)
			if float(c.elev.bands_deg[el2]) < lim - 0.001 or el2 == C7.EL_REST:
				worst_el = el2 + 100
			dd += 0.1
	check_eq(worst_el, 0, "el_band over 0-20 tiles never returns a band below the limit or the rest band")
	# a content band below the limit is skipped by the sim (a hand-edited elev block cannot put the barrels below it)
	var c2: Dictionary = c.duplicate(true)
	c2.elev.bands_deg = [-60.0, -25.0, -18.0, -14.5, 8.0, 32.0]
	check(C7.el_band(c2, 3.0, false) != 0, "a band below the limit is never chosen (el_band skips band 0 = -60)")


## The sim's own engageability predicate, measured: for each mount and three directions inside the compound, the first
## range at which a Machine crawler becomes a valid ground target (0.01-tile steps) is the blind radius.
func test_blind_ring_measured_per_mount() -> void:
	var w := _setup(41)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var c := C7.cfg()
	var R := C7.blind_radius(c, false)
	var tid := _unit(w, "m_breacher_crawler", M, Vector2(5.0, 5.0))
	var t: Dictionary = w.entities[tid]
	var report := []
	for bid in ms:
		var b: Dictionary = w.entities[bid]
		var mp := _mp(w, bid)
		var area: Rect2 = C7._area(w, _rec(w, bid), c)
		for dir in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1).normalized()]:
			var first := -1.0
			var s := 6.0
			while s <= 12.0:
				var p: Vector2 = mp + dir * s
				HotState.set_pos(w, tid, p)
				if C7._ground_ok(w, b, c, mp, t, area):
					first = s
					break
				s += 0.01
			if not check(first > 0.0, "mount %d dir %s: the crawler becomes engageable by 12 tiles" % [bid, str(dir)]):
				continue
			check(absf(first - R) <= 0.011, "mount %d dir %s: measured blind radius %.2f ~ %.3f" % [bid, str(dir), first, R])
			report.append("%d %s = %.2f" % [bid, str(dir.snapped(Vector2(0.1, 0.1))), first])
	print("CIWS7-6 blind ring measured per mount (tiles from the mount point): %s (closed form ground %.3f, air %.3f)" % [", ".join(report), R, C7.blind_radius(c, true)])


## In play, one mount live, the crawler held in place each tick: inside the blind ring (4 / 7 / 8.3 tiles east, 8.3 south) it
## is never engaged, outside it (9.0 east / 9.0 south / 9.5 / 14.5) it is, and no engagement happens inside the radius.
func test_ring_crawler_never_engaged_outside_is() -> void:
	var w := _setup(43)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	w.entities[ms[1]].emp_until = w.tick + 1000000
	var a: int = ms[0]
	var c := C7.cfg()
	var R := C7.blind_radius(c, false)
	var cases := [[Vector2(4.0, 0.0), false], [Vector2(7.0, 0.0), false], [Vector2(8.3, 0.0), false], [Vector2(0.0, 8.3), false],
		[Vector2(9.0, 0.0), true], [Vector2(0.0, 9.0), true], [Vector2(9.5, 0.0), true], [Vector2(14.5, 0.0), true]]
	var inside_fired := 0
	var outside_ok := 0
	var min_d := 99.0
	for cs in cases:
		var off: Vector2 = cs[0]
		var tid := _unit(w, "m_breacher_crawler", M, _mp(w, a) + off)
		w.entities[tid].hp = 100000.0
		w.entities[tid].max_hp = 100000.0
		var got := 0
		var tgt_held := 0
		for i in 80:
			_step_pinned(w, tid, _mp(w, a) + off)
			if int(_rec(w, a).t) == tid:
				tgt_held += 1
			for ev in w.events:
				if String(ev.type) == "ShotFired" and bool(ev.get("ciws7", false)) and int(ev.get("target", -1)) == tid:
					got += 1
					min_d = minf(min_d, float(ev.d))
		var dist := off.length()
		if bool(cs[1]):
			check(got > 0 and tgt_held > 0, "a crawler %.1f tiles out (outside the ring) is engaged (%d shots, held %d ticks)" % [dist, got, tgt_held])
			outside_ok += 1 if got > 0 else 0
		else:
			check_eq(got, 0, "a crawler %.1f tiles out (inside the ~%.2f-tile ring) is never fired on" % [dist, R])
			check_eq(tgt_held, 0, "the mount never takes the %.1f-tile crawler as its target" % dist)
			inside_fired += got
		w.destroy(tid, "test", SimWorld.NEUTRAL)
		_run(w, 3)
	check_eq(int(C7.counters.get("ring_viol", 0)), 0, "the in-sim tripwire counted no ground fire tick inside the ring")
	check(min_d >= R - 0.001, "no ground engagement closer than the blind radius (nearest fired-on range %.3f >= %.3f)" % [min_d, R])
	print("CIWS7-6 ring play: inside shots %d, outside engaged %d/4, nearest fired-on %.3f tiles (radius %.3f)" % [inside_fired, outside_ok, min_d, R])


## A held ground target that walks into the ring is dropped; the shown band never goes below the limit, with air targets
## laid inside the ring too (air engagement unchanged: the barrels sit at the lowest band).
func test_shown_band_never_below_limit_in_play() -> void:
	var w := _setup(47)
	var fac := _facility(w)
	var ms := C7.mounts_of(w, fac)
	if not check_eq(ms.size(), 2, "mounts"):
		return
	var c := C7.cfg()
	var lim := C7.depress_min(c)
	var a: int = ms[0]
	w.entities[ms[1]].emp_until = w.tick + 1000000
	var bands: Array = c.elev.bands_deg
	# a crawler engaged outside the ring, then moved into it
	var tid := _unit(w, "m_breacher_crawler", M, _east(w, a, 11.0))
	w.entities[tid].hp = 100000.0
	w.entities[tid].max_hp = 100000.0
	for i in 60:
		_step_pinned(w, tid, _east(w, a, 11.0))
	check_eq(int(_rec(w, a).t), tid, "the mount holds the crawler 11 tiles out")
	var held := 0
	for i in 40:
		_step_pinned(w, tid, _east(w, a, 5.0))
		if int(_rec(w, a).t) == tid:
			held += 1
	check_eq(held, 0, "the crawler walked into the blind ring: it is dropped, not held")
	w.destroy(tid, "test", SimWorld.NEUTRAL)
	# drones at 3 / 6 / 9 / 12 tiles on different bearings: whatever the mount is laid on, the shown band is not below the limit
	var shown_low := 0
	var shown_aim := 0
	var samples := 0
	for k in 4:
		var dist := 3.0 + 3.0 * float(k)
		var did := _unit(w, "m_micro_drone", M, _mp(w, a) + Vector2.from_angle(float(k) * 1.9 + 0.3) * dist)
		for i in 60:
			_step(w)
			var el := int(w.entities[a].facing_i) / 8
			if el <= 3:
				shown_aim += 1
				if float(bands[el]) < lim - 0.001:
					shown_low += 1
			var mel := int(_rec(w, a).el)
			if mel <= 3 and float(bands[mel]) < lim - 0.001:
				shown_low += 1
			samples += 1
		if w.entities.has(did):
			w.destroy(did, "test", SimWorld.NEUTRAL)
	check_eq(shown_low, 0, "the band the mount shows was never below the limit over %d ticks (%d with the barrels depressed)" % [samples, shown_aim])
	check(shown_aim > 0, "the run did depress the barrels onto air targets (%d ticks)" % shown_aim)
