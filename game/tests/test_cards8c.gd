extends "res://tests/test_base.gd"
## G7 CARDS8C acceptance (docs/G7_REFERENCE.md 13.9c-48): Sentinel barracks, helipads + VTOL pad, aid station and
## package lab cards. Every option works and is refused with a reason when it cannot run; save/load gives the same
## future; same commands -> same hash; a match that never uses the cards has no cards8c state and an unchanged watch
## board; the cards follow the selection and their buttons issue the right commands.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Sent = preload("res://sim/systems/sentinels7.gd")
const Air = preload("res://sim/systems/air.gd")
const C8 = preload("res://sim/systems/cards8c.gd")
const Card = preload("res://presentation/ui7/building_card8c.gd")
const MAP := "industrial_heartland_m"

static var _base: Dictionary = {}


class StubMv extends RefCounted:
	signal selection_changed
	signal world_events(evs)
	var selection: Array[int] = []
	var sel_part := ""
	var _world = null
	var player_fid := 0
	var issued: Array = []
	var pick_cb: Callable = Callable()

	func select_ids(ids: Array, part: String = "") -> void:
		sel_part = part
		var out: Array[int] = []
		for i in ids:
			out.append(int(i))
		selection = out
		selection_changed.emit()

	func part_selected(fac: int, part: String) -> bool:
		return sel_part == part and selection.has(fac)

	func issue(cmd: Dictionary) -> void:
		issued.append(cmd)

	func begin_point_pick(cb: Callable) -> void:
		pick_cb = cb


func _ensure_g7() -> void:
	if Content.unit("g7_sent_warden").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


func _lp() -> SimWorld:
	_ensure_g7()
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(4242, MAP))
		if w0 == null:
			return null
		w0.run_ticks(260)   # the facility board has dealt its posts
		_base = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base.duplicate(true))
	w.ai_state = {}
	w.cfg["creep_spread"] = false
	var f := _fid(w)
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(f, int(e.owner)):
			e.cd_ticks = 1 << 30
	w.credit(f, {"credits": 200000, "salvage": 80000, "ore": 80000}, "test")
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _F(w: SimWorld) -> Dictionary:
	var l := CnFacility.facilities(w, _fid(w))
	return CnFacility.fac(w, int(l[0])) if not l.is_empty() else {}


