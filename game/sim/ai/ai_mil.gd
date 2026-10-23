extends RefCounted
## AI military support (owner: agent G): intel bookkeeping, unit production mix, rally points
## and scouting. The army state machine lives in ai_army.gd.
## Fairness: see the convention in ai_util.gd.

const U = preload("res://sim/ai/ai_util.gd")

const URGENT_BUILDS := ["generator", "barracks", "depot", "motor_pool"]


## Updates known_contacts from legal sources only (visible_enemies + own memory).
static func update_intel(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var vis := w.visible_enemies(fid)
	var by_def := {}
	var vehicles := 0
	var near_base := 0
	var base := U.base_pos(w, fid)
	for e in vis:
		if e.kind != "unit":
			continue
		by_def[String(e.def)] = int(by_def.get(String(e.def), 0)) + 1
		if U.is_vehicle(String(e.def)):
			vehicles += 1
		if Vector2(e.pos).distance_to(base) <= 14.0:
			near_base += 1
	st.enemy_vehicles_seen = maxi(int(st.enemy_vehicles_seen), vehicles)
	var mem: Dictionary = w.memory[fid]
	var hq_known := false
	for eid in mem:
		if String(mem[eid].def) == "hq":
			hq_known = true
		elif String(mem[eid].def) == "guard_tower":
			st.tower_seen = true  # adapt: heavy armour cracks towers (HMG barely scratches an MBT)
	st.known_contacts = {"visible_units": by_def, "visible_total": vis.size(), "near_base": near_base,
		"remembered_buildings": mem.size(), "enemy_hq_known": hq_known,
		"max_vehicles_seen": int(st.enemy_vehicles_seen)}
	ctx.visible = vis


## Last known enemy HQ position (memory), else another remembered building, else the public spawn.
static func attack_target(w: SimWorld, fid: int) -> Vector2:
	var mem: Dictionary = w.memory[fid]
	var other = null
	for eid in mem:
		var m: Dictionary = mem[eid]
		if String(m.def) == "hq":
			return Vector2(m.pos)
		if other == null:
			other = Vector2(m.pos)
	if other != null:
		return other
	return U.enemy_spawn(w, fid)


static func patrol_points(w: SimWorld, fid: int) -> Array:
	var a := Vector2.ZERO
	var na := 0
	var b := Vector2.ZERO
	var nb := 0
	for c in w.map.ford_cells:
		var cc: Vector2i = c
		if cc.x - cc.y < 0:
			a += Vector2(cc) + Vector2(0.5, 0.5)
			na += 1
		else:
			b += Vector2(cc) + Vector2(0.5, 0.5)
			nb += 1
	var br := Vector2.ZERO
	for c in w.map.bridge_cells:
		br += Vector2(Vector2i(c)) + Vector2(0.5, 0.5)
	var pts := []
	if na > 0:
		pts.append(a / na)
	if not w.map.bridge_cells.is_empty():
		pts.append(br / w.map.bridge_cells.size())
	if nb > 0:
		pts.append(b / nb)
	if not w.map.bridge_cells.is_empty():
		pts.append(br / w.map.bridge_cells.size())
	return pts


static func manage_scout(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var s = U.own(w, fid, int(st.scout_id))
	if s == null:
		return
	var key := "scout"
	if String(st.scout_phase) == "enemy_base":
		var tgt := U.enemy_spawn(w, fid)
		if bool(st.known_contacts.get("enemy_hq_known", false)) or Vector2(s.pos).distance_to(tgt) < 7.0:
			st.scout_phase = "patrol"
			st.scout_wp = 0
			U.log_line(st, w, "scout reached the enemy start; patrolling crossings")
		elif String(s.order.type) != "move":
			U.submit(w, fid, st, {"type": "move", "unit_ids": [int(s.id)], "target": tgt}, key)
		return
	var pts: Array = st.patrol
	if pts.is_empty():
		return
	var wp: Vector2 = pts[int(st.scout_wp) % pts.size()]
	if Vector2(s.pos).distance_to(wp) < 3.0 or (String(s.order.type) == "idle" and not s.moving):
		st.scout_wp = (int(st.scout_wp) + 1) % pts.size()
		wp = pts[int(st.scout_wp)]
		U.submit(w, fid, st, {"type": "move", "unit_ids": [int(s.id)], "target": wp}, key)


## Desired army shares by unit category. With a motor pool the mix leans on armour: salvage is the
## finite resource and an MBT is the most salvage-efficient way to crack towers and the HQ, while
## ore (vehicles) is plentiful. AT share rises when enemy vehicles are seen.
static func _shares(st: Dictionary, has_mp: bool) -> Dictionary:
	var vehicles_seen := int(st.enemy_vehicles_seen) >= 1  # G2: prefer AT/MBT once any enemy vehicle is seen
	var heavy := vehicles_seen or bool(st.get("tower_seen", false))
	if not has_mp:
		return {"rifle": 0.45, "at": 0.55, "vehicle": 0.0} if heavy else {"rifle": 0.6, "at": 0.4, "vehicle": 0.0}
	if vehicles_seen:
		return {"rifle": 0.15, "at": 0.35, "vehicle": 0.5}
	return {"rifle": 0.25, "at": 0.2, "vehicle": 0.55}


static func _category(def_id: String) -> String:
	match def_id:
		"rifleman", "rifle_squad":
			return "rifle"
		"at_gunner", "at_team":
			return "at"
		"ifv", "mbt":
			return "vehicle"
	return ""


static func manage_production(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var f: Dictionary = w.factions[fid]
	var barracks = null
	var motor = null
	for b in ctx.buildings:
		if not b.built or not Content.building(b.def).has("produces") or b.def == "hq":
			continue
		if not st.rallied.has(int(b.id)):
			if U.submit(w, fid, st, {"type": "set_rally", "building_id": int(b.id), "target": Vector2(st.rally)}, "rally:%d" % int(b.id)):
				st.rallied[int(b.id)] = true
		if b.def == "barracks" and b.queue.size() < 2 and (barracks == null or b.queue.size() < barracks.queue.size()):
			barracks = b
		elif b.def == "motor_pool" and b.queue.size() < 1:
			motor = b
	if barracks == null and motor == null:
		return
	# scout replacement (cheap, at most twice)
	if barracks != null and U.own(w, fid, int(st.scout_id)) == null and int(st.recon_requeues) < 2 and w.tick > 2400:
		if w.can_afford(fid, Content.production("recon").cost) == "":
			if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(barracks.id), "item": "recon"}, "queue:recon"):
				st.recon_requeues = int(st.recon_requeues) + 1
				st.want_scout = true
			return
	# current + queued army pop per category
	var have := {"rifle": 0, "at": 0, "vehicle": 0}
	for e in ctx.army:
		var cat := _category(String(e.def))
		if cat != "":
			have[cat] += U.pop_of(String(e.def))
	var queued_any := false
	for b in ctx.buildings:
		for q in b.queue:
			var cat := _category(String(q.item))
			if cat != "":
				queued_any = true
				for u in Content.production(String(q.item)).spawns:
					have[cat] += U.pop_of(String(u))
	var total := float(have.rifle + have.at + have.vehicle)
	var shares := _shares(st, motor != null or int(ctx.built.get("motor_pool", 0)) > 0)
	var order := []
	for cat in ["at", "rifle", "vehicle"]:
		if float(shares[cat]) <= 0.0:
			continue
		if cat == "vehicle" and motor == null:
			continue
		if cat != "vehicle" and barracks == null:
			continue
		order.append([-(float(shares[cat]) * (total + 4.0) - float(have[cat])), cat])
	if order.is_empty():
		return
	order.sort()
	var reserve := 0
	if String(st.saving_for) in URGENT_BUILDS:
		reserve = int(Content.building(String(st.saving_for)).cost.credits)
	var defending := String(st.objective) == "defend"
	for i in order.size():
		var cat := String(order[i][1])
		var item := "rifle_squad"
		var fac = barracks
		if cat == "at":
			item = "at_team"
		elif cat == "vehicle":
			fac = motor
			# MBT by default (towers/HQ); an IFV only when ore is short for a tank
			var mbt_ore := int(Content.production("mbt").cost.get("ore", 0))
			item = "mbt" if int(f.stock.ore) >= mbt_ore or int(st.enemy_vehicles_seen) >= 1 else "ifv"
		var p := Content.production(item)
		var item_pop := 0
		for u in p.spawns:
			item_pop += U.pop_of(String(u))
		if int(f.pop) + int(ctx.queued_pop) + item_pop > int(f.pop_cap):
			return  # supply capped: the depot rule in ai_econ handles it
		var affordable := w.can_afford(fid, p.cost) == "" and int(f.credits) - int(p.cost.credits) >= reserve
		if affordable:
			U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, "queue:%d" % int(fac.id))
			return
		# save for the top choice unless we are defending (then buy whatever is affordable)
		if not defending and (queued_any or i == 0):
			return
