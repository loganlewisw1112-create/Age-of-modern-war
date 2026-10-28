extends "res://tests/test_base.gd"
## G7 AIRV7 acceptance: the CN Vanta rotorless gunship (docs/G7_REFERENCE.md 13.9c-14, 13.9c-15).
## Roof-pad basing, every hardpoint item firing from its own mount, mirrored side pair, rearm / refuel / loadout swap
## on the pad, flares / deterrents vs a guided SAM, stealth, AI defence, no facility = no state, hash twice-same.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Vanta7 = preload("res://sim/systems/vanta7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Airdef = preload("res://sim/systems/airdef.gd")
const Combat = preload("res://sim/systems/combat.gd")


func _ensure_g7() -> void:
	if Content.unit("cn_vanta_a").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


func _setup() -> Array:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
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
	return [w, o]


func _facility(w: SimWorld, o: Vector2i) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return id


func _fac_id(w: SimWorld) -> int:
	var fs: Array = CnFacility.facilities(w, 0)
	return int(fs[0]) if not fs.is_empty() else 0


## A Vanta for side 0 registered on the facility's roof pad.
func _vanta(w: SimWorld) -> Dictionary:
	var fk := _fac_id(w)
	var rp := Vanta7.pad_of(w, fk)
	var id := w.spawn_unit("cn_vanta_a", 0, Vector2(rp.centre) + Vector2(3, 3))
	w.run_ticks(1)
	return w.entities[id]


## Lifts e and parks it in the air at p facing `face` (radians), every mag full.
func _hover_at(w: SimWorld, e: Dictionary, p: Vector2, face: float) -> void:
	var Air = load("res://sim/systems/air.gd")
	var f: Dictionary = Air._ensure(w, e)
	Air._lift(w, e, f)
	e.pos = p
	e.facing = face
	Movement.stop_path(e)
	e.order = {"type": "idle"}
	var r := Vanta7.rec(w, int(e.id))
	r.rdy = {}
	Vanta7._fill(r)


func _shots(w: SimWorld, ticks: int, shooter: int) -> Array:
	var out := []
	for i in ticks:
		w.run_ticks(1)
		for ev in w.events:
			if String(ev.type) == "ShotFired" and int(ev.shooter) == shooter:
				out.append(ev)
	return out


func test_no_facility_no_state() -> void:
	var w := make_world()
	_ensure_g7()
	w.run_ticks(60)
	check(not w.sys_state.has("vanta7"), "a match without a Vanta has no vanta7 state (hash unchanged)")
	check(Vanta7.can_produce(w, 0, "cn_vanta_a") != "", "no facility -> no roof pad -> cannot train a Vanta: '%s'" % Vanta7.can_produce(w, 0, "cn_vanta_a"))
	check_eq(Vanta7.can_produce(w, 0, "rifleman"), "", "other items are not gated")


func test_roof_pad_basing_and_one_per_pad() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var fk := _fac_id(w)
	check(fk > 0, "facility raised")
	check_eq(Vanta7.can_produce(w, 0, "cn_vanta_a"), "", "a free roof pad allows one Vanta")
	var bar := int(CnFacility.fac(w, fk).get("bar", 0))
	check(bar > 0 and Content.building(String(w.entities[bar].def)).get("produces", []).has("cn_vanta_a"), "the Sentinel barracks lists the Vanta")
	var e := _vanta(w)
	var rp := Vanta7.pad_of(w, fk)
	check(bool(e.air_landed) and (rp.rect as Rect2).has_point(Vector2(e.pos)), "new Vanta stands on the barracks roof pad at %s" % str(e.pos))
	check(float(e.get("vt_deck", 0.0)) > 0.5, "drawn at the deck height (vt_deck %s)" % str(e.get("vt_deck")))
	check_eq(String(e.get("art_def", "")), "g7_vanta_cannon_missiles_flares", "default loadout sheet")
	check(Vanta7.can_produce(w, 0, "cn_vanta_a") != "", "pad taken -> second Vanta refused")
	check(not ArtCatalog.manifest().get("vehicles", {}).get("g7_vanta_cannon_missiles_flares", {}).is_empty(), "loadout sheet registered in the art catalog")


