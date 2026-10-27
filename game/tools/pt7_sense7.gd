extends RefCounted
## G7 playtest flow sense7 (SENSE7): view cones shown for selected soldiers, a flank surprise (an enemy at a
## soldier's back stays unseen until he fires), heard gunfire from the fog (an uncertainty ring + bearing, and the
## squad's suppression point moves onto it), and a squad cut off the radio acting on stale intel while a connected
## squad gets the new report. Real sim state; screenshots of each scene.
## Honest note: the heard-gunfire scene marks the fog shooter's shot by setting last_fired_tick (what Combat._fire
## sets) because a real shot needs a target the listener's side would then see; everything after it is the sim.

const H = preload("res://tests/test_machine_g6.gd")
const Senses7 = preload("res://sim/systems/senses7.gd")
const SenseLayer = preload("res://presentation/view/sense_layer.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Intel = preload("res://sim/systems/intel.gd")


func _layer(mv) -> Node:
	var l = mv.get_node_or_null("SenseLayer")
	if l == null:
		l = SenseLayer.new()
		mv.add_child(l)
		l.setup(mv)
	l.visible = true
	return l


## Hold position (SquadAI never moves it; Combat fires within range only), so facings stay as set.
func _hold(u: Dictionary) -> void:
	u.stance = "hold_position"
	u.order = {"type": "hold"}
	u.moving = false


func _select(mv, ids: Array) -> void:
	mv.selection.clear()
	for id in ids:
		mv.selection.append(int(id))


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	var h = H.new()
	var on := Senses7.enabled(w)
	pt._log("sense7_enabled", on, "rules g7_senses enabled = %s" % str(on))
	var c: Vector2i = h._open(w, 12)
	var cf := Vector2(c) + Vector2(0.5, 0.5)
	var layer := _layer(mv)
	# 1. view cones: three soldiers facing different ways, one with a scope
	var a: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(-3.0, 0.0))
	var b: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(0.0, 2.0))
	var s: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(2.0, -2.0))
	a.facing = 0.0
	b.facing = PI * 0.5
	s.facing = -PI * 0.25
	s.optics = true
	for u in [a, b, s]:
		_hold(u)
	_select(mv, [a.id, b.id, s.id])
	mv.center_camera_on(cf)
	await pt._wait(1.0)
	pt._log("sense7_cones_shown", layer.is_inside_tree() and layer.visible and w.sys_state.has("senses7"),
		"layer in tree %s, selection %d, senses state %s" % [str(layer.is_inside_tree()), mv.selection.size(), str(w.sys_state.has("senses7"))])
	await pt._shot("sense7_cones")
	# 2. flank surprise: an enemy creeps up 5 tiles behind soldier a (facing east) and stays unseen
	a.facing = 0.0   # east; the flanker comes in from the west, 3.5 tiles behind
	var fl: Dictionary = h._unit(w, "b_militia", 1, Vector2(a.pos) + Vector2(-3.5, 0.0))
	fl.facing = PI   # looking away too, so he does not open fire yet
	_hold(fl)
	_select(mv, [a.id])
	mv.center_camera_on(Vector2(a.pos))
	await pt._wait(1.5)
	var vis_cell: bool = Fog.is_visible(w, 0, fl.pos)
	var hidden_before := Senses7.hidden(w, 0, fl) and not Fog.entity_visible(w, 0, fl)
	var spot := []
	for u in w.entities.values():
		if int(u.get("owner", -1)) == 0 and (u.kind == "unit" or u.kind == "building") and Senses7._opos(u).distance_to(fl.pos) < 14.0 and Senses7.can_see(w, u, fl):
			spot.append("%s#%d d=%.1f" % [String(u.def), int(u.id), Senses7._opos(u).distance_to(fl.pos)])
	print("PLAYTEST-DBG sense7 flank a: facing %.2f moving %s order %s path %s pos %s fl %s tick %d" % [float(a.get("facing", 0.0)), str(a.get("moving", false)), str(a.get("order", {})), str(a.get("path", [])).left(60), str(a.pos), str(fl.pos), w.tick])
	print("PLAYTEST-DBG sense7 flank: tier %s moving %s order %s fired %d spotters %s hidset %s" % [str(fl.get("tier", -1)), str(fl.get("moving", false)), str(fl.get("order", {}).get("type", "")), int(fl.get("last_fired_tick", -1)), str(spot), str(Senses7.hidden(w, 0, fl))])
	var f0 := float(a.facing)
	a.facing = PI
	var would := Senses7.can_see(w, a, fl)   # control: had he looked back he would have seen him
	a.facing = f0
	pt._log("sense7_flank_unseen", vis_cell and hidden_before and would and absf(f0) < 0.3,
		"enemy 3.5 tiles behind on a visible cell: hidden %s; facing %.2f; looking back would spot him %s" % [str(hidden_before), f0, str(would)])
	print("PLAYTEST-DBG sense7 flank a at shot: facing %.2f tick %d hidden %s" % [float(a.get("facing", 0.0)), w.tick, str(Senses7.hidden(w, 0, fl))])
	await pt._shot("sense7_flank_unseen")
	fl.facing = 0.0   # he turns to the soldier's back and fires
	await pt._wait(2.5)
	var fired := w.tick - int(fl.get("last_fired_tick", -9999)) < 120
	print("PLAYTEST-DBG sense7 flank2: a hidden from side1 %s, fl facing %.2f, order %s, a alive %s" % [str(Senses7.hidden(w, 1, a)), float(fl.get("facing", 0.0)), str(fl.get("order", {})), str(w.entities.has(int(a.id)))])
	pt._log("sense7_flank_surprise", fired and Fog.entity_visible(w, 0, fl), "enemy fired %s, now seen %s" % [str(fired), str(Fog.entity_visible(w, 0, fl))])
	await pt._shot("sense7_flank_fire")
	# 3. heard gunfire from the fog
	var lis: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(0.0, 8.0))
	lis.squad = 9101
	var fog_p := Vector2(lis.pos) + Vector2(22.0, 0.0)
	var sh: Dictionary = h._unit(w, "b_militia", 1, fog_p)
	var heard := []
	for i in 6:
		sh.last_fired_tick = w.tick
		await pt._wait(0.35)
		heard = Senses7.heard(w, 0)
		if not heard.is_empty():
			break
	var hd: Dictionary = {}
	for x in heard:
		if String(x.kind) == "gunfire" and Vector2(x.pos).distance_to(fog_p) <= float(x.err) + 0.5:
			hd = x
	var hcid := 0   # the heard contact in the squad's picture (on the net: its side's Intel, src "heard")
	for x in Senses7.knowledge(w, lis):
		if String(x.src) == "heard" and not hd.is_empty() and Vector2(x.pos).distance_to(Vector2(hd.pos)) < 0.5:
			hcid = int(x.id)
	var sp = Senses7.suppress_point(w, lis, hcid) if hcid != 0 else null
	pt._log("sense7_heard_gunfire", not hd.is_empty() and not Fog.entity_visible(w, 0, sh),
		"heard %s (shooter in fog, not revealed)" % str(hd))
	pt._log("sense7_heard_reaction", sp != null and not hd.is_empty() and Vector2(sp).distance_to(Vector2(hd.pos)) < 0.5,
		"heard contact id %d in the squad picture; suppression point %s = the guessed position" % [hcid, str(sp)])
	_select(mv, [lis.id])
	mv.center_camera_on(Vector2(lis.pos) + Vector2(11.0, 0.0))
	await pt._wait(0.5)
	await pt._shot("sense7_heard")
	# 4. a squad cut off the radio acts on stale intel
	var q1: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(-6.0, -6.0))
	var q2: Dictionary = h._unit(w, "rifleman", 0, cf + Vector2(6.0, -6.0))
	q1.squad = 9201
	q2.squad = 9202
	Senses7.force_cut(w, 0, 9202)
	await pt._wait(2.5)
	var rp := Vector2(q1.pos) + Vector2(0.0, -14.0)
	Intel.note_contact(w, 0, rp, "b_militia", 0.0, "report")
	await pt._wait(0.3)
	var k1 := false
	for x in Senses7.knowledge(w, q1):
		if Vector2(x.pos).distance_to(rp) < 0.1:
			k1 = true
	var k2 := false
	for x in Senses7.knowledge(w, q2):
		if Vector2(x.pos).distance_to(rp) < 0.1:
			k2 = true
	pt._log("sense7_cutoff_stale", Senses7.cut_off(w, q2) and k1 and not k2,
		"cut off %s; report reached connected squad %s, cut-off squad %s" % [str(Senses7.cut_off(w, q2)), str(k1), str(k2)])
	_select(mv, [q1.id, q2.id])
	mv.center_camera_on(cf + Vector2(0.0, -6.0))
	await pt._wait(0.5)
	await pt._shot("sense7_cutoff")
	Senses7.force_cut(w, 0, 9202, false)
