extends "res://tests/test_base.gd"
## G6.1 acceptance (owner: GEN61): AI Commander slots with objective {type: "auto"} are full generals
## (sim/ai/general.gd + general_war.gd). Real checks, no player input unless the test says so.

const AiCommand = preload("res://sim/systems/ai_command.gd")
const Companies = preload("res://sim/systems/companies.gd")
const General = preload("res://sim/ai/general.gd")
const War = preload("res://sim/ai/general_war.gd")
const U = preload("res://sim/ai/ai_util.gd")
const Movement = preload("res://sim/systems/movement.gd")
const BIG := 1000000
const SAVE_DIR := "user://test_gen61"
const SaveSystem = preload("res://sim/save_system.gd")


## Default match, side 1 inert, an open grass field at x 22-73, y 0-25, money for everything.
func _world() -> SimWorld:
	var w := make_world()
	w.ai_state = {}
	var t: PackedByteArray = w.map.terrain
	for y in range(0, 26):
		for x in range(22, 74):
			t[y * int(w.map.w) + x] = Terrain.GRASS
	w.map.terrain = t
	Movement.rebuild_nav(w)
	for fid in [0, 1]:
		var f: Dictionary = w.factions[fid]
		f.stage = 8
		f.credits = BIG
		f.stock.salvage = BIG
		f.stock.ore = BIG
	for e in w.units_of(1):   # REGRESS7-5 setup (see _face_away): side 1's start units face east as before too
		_face_away(w, int(e.id))
	return w


func _squad(w: SimWorld, fid: int, n: int, p: Vector2, role: String = "infantry") -> Array:
	var d := U.role_unit(w, fid, role)
	var out := []
	for i in n:
		out.append(w.spawn_unit(d, fid, p + Vector2(float(i % 3), float(i / 3))))
		if fid == 1:
			_face_away(w, int(out[-1]))
	return out


## G7 REGRESS7-5 (ORCH ruling on need seq 2471, setup only, oracles unchanged): spawn_unit now faces a new unit
## toward its owner's front, i.e. side 1 now watches side 0 (G7_REFERENCE section 2 "Realistic senses": view cones,
## spot passes every 16 ticks). These scenarios were built on the side-1 groups not watching that way (the old
## east-facing default), so they face east again after spawning.
func _face_away(w: SimWorld, id: int) -> void:
	w.entities[id].facing = 0.0


func _run(w: SimWorld, n: int, evs: Array) -> void:
	for i in n:
		w.step()
		evs.append_array(w.events)


## Runs until pred() or n ticks; returns true when pred held.
func _run_until(w: SimWorld, n: int, evs: Array, pred: Callable) -> bool:
	for i in n:
		w.step()
		evs.append_array(w.events)
		if pred.call():
			return true
	return false


func _auto(w: SimWorld, slot: int, target: Dictionary, ps: String, stance: String = "balanced", budget = null) -> Array:
	var cmd := {"type": "set_ai_commander", "slot": slot, "target": target, "playstyle": ps, "stance": stance}
	if budget != null:
		cmd.budget = budget
	var ev := do_cmd(w, 0, cmd)
	check_eq(rejected_reason(ev), "", "set_ai_commander (auto by default) accepted (%s)" % ps)
	return ev


func _slot(w: SimWorld, sl: int) -> Dictionary:
	return w.sys_state.ai_cmd.slots[0].get(sl, {})


func _gen(w: SimWorld, sl: int = 0) -> Dictionary:
	return _slot(w, sl).get("gen", {})


func _op(w: SimWorld, sl: int = 0) -> String:
	return String((_gen(w, sl).get("op", {}) as Dictionary).get("type", ""))


func _ops_seen(evs: Array) -> Dictionary:
	var out := {}
	for ev in evs:
		if String(ev.type) == "AiGeneralOp" and int(ev.fid) == 0:
			out[String(ev.op)] = true
	return out


func _centroid(w: SimWorld, ids: Array) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in ids:
		if w.entities.has(int(id)):
			s += Vector2(w.entities[int(id)].pos)
			n += 1
	return s / float(maxi(n, 1))