func test_each_loadout_fires_from_its_mount() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_facility(w, s[1])
	var e := _vanta(w)
	var vid := int(e.id)
	var r := Vanta7.rec(w, vid)
	var c := Vector2(o) + Vector2(30, 45)
	var expect := {"cannon": "g7_vanta_cannon", "missiles": "g7_vanta_missile", "gun": "g7_vanta_mg", "anti_drone": "g7_vanta_ad"}
	for slot in ["nose", "side", "rear"]:
		for it in (Vanta7.R().slots[slot] as Array):
			if it == "flares" or it == "deterrents":
				continue
			r.n = it if slot == "nose" else "cannon"
			r.s = it if slot == "side" else "drones"
			r.r = it if slot == "rear" else "flares"
			if slot != "nose":
				r.n = "anti_drone"   # no pivot toward the ground target (a cannon / missile nose turns the craft to face it)
			var face := 0.0
			var tp := c + Vector2(5, 0)          # ahead
			if slot == "side":
				tp = c + Vector2(0, 5)           # right side (facing +x: right = +y)
			elif slot == "rear":
				tp = c + Vector2(-5, 0)          # behind
			var tdef := "cn_gun_drone" if it == "anti_drone" else "a_apc"
			_hover_at(w, e, c, face)
			var tid := w.spawn_unit(tdef, 1, tp)
			if it != "anti_drone":
				e.target = tid
			var hp0 := float(w.entities[tid].hp)
			if it == "drones":
				var got := false
				for i in 20:
					w.run_ticks(1)
					for ev in w.events:
						if String(ev.type) == "VantaDrones" and int(ev.id) == vid:
							got = (ev.drones as Array).size() == 2
				check(got, "side drones: one defence drone launched from each side")
			else:
				var sh := _shots(w, 30, vid)
				var mounts := {}
				var wid := ""
				for ev in sh:
					mounts[String(ev.get("vt", ""))] = true
					wid = String(ev.weapon) if String(ev.get("vt", "")) == ("nose" if slot == "nose" else ("rear" if slot == "rear" else "sr")) else wid
				var want_m := "nose" if slot == "nose" else ("rear" if slot == "rear" else "sr")
				check(mounts.has(want_m), "%s %s fires from mount %s (mounts seen %s)" % [slot, it, want_m, str(mounts.keys())])
				check_eq(wid, String(expect[it]), "%s %s weapon" % [slot, it])
				if w.entities.has(tid):
					check(float(w.entities[tid].hp) < hp0, "%s %s damages the target" % [slot, it])
				if slot == "side" and it != "anti_drone":
					check(not mounts.has("sl"), "the left side does not fire across the hull at a target on the right")
			if w.entities.has(tid):
				w.destroy(tid, "test", 0)
			w.run_ticks(1)
	# both sides of the mirrored pair fire at a target dead ahead
	r.n = "anti_drone"
	r.s = "gun"
	r.r = "flares"
	_hover_at(w, e, c, 0.0)
	var t2 := w.spawn_unit("a_apc", 1, c + Vector2(5, 0))
	e.target = t2
	var ms := {}
	for ev in _shots(w, 30, vid):
		ms[String(ev.get("vt", ""))] = true
	check(ms.has("sl") and ms.has("sr"), "both side guns fire at a target ahead (mounts %s)" % str(ms.keys()))
	# a target behind is out of the nose / side arcs
	if w.entities.has(t2):
		w.destroy(t2, "test", 0)
	r.n = "cannon"
	r.s = "missiles"
	r.r = "flares"
	_hover_at(w, e, c, 0.0)
	e.moving = false
	var t3 := w.spawn_unit("a_apc", 1, c + Vector2(-5, 0))
	e.target = t3
	e.facing = 0.0
	w.run_ticks(1)
	var early := 0
	for ev in w.events:
		if String(ev.type) == "ShotFired" and int(ev.shooter) == vid:
			early += 1
	check_eq(early, 0, "nose cannon / side missiles do not fire at a target straight behind")


func test_rearm_refuel_and_loadout_swap_on_pad() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_facility(w, s[1])
	var e := _vanta(w)
	var vid := int(e.id)
	var r := Vanta7.rec(w, vid)
	var why := Vanta7.validate_command(w, {"type": "vanta_loadout", "issuer": 0, "unit_ids": [vid], "side": "anti_drone"})
	check_eq(why, "", "loadout change accepted on the pad")
	_hover_at(w, e, Vector2(o) + Vector2(30, 40), 0.0)
	check(Vanta7.validate_command(w, {"type": "vanta_loadout", "issuer": 0, "unit_ids": [vid], "side": "gun"}) != "", "no loadout change in the air")
	for m in Vanta7.MOUNTS:
		r.mag[m] = 0
	r.fl = 0
	e.fuel = 100.0
	var evs := do_cmd(w, 0, {"type": "vanta_rtb", "unit_ids": [vid]})
	check_eq(rejected_reason(evs), "", "vanta_rtb accepted")
	var landed_t := -1
	for i in 900:
		w.run_ticks(1)
		if bool(e.air_landed) and Vanta7.on_pad(w, e, r):
			landed_t = i
			break
	check(landed_t >= 0, "returned and landed on the roof pad (%d ticks)" % landed_t)
	var f0 := float(e.get("fuel", 0.0))
	w.run_ticks(int(Vanta7.rf("rearm_s", 8.0) * SimWorld.TICK_RATE) + 20)
	check(Vanta7._full(r), "rearmed on the pad: mags %s, flares %d" % [str(r.mag), int(r.fl)])
	check(float(e.get("fuel", 0.0)) > f0, "refuelled on the pad (%.0f -> %.0f)" % [f0, float(e.get("fuel", 0.0))])
	evs = do_cmd(w, 0, {"type": "vanta_loadout", "unit_ids": [vid], "nose": "missiles", "cycle": "side"})
	check_eq(rejected_reason(evs), "", "loadout command on the pad")
	w.run_ticks(int(Vanta7.rf("swap_s", 10.0) * SimWorld.TICK_RATE) + 2)
	check_eq(Vanta7.loadout(w, vid), {"nose": "missiles", "side": "gun", "rear": "flares"}, "swap applied after swap_s (side cycled missiles -> gun)")
	check_eq(String(e.art_def), "g7_vanta_missiles_gun_flares", "sheet follows the loadout")


