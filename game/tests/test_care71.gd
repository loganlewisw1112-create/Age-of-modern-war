extends "res://tests/test_base.gd"
## G7.1 DAMAGE71 (J2 + G1 combat medics+): triage tags (medic near), save order red > yellow > green (black left
## out), morphine for the black-tagged then a quiet death, call-for-medic, player override commands.

const Movement = preload("res://sim/systems/movement.gd")
const HotState = preload("res://sim/hot_state.gd")
const Care71 = preload("res://sim/systems/care71.gd")
const Gore71 = preload("res://sim/systems/gore71.gd")
const Wounds = preload("res://sim/systems/wounds.gd")
const C := Vector2(0.5, 0.5)
const H := 0


func _setup() -> SimWorld:
	var w := make_world({"victory": "endless", "sides": [
		{"faction": "human_a", "stage": 8, "credits": 5000, "ai": false, "name": "H", "team": 0},
		{"faction": "machine", "stage": 8, "credits": 5000, "ai": false, "name": "M", "team": 1}]})
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	t.fill(Terrain.GRASS)
	w.map.terrain = t
	for id in w.entities.keys():
		w.entities.erase(id)
	w.cache.clear()
	if w.hot != null:
		HotState.sync(w)
	Movement.rebuild_nav(w)
	Care71.enable(w)
	Gore71.enable(w)
	return w


func _spawn(w: SimWorld, def: String, at: Vector2, idle := false) -> Dictionary:
	var id := w.spawn_unit(def, H, at)
	var e: Dictionary = w.entities[id]
	e.order = {"type": "idle"} if idle else {"type": "hold", "target": e.pos}
	return e


func _bleed(w: SimWorld, e: Dictionary, wb: float) -> void:
	e.wz = {"torso": 1}
	e.wb = wb
	Wounds._state(w).bleed[int(e.id)] = 1


## Three casualties around one medic: red (down, 90 s left), yellow (bleeding 1 hp/s, awake), black (down, 5 s left).
func _scene(w: SimWorld) -> Dictionary:
	var med := _spawn(w, "a_medic_team", Vector2(20, 20) + C, true)
	var red := _spawn(w, "rifleman", Vector2(23, 20) + C)
	var yel := _spawn(w, "rifleman", Vector2(21, 22) + C)
	var blk := _spawn(w, "rifleman", Vector2(22, 18) + C)
	_bleed(w, yel, 1.0)
	_bleed(w, red, 1.0)
	Wounds.go_down(w, red)
	_bleed(w, blk, 1.0)
	Wounds.go_down(w, blk)
	w.sys_state.medical.wounded[int(blk.id)] = int(5 * SimWorld.TICK_RATE)
	return {"med": med, "red": red, "yel": yel, "blk": blk}


func test_triage_tags_and_order() -> void:
	var w := _setup()
	var s := _scene(w)
	check(Wounds.is_medic(w, s.med), "the medic team counts as a medic")
	var first := -1
	for k in 12:
		w.step()
		for ev in w.events:
			if String(ev.type) == "CareStarted" and first < 0 and int(ev.id) == int(s.med.id):
				first = int(ev.casualty)
	check_eq(Care71.tag_of(s.red), "red", "down with time left = red")
	check_eq(Care71.tag_of(s.yel), "yellow", "bleeding, awake = yellow")
	check_eq(Care71.tag_of(s.blk), "black", "down with seconds left = black (expectant)")
	check_eq(Care71.order(w, [int(s.blk.id), int(s.yel.id), int(s.red.id)]), [int(s.red.id), int(s.yel.id)],
		"save order red, yellow; black left out")
	check_eq(first, int(s.red.id), "the medic goes to the red casualty first")
	check(Care71.casualties(w, H).has(int(s.yel.id)), "casualties lists the side's wounded")
	var g := _spawn(w, "rifleman", Vector2(30, 30) + C)
	g.wz = {"arm_l": 1}
	check_eq(Care71.tag_for(w, g, w.sys_state.medical), "green", "walking wounded = green")