func _alive(w: SimWorld, ids: Array) -> int:
	var n := 0
	for id in ids:
		if w.entities.has(int(id)):
			n += 1
	return n


## A unit def of this side's faction with a strike block of `kind` ("" when none).
func _strike_def(w: SimWorld, fid: int, kind: String) -> String:
	var ids := Content.ids("units")
	ids.sort()
	for d in ids:
		var u := Content.unit(String(d))
		if String(u.get("strike", {}).get("kind", "")) == kind and U.available(w, fid, String(d)):
			return String(d)
	for d in ids:
		if String(Content.unit(String(d)).get("strike", {}).get("kind", "")) == kind:
			return String(d)
	return ""


# ================================================================ (a) strike
func test_auto_is_default_and_strikes_weak_visible_enemy() -> void:
	var w := _world()
	var home := U.base_pos(w, 0)
	var ids := _squad(w, 0, 6, Vector2(44.5, 12.5))
	var foe := _squad(w, 1, 1, Vector2(52.5, 12.5))
	var evs := _auto(w, 0, {"units": ids}, "aggressive")
	check_eq(String(_slot(w, 0).objective.type), "auto", "a slot without an objective is an auto general")
	var struck := _run_until(w, 400, evs, func(): return _ops_seen(evs).has("strike"))
	check(struck, "the general picks STRIKE on a visible weak enemy (ops %s, home %s)" % [str(_ops_seen(evs)), str(home)])
	var gone := _run_until(w, 1200, evs, func(): return _alive(w, foe) == 0)
	check(gone, "the strike kills the weak enemy (alive %d)" % _alive(w, foe))
	var view: Dictionary = AiCommand.slots(w, 0)[0].general
	check(String(view.status) != "" and not (view.log as Array).is_empty(), "panel view: status '%s', log %s" % [String(view.status), str(view.log)])


# ================================================================ (b) defend
func test_switches_to_defend_when_base_attacked() -> void:
	var w := _world()
	var home := U.base_pos(w, 0)
	var ids := _squad(w, 0, 6, Vector2(44.5, 12.5))
	_squad(w, 1, 2, Vector2(62.5, 12.5))
	var evs := _auto(w, 0, {"units": ids}, "combined")
	_run(w, 250, evs)
	check(_op(w) != "defend", "not defending before the base is attacked (op %s)" % _op(w))
	_squad(w, 1, 3, home + Vector2(4, 4))
	var ok := _run_until(w, 500, evs, func(): return _op(w) == "defend")
	check(ok, "the general switches to DEFEND when its base is attacked (op %s, seen %s)" % [_op(w), str(_ops_seen(evs))])


# ================================================================ (c) infil / exfil
func test_infil_exfil_returns_by_a_different_route() -> void:
	var w := _world()
	var home := U.base_pos(w, 0)
	var ids := _squad(w, 0, 4, Vector2(40.5, 12.5))
	var art := ""
	for d in Content.ids("units"):
		if U.is_artillery(String(d)) and U.available(w, 1, String(d)) and not U.is_air(String(d)):
			art = String(d)
			break
	if not check(art != "", "an artillery def exists for side 1"):
		return
	var tgt := w.spawn_unit(art, 1, Vector2(54.5, 12.5))
	_face_away(w, tgt)   # REGRESS7-5 setup (see _face_away)
	_squad(w, 1, 2, Vector2(55.5, 14.5))
	# G7 REG8A (setup only, G7_REFERENCE "Lethality test-setup authority", before 13.9c-48): the subject is the route in
	# and out, not toughness. Side 1's roaming start recon is not part of this scenario (the planted defenders are the
	# artillery + 2 guards); with G7 hit chance / lethality it caught the fire-held team on the way in and broke the op
	# off at 46% losses (limit 45%). It is removed before the op; every assertion is unchanged.
	for e in w.units_of(1):
		if String(e.def) == "recon":
			w.destroy(int(e.id), "test_setup")
	var evs := _auto(w, 0, {"units": ids}, "specops")
	var started := _run_until(w, 2400, evs, func(): return _op(w) == "infil")
	check(started, "the specops general picks INFIL/EXFIL on a valuable target (ops %s)" % str(_ops_seen(evs)))
	var done := _run_until(w, 6000, evs, func():
		var g := _gen(w)
		return not (g.get("hist", []) as Array).is_empty() and String(g.hist.back().type) == "infil")
	if not check(done, "the infil op ends (op %s phase %s)" % [_op(w), String(_gen(w).get("op", {}).get("phase", ""))]):
		return
	var last: Dictionary = _gen(w).last
	check(bool(_gen(w).hist.back().ok), "the infil ended in success, not broken off")
	var tin: Array = last.trail_in
	var tout: Array = last.trail_out
	check(tin.size() >= 2 and tout.size() >= 2, "both legs recorded (in %d, out %d)" % [tin.size(), tout.size()])
	var mi := (Vector2(last.wp_in))
	var mo := (Vector2(last.wp_out))
	check(mi.distance_to(mo) >= 6.0, "exfil route differs from the way in (waypoints %s vs %s)" % [str(mi), str(mo)])
	var surv := []
	for id in ids:
		if w.entities.has(int(id)):
			surv.append(id)
	check(not surv.is_empty(), "survivors made it out (%d of %d)" % [surv.size(), ids.size()])
	check(_centroid(w, surv).distance_to(Vector2(last.rally)) <= 6.0, "survivors are back at the rally point %s (at %s)" % [
		str(last.rally), str(_centroid(w, surv))])


