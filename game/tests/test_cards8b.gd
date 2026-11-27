extends "res://tests/test_base.gd"
## G7 CARDS8B acceptance (docs/G7_REFERENCE.md 13.9c-48): Armory + Suit Foundry card and Garages / workshop / decon
## wash card. Every option works and is refused with a reason when it cannot run; save/load gives the same future;
## same commands -> same hash; a match that never uses the cards has no cards8b state; the cards follow the selection
## and their buttons / hotkeys issue the c8b_* commands.

const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const Apc7 = preload("res://sim/systems/apc7.gd")
const C8 = preload("res://sim/systems/cards8b.gd")
const ArmCard = preload("res://presentation/ui7/armory_card8.gd")
const GarCard = preload("res://presentation/ui7/garage_card8.gd")
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
	if Content.unit("g7_sent_warden").is_empty() or Content.building("a_cn_facility").is_empty() or Content.rules().get("cards8b") == null:
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


func _lp() -> SimWorld:
	_ensure_g7()
	if _base.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(4242, MAP))
		if w0 == null:
			return null
		w0.run_ticks(25)
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


static func registered() -> bool:
	return SimWorld.COMMANDS.has("c8b_preset")


## Issues cmd as the player: through world.submit when ORCH registered the c8b commands, else straight through
## the system (same validate / apply). Returns the refusal ("" = applied).
func _do(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = _fid(w)
	if not cmd.has("building_id"):
		cmd.building_id = int(_F(w).id)
	if registered():
		var why := w.preview_command(cmd)
		if why != "":
			return why
		w.submit(cmd)
		w.run_ticks(1)
		return ""
	var r := C8.reason(w, cmd)
	if r != "":
		return r
	C8.apply_command(w, cmd)
	return ""


func _run(w: SimWorld, n: int) -> void:
	if registered():
		w.run_ticks(n)
		return
	for i in n:
		w.run_ticks(1)
		C8.tick(w)


func _parked(w: SimWorld) -> Array:
	var out := []
	for T in C8.teams(w, _F(w)):
		if String(T.phase) == "garage" and not C8.team_apcs(w, T).is_empty():
			out.append(T)
	return out


func test_armory_options() -> void:
	var w := _lp()
	if not check(w != null and not _F(w).is_empty(), "Last Protocol world with a facility"):
		return
	var F := _F(w)
	var ap = C8.armory_part(w, F)
	if not check(ap != null, "the facility has its Suit Foundry part"):
		return
	# loadout presets per role
	check(_do(w, {"type": "c8b_preset", "role": "pilots", "preset": "at_heavy"}) != "", "unknown role refused")
	check(_do(w, {"type": "c8b_preset", "role": "strike", "preset": "nope"}) == "Unknown loadout preset.", "unknown preset refused with its reason")
	check_eq(_do(w, {"type": "c8b_preset", "role": "strike", "preset": "at_heavy"}), "", "AT-heavy preset for strike teams accepted")
	_run(w, 45)
	var picked := 0
	for T in C8.teams(w, F):
		if C8.team_role(w, T) != "strike" or String(T.phase) != "garage":
			continue
		for a in C8.team_apcs(w, T):
			if a.has("a7") and int(a.a7.rl.load.get("tandem", 0)) == 12:
				picked += 1
	check(picked > 0, "parked strike APCs picked up the AT-heavy rocket mix (%d)" % picked)
	check(String(C8.fs(w, int(F.id)).presets.get("strike", "")) == "at_heavy", "preset saved in the facility state")
	# suit build + rush
	check(_do(w, {"type": "c8b_suit_build", "role": "nope"}) != "", "unknown suit role refused")
	check(_do(w, {"type": "c8b_suit_rush"}) == "No suit in the build queue to rush.", "rush refused with an empty queue")
	var qn := (ap.queue as Array).size()
	var r := _do(w, {"type": "c8b_suit_build", "role": "bastion"})
	check_eq(r, "", "Bastion suit queued at the Suit Foundry")
	check_eq((ap.queue as Array).size(), qn + 1, "Suit Foundry queue grew by one")
	if (ap.queue as Array).size() > 0:
		var p0 := float(ap.queue[0].progress)
		check_eq(_do(w, {"type": "c8b_suit_rush"}), "", "rush accepted")
		check(float(ap.queue[0].progress) >= p0 + 0.45, "rush moved the head suit ahead (%.2f -> %.2f)" % [p0, float(ap.queue[0].progress)])
	# suit repair queue
	var sdef := String(Content.production(C8.suit_item(w, _fid(w), "bastion")).get("spawns", [""])[0])
	var sid := w.spawn_unit(sdef, _fid(w), C8._repair_spot(F, ap))
	var s: Dictionary = w.entities[sid]
	check(_do(w, {"type": "c8b_suit_repair", "unit_id": sid}) == "That suit is not damaged.", "undamaged suit refused")
	s.hp = C8._maxhp(s) * 0.4
	var h0 := float(s.hp)
	check_eq(_do(w, {"type": "c8b_suit_repair", "unit_id": sid}), "", "damaged suit queued for repair")
	check(_do(w, {"type": "c8b_suit_repair", "unit_id": sid}) == "That suit is already in the repair queue.", "re-queue refused")
	_run(w, 200)
	check(float(w.entities[sid].hp) > h0 + 100.0, "suit repaired at the bay (%.0f -> %.0f)" % [h0, float(w.entities[sid].hp)])
	# weapon upgrades
	check(_do(w, {"type": "c8b_upgrade", "key": "lasers"}) == "Unknown upgrade.", "unknown upgrade refused")
	check_eq(_do(w, {"type": "c8b_upgrade", "key": "ap_rounds"}), "", "AP rounds research started")
	check(_do(w, {"type": "c8b_upgrade", "key": "optics"}).begins_with("The armory is already researching"), "second research refused while one runs")
	check(C8.round_mods(w, s).is_empty(), "no round change before the research finishes")
	_run(w, C8.secs(45) + 45)
	check(C8.side_up(w, _fid(w)).has("ap_rounds"), "AP rounds researched")
	_run(w, 45)   # CARDS8C: the upgrade reaches LETHAL8's ballistics as the saved e.r8up field (fact api.rounds8)
	check(String(w.entities[sid].get("r8up", {}).get("id", "")).begins_with("c8b:") and is_equal_approx(float(w.entities[sid].get("r8up", {}).get("pen", 1.0)), 1.5), "AP rounds: the suit fires with e.r8up pen x1.5 (%s)" % str(w.entities[sid].get("r8up", {})))
	check(is_equal_approx(float(C8.round_mods(w, s).get("pen", 1.0)), 1.5), "AP rounds: CN unit round pen x1.5 (LETHAL8 model)")
	check(_do(w, {"type": "c8b_upgrade", "key": "ap_rounds"}).ends_with("already fitted."), "AP rounds twice refused")
	check(is_equal_approx(C8.armour_mult(w, s), 1.0), "no plates yet: armour x1.0")
	var foe := -1
	for e in w.entities.values():
		if String(e.get("kind", "")) == "unit" and int(e.owner) != _fid(w):
			foe = int(e.id)
			break
	if foe >= 0:
		check(C8.round_mods(w, w.entities[foe]).is_empty(), "other sides' rounds unchanged")


func test_garage_options() -> void:
	var w := _lp()
	if not check(w != null and not _F(w).is_empty(), "Last Protocol world with a facility"):
		return
	var F := _F(w)
	var pk := _parked(w)
	if not check(pk.size() >= 2, "at least two vehicle teams parked (%d)" % pk.size()):
		return
	var T: Dictionary = pk[0]
	var a: Dictionary = C8.team_apcs(w, T)[0]
	# repair priority
	check(_do(w, {"type": "c8b_veh_repair", "team": int(T.id)}) == "Those vehicles are not damaged.", "undamaged team refused")
	check(_do(w, {"type": "c8b_veh_repair", "team": 999999}) != "", "unknown team refused")
	a.hp = C8._maxhp(a) * 0.5
	var h0 := float(a.hp)
	var c0 := int(w.factions[_fid(w)].credits)
	check_eq(_do(w, {"type": "c8b_veh_repair", "team": int(T.id)}), "", "damaged team queued for priority repair")
	_run(w, 60)
	check(float(a.hp) > h0 + 120.0, "workshop crew repaired faster than the garage alone (%.0f -> %.0f)" % [h0, float(a.hp)])
	check(int(w.factions[_fid(w)].credits) < c0, "repair cost credits")
	# vehicle upgrades
	check(_do(w, {"type": "c8b_veh_upgrade", "team": int(T.id), "key": "warp"}) == "Unknown vehicle upgrade.", "unknown kit refused")
	var mh := C8._maxhp(a)
	check_eq(_do(w, {"type": "c8b_veh_upgrade", "team": int(T.id), "key": "armour_kit"}), "", "armour kit fitted")
	check(is_equal_approx(C8._maxhp(a), mh * 1.25), "armour kit: max hp x1.25")
	check(_do(w, {"type": "c8b_veh_upgrade", "team": int(T.id), "key": "armour_kit"}).ends_with("already fitted."), "armour kit twice refused")
	check_eq(_do(w, {"type": "c8b_veh_upgrade", "team": int(T.id), "key": "engines"}), "", "engines fitted")
	check(is_equal_approx(float(a.get("c8mv", 1.0)), 1.15), "engines: c8mv 1.15 on the APC")
	_run(w, 60)   # CARDS8C: Morale's realism pass multiplies e.c8mv into e.mvm (the speed factor Movement reads)
	check(float(a.get("mvm", 1.0)) > 1.1, "engines: the APC's speed factor rose (mvm %.2f)" % float(a.get("mvm", 1.0)))
	var rp := _do(w, {"type": "c8b_veh_upgrade", "team": int(T.id), "key": "rocket_pod"})
	if rp == "":
		var base := 0
		for k in a.a7.rl.load:
			base += int(a.a7.rl.load[k])
		check_eq(Apc7.rockets_left(a), base + 6, "rocket pod: +6 rounds on the rack")
	else:
		check(rp == "These vehicles have no rocket launcher.", "rocket pod refused with a reason (%s)" % rp)
	var dr := _do(w, {"type": "c8b_veh_upgrade", "team": int(T.id), "key": "dome_shield"})
	if dr == "":
		var ch := float(Apc7.cfg_of(String(a.def)).get("dome", {}).get("charge", 1000.0))
		check(is_equal_approx(float(a.a7.dome), ch * 1.5), "dome shield: dome charge x1.5")
	else:
		check(dr == "These vehicles have no dome emitter.", "dome shield refused with a reason (%s)" % dr)
	# decon
	check(_do(w, {"type": "c8b_decon_force"}) == "Nobody is contaminated.", "decon refused with nobody contaminated")
	var foot := -1
	for e in w.entities.values():
		if int(e.owner) == _fid(w) and String(e.get("kind", "")) == "unit" and String(Content.unit(String(e.def)).get("move_class", "foot")) == "foot" and CN.team_of(e) < 0 and String(e.order.get("type", "")) != "hold":
			foot = int(e.id)
			break
	if check(foot >= 0, "a soldier on foot to contaminate"):
		w.entities[foot].cn_exp = 0.5
		check_eq(_do(w, {"type": "c8b_decon_force"}), "", "force decon accepted")
		check(String(w.entities[foot].order.get("type", "")) == "move", "contaminated soldier ordered to the wash")
	check_eq(_do(w, {"type": "c8b_decon_skip", "on": true}), "", "skip wash under fire on")
	check(bool(C8.fs(w, int(F.id)).skip), "skip flag saved")
	# convoy launch / recall
	check(_do(w, {"type": "c8b_recall"}) == "No vehicle team is out.", "recall refused with nobody out")
	check(_do(w, {"type": "c8b_convoy", "teams": [int(pk[0].id), int(pk[1].id)]}) == "Pick a destination.", "convoy without destination refused")
	var tgt := CnFacility.compound_rect(F).end + Vector2(-16, 6)
	check_eq(_do(w, {"type": "c8b_convoy", "teams": [int(pk[0].id), int(pk[1].id)], "target": [tgt.x, tgt.y]}), "", "convoy of two teams launched")
	_run(w, 12)
	check(String(CnFacility.team(w, int(pk[0].id)).phase) != "garage" and String(CnFacility.team(w, int(pk[1].id)).phase) != "garage", "both teams left their garages")
	var out := false
	for i in 150:
		_run(w, 20)
		if String(CnFacility.team(w, int(pk[0].id)).phase) == "out":
			out = true
			break
	check(out, "convoy team out through the gate (%s)" % String(CnFacility.team(w, int(pk[0].id)).phase))
	if out:
		check_eq(_do(w, {"type": "c8b_recall"}), "", "recall all accepted")
		_run(w, 2)
		check(String(CnFacility.team(w, int(pk[0].id)).phase) != "out", "recalled team heading home (%s)" % String(CnFacility.team(w, int(pk[0].id)).phase))


func _script(w: SimWorld) -> void:
	var F := _F(w)
	var pk := _parked(w)
	_do(w, {"type": "c8b_preset", "role": "strike", "preset": "demolition"})
	_do(w, {"type": "c8b_upgrade", "key": "plates"})
	_do(w, {"type": "c8b_suit_build", "role": "aegis"})
	if not pk.is_empty():
		var a: Dictionary = C8.team_apcs(w, pk[0])[0]
		a.hp = C8._maxhp(a) * 0.6
		_do(w, {"type": "c8b_veh_repair", "team": int(pk[0].id)})
		_do(w, {"type": "c8b_veh_upgrade", "team": int(pk[0].id), "key": "armour_kit"})
	if pk.size() > 1:
		var g := CnFacility.zone(F, "gate").get_center()
		_do(w, {"type": "c8b_convoy", "teams": [int(pk[1].id)], "target": [g.x, g.y + 12.0]})
	_run(w, 100)


func test_save_load_same_future() -> void:
	var w := _lp()
	if w == null:
		return
	_script(w)
	check(w.sys_state.has("cards8b"), "cards8b state exists after use")
	var w2 := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(w2.state_hash(), w.state_hash(), "loaded world has the same hash")
	_run(w, 300)
	_run(w2, 300)
	check_eq(w2.state_hash(), w.state_hash(), "same future after save/load (300 ticks)")
	check_eq(str(C8.fs(w2, int(_F(w2).id))), str(C8.fs(w, int(_F(w).id))), "same card state after 300 ticks")


func test_determinism_and_untouched() -> void:
	var hs := []
	for k in 2:
		var w := _lp()
		if w == null:
			return
		_script(w)
		_run(w, 200)
		hs.append(w.state_hash())
	check_eq(hs[0], hs[1], "same commands -> same hash")
	var w3 := _lp()
	_run(w3, 100)
	check(not w3.sys_state.has("cards8b"), "a match that never uses the cards has no cards8b state")


func test_cards_follow_selection_and_issue() -> void:
	var w := _lp()
	if w == null:
		return
	var F := _F(w)
	var fac := int(F.id)
	var ap = C8.armory_part(w, F)
	var mv := StubMv.new()
	mv._world = w
	mv.player_fid = _fid(w)
	var ac = ArmCard.new()
	var gc = GarCard.new()
	for c in [ac, gc]:
		c.mv = mv
		c._ready()
		mv.selection_changed.connect(c._on_selection_changed)
	ac.refresh()
	gc.refresh()
	check(not ac.visible and not gc.visible, "no selection: both cards hidden")
	mv.select_ids([int(ap.id)])
	check(ac.visible and not gc.visible, "Suit Foundry selected: only the armory card")
	mv.select_ids([fac], "garage")
	check(gc.visible and not ac.visible, "garage selected: only the garage card")
	mv.select_ids([fac], "drone_bay")
	check(not gc.visible and not ac.visible, "drone bay part: the drone bay card's, not the garage card (CARDS8C: garage bays select part garage in match_view)")
	mv.select_ids([fac])
	check(not gc.visible and not ac.visible, "facility core without a part: both hidden")
	# armory buttons
	mv.select_ids([int(ap.id)])
	check(ac.btns.arm8b_rush.disabled and String(ac.btns.arm8b_rush.tooltip_text).contains("No suit in the build queue"), "RUSH disabled with the sim reason as tooltip")
	ac._on_build()
	check(String(mv.issued[-1].type) == "c8b_suit_build" and String(mv.issued[-1].role) == "bastion", "BUILD issues c8b_suit_build bastion")
	ac._on_role()
	ac._on_preset()
	check(String(mv.issued[-1].type) == "c8b_preset" and String(mv.issued[-1].role) == "tactical", "ROLE then PRESET issues c8b_preset for tactical")
	ac._on_upgrade()
	check(String(mv.issued[-1].type) == "c8b_upgrade" and String(mv.issued[-1].key) == "ap_rounds", "RESEARCH issues c8b_upgrade ap_rounds")
	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.shift_pressed = true
	ev.pressed = true
	var n0 := mv.issued.size()
	check(ac.handle_key(ev) and mv.issued.size() == n0 + 1 and String(mv.issued[-1].type) == "c8b_suit_build", "Shift+B hotkey builds a suit")
	# garage buttons
	mv.select_ids([fac], "garage")
	check(gc.btns.gar8b_recall.disabled and String(gc.btns.gar8b_recall.tooltip_text).contains("No vehicle team is out"), "RECALL disabled with the sim reason")
	gc._on_pick()
	gc._on_launch()
	check(gc.picking and mv.pick_cb.is_valid(), "LAUNCH arms a map point pick")
	mv.pick_cb.call(Vector2(10, 12))
	check(String(mv.issued[-1].type) == "c8b_convoy" and (mv.issued[-1].teams as Array).size() == 1, "the map click issues c8b_convoy with the picked team")
	gc._on_skip()
	check(String(mv.issued[-1].type) == "c8b_decon_skip" and bool(mv.issued[-1].on), "SKIP WASH issues c8b_decon_skip on")
	gc._on_fit()
	check(String(mv.issued[-1].type) == "c8b_veh_upgrade" and String(mv.issued[-1].key) == "armour_kit", "FIT issues c8b_veh_upgrade armour_kit")
	ac.free()
	gc.free()