## DAMAGE71-6 tag mix: a yellow-tagged soldier whose bleeding stops (bandaged) stays tracked, so the medic beside him
## re-tags him green; the green tag stays on him after he leaves the casualty list (green_keep_s later).
func test_patched_up_turns_green() -> void:
	var w := _setup()
	var med := _spawn(w, "a_medic_team", Vector2(20, 20) + C, true)
	var yel := _spawn(w, "rifleman", Vector2(21, 22) + C)
	_bleed(w, yel, 1.0)
	for k in 12:
		w.step()
	check_eq(Care71.tag_of(yel), "yellow", "bleeding, awake = yellow")
	yel.wb = 0.0   # bandaged: the wounds bleed set drops him
	Wounds._state(w).bleed.erase(int(yel.id))
	w.sys_state.wounds.care.clear()
	var greens := 0
	for k in 12:
		w.step()
		for ev in w.events:
			if String(ev.type) == "Triage71" and int(ev.id) == int(yel.id) and String(ev.tag) == "green":
				greens += 1
	check(w.entities.has(int(med.id)), "the medic is still there")
	check_eq(Care71.tag_of(yel), "green", "patched up and walking = re-tagged green")
	check_eq(greens, 1, "one green Triage71 event")
	var keep := int(float(Care71.R().get("green_keep_s", 30.0)) * SimWorld.TICK_RATE)
	for k in keep + 12:
		w.step()
	check(not Care71.casualties(w, H).has(int(yel.id)), "a green leaves the casualty list green_keep_s later")
	check_eq(Care71.tag_of(yel), "green", "the green tag stays on him")


func test_morphine_then_comfort() -> void:
	var w := _setup()
	var s := _scene(w)
	var got := false
	for k in 12:
		w.step()
		for ev in w.events:
			if String(ev.type) == "Morphine71" and int(ev.id) == int(s.blk.id):
				got = true
	check(got and s.blk.has("c71mor"), "the black-tagged soldier gets morphine")
	var bid := int(s.blk.id)
	var died := ""
	var comfort := int(float(Content.rules().g71_care.comfort_s) * SimWorld.TICK_RATE)
	for k in comfort + 20:
		w.step()
		for ev in w.events:
			if String(ev.type) == "EntityDestroyed" and int(ev.id) == bid:
				died = String(ev.cause)
	check_eq(died, "expectant", "made comfortable, then dies quietly (not bled out first)")
	var comf := 0
	for b in Gore71.bodies(w).values():
		if String(b.out) == "comfort":
			comf += 1
	check_eq(comf, 1, "his body stays (comfort outcome)")


func test_call_for_medic_without_medic() -> void:
	var w := _setup()
	var c := _spawn(w, "rifleman", Vector2(40, 40) + C)
	_bleed(w, c, 0.5)
	Wounds.go_down(w, c)
	var calls := 0
	for k in 40:
		w.step()
		for ev in w.events:
			if String(ev.type) == "CallMedic71" and int(ev.id) == int(c.id):
				calls += 1
	check(calls >= 1, "a down soldier with no medic near calls for one")
	check_eq(Care71.tag_of(c), "", "no medic near: untagged")


func test_player_commands() -> void:
	var w := _setup()
	var s := _scene(w)
	check_eq(w.preview_command({"type": "triage_tag", "issuer": H, "id": int(s.yel.id), "tag": "pink"}), "bad tag", "bad tag refused")
	check(w.preview_command({"type": "triage_tag", "issuer": 1, "id": int(s.yel.id), "tag": "red"}) != "", "not your soldier refused")
	check_eq(Care71.validate_command(w, {"type": "triage_tag", "issuer": H, "id": int(s.yel.id), "tag": "red"}), "", "own soldier ok")
	Care71.apply_command(w, {"type": "triage_tag", "issuer": H, "id": int(s.yel.id), "tag": "red"})
	for k in 12:
		w.step()
	check_eq(Care71.tag_of(s.yel), "red", "the player's tag wins over the medic's")
	Care71.apply_command(w, {"type": "give_morphine", "issuer": H, "id": int(s.red.id)})
	check(s.red.has("c71mor") and Care71.tag_of(s.red) == "black", "give_morphine: morphine + black tag")
	check_eq(Care71.validate_command(w, {"type": "give_morphine", "issuer": H, "id": int(s.red.id)}), "already given", "no second dose")