# ================================================================ (d) budget
func _hq(w: SimWorld) -> int:
	var hd := String(Companies.leaders(Companies.faction_of(w, 0)).get("hq", ""))
	var hq := w.spawn_building(hd, 0, Vector2i(30, 4), true)
	for k in 3:
		w.spawn_building("depot", 0, Vector2i(24 + k * 3, 20), true)
	return hq


func test_trains_replacement_within_budget_only() -> void:
	var w := _world()
	_hq(w)
	var ids := _squad(w, 0, 4, Vector2(44.5, 12.5))
	var tids := Companies.templates_for(0, w)
	if not check(not tids.is_empty(), "side 0 has company templates"):
		return
	var cheapest := {}
	for tid in tids:
		var t := Companies.template(w, 0, String(tid))
		var c: Dictionary = Companies.plan(w, 0, t, "platoon", true).cost
		if cheapest.is_empty() or int(c.get("credits", 0)) < int(cheapest.get("credits", 0)):
			cheapest = c
	var lump := {}
	for k in War.RES:
		lump[k] = int(int(cheapest.get(k, 0)) * 1.5)
	var credits0 := int(w.factions[0].credits)
	_auto(w, 0, {"units": ids}, "combined", "balanced", {"lump": lump})
	_run(w, 2, [])
	_slot(w, 0).peak_power = 100.0  # a depleted force: it once had far more combat power
	var evs := []
	var queued := 0
	var ok := true
	for i in 3000:
		w.step()
		evs.append_array(w.events)
		for ev in w.events:
			if String(ev.type) == "CompanyQueued" and int(ev.owner) == 0:
				queued += 1
		var bl := War.budget_left(w, _slot(w, 0))
		for k in War.RES:
			if int(bl.get(k, 0)) < 0:
				ok = false
	check_eq(queued, 1, "exactly one replacement company trained from a lump that covers one (lump %s)" % str(lump))
	check(ok, "the slot's budget never goes below zero")
	var spent := credits0 - int(w.factions[0].credits)
	check(spent > 0 and spent <= int(lump.credits), "side credits spent (%d) stay within the granted lump (%d)" % [spent, int(lump.credits)])
	var bud: Dictionary = _slot(w, 0).budget
	for k in War.RES:
		check(int(bud.spent[k]) <= int(lump[k]), "%s booked %d <= granted %d" % [k, int(bud.spent[k]), int(lump[k])])
	# a rate grant through set_ai_budget accrues over time
	if SimWorld.COMMANDS.has("set_ai_budget"):  # registered by ORCH (CR change_request.world.commands)
		var ev := do_cmd(w, 0, {"type": "set_ai_budget", "slot": 0, "budget": {"credits_pm": 600}})
		var c0 := int(War.budget_left(w, _slot(w, 0)).credits)
		_run(w, 1200, [])
		check(rejected_reason(ev) == "" and int(War.budget_left(w, _slot(w, 0)).credits) >= c0, "a per-minute grant accrues (%d -> %d)" % [c0, int(War.budget_left(w, _slot(w, 0)).credits)])


