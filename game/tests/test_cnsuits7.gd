extends "res://tests/test_base.gd"
## G7 acceptance (owner: EXO7). G7_REFERENCE 13.9c-20: the counter-nanite armoured suits from the facility's
## Armory + Suit Bay: each variant built only at the armory, one gunner per suit (pilot def), the gunner ejects when
## the suit is destroyed (G6 Exo rules), clear roles and weapons, no facility = nothing to build and nothing spent,
## art sheets for every def, and two identical runs hash the same.

const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Exo = preload("res://sim/systems/exo.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Movement = preload("res://sim/systems/movement.gd")
const TYPES := ["bastion", "breaker", "aegis", "purifier"]

var _paid: Dictionary = {}   # the queue entry's paid cost of the last _build


func _ensure_g7() -> void:
	if Content.building("cn_armory").is_empty() or Content.unit("g7_cns_bastion").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


func _ids(b: bool) -> Array:
	var out: Array = []
	for t in TYPES:
		out.append(("g7_b_cns_" if b else "g7_cns_") + t)
	return out


## Inert 2-side world with a 60x60 GRASS arena; side 0 rich and at Stage 10. Returns [w, arena origin].
func _setup(stage: int = 10) -> Array:
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
	for f in [0, 1]:
		w.factions[f].credits = 200000
		w.factions[f].stage = stage
		w.factions[f].pop_cap = 400
		w.factions[f].pop_cap_floor = 400   # the facility garrison alone can fill the skirmish cap
		for k in ["salvage", "ore", "fuel", "ammo"]:
			w.factions[f].stock[k] = 200000
	return [w, o]


func _facility(w: SimWorld, o: Vector2i, def_id := "a_cn_facility", fid := 0) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building(def_id, fid, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 1)
	return id


func _armory(w: SimWorld, fid: int) -> int:
	var best := -1
	for e in w.entities.values():
		if String(e.kind) == "building" and String(e.def) == "cn_armory" and int(e.owner) == fid:
			if best < 0 or int(e.id) < best:
				best = int(e.id)
	return best


func _stock(w: SimWorld, fid: int) -> Array:
	var f: Dictionary = w.factions[fid]
	return [int(f.credits), int(f.stock.get("salvage", 0)), int(f.stock.get("ore", 0))]


## Queues item at building bid for side 0 and runs until it is built (train time forced short). Returns the new id.
func _build(w: SimWorld, bid: int, item: String) -> int:
	var cmd := {"type": "queue_unit", "issuer": 0, "building_id": bid, "item": item}
	var why := w.preview_command(cmd)
	if not check(why == "", "queue %s at the armory: %s" % [item, why]):
		return -1
	w.submit(cmd)
	w.step()
	var b: Dictionary = w.entities[bid]
	if not check(not (b.queue as Array).is_empty(), "%s queued" % item):
		return -1
	_paid = (b.queue[0].paid as Dictionary).duplicate()
	for i in 2400:
		w.step()
		for ev in w.events:
			if String(ev.type) == "UnitSpawned" or String(ev.type) == "ProductionComplete":
				for e in w.entities.values():
					if String(e.def) == item and int(e.owner) == 0:
						return int(e.id)
		if (b.queue as Array).is_empty():
			break
	for e in w.entities.values():
		if String(e.def) == item and int(e.owner) == 0:
			return int(e.id)
	return -1


# ================================================================ content
func test_variants_roles_and_weapons() -> void:
	_ensure_g7()
	var want := {"bastion": "autocannon", "breaker": "top_attack", "aegis": "autocannon", "purifier": "energy"}
	for b in [false, true]:
		var ws := {}
		for id in _ids(b):
			var d := Content.unit(String(id))
			if not check(not d.is_empty(), "%s defined" % id):
				continue
			check(bool(d.get("exo_suit", false)), "%s is an exo suit (G6 Exo rules)" % id)
			check_eq(String(d.get("element_class", "")), "vehicle", "%s is one vehicle element" % id)
			check_eq(String(d.get("faction", "")), "human_b" if b else "human_a", "%s side" % id)
			var pd := String(d.get("pilot_def", ""))
			check_eq(pd, "g7_b_cns_gunner" if b else "g7_cns_gunner", "%s crewed by one suit gunner" % id)
			check(String(Content.unit(pd).get("role", "")) == "infantry" and Content.production(pd).is_empty(),
				"%s: the gunner is infantry and not trainable on its own" % id)
			var wd := Content.weapon(String(d.weapon))
			check_eq(String(wd.get("class", "")), want[String(d.cn_suit)], "%s weapon class" % id)
			ws[String(d.weapon)] = true
			check(int(d.hp) > 700 and float(d.speed) <= float(Content.unit("a_exo_rifle").speed) and int(d.pop) == 3, "%s heavier than a G6 exo suit" % id)
		check_eq(ws.size(), 4, "four distinct weapons (%s)" % ("B" if b else "A"))
	check(bool(Content.weapon("g7_cns_atgm").get("guided", false)), "Breaker missiles are guided")
	check(float(Content.weapon("g7_cns_cuas").get("anti_drone_mult", 1.0)) >= 3.0 and bool(Content.weapon("g7_cns_cuas").get("anti_air", false)),
		"Aegis cannon is the counter-air / counter-drone weapon")
	check(bool(Content.weapon("g7_cns_disruptor").get("nanite_disruptor", false)), "Purifier carries the nanite disruptor")
	check(not bool(Content.weapon("g7_cns_hmg").get("anti_air", false)) and bool(Content.weapon("g7_cns_hmg").get("anti_air_low", false)),
		"Bastion gun reaches helicopters / drones, not jets")


func test_built_only_at_the_armory() -> void:
	_ensure_g7()
	var arm := Content.building("cn_armory")
	check(bool(arm.get("exo_garage", false)), "the suit bay counts as an exo garage (Exo.can_produce / re-suit)")
	for b in [false, true]:
		for id in _ids(b):
			check_eq(String(Content.production(String(id)).get("facility", "")), "cn_armory", "%s built at the armory" % id)
			check((arm.get("produces", []) as Array).has(id), "armory produces %s" % id)
	for bid in Content.ids("buildings"):
		if String(bid) == "cn_armory":
			continue
		for item in Content.building(String(bid)).get("produces", []):
			for u in Content.production(String(item)).get("spawns", []):
				check(String(Content.unit(String(u)).get("cn_suit", "")) == "", "%s does not build CN suits (%s)" % [bid, item])
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var aid := _armory(w, 0)
	check(aid > 0, "the facility raises its armory + suit bay part")
	if aid > 0:
		var F := CnFacility.fac(w, fid)
		check((F.parts as Array).has(aid), "armory is a facility part")
		check(CnFacility.zone(F, "armory").has_point(Vector2(w.entities[aid].cell) + Vector2(1, 1)), "armory sits on the armory zone")
		check(bool(w.entities[aid].get("built", false)) and int(w.entities[aid].owner) == 0, "built and owned by the facility owner")


func test_each_variant_built_at_the_armory_with_one_gunner() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var aid := _armory(w, 0)
	if not check(aid > 0, "armory present"):
		return
	for id in _ids(false):
		var c: Dictionary = Content.production(String(id)).cost
		var uid := _build(w, aid, String(id))
		check(uid > 0, "%s built at the armory" % id)
		for k in ["credits", "salvage", "ore"]:
			check_eq(int(_paid.get(k, 0)), int(c.get(k, 0)), "%s paid %s" % [id, k])
		var crew := 0
		for e in w.entities.values():
			if String(e.def) == String(Content.unit(String(id)).pilot_def) and int(e.owner) == 0:
				crew += 1
		check_eq(crew, 0, "%s: the gunner rides inside (no separate crew unit while the suit lives)" % id)
	# the other side's variant and a foreign facility are refused
	var r := w.preview_command({"type": "queue_unit", "issuer": 0, "building_id": aid, "item": "g7_b_cns_bastion"})
	check(r != "", "Human B suit refused at a Human A armory (%s)" % r)
	r = w.preview_command({"type": "queue_unit", "issuer": 1, "building_id": aid, "item": "g7_cns_bastion"})
	check(r != "", "only the facility owner builds at its armory (%s)" % r)


func test_human_b_facility_builds_b_suits() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	w.factions[0].faction_def = "human_b"
	_facility(w, s[1], "b_cn_facility")
	var aid := _armory(w, 0)
	if not check(aid > 0, "Human B facility has its armory"):
		return
	check(_build(w, aid, "g7_b_cns_purifier") > 0, "Human B Purifier built")


func test_stage_gate_and_no_facility_no_cost() -> void:
	var s := _setup(9)
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var aid := _armory(w, 0)
	var before := _stock(w, 0)
	var cmd := {"type": "queue_unit", "issuer": 0, "building_id": aid, "item": "g7_cns_breaker"}
	var r := w.preview_command(cmd)
	check(r.contains("Stage"), "Stage 9: refused (%s)" % r)
	w.submit(cmd)
	w.step()
	check_eq(_stock(w, 0), before, "nothing spent on a refused suit")
	# no facility: no armory exists, no other building takes the order, nothing is spent
	var s2 := _setup()
	var w2: SimWorld = s2[0]
	check(_armory(w2, 0) < 0, "no facility = no armory")
	var b0 := _stock(w2, 0)
	var any_b := -1
	for e in w2.entities.values():
		if String(e.kind) == "building" and int(e.owner) == 0:
			any_b = int(e.id)
			break
	if any_b >= 0:
		var c2 := {"type": "queue_unit", "issuer": 0, "building_id": any_b, "item": "g7_cns_bastion"}
		var r2 := w2.preview_command(c2)
		check(r2 != "", "no facility: %s cannot build a suit (%s)" % [w2.entities[any_b].def, r2])
		w2.submit(c2)
	check_eq(Exo.can_produce(w2, 0, "g7_cns_bastion"), "Requires an Exo-Suit Garage", "Exo gate without a suit bay")
	w2.step()
	check_eq(_stock(w2, 0), b0, "no facility = no cost")


## Kills unit uid with an enemy hit through the Damage pipeline (G6Hooks -> Exo.on_destroyed). Returns the events.
func _kill(w: SimWorld, uid: int) -> Array:
	var foe := w.spawn_unit("rifleman", 1, w.entities[uid].pos + Vector2(3, 0))
	var evs: Array = []
	for i in 6:
		if not w.entities.has(uid):
			break
		Damage.apply_hit(w, w.entities[foe], w.entities[uid], {"damage": 5000.0, "cls": "at", "weapon": ""}, true)
		w.step()
		evs.append_array(w.events)
	return evs


func test_gunner_ejects_when_the_suit_is_destroyed() -> void:
	for b in [false, true]:
		var s := _setup()
		var w: SimWorld = s[0]
		var o: Vector2i = s[1]
		w.factions[0].faction_def = "human_b" if b else "human_a"
		w.spawn_building("b_hospital" if b else "a_hospital", 0, o + Vector2i(40, 40), true)
		for id in _ids(b):
			var n0 := 0
			for e in w.entities.values():
				if String(e.get("pilot_of", "")) != "":
					n0 += 1
			var uid := w.spawn_unit(String(id), 0, Vector2(o) + Vector2(20.5, 20.5))
			var evs := _kill(w, uid)
			check(not w.entities.has(uid), "%s destroyed" % id)
			var ej := 0
			var pid := -1
			for e in w.entities.values():
				if String(e.get("pilot_of", "")) == String(id):
					ej += 1
					pid = int(e.id)
			check_eq(ej, 1, "%s: exactly one gunner ejects (%d events seen)" % [id, evs.size()])
			if pid >= 0 and w.entities.has(pid):
				var p: Dictionary = w.entities[pid]
				check_eq(String(p.def), String(Content.unit(String(id)).pilot_def), "%s: the ejected man is its suit gunner" % id)
				check_eq(String(p.get("pilot_of", "")), String(id), "%s: gunner remembers his suit (re-suit)" % id)
	# no medical capability: the gunner is lost with the suit (G6 rule)
	var s3 := _setup()
	var w3: SimWorld = s3[0]
	var u3 := w3.spawn_unit("g7_cns_aegis", 0, Vector2(s3[1]) + Vector2(20.5, 20.5))
	_kill(w3, u3)
	var got := 0
	for e in w3.entities.values():
		if String(e.get("pilot_of", "")) != "":
			got += 1
	check(not w3.entities.has(u3) and (got == 0 or SimWorld.Medical.has_medical(w3, 0)), "no medical: the gunner is lost with the suit (G6 Exo rule)")


func test_resuit_at_the_suit_bay() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	_facility(w, s[1])
	var aid := _armory(w, 0)
	if not check(aid > 0, "armory present"):
		return
	var a: Dictionary = w.entities[aid]
	var pid := w.spawn_unit("g7_cns_gunner", 0, Vector2(a.cell) + Vector2(-0.5, 0.5))
	w.entities[pid].pilot_of = "g7_cns_breaker"
	var pr := Exo.plan_resuit(w, {"issuer": 0, "building_id": aid, "pilot_id": pid})
	check_eq(String(pr.reason), "", "a treated gunner re-suits at the suit bay")
	check_eq(int(pr.cost.get("credits", 0)), roundi(680 * 0.5), "re-suit costs half")


func _match_hash() -> String:
	var s := _setup()
	var w: SimWorld = s[0]
	var o: Vector2i = s[1]
	_facility(w, o)
	w.spawn_building("a_hospital", 0, o + Vector2i(40, 40), true)
	var aid := _armory(w, 0)
	_build(w, aid, "g7_cns_bastion")
	var foes: Array = []
	for i in 4:
		foes.append(w.spawn_unit("rifleman", 1, Vector2(o) + Vector2(36.5 + i, 8.5)))
	for e in w.entities.values():
		if String(e.def).begins_with("g7_cns_") and int(e.owner) == 0:
			e.order = {"type": "attack_move", "target": Vector2(o) + Vector2(36.5, 8.5)}
	w.run_ticks(400)
	return w.state_hash()


func test_hash_twice_same() -> void:
	var h1 := _match_hash()
	var h2 := _match_hash()
	check_eq(h1, h2, "two identical suit matches hash the same (%s)" % h1)


# ================================================================ art
func test_art_sheets_for_every_def() -> void:
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/g7_cnsuits/manifest.json"))
	if not check(man is Dictionary, "g7_cnsuits manifest present"):
		return
	var need := ["idle", "walk_0", "run_0", "aim", "fire_s", "reload_0", "reload_1", "stumble", "knock", "die_0", "die_1", "die_2"]
	for b in [false, true]:
		for id in _ids(b):
			var e: Dictionary = (man.infantry as Dictionary).get(id, {})
			if not check(not e.is_empty(), "%s sheet" % id):
				continue
			check_eq(int(e.facings), 8, "%s 8 facings" % id)
			for f in need:
				check((e.frames as Array).has(f), "%s has %s" % [id, f])
			check(e.has("anim61"), "%s carries the G6.1 animation set" % id)
			for i in 12:   # EXO7-3 (13.9c-20b): the 12-frame walk and its measured stride (speed-matched display)
				check((e.frames as Array).has("swalk_%d" % i), "%s has swalk_%d" % [id, i])
			check(float((e.get("g7", {}) as Dictionary).get("stride_tiles", 0.0)) > 0.3, "%s stride_tiles" % id)
			check((man.get("vehicle_wrecks", {}) as Dictionary).has(id), "%s wreck (hatch open)" % id)
			check(FileAccess.file_exists("res://assets/art/g7_cnsuits/" + String(e.mask)), "%s team mask" % id)
		var pd := "g7_b_cns_gunner" if b else "g7_cns_gunner"
		check((man.infantry as Dictionary).has(pd), "%s pilot sheet (CN gunner alias)" % pd)