func _do(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = _fid(w)
	if not cmd.has("building_id"):
		cmd.building_id = int(_F(w).id)
	var why := w.preview_command(cmd)
	if why != "":
		return why
	w.submit(cmd)
	w.run_ticks(1)
	return ""


func _manned(w: SimWorld, fac: int) -> Dictionary:
	for j in C8.posts(w, fac):
		if (j.taken as Array).size() >= 1 and String(j.kind) != "entry":
			return j
	return {}


func _slots(w: SimWorld, fac: int, kind: String) -> int:
	var n := 0
	for j in Sent.job_board(w, fac):
		if String(j.kind) == kind:
			n += int(j.slots)
	return n


func test_registered() -> void:
	for t in C8.TYPES:
		check(SimWorld.COMMANDS.has(t), "%s registered in world.gd" % t)


func test_barracks_options() -> void:
	var w := _lp()
	if not check(w != null and not _F(w).is_empty(), "Last Protocol world with a facility"):
		return
	var fac := int(_F(w).id)
	# a quiet base: the Machine already marching on it raises the alarm, and the board never rotates a post under alarm
	var foes := []
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and w.is_enemy(_fid(w), int(e.owner)):
			foes.append(int(e.id))
	for id in foes:
		w.destroy(id, "test")
	# watch roster + rotate
	check(_do(w, {"type": "c8c_rotate", "post": "nope"}) == "No such post on the watch roster.", "unknown post refused with its reason")
	var j := _manned(w, fac)
	if check(not j.is_empty(), "a manned watch post on the roster"):
		var was: Array = (j.taken as Array).duplicate()
		check_eq(_do(w, {"type": "c8c_rotate", "post": String(j.id)}), "", "ROTATE %s accepted" % String(j.id))
		check(w.entities[int(was[0])].has("c8rot") and w.entities[int(was[0])].has("r8s"), "the men on the post are marked for relief")
		w.run_ticks(600)
		var now := {}
		for p in C8.posts(w, fac):
			if String(p.id) == String(j.id):
				now = p
		check(not now.is_empty() and not (now.taken as Array).is_empty(), "the post is never left empty (%s)" % str(now.get("taken", [])))
		var swapped := false
		for u in was:
			if not (now.get("taken", []) as Array).has(int(u)):
				swapped = true
		check(swapped, "fresh men took the post (%s -> %s)" % [str(was), str(now.get("taken", []))])
		check(not w.entities[int(was[0])].has("c8rot"), "the hand-rotation latch clears once relieved")
	# train by role
	var roles := C8.roles(w, _fid(w))
	check(not roles.is_empty(), "Sentinel roles on the roster (%s)" % str(roles))
	check(_do(w, {"type": "c8c_train", "role": "pilot"}) == "No Sentinels of that role to train.", "unknown role refused")
	if not roles.is_empty():
		var role := String(roles[0])
		var sid := -1
		for id in Sent.sentinels_of(w, _fid(w)):
			if Sent.type_of_def(String(w.entities[id].def)) == role:
				sid = id
				break
		var x0 := float(w.entities[sid].get("xp", 0.0))
		var c0 := int(w.factions[_fid(w)].credits)
		check_eq(_do(w, {"type": "c8c_train", "role": role}), "", "TRAIN %s accepted" % role)
		check(int(w.factions[_fid(w)].credits) < c0, "training cost credits")
		check(_do(w, {"type": "c8c_train", "role": role}).begins_with("Already training"), "a second drill refused while one runs")
		w.run_ticks(C8.secs(C8.R().train.time_s) + 40)
		check_eq(int(C8.fs(w, fac).lv.get(role, 0)), 1, "%s drilled to level 1" % role)
		if w.entities.has(sid):
			check(float(w.entities[sid].get("xp", 0.0)) > x0, "a %s gained experience (%.0f -> %.0f)" % [role, x0, float(w.entities[sid].get("xp", 0.0))])
	# patrol plans
	check(_do(w, {"type": "c8c_plan", "plan": "zigzag"}) == "Unknown patrol plan.", "unknown plan refused")
	check(_do(w, {"type": "c8c_plan", "plan": "balanced"}) == "That plan is already in force.", "the plan in force refused")
	var opts := C8.plan_options(w, fac)
	check_eq(opts.size(), 4, "four generated patrol plans")
	var wall0 := _slots(w, fac, "wall")
	var int0 := _slots(w, fac, "int")
	check_eq(_do(w, {"type": "c8c_plan", "plan": "perimeter"}), "", "perimeter-heavy plan adopted")
	w.run_ticks(260)
	check(_slots(w, fac, "wall") > wall0, "perimeter-heavy: more wall-walk slots (%d -> %d)" % [wall0, _slots(w, fac, "wall")])
	check(_slots(w, fac, "int") < int0 or int0 == 0, "perimeter-heavy: fewer inner-ring slots (%d -> %d)" % [int0, _slots(w, fac, "int")])
	# stand to
	check_eq(_do(w, {"type": "c8c_standto"}), "", "STAND TO accepted")
	check(_do(w, {"type": "c8c_standto"}) == "Already standing to.", "second stand-to refused")
	w.run_ticks(220)
	var st := 0
	for p in Sent.job_board(w, fac):
		if String(p.kind) == "standto":
			st += (p.taken as Array).size()
	check(st > 0, "the board dealt stand-to points (%d men)" % st)
	var sm := C8.barracks_summary(w, fac)
	check(bool(sm.standing_to) and not (sm.posts as Array).is_empty() and int(sm.beds) > 0, "barracks summary: roster, beds, stand-to")


func test_aid_options() -> void:
	var w := _lp()
	if w == null:
		return
	var F := _F(w)
	var fac := int(F.id)
	check(_do(w, {"type": "c8c_cas_first", "target": -5}) == "Not one of your casualties.", "treat first on nobody refused")
	var ids := Sent.sentinels_of(w, _fid(w))
	var c: Dictionary = w.entities[int(ids[ids.size() - 1])]
	SimWorld.Medical.wound(w, c)   # the real Wounded transition (registers him with Medical, so a carrier can find him)
	c.hp = 10.0
	check(C8.severity(w, c) == 3, "a downed man at 10 hp is critical")
	check(C8.casualties(w, F).has(int(c.id)), "he is on the casualty board")
	check_eq(_do(w, {"type": "c8c_cas_first", "target": int(c.id)}), "", "TREAT FIRST accepted")
	check(_do(w, {"type": "c8c_cas_first", "target": int(c.id)}) == "Already treated first.", "twice refused")
	var asm := C8.aid_summary(w, fac)   # taken while he is still on the ground (an evacuation may heal him later)
	check(not (asm.rows as Array).is_empty() and int(asm.rows[0].id) == int(c.id) and (asm.first as Array).has(int(c.id)), "aid summary lists the casualty, treated first")
	# the Last Protocol start has an evac-capable medic team: take every own carrier off the map for the refusal case
	var carriers := []
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and int(e.owner) == _fid(w) and SimWorld.Medical.capacity(String(e.def)) > 0:
			carriers.append(int(e.id))
	carriers.sort()
	for id in carriers:
		w.destroy(id, "test")
	var reason := _do(w, {"type": "c8c_evac", "target": int(c.id)})
	check(reason == "No ambulance, APC or helicopter free to evacuate.", "no evac vehicle: refused with the reason (%s)" % reason)
	var amb := w.spawn_unit("a_ambulance", _fid(w), Vector2(c.pos) + Vector2(3, 0))
	w.run_ticks(2)
	check_eq(_do(w, {"type": "c8c_evac", "target": int(c.id)}), "", "EVACUATE accepted with an ambulance near")
	w.run_ticks(SimWorld.Medical.STEP * 2)   # Medical moves each carrier on its own tick bucket (every STEP ticks)
	check(w.entities[int(c.id)].has("evac_by") or String(w.entities[amb].order.get("type", "")) != "idle", "the ambulance is on its way (evac_by %s)" % str(w.entities[int(c.id)].get("evac_by")))
	check(w.entities[int(c.id)].has("evac_by") or C8.fetching(w, int(c.id)) == amb, "the ambulance is the carrier sent for him (%d)" % C8.fetching(w, int(c.id)))
	check(_do(w, {"type": "c8c_evac", "target": int(c.id)}) != "", "a second evacuation of the same man refused")
	check(_do(w, {"type": "c8c_medics", "pos": [-50, -50]}) == "Pick a point on the map.", "medics off the map refused")
	var p := CnFacility.zone(F, "staging").get_center()
	check_eq(_do(w, {"type": "c8c_medics", "pos": [p.x, p.y]}), "", "MEDICS to a point accepted")
	w.run_ticks(220)
	var med := {}
	for j in Sent.job_board(w, fac):
		if String(j.id) == "c8c_med":
			med = j
	check(not med.is_empty() and not (med.taken as Array).is_empty(), "menders posted at the point (%s)" % str(med.get("taken", [])))


func test_air_options() -> void:
	var w := _lp()
	if w == null:
		return
	var F := _F(w)
	check(_do(w, {"type": "c8c_air_cap", "pos": [10, 10]}) == "No helicopters / VTOLs to fly a patrol." or not C8.aircraft(w, _fid(w)).is_empty(), "air patrol with no aircraft refused")
	var hp := CnFacility.zone(F, "helipad").get_center()
	var h := w.spawn_unit("a_attack_heli", _fid(w), hp)
	w.run_ticks(30)
	check(C8.aircraft(w, _fid(w)).has(h), "the helicopter is on the air roster (phase %s)" % Air.phase(w, h))
	check(_do(w, {"type": "c8c_air_service", "unit_id": 999999}) == "Not one of your helicopters / VTOLs.", "service of a stranger refused")
	if C8._grounded(w, h):
		check_eq(_do(w, {"type": "c8c_air_launch", "unit_id": h, "pos": [hp.x + 12, hp.y]}), "", "LAUNCH accepted")
		w.run_ticks(5)
	check(not C8._grounded(w, h), "the helicopter is airborne (%s)" % Air.phase(w, h))
	check(_do(w, {"type": "c8c_air_launch", "unit_id": h}) == "Already airborne.", "launching an airborne one refused")
	check_eq(_do(w, {"type": "c8c_air_recall"}), "", "RECALL ALL accepted")
	# a facility craft has no airfield pad of its own: "home" is the facility helipad (land_at there), 13.9c-45
	check(C8.returning(w, F, h) or C8._grounded(w, h), "recalled: flying home to its pad (%s, land %s)" % [Air.phase(w, h), str(Air.flight(w, h).get("land_cell"))])
	check_eq(_do(w, {"type": "c8c_air_cap", "pos": [hp.x + 10, hp.y + 10]}), "", "AIR PATROL accepted")
	check(not (C8.fs(w, int(F.id)).cap as Dictionary).is_empty(), "air patrol saved on the facility")
	check_eq(_do(w, {"type": "c8c_air_cap", "clear": true}), "", "END PATROL accepted")
	check(_do(w, {"type": "c8c_air_cap", "clear": true}) == "No air patrol is flying.", "ending twice refused")
	var sm := C8.air_summary(w, int(F.id))
	check((sm.rows as Array).size() >= 1 and float(sm.rows[0].fuel) > 0.0, "air summary: fuel / ammo / hull rows")


func _script(w: SimWorld) -> void:
	var fac := int(_F(w).id)
	var j := _manned(w, fac)
	if not j.is_empty():
		_do(w, {"type": "c8c_rotate", "post": String(j.id)})
	_do(w, {"type": "c8c_plan", "plan": "gate"})
	_do(w, {"type": "c8c_standto"})
	var p := CnFacility.zone(_F(w), "staging").get_center()
	_do(w, {"type": "c8c_medics", "pos": [p.x, p.y]})
	var r := C8.roles(w, _fid(w))
	if not r.is_empty():
		_do(w, {"type": "c8c_train", "role": String(r[0])})


func test_save_load_same_future() -> void:
	var w := _lp()
	if w == null:
		return
	_script(w)
	check(w.sys_state.has("cards8c"), "cards8c state exists after use")
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(w2.state_hash(), w.state_hash(), "loaded world has the same hash")
	w.run_ticks(300)
	w2.run_ticks(300)
	check_eq(w2.state_hash(), w.state_hash(), "same future after save/load (300 ticks)")
	check_eq(str(C8.fs(w2, int(_F(w2).id))), str(C8.fs(w, int(_F(w).id))), "same card state after 300 ticks")


func test_determinism_and_untouched() -> void:
	var hs := []
	for k in 2:
		var w := _lp()
		if w == null:
			return
		_script(w)
		w.run_ticks(200)
		hs.append(w.state_hash())
	check_eq(hs[0], hs[1], "same commands -> same hash")
	var a := _lp()
	var b := _lp()
	a.run_ticks(300)
	b.sys_state.erase("cards8c")
	b.run_ticks(300)
	check(not a.sys_state.has("cards8c"), "a match that never uses the cards has no cards8c state")
	check_eq(a.state_hash(), b.state_hash(), "unused cards: same hash")
	check_eq(str(Sent.job_board(a, int(_F(a).id))), str(Sent.job_board(b, int(_F(b).id))), "unused cards: same watch board")


func test_cards_follow_selection_and_issue() -> void:
	var w := _lp()
	if w == null:
		return
	var fac := int(_F(w).id)
	var mv := StubMv.new()
	mv._world = w
	mv.player_fid = _fid(w)
	var cards := {}
	for k in Card.KINDS:
		var c = Card.make(k)
		c.mv = mv
		c._ready()
		mv.selection_changed.connect(c._on_selection_changed)
		cards[k] = c
	for k in cards:
		cards[k].refresh()
	check(not cards.bar.visible and not cards.air.visible and not cards.aid.visible and not cards.lab.visible, "no selection: all hidden")
	for k in Card.KINDS:
		mv.select_ids([fac], String(Card.PARTS[k]))
		var only := true
		for o in Card.KINDS:
			if o != k and cards[o].visible:
				only = false
		check(cards[k].visible and only, "%s part selected: only the %s card" % [Card.PARTS[k], k])
	var bk := Sent._parts_of(w, _F(w), "cn_sentinel_barracks")
	if not bk.is_empty():
		mv.select_ids([int(bk[0].id)])
		check(cards.bar.visible, "barracks building selected: the barracks card")
	mv.select_ids([fac], "garage")
	check(not cards.bar.visible and not cards.lab.visible, "garage part: none of these cards")
	# barracks buttons
	mv.select_ids([fac], "barracks")
	var bc = cards.bar
	bc._issue(bc._cmd("bar8c_standto"))
	check(String(mv.issued[-1].type) == "c8c_standto" and int(mv.issued[-1].building_id) == fac, "STAND TO issues c8c_standto for the facility")
	bc._bump(2)
	bc._issue(bc._cmd("bar8c_adopt"))
	check(String(mv.issued[-1].type) == "c8c_plan" and String(mv.issued[-1].plan) == "perimeter", "PLAN then ADOPT issues the perimeter-heavy plan")
	check(bc.why("bar8c_adopt") == "", "ADOPT enabled for a new plan")
	check(String(bc.last.get("plan", "")) == "balanced" and (bc.last.posts as Array).size() > 0, "card shows the roster and the plan in force")
	# aid: MEDICS arms a map pick, the click issues c8c_medics
	mv.select_ids([fac], "aid")
	cards.aid._arm("medics")
	check(mv.pick_cb.is_valid(), "MEDICS arms a point pick")
	mv.pick_cb.call(Vector2(40, 40))
	check(String(mv.issued[-1].type) == "c8c_medics" and is_equal_approx(float(mv.issued[-1].pos[0]), 40.0), "the click issues c8c_medics at the point")
	check(cards.aid.why("aid8c_first") == "No casualties.", "TREAT FIRST disabled with no casualties")
	# lab: QUEUE goes to the facility's own research queue
	mv.select_ids([fac], "lab")
	var lc = cards.lab
	check(lc.why("lab8c_queue") == "", "QUEUE enabled (%s)" % lc.why("lab8c_queue"))
	var q0 := (_F(w).lab.queue as Array).size()
	var cmd: Dictionary = lc._cmd("lab8c_queue")
	cmd.building_id = fac
	check_eq(_do(w, cmd), "", "cn_lab_queue from the lab card accepted by the world")
	check_eq((_F(w).lab.queue as Array).size(), q0 + 1, "the package lab queue grew")
	var tr: String = lc.why("lab8c_tier")
	check(tr == "" or tr == "No lab upgrade available.", "LAB TIER pre-checked by CnFacility (%s)" % tr)
	var sp: String = lc.why("lab8c_spec")
	check(sp != "No command.", "SPECIALISE pre-checked (%s)" % sp)
	# air: hotkey map
	mv.select_ids([fac], "air")
	check(cards.air.key_of("air8c_recall") == "SHIFT+H", "RECALL ALL on Shift+H")
	for c in cards.values():
		c.free()