# ================================================================ (e) fire support
func test_calls_owned_strike_never_danger_close() -> void:
	var w := _world()
	var sd := _strike_def(w, 0, "mlrs")
	if not check(sd != "", "an MLRS strike def exists"):
		return
	var ids := _squad(w, 0, 3, Vector2(36.5, 12.5))
	var mlrs := w.spawn_unit(sd, 0, Vector2(40.5, 14.5))
	ids.append(mlrs)
	var spot := [w.spawn_unit("recon", 0, Vector2(49.5, 12.5))]   # long-sight spotter
	ids.append_array(spot)
	_squad(w, 1, 3, Vector2(56.5, 12.5))      # the group to hit (7+ cells from the spotter, in MLRS range)
	_squad(w, 1, 1, Vector2(41.5, 11.5))      # danger close to our own infantry
	_run(w, 40, [])                            # let Fog see the field first
	var evs := _auto(w, 0, {"units": ids}, "defensive", "cautious")
	var fired := 0
	var close := 0
	for i in 901:
		if i > 0:
			w.step()
		# GEN61-2: i == 0 scans the events of the set_ai_commander step itself (the first think can call
		# the strike there, with real Intel the general is ready one think earlier)
		for ev in (evs if i == 0 else w.events):
			if String(ev.type) == "AiFireSupport" and int(ev.fid) == 0:
				fired += 1
				var p := Vector2(ev.cell) + Vector2(0.5, 0.5)
				for e in w.units_of(0):
					if (e.pos as Vector2).distance_to(p) <= War.W("danger_close"):
						close += 1
	var dbg := ""
	if fired == 0:  # diagnostics in the failure message
		var Sk = load("res://sim/systems/strikes.gd")
		var e = w.entities.get(mlrs)
		dbg = "mlrs def=%s alive=%s kind=%s range=%s" % [sd, str(e != null), Sk.kind_of(e) if e != null else "", str(Sk.range_of(e)) if e != null else ""]
		for c in General.clusters(General.belief(w, 0)):
			var aim := Vector2(floori(c.pos.x), floori(c.pos.y)) + Vector2(0.5, 0.5)
			dbg += " | cluster %s n=%d err='%s' clear=%s" % [str(c.pos), int(c.n), Sk.strike_error(w, e, aim) if e != null else "-", str(War.clear_of_friends(w, 0, aim, 7.0))]
		dbg += " | op=" + _op(w) + " units=" + str(_slot(w, 0).get("units", []))
	check(fired >= 1, "the general calls a strike the side owns (%d calls) %s" % [fired, dbg])
	check_eq(close, 0, "no strike is called danger-close to its own troops")


# ================================================================ (f) flank
func test_deliberate_attack_flanks() -> void:
	var w := _world()
	var ids := _squad(w, 0, 9, Vector2(40.5, 11.5))
	_squad(w, 1, 2, Vector2(54.5, 12.5))
	w.spawn_building("depot", 1, Vector2i(56, 13), true)
	var evs := _auto(w, 0, {"units": ids}, "combined")
	var ok := _run_until(w, 2500, evs, func():
		var op: Dictionary = _gen(w).get("op", {})
		return float(_gen(w).get("last_flank_deg", 0.0)) > 0.0 and String(op.get("type", "")) == "attack")
	check(_ops_seen(evs).has("attack"), "the combined-arms general runs a DELIBERATE ATTACK (ops %s)" % str(_ops_seen(evs)))
	check(ok and float(_gen(w).last_flank_deg) >= 60.0, "the main effort's path ends >= 60 deg off the direct axis (%.1f deg)" % float(_gen(w).get("last_flank_deg", 0.0)))


