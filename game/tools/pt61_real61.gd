extends RefCounted
## G6.1 REAL61 playtest flow (--ui-playtest-real61): MG fire pins a squad in the open (shot), a veteran's
## inspector lines (shot). Suppression is fed through Morale.add_supp with the hmg weapon factor (exactly what
## Damage.suppress does once ORCH CR realism_damage is in), so the pin does not depend on hit rolls.

const Morale = preload("res://sim/systems/morale.gd")
const Veterancy = preload("res://sim/systems/veterancy.gd")
const Info = preload("res://presentation/ui6/realism_info.gd")


func _free_spot(pt, base: Vector2) -> Vector2:
	var w: SimWorld = pt._w()
	for r in range(3, 12):
		for d in [Vector2(r, 0), Vector2(0, r), Vector2(-r, 0), Vector2(0, -r), Vector2(r, r)]:
			var p: Vector2 = base + d
			var c := Vector2i(floori(p.x), floori(p.y))
			if w.in_bounds(c) and w.terrain_at(c) == Terrain.GRASS:
				return Vector2(c) + Vector2(0.5, 0.5)
	return base + Vector2(4.5, 0.5)


func run(pt) -> void:
	var hq: Dictionary = pt._hq()
	pt._log("real_hq", not hq.is_empty())
	if hq.is_empty():
		return
	pt._mv().join_sim()
	var w: SimWorld = pt._w()
	var p := _free_spot(pt, Vector2(hq.pos))
	var sq: Array = []
	for i in 3:
		sq.append(w.spawn_unit("rifleman", 0, p + Vector2(i * 0.8, 0)))
	pt._log("real_squad_spawned", sq.size() == 3, str(sq))
	var hmg := Morale.weapon_supp({"weapon": "hmg", "cls": "small_arms", "cooldown": 0.4})
	pt._log("real_mg_factor", hmg > 1.0, "hmg suppression factor %s" % hmg)
	var per_hit := float((Content.rules().get("suppression", {}) as Dictionary).get("per_hit", 18))
	for k in 12:
		pt._mv().join_sim()
		for id in sq:
			var e = pt._w().entities.get(id)
			if e != null:
				Morale.add_supp(pt._w(), e, per_hit, hmg)
		await pt._wait(0.1)
	pt._mv().join_sim()
	var pinned := 0
	for id in sq:
		var e = pt._w().entities.get(id)
		if e != null and Morale.is_pinned(pt._w(), e):
			pinned += 1
	pt._log("real_squad_pinned", pinned == sq.size(), "pinned %d / %d" % [pinned, sq.size()])
	pt._log("real_select_pinned", await pt._g5_select(int(sq[0])))
	var e0 = pt._w().entities.get(int(sq[0]))
	var l0: Array = Info.lines(pt._w(), e0) if e0 != null else []
	pt._log("real_pinned_lines", l0.size() > 0 and String(l0[0]).begins_with("Suppression: Pinned"), str(l0))
	await pt._shot("real61_mg_pinned")
	# a veteran's inspector lines
	pt._mv().join_sim()
	w = pt._w()
	var vid: int = w.spawn_unit("rifleman", 0, p + Vector2(0, 2))
	Veterancy.add_xp(w, w.entities[vid], 200.0)
	pt._log("real_veteran_rank", Veterancy.rank(w, vid) == 2, "rank %s" % Veterancy.rank_name(Veterancy.rank(w, vid)))
	pt._log("real_select_veteran", await pt._g5_select(vid))
	var ev = pt._w().entities.get(vid)
	var lv: Array = Info.lines(pt._w(), ev) if ev != null else []
	var has_rank := false
	var has_trait := false
	for s in lv:
		has_rank = has_rank or String(s).begins_with("Rank: Veteran")
		has_trait = has_trait or String(s).begins_with("Traits:")
	pt._log("real_veteran_lines", has_rank and has_trait, str(lv))
	await pt._shot("real61_veteran_inspector")