## DAMAGE71-7: every field of sys_state.care71 (cas, mor, trk incl. a green timeout) survives a save -> load with the
## same keys (int ids stay ints, same order), the same hash and the same future, through the real save file bytes
## (SaveSystem.encode_dict / decode_bytes; binary var_to_bytes, so no JSON string keys).
func test_save_load_keeps_care_state() -> void:
	var SaveSystem = load("res://sim/save_system.gd")
	var w := _setup()
	var s := _scene(w)
	for k in 12:
		w.step()
	s.yel.wb = 0.0   # bandaged: tracked by st.trk, re-tagged green on the next pass
	Wounds._state(w).bleed.erase(int(s.yel.id))
	w.sys_state.wounds.care.clear()
	for k in 12:
		w.step()
	var st: Dictionary = w.sys_state.care71
	check(st.has("trk") and not (st.trk as Dictionary).is_empty(), "trk holds tracked soldiers (%s)" % str(st.get("trk")))
	var green_t := false
	for id in st.trk:
		if int(st.trk[id]) > 0:
			green_t = true
	check(green_t, "trk holds a green timeout tick")
	check(not (st.mor as Dictionary).is_empty(), "mor holds the black-tagged soldier's comfort tick")
	var res: Dictionary = SaveSystem.decode_bytes(SaveSystem.encode_dict(w.to_dict(), "test"))
	check(bool(res.ok), "save bytes decode (%s)" % String(res.reason))
	var c := SimWorld.from_dict(res.dict)
	check_eq(c.state_hash(), w.state_hash(), "save -> load = same hash")
	var cs: Dictionary = c.sys_state.care71
	for f in ["cas", "mor", "trk"]:
		check_eq(str(cs[f]), str(st[f]), "care71.%s same contents + order after load" % f)
		for id in cs[f]:
			check_eq(typeof(id), TYPE_INT, "care71.%s key %s stays an int" % [f, str(id)])
	for id in cs.cas:
		for cid in cs.cas[id]:
			check_eq(typeof(cid), TYPE_INT, "care71.cas[%s] key stays an int" % str(id))
	for k in 400:
		w.step()
		c.step()
	check_eq(c.state_hash(), w.state_hash(), "save -> load gives the same future (400 ticks: green timeout + comfort)")


func _body(w: SimWorld, owner: int, at: Vector2) -> int:
	return Gore71.add_body(w, {"kind": "body", "def": "rifleman", "owner": owner, "pos": at, "rot": 0.0, "out": "bleed",
		"t": w.tick, "sz": 0.4, "lost": 0, "ch": false, "tr": 0, "rc": "rifle"})


## DAMAGE71-8: medics recover our dead (J1 "unless dragged away (medics recover ours)"): an idle medic walks to the
## nearest own body within recover.seek_r, works on it recover.secs, and it is carried off (BodyRecovered71); enemy
## bodies and bodies beyond seek_r stay; while his side has a casualty listed he does not start (the living first).
func test_medic_recovers_body() -> void:
	var w := _setup()
	var med := _spawn(w, "a_medic_team", C + Vector2(10, 10), true)
	var own := _body(w, H, C + Vector2(14, 10))
	var foe := _body(w, 1, C + Vector2(11, 11))
	var far := _body(w, H, C + Vector2(10, 30))
	var hurt := _spawn(w, "rifleman", C + Vector2(10, 12))
	_bleed(w, hurt, 1.0)
	for k in 40:
		w.step()
	var st: Dictionary = w.sys_state.care71
	check(not Care71.casualties(w, H).is_empty(), "a casualty is listed (%s)" % str(Care71.casualties(w, H)))
	check((st.get("rec", {}) as Dictionary).is_empty(), "no recovery job while a casualty is listed (%s)" % str(st.get("rec")))
	check(Gore71.bodies(w).has(own), "the body is still there while the living come first")
	w.destroy(int(hurt.id), "test")   # the casualty is gone (evacuated): the medic is free
	var got := -1
	var by := -1
	for k in 600:
		w.step()
		for ev in w.events:
			if String(ev.get("type", "")) == "BodyRecovered71":
				var d: Dictionary = ev.get("data", ev)
				got = int(d.body)
				by = int(d.by)
		if got >= 0:
			break
	check_eq(got, own, "the own body within seek_r is recovered (tick %d, rec %s)" % [w.tick, str(st.get("rec"))])
	check_eq(by, int(med.id), "by the medic")
	check(not Gore71.bodies(w).has(own), "recovered body removed from Gore71")
	check(Gore71.bodies(w).has(foe), "the enemy body stays")
	check(Gore71.bodies(w).has(far), "the own body beyond seek_r stays")
	check(String(med.order.get("type", "")) == "idle", "the medic ends idle (%s)" % str(med.order))