# ================================================================ (g) override window
func test_never_orders_unit_player_touched() -> void:
	var w := _world()
	var ids := _squad(w, 0, 6, Vector2(44.5, 12.5))
	_squad(w, 1, 1, Vector2(52.5, 12.5))
	var evs := _auto(w, 0, {"units": ids}, "aggressive")
	_run(w, 30, evs)
	var a := int(ids[0])
	check_eq(rejected_reason(do_cmd(w, 0, {"type": "move", "unit_ids": [a], "target": Vector2(30.5, 20.5)})), "", "player move accepted")
	var bad := 0
	for i in 380:
		for c in w.pending:
			if int(c.get("issuer", -1)) == 0 and c.has("ai_cmd") and (c.get("unit_ids", []) as Array).has(a):
				bad += 1
		w.step()
	check_eq(bad, 0, "no general order touches the unit the player ordered within 20 s")
	check((Vector2(w.entities[a].pos)).distance_to(Vector2(30.5, 20.5)) < 3.0, "the unit went where the player sent it")


# ================================================================ (h) 10-minute run
func test_ten_minutes_five_operation_types() -> void:
	var w := _world()
	_hq(w)
	var home := U.base_pos(w, 0)
	var ids := _squad(w, 0, 9, Vector2(40.5, 11.5))
	ids.append(w.spawn_unit("recon", 0, Vector2(41.5, 14.5)))   # long-sight scout in the force
	var evs := _auto(w, 0, {"units": ids}, "combined", "balanced", {"credits_pm": 300, "salvage_pm": 100, "ore_pm": 100})
	var spawned := {}
	for t in 12000:
		w.step()
		evs.append_array(w.events)
		var us := []
		for id in _slot(w, 0).get("units", []):
			if w.entities.has(int(id)):
				us.append(int(id))
		var cen := _centroid(w, us) if not us.is_empty() else Vector2(40, 12)
		var ahead := Vector2(clampf(cen.x + 10.0, 24.0, 72.0), clampf(cen.y, 2.0, 23.0))
		if t == 600 and not spawned.has("weak"):
			spawned.weak = _squad(w, 1, 1, ahead)
		if t == 2600:
			spawned.post = _squad(w, 1, 3, ahead + Vector2(1, 0))
		if t == 6000:
			spawned.raid = _squad(w, 1, 3, home + Vector2(4, 4))
		if t == 8400:
			spawned.horde = _squad(w, 1, 12, Vector2(clampf(cen.x + 6.0, 1.0, float(w.map.w) - 4.0), clampf(cen.y - 1.0, 1.0, float(w.map.h) - 5.0)), "infantry")
	var seen := _ops_seen(evs)
	var g := _gen(w)
	var hs := []
	for h in g.get("hist", []):
		hs.append("%s%d%s" % [String(h.type).left(4), int(h.tick) / 100, "+" if bool(h.ok) else "-"])
	check(seen.size() >= 5, "%d types in 10 min: %s alive %d op %s" % [seen.size(), " ".join(PackedStringArray(hs)), _alive(w, ids), _op(w)])
	var log_lines := 0
	for ev in evs:
		if String(ev.type) == "AiGeneralOp":
			log_lines += 1
	check(log_lines >= 10, "the general reports its operations (%d AiGeneralOp events)" % log_lines)


# ================================================================ (i) determinism + save/load
func _det_world() -> SimWorld:
	var w := _world()
	_hq(w)
	var ids := _squad(w, 0, 8, Vector2(40.5, 11.5))
	_squad(w, 1, 2, Vector2(54.5, 12.5))
	w.spawn_building("depot", 1, Vector2i(56, 13), true)
	do_cmd(w, 0, {"type": "set_ai_commander", "slot": 0, "target": {"units": ids}, "playstyle": "combined",
		"stance": "balanced", "budget": {"credits_pm": 600, "lump": {"credits": 500}}})
	return w