func test_flares_deterrents_and_stealth_vs_sam() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_facility(w, s[1])
	var e := _vanta(w)
	var vid := int(e.id)
	var r := Vanta7.rec(w, vid)
	_hover_at(w, e, Vector2(o) + Vector2(30, 40), 0.0)
	var sam := w.spawn_building("a_sam_site", 1, w.cell_of(Vector2(e.pos)) + Vector2i(4, 0), true)
	var sb: Dictionary = w.entities[sam]
	var st := Combat.stats(sb)
	check(bool(st.guided), "the SAM fires guided missiles")
	var n0 := int(r.fl)
	var blocked := 0
	for i in n0 + 2:
		w.tick += 20
		if Vanta7.shot_blocked(w, sb, st, e, Vector2(e.pos)):
			blocked += 1
	check_eq(int(r.fl), 0, "each decoyed missile uses one flare charge")
	check(blocked >= n0, "flares decoy one SAM missile per charge (%d of %d)" % [blocked, n0 + 2])
	r.r = "deterrents"
	r.dg = 0
	check(Vanta7.shot_blocked(w, sb, st, e, Vector2(e.pos)), "deterrent defeats a SAM missile")
	check(not Vanta7.shot_blocked(w, sb, st, e, Vector2(e.pos)), "deterrent then needs its cooldown")
	var gun := Combat.stats({"kind": "unit", "def": "a_apc"})
	r.dg = 0
	check(not Vanta7.shot_blocked(w, sb, gun, e, Vector2(e.pos)), "gunfire is never decoyed")
	check(Airdef._stealth_range(e) > 0.0 and Airdef._stealth_range(e) <= 6.0, "stealth airframe: radar sees it only within %.1f tiles" % Airdef._stealth_range(e))
	# end to end: the SAM shoots at the Vanta through Combat; flares spend and VantaFlares fires
	r.r = "flares"
	r.fl = 8
	w.factions[1].credits = 100000
	var flared := 0
	for i in 400:
		w.run_ticks(1)
		for ev in w.events:
			if String(ev.type) == "VantaFlares" and int(ev.id) == vid:
				flared += 1
	print("VANTA7 sam_flares=%d left=%d hp=%.0f" % [flared, int(r.fl), float(e.hp)])


func test_ai_defends_facility() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var e := _vanta(w)
	var r := Vanta7.rec(w, int(e.id))
	var rp := Vanta7.pad_of(w, int(r.fac))
	var foe := w.spawn_unit("a_apc", 1, Vector2(rp.centre) + Vector2(8, 6))
	w.run_ticks(12)
	Vanta7._think(w, e, r, true)
	check(String(e.order.get("type", "")) != "attack", "a player's Vanta is never flown by the AI")
	w.ai_state[0] = {}
	Vanta7._think(w, e, r, true)
	w.ai_state.erase(0)
	check(String(e.order.get("type", "")) == "attack" and int(e.order.get("target_id", -1)) == foe, "AI side: lifts to attack an enemy near the facility (order %s)" % str(e.order))


func _scenario() -> String:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_facility(w, s[1])
	var e := _vanta(w)
	_hover_at(w, e, Vector2(o) + Vector2(30, 40), 0.0)
	var t := w.spawn_unit("a_apc", 1, Vector2(o) + Vector2(36, 41))
	e.target = t
	w.spawn_unit("cn_gun_drone", 1, Vector2(o) + Vector2(27, 40))
	w.run_ticks(300)
	return w.state_hash()


func test_hash_twice_same() -> void:
	var a := _scenario()
	var b := _scenario()
	print("VANTA7 hash %s %s" % [a, b])
	check_eq(a, b, "Vanta fight is deterministic (same hash twice)")
