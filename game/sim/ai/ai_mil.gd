extends RefCounted
## AI military support (owner: agent G): intel bookkeeping, unit production mix, rally points
## and scouting. The army state machine lives in ai_army.gd.
## Fairness: see the convention in ai_util.gd.

const U = preload("res://sim/ai/ai_util.gd")
const G3 = preload("res://sim/ai/ai_g3.gd")
const Stage = preload("res://sim/ai/ai_stage.gd")

## G3a: building roles whose saving blocks army spending (G2: generator, barracks, depot, motor pool).
const URGENT_ROLES := ["power", "barracks", "depot", "factory", "comms"]  # G3b: + comms (8->9 gate); the lab never delays the first waves
## Production categories (G2 "rifle"/"at" are the infantry/antitank roles; "vehicle" = light|heavy).
## G3b: Stage 9 roles precision / ew / anti_air (ai_stage.stage_shares).
const CATS := ["antitank", "infantry", "vehicle", "artillery", "air", "precision", "ew", "anti_air"]


## Updates known_contacts from legal sources only (visible_enemies + own memory).
static func update_intel(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var vis := w.visible_enemies(fid)
	var by_def := {}
	var vehicles := 0
	var air_n := 0
	var near_base := 0
	var base := U.base_pos(w, fid)
	for e in vis:
		if e.kind != "unit":
			continue
		var d := String(e.def)
		by_def[d] = int(by_def.get(d, 0)) + 1
		var u := U.ud(d)  # G3b think cost: one cached per-def lookup per contact
		if bool(u.armored):
			vehicles += 1
		elif bool(u.air):
			air_n += 1
		if Vector2(e.pos).distance_to(base) <= 14.0:
			near_base += 1
	st.enemy_vehicles_seen = maxi(int(st.enemy_vehicles_seen), vehicles)
	st.vis_n = vis.size()  # G3b: think-cost load (ai_controller.think_mult)
	if st.has("g4"):
		st.g4.enemy_air_seen = maxi(int(st.g4.get("enemy_air_seen", 0)), air_n)
	var mem: Dictionary = w.memory[fid]
	var hq_known := false
	var tgt := int(st.g3.target_side)
	for eid in mem:
		var md := String(mem[eid].def)
		if U.is_hq_def(md):
			if tgt < 0 or int(mem[eid].get("owner", -1)) == tgt:
				hq_known = true
		elif String(Content.building(md).get("weapon", "")) != "":
			st.tower_seen = true  # adapt: heavy armour cracks towers (HMG barely scratches an MBT)
	st.known_contacts = {"visible_units": by_def, "visible_total": vis.size(), "near_base": near_base,
		"remembered_buildings": mem.size(), "enemy_hq_known": hq_known,
		"max_vehicles_seen": int(st.enemy_vehicles_seen)}
	ctx.visible = vis


## G3a: the target side's last known HQ, else another of its remembered buildings, else its start.
static func attack_target(w: SimWorld, fid: int) -> Vector2:
	return G3.hq_target(w, fid, w.ai_state[fid])


static func patrol_points(w: SimWorld, fid: int) -> Array:
	if Stage.multi_crossing(w):
		return Stage.patrol_points(w, fid)  # G3b maps: bridges list + ford clusters
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




## Desired army shares by production category, per faction. With a factory the mix leans on
## armour: salvage is the finite resource and heavy armour is the most salvage-efficient way to
## crack defences and the HQ, while ore (vehicles) is plentiful. AT/heavy share rises once armour is
## seen. Human A keeps the G2 numbers. Human B adds artillery behind a carrier/tank line; the
## Machine adds drone pairs (raids) before and after its crawler works.
static func _shares(w: SimWorld, fid: int, st: Dictionary, has_factory: bool) -> Dictionary:
	var armored_seen := int(st.enemy_vehicles_seen) >= 1  # G2: prefer AT/MBT once any enemy vehicle is seen
	var heavy := armored_seen or bool(st.get("tower_seen", false))
	match U.fac(w, fid):
		"human_b":
			if not has_factory:
				return {"infantry": 0.4, "antitank": 0.6} if heavy else {"infantry": 0.6, "antitank": 0.4}
			if armored_seen:
				return {"infantry": 0.15, "antitank": 0.2, "vehicle": 0.5, "artillery": 0.15}
			return {"infantry": 0.2, "antitank": 0.15, "vehicle": 0.45, "artillery": 0.2}
		"machine":
			if not has_factory:
				return {"infantry": 0.45, "air": 0.55}
			if armored_seen:
				return {"infantry": 0.1, "air": 0.2, "vehicle": 0.6, "artillery": 0.1}
			return {"infantry": 0.15, "air": 0.25, "vehicle": 0.45, "artillery": 0.15}
	if not has_factory:
		return {"infantry": 0.45, "antitank": 0.55} if heavy else {"infantry": 0.6, "antitank": 0.4}
	if armored_seen:
		return {"infantry": 0.15, "antitank": 0.35, "vehicle": 0.5}
	return {"infantry": 0.25, "antitank": 0.2, "vehicle": 0.55}


## Unit def -> category for this side (vehicle roles first: the Machine walker is both antitank
## and heavy, and comes from the factory).
static func _cat_map(w: SimWorld, fid: int) -> Dictionary:
	var out := {}
	for r in ["light", "heavy"]:
		var item := U.role(w, fid, r)
		if item != "":
			for u in Content.production(item).get("spawns", []):
				out[String(u)] = "vehicle"
	for r in ["infantry", "antitank", "artillery", "air", "precision", "ew", "anti_air"]:
		var item := U.role(w, fid, r)
		if item != "":
			for u in Content.production(item).get("spawns", []):
				if not out.has(String(u)):
					out[String(u)] = r
	return out


## Production item for a category ("" when the faction has none).
static func _item_for(w: SimWorld, fid: int, st: Dictionary, cat: String) -> String:
	if cat != "vehicle":
		return U.role(w, fid, cat)
	var hv := U.role(w, fid, "heavy")
	var lt := U.role(w, fid, "light")
	if hv == "" or lt == "":
		return hv if hv != "" else lt
	# heavy by default (defences/HQ); the light vehicle only when ore is short for a heavy one
	var hv_ore := int(Content.production(hv).cost.get("ore", 0))
	var ore := int(w.factions[fid].stock.ore)
	return hv if ore >= hv_ore or int(st.enemy_vehicles_seen) >= 1 else lt


static func _pop_of_item(item: String) -> int:
	var p := 0
	for u in Content.production(item).get("spawns", []):
		p += U.pop_of(String(u))
	return p


static func manage_production(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var f: Dictionary = w.factions[fid]
	var barracks_def := U.role(w, fid, "barracks")
	var factory_def := U.role(w, fid, "factory")
	var free := {}  # producing building def -> least-loaded built building with queue room
	for b in ctx.buildings:
		var bd := String(b.def)
		if not b.built or not Content.building(bd).has("produces") or U.is_hq_def(bd):
			continue
		if not st.rallied.has(int(b.id)):
			if U.submit(w, fid, st, {"type": "set_rally", "building_id": int(b.id), "target": Vector2(st.rally)}, "rally:%d" % int(b.id)):
				st.rallied[int(b.id)] = true
		var room := 2 if bd == barracks_def else 1
		if b.queue.size() < room and (not free.has(bd) or b.queue.size() < free[bd].queue.size()):
			free[bd] = b
	if free.is_empty():
		return
	# scout replacement (cheap, at most twice)
	var rec := U.role(w, fid, "recon")
	if rec != "" and U.own(w, fid, int(st.scout_id)) == null and int(st.recon_requeues) < 2 and w.tick > 2400:
		var rf = free.get(String(Content.production(rec).facility))
		if rf != null and w.can_afford(fid, Content.production(rec).cost) == "":
			if U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(rf.id), "item": rec}, "queue:recon"):
				st.recon_requeues = int(st.recon_requeues) + 1
				st.want_scout = true
			return
	# current + queued army pop per category
	var cmap := _cat_map(w, fid)
	var have := {}
	for c in CATS:
		have[c] = 0
	for e in ctx.army + ctx.arty + ctx.air + ctx.get("ew", []):
		var cat := String(cmap.get(String(e.def), ""))
		if cat != "":
			have[cat] += U.pop_of(String(e.def))
	var queued_any := false
	for b in ctx.buildings:
		for q in b.queue:
			for u in Content.production(String(q.item)).get("spawns", []):
				var cat := String(cmap.get(String(u), ""))
				if cat != "":
					queued_any = true
					have[cat] += U.pop_of(String(u))
	var total := 0.0
	for c in CATS:
		total += float(have[c])
	var has_fac := int(ctx.built.get(factory_def, 0)) > 0
	var shares := Stage.stage_shares(w, fid, st, _shares(w, fid, st, has_fac), has_fac)
	var order := []
	for cat in CATS:
		if float(shares.get(cat, 0.0)) <= 0.0:
			continue
		var item := _item_for(w, fid, st, cat)
		if item == "" or not free.has(String(Content.production(item).facility)):
			continue
		order.append([-(float(shares[cat]) * (total + 4.0) - float(have[cat])), cat, item])
	if order.is_empty():
		return
	order.sort()
	var reserve := 0
	for r in URGENT_ROLES:
		if String(st.saving_for) != "" and String(st.saving_for) == U.role(w, fid, r):
			reserve = int(Content.building(String(st.saving_for)).cost.credits)
	var defending := String(st.objective) == "defend"
	# G3b: research / advancement savings (ai_stage sets them only while a defensive core stands)
	var hold: Dictionary = {} if defending else Stage.reserve(st)
	for i in order.size():
		var item := String(order[i][2])
		var p := Content.production(item)
		var fac = free[String(p.facility)]
		if int(f.pop) + int(ctx.queued_pop) + _pop_of_item(item) > int(f.pop_cap):
			return  # supply capped: the depot rule in ai_econ handles it
		var affordable := w.can_afford(fid, p.cost) == "" and int(f.credits) - int(p.cost.credits) >= reserve + int(hold.get("credits", 0)) 			and int(f.stock.salvage) - int(p.cost.get("salvage", 0)) >= int(hold.get("salvage", 0)) 			and int(f.stock.ore) - int(p.cost.get("ore", 0)) >= int(hold.get("ore", 0))
		if affordable:
			U.submit(w, fid, st, {"type": "queue_unit", "building_id": int(fac.id), "item": item}, "queue:%d" % int(fac.id))
			return
		# save for the top choice unless we are defending (then buy whatever is affordable).
		# G3a: never save for an item blocked on ORE (ore only arrives from crews; infantry needs
		# none) - Human B banked 2400 credits for 15k ticks waiting on a tank with ore=8 (ffa seed 2).
		var ore_short := int(p.cost.get("ore", 0)) > int(f.stock.ore)
		if not defending and not ore_short and (queued_any or i == 0):
			return