func test_determinism_and_save_load_mid_op() -> void:
	var a := _det_world()
	var b := _det_world()
	_run(a, 500, [])
	_run(b, 500, [])
	check_eq(a.state_hash(), b.state_hash(), "same setup, same hash after 500 ticks")
	check(_op(a) != "" or not (_gen(a).get("hist", []) as Array).is_empty(), "an operation is under way at the save (%s)" % _op(a))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + "/gen61.sav"
	if not check_eq(SaveSystem.save(a, path), "", "save mid-op"):
		return
	var l: SimWorld = SaveSystem.load(path)
	if not check(l != null, "the save loads"):
		return
	check_eq(l.state_hash(), a.state_hash(), "state_hash equal after the round trip")
	check_eq(str(l.sys_state.ai_cmd), str(a.sys_state.ai_cmd), "general state (op, memory, budget) survives the save")
	for x in [a, b, l]:
		_run(x, 600, [])
	check_eq(l.state_hash(), a.state_hash(), "loaded match continues hash-equal (600 ticks)")
	check_eq(b.state_hash(), a.state_hash(), "an unsaved twin stays hash-equal (600 ticks)")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")


# ================================================================ GEN61-2: full general (war effort, fires, logistics, chain, AI)
const War2 = preload("res://sim/ai/general_war2.gd")
const GNet = preload("res://sim/ai/general_net.gd")
const CommandNet = preload("res://sim/systems/command_net.gd")


## Events of type t for side fid in evs.
func _evs_of(evs: Array, t: String, fid: int = 0) -> Array:
	var out := []
	for ev in evs:
		if String(ev.type) == t and int(ev.get("fid", -99)) == fid:
			out.append(ev)
	return out


## (j) queues a replacement unit at a production building within the slot budget, and it joins the slot.
func test_queues_replacement_units_within_budget() -> void:
	var w := _world()
	var d := U.role_unit(w, 0, "infantry")
	var item := ""
	var bdef := ""
	var bids := Content.ids("buildings")
	bids.sort()
	var tbl: Dictionary = Content.table("production")
	var pk := tbl.keys()
	pk.sort()
	for k in pk:
		if tbl[k] is Dictionary and (tbl[k].get("spawns", []) as Array).has(d) and String(tbl[k].get("faction", "shared")) in ["shared", String(w.factions[0].faction_def)]:
			for b in bids:
				if (Content.building(String(b)).get("produces", []) as Array).has(String(k)):
					item = String(k)
					bdef = String(b)
					break
		if item != "":
			break
	if not check(bdef != "", "a building of side 0 produces an item that spawns %s (%s at %s)" % [d, item, bdef]):
		return
	w.spawn_building(bdef, 0, Vector2i(30, 4), true)
	var cost: Dictionary = Content.production(item).cost
	var lump := {}
	for k in War.RES:
		lump[k] = int(cost.get(k, 0))   # covers exactly one unit
	var ids := _squad(w, 0, 4, Vector2(44.5, 12.5))
	_auto(w, 0, {"units": ids}, "defensive", "cautious", {"lump": lump})
	_run(w, 2, [])
	_gen(w).roster[d] = 6   # the slot once held 6 of them: two lost
	var evs := []
	var neg := false
	for i in 2400:
		w.step()
		evs.append_array(w.events)
		for k in War.RES:
			if int(War.budget_left(w, _slot(w, 0)).get(k, 0)) < 0:
				neg = true
	var q := []
	for ev in _evs_of(evs, "AiGeneralSpend"):
		if String(ev.what) == "queue_unit":
			q.append(ev)
	check_eq(q.size(), 1, "exactly one replacement unit queued from a lump that covers one")
	check(not neg, "the slot budget never goes below zero")
	var joined := false
	for id in (_slot(w, 0).spec as Dictionary).get("units", []):
		if not ids.has(int(id)) and w.entities.has(int(id)) and String(w.entities[int(id)].def) == d:
			joined = true
	check(joined, "the produced %s joined the slot (spec.units %s)" % [d, str(_slot(w, 0).spec.get("units", []))])


