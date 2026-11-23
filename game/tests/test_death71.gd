extends "res://tests/test_base.gd"
## G7.1 I7 machine deaths: cell blast chains, nanite bleed seeds creep, last-gasp near troops.

const Death71 = preload("res://sim/systems/death71.gd")
const Creep = preload("res://sim/systems/creep.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_machine_death_blast_bleed_gasp() -> void:
	var c := LastProtocol.make_config(84, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 8:
		w.step()
	var mach_fid := -1
	var human_fid := -1
	for fid in w.factions:
		var fd := String(w.factions[fid].get("faction_def", ""))
		if fd == "machine":
			mach_fid = int(fid)
		elif human_fid < 0:
			human_fid = int(fid)
	if not check(mach_fid >= 0 and human_fid >= 0, "factions"):
		return
	var seeds0 := (Creep.seeds(w) as Array).size()
	var adef := _machine_def()
	var hdef := _human_def()
	if not check(adef != "" and hdef != "", "defs"):
		return
	var aid := w.spawn_unit(adef, mach_fid, Vector2(40, 40))
	var bid := w.spawn_unit(adef, mach_fid, Vector2(40.8, 40.2))
	var hid := w.spawn_unit(hdef, human_fid, Vector2(41.2, 40.1))
	if not check(aid >= 0 and bid >= 0, "spawn machines"):
		return
	var b = w.entities[bid]
	var bhp0 := float(b.hp)
	var hhp0 := float(w.entities[hid].hp) if w.entities.has(hid) else 0.0
	w.destroy(aid, "test_kill")
	w.step()
	var board := Death71.board(w)
	var blasted := int(board.get("blasts", 0)) >= 1
	var b_hurt := not w.entities.has(bid) or float(w.entities[bid].hp) < bhp0
	check(blasted or b_hurt, "blast hit neighbor or killed it")
	check((Creep.seeds(w) as Array).size() > seeds0 or int(board.get("seeds", 0)) >= 1, "nanite bleed seeded")
	if w.entities.has(hid):
		check(int(board.get("gasps", 0)) >= 1 or float(w.entities[hid].hp) < hhp0, "gasp damaged troop")


func _machine_def() -> String:
	for d in ["g71_m_reclaimer", "g71_m_hive_conductor", "m_swarm", "swarm_crawler", "machine_drone"]:
		if not Content.unit(d).is_empty():
			return d
	return ""


func _human_def() -> String:
	for d in ["rifleman", "a_rifleman", "infantry", "squad_rifle"]:
		if not Content.unit(d).is_empty():
			return d
	return ""