## (k) strike sorties by the slot's aircraft on a believed enemy group, never danger-close.
func test_air_sortie_on_belief_never_danger_close() -> void:
	var w := _world()
	var ids := _squad(w, 0, 3, Vector2(30.5, 12.5))
	var jet := w.spawn_unit("a_strike_jet", 0, Vector2(32.5, 8.5))
	ids.append(jet)
	ids.append(w.spawn_unit("recon", 0, Vector2(50.5, 12.5)))
	_squad(w, 1, 3, Vector2(60.5, 12.5))
	_squad(w, 1, 1, Vector2(31.5, 14.5))   # danger close to our own infantry
	_run(w, 40, [])
	var evs := _auto(w, 0, {"units": ids}, "defensive", "cautious")
	_run(w, 600, evs)
	var air := 0
	var close := 0
	for ev in _evs_of(evs, "AiFireSupport"):
		if String(ev.get("kind", "")) != "air sortie":
			continue
		air += 1
		if int(ev.src) != jet:
			close += 100
	check(air >= 1, "the general sends the slot's strike jet on a sortie (%d)" % air)
	# danger close: every aim cell was clear of own units when called (checked by the general); re-check
	var cells := []
	for ev in _evs_of(evs, "AiFireSupport"):
		if String(ev.get("kind", "")) == "air sortie":
			cells.append(Vector2(ev.cell) + Vector2(0.5, 0.5))
	for p in cells:
		if (p as Vector2).distance_to(Vector2(31.5, 14.5)) < 3.0:
			close += 1
	check_eq(close, 0, "no sortie aimed at the enemy next to our own infantry")


## (l) a JTAC in the slot designates a believed enemy group; medevac goes on for evac-capable units.
func test_designates_and_sets_medevac() -> void:
	var w := _world()
	var ids := _squad(w, 0, 3, Vector2(36.5, 12.5))
	var jtac := w.spawn_unit("a_jtac", 0, Vector2(42.5, 12.5))
	var med := w.spawn_unit("a_ambulance", 0, Vector2(34.5, 10.5))
	ids.append_array([jtac, med])
	_squad(w, 1, 3, Vector2(53.5, 12.5))   # 13 tiles from the JTAC: in designator range, not danger close
	_run(w, 40, [])
	var evs := _auto(w, 0, {"units": ids}, "defensive", "cautious")
	_run(w, 300, evs)
	var des := 0
	for ev in _evs_of(evs, "AiFireSupport"):
		if String(ev.get("kind", "")) == "designation" and int(ev.src) == jtac:
			des += 1
	check(des >= 1, "the JTAC designates the believed enemy group (%d)" % des)
	var ev_st: Dictionary = w.sys_state.get("medical", {}).get("evac", {})
	check(ev_st.has(med) or ev_st.has(str(med)), "the ambulance is on auto medevac (Medical evac state %s)" % str(ev_st.keys()))
	check((_gen(w).get("evac", {}) as Dictionary).has(med), "the general recorded the medevac order")


## (m) an ammo bearer in the slot joins one of the slot's squads.
func test_bearer_joins_a_slot_squad() -> void:
	var w := _world()
	var ids := []
	for i in 4:
		var id := w.spawn_unit("rifleman", 0, Vector2(40.5 + float(i), 12.5))
		w.entities[id].squad = 9501
		ids.append(id)
	var b := w.spawn_unit("a_ammo_bearer", 0, Vector2(38.5, 13.5))
	ids.append(b)
	_auto(w, 0, {"units": ids}, "defensive", "cautious")
	_run(w, 300, [])
	var joined := int((_gen(w).get("bearer", {}) as Dictionary).get(b, -1))
	check(ids.has(joined) and joined != b, "the bearer was sent to join the squad of unit %d" % joined)
	var e = w.entities.get(b)
	check(e != null and int(e.get("squad", -1)) == 9501 or e != null and int(e.get("bearer_squad", e.get("squad", -1))) == 9501,
		"the bearer is now with squad 9501 (squad=%s)" % str(e.get("squad", "-") if e != null else "dead"))


## (n) the general's intent goes down the CommandNet (from_id 0) with radio delay; the general consumes its
## own delivered order (take_orders: no double execution by the net) and the company waits for it.
func test_intent_goes_down_command_net() -> void:
	var w := _world()
	_hq(w)
	var cid := Companies.spawn_company_at(w, 0, "a_rifle_co", "platoon", Vector2i(33, 8), Vector2(33.5, 8.5))  # in radio reach of the HQ
	if not check(cid >= 0, "a side-0 rifle company formed"):
		return
	var c: Dictionary = w.sys_state.companies.companies[cid]
	var cu: Array = Companies.units_of(w, c)
	_squad(w, 1, 2, Vector2(58.5, 12.5))
	_run(w, 40, [])
	var evs := _auto(w, 0, {"units": [int(c.captain)]}, "aggressive", "aggressive")
	(_slot(w, 0).spec as Dictionary).companies = [cid]
	# the slot now holds the company: re-plan at once, while it still sits in radio reach of the HQ
	General.finish(w, 0, _slot(w, 0), false, "test: company attached")
	_gen(w).pause_until = 0
	var first_order := -1
	var delivered := -1
	var by := ""
	for i in 1200:
		w.step()
		evs.append_array(w.events)
		for ev in w.events:
			if String(ev.type) == "AiGeneralOrder" and int(ev.fid) == 0 and delivered < 0:
				delivered = w.tick
				by = String(ev.by)
			if String(ev.type) == "AiDecision" and int(ev.get("fid", -1)) == 0 and first_order < 0:
				first_order = w.tick
		if delivered >= 0 and i > 300:
			break
	var issued := 0
	for ev in evs:
		if String(ev.type) == "OrderIssued" and int(ev.fid) == 0 and int(ev.from) == 0:
			issued += 1
	check(issued >= 1, "the general's op intent was issued down the CommandNet from the General (%d orders)" % issued)
	check(delivered >= 0 and by == "radio", "the company's captain received it by radio (tick %d, %s)" % [delivered, by])
	var net_exec := 0
	for ev in evs:
		if String(ev.type) == "OrderExecuted" and int(ev.fid) == 0 and String(ev.get("by", "")) == "net" and String(ev.node) == "c:%d" % cid:
			net_exec += 1
	check_eq(net_exec, 0, "the net never executed the general's order a second time (double-control rule)")
	var left := 0
	for rec in CommandNet.orders_for(w, int(c.captain)):
		if String(rec.get("source", "")) == "general":
			left += 1
	check_eq(left, 0, "the general consumed its delivered orders (take_orders)")
	var nets: Dictionary = _gen(w).get("net", {})
	check(nets.has(cid) and int(nets[cid].got) >= int(nets[cid].sent), "the slot records the delivery (net %s)" % str(nets))


## (o) an AI side may run the same General engine for its companies (guarded flag); off, nothing is created.
func test_enemy_ai_general_runs_its_companies() -> void:
	var w0 := make_world({}, true)
	_run(w0, 60, [])
	check(not (w0.sys_state.get("ai_cmd", {}) as Dictionary).has("egen"), "without the flag no AI general state exists")
	var w := make_world({}, true)
	w.factions[1].ai_general = true
	var tids := Companies.templates_for(1, w)
	if not check(not tids.is_empty(), "side 1 has company templates"):
		return
	var base := U.base_pos(w, 1)
	var cid := Companies.spawn_company_at(w, 1, String(tids[0]), "platoon", w.cell_of(base + Vector2(-6, 0)), base + Vector2(-6, 0))
	if not check(cid >= 0, "a side-1 company formed"):
		return
	var evs := []
	_run(w, 400, evs)
	var eg: Dictionary = w.sys_state.ai_cmd.get("egen", {})
	check(eg.has(1) and ((eg[1].spec as Dictionary).companies as Array).has(cid), "side 1's general holds its company (%s)" % str(eg.keys()))
	var badged := 0
	for id in Companies.units_of(w, w.sys_state.companies.companies[cid]):
		var e = w.entities.get(int(id))
		if e != null and String(e.get("ai_cmd", "")) == "general":
			badged += 1
	check(badged >= 1, "the company's units carry the general badge, so side 1's own doctrine skips them (%d)" % badged)
	check(not _evs_of(evs, "AiGeneralOp", 1).is_empty() or (eg.get(1, {}).get("gen", {}) as Dictionary).has("op"),
		"side 1's general plans operations (AiGeneralOp events %d)" % _evs_of(evs, "AiGeneralOp", 1).size())
	w.factions[1].ai_general = false
	_run(w, 40, [])
	check(not (w.sys_state.ai_cmd.egen as Dictionary).has(1), "turning it off releases the companies")
