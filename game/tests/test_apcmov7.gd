extends "res://tests/test_base.gd"
## G7 acceptance (owner: APCMOV7). Owner note 13.9c-16: smooth, realistic APC driving inside the counter-nanite facility.
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")
const Movement = preload("res://sim/systems/movement.gd")
const NOFIRE := 100000


func _ensure_g7() -> void:
	if Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")


func _native() -> bool:
	for s in SimWorld.SYSTEM_ORDER:
		if s == FacDrive7:
			return true
	return false


## One world tick; drives the controller by hand (right after the whole step) until ORCH has it in SYSTEM_ORDER.
func _step(w: SimWorld) -> void:
	w.step()
	if not _native():
		FacDrive7.tick(w)


func _setup() -> Array:
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
	w.factions[0].credits = 400000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[0].stock[k] = 400000
	return [w, o]


func _facility(w: SimWorld, o: Vector2i) -> int:
	var off: Array = CnFacility.conf().core_offset
	var id := w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	for i in CnFacility.DISCOVER_EVERY + 1:
		_step(w)
	return id


func _cmd(w: SimWorld, cmd: Dictionary) -> String:
	cmd.issuer = 0
	if SimWorld.COMMANDS.has(String(cmd.type)):
		return rejected_reason(do_cmd(w, 0, cmd))
	var sys = FacDrive7 if String(cmd.type) == "fd7_go" else CnFacility
	var why: String = sys.validate_command(w, cmd)
	if why == "":
		sys.apply_command(w, cmd)
	_step(w)
	return why


func _train(w: SimWorld, fid: int, kind: String) -> int:
	_cmd(w, {"type": "cn_train", "building_id": fid, "kind": kind})
	var F := CnFacility.fac(w, fid)
	if not check(not (F.queue as Array).is_empty(), "cn_train queued %s" % kind):
		return 0
	F.queue[0].left = 1.0
	for i in 3:
		_step(w)
		for ev in w.events:
			if ev.has("team") and (String(ev.type) == "CnTeamReady"):
				return int(ev.team)
	return 0


func _quiet(w: SimWorld, ids: Array) -> void:
	for id in ids:
		var e = w.entities.get(int(id))
		if e != null:
			e.cd_ticks = NOFIRE
			for u in e.get("cargo", []):
				u.cd_ticks = NOFIRE


# ---------------------------------------------------------------- geometry: every route of the layout
func test_every_route_clears_buildings_with_a_turning_radius() -> void:
	_ensure_g7()
	var c := CnFacility.conf()
	var G := FacDrive7.graph()
	var ng := (c.garages as Array).size()
	var nb := (G.bay as Array).size()
	check_eq(nb, 2, "two staging bays")
	var pairs := []
	for i in ng:
		pairs.append(["g%d" % i, "x", i])
		for j in nb:
			pairs.append(["g%d" % i, "b%d" % j, i])
		pairs.append(["w0", "g%d" % i, i])
		pairs.append(["e", "w0", i])
	for j in nb:
		pairs.append(["b%d" % j, "x", -1])
	var bad := []
	var worst_r := 99.0
	var worst_dh := 0.0
	for pr in pairs:
		var legs := FacDrive7.plan(String(pr[0]), String(pr[1]), int(pr[2]),
			PackedVector2Array([Vector2(G.pos[int(G.entry)]) + Vector2(0, 1.6), Vector2(G.pos[int(G.entry)]) + Vector2(0, 0.4)]) if String(pr[0]) == "e" else PackedVector2Array())
		if legs.is_empty():
			bad.append("%s->%s: no route" % [pr[0], pr[1]])
			continue
		var V := {"id": -1, "legs": [], "gar": int(pr[2]), "rv": 1}
		for l in legs:
			V.legs.append([int(l[0]), FacDrive7._flat(l[1])])
		var w := make_world()
		var R := FacDrive7._route(w, V)
		worst_r = minf(worst_r, float(R.rmin))
		var s := 0.0
		var lh := float(FacDrive7.pose_at(R, 0.0)[1])
		var hits := 0
		while s <= float(R.len):
			var pp: Array = FacDrive7.pose_at(R, s)
			if not FacDrive7.pose_clear(G, pp[0], pp[1], int(pr[2])):
				hits += 1
				if hits == 1:
					bad.append("%s->%s: body on a footprint at %s" % [pr[0], pr[1], (pp[0] as Vector2).snappedf(0.1)])
			worst_dh = maxf(worst_dh, absf(wrapf(float(pp[1]) - lh, -PI, PI)))
			lh = float(pp[1])
			s += 0.1
	check(bad.is_empty(), "every garage / bay / gate route clears every building: %s" % [bad.slice(0, 6)])
	check(worst_r >= FacDrive7.R_MIN - 0.001, "turning radius >= %.1f tiles everywhere (worst %.2f)" % [FacDrive7.R_MIN, worst_r])
	check(worst_dh <= 0.1 / FacDrive7.R_MIN + 0.01, "heading changes smoothly along every route (max %.3f rad per 0.1 tile)" % worst_dh)


# ---------------------------------------------------------------- flows (the controller drives; force_on until ORCH registers it)
func _on() -> void:
	FacDrive7.force_on = true


func _off() -> void:
	FacDrive7.force_on = false


func _local(w: SimWorld, fid: int, p: Vector2) -> Vector2:
	return p - Vector2(CnFacility.origin(CnFacility.fac(w, fid)))


func _new_stats() -> Dictionary:
	return {"hits": 0, "hit_at": "", "maxdh": 0.0, "dh_at": "", "lastf": {}, "mind": 99.0, "mind_at": "", "bayed": {}, "queued": {},
		"seq": {}, "cross": {}, "maxbay": 0, "drove": {}}


## Per-tick watcher over the APCs: body clear and heading rate while the controller drives, spacing inside the compound,
## bays used, queueing, convoy seq and gate crossing ticks.
func _watch(w: SimWorld, fid: int, ids: Array, st: Dictionary) -> void:
	var G := FacDrive7.graph()
	var cs := float(CnFacility.conf().compound)
	var lim := FacDrive7.V_FWD / float(SimWorld.TICK_RATE) / FacDrive7.R_MIN + 0.002
	var inside := []
	var nb := 0
	for id in ids:
		var e = w.entities.get(int(id))
		if e == null:
			continue
		var V := FacDrive7.vstate(w, int(id))
		var lp := _local(w, fid, Vector2(e.pos))
		var k := str(id)
		if not V.is_empty() and (String(V.st) == "drive" or String(V.st) == "hold"):
			st.drove[k] = true
			if not FacDrive7.pose_clear(G, lp, float(e.facing), int(V.gar)):
				st.hits += 1
				if st.hit_at == "":
					st.hit_at = "%s at %s" % [k, lp.snappedf(0.1)]
			if st.lastf.has(k):
				var dh := absf(wrapf(float(e.facing) - float(st.lastf[k]), -PI, PI))
				st.maxdh = maxf(float(st.maxdh), dh)
				if dh > lim and st.dh_at == "":
					st.dh_at = "%s turned %.3f rad in one tick at %s" % [k, dh, lp.snappedf(0.1)]
			st.lastf[k] = float(e.facing)
		else:
			st.lastf.erase(k)
		if Rect2(0, 0, cs, cs).has_point(lp):
			inside.append([lp, k])
		if not V.is_empty() and String(V.st) == "park" and String(V.at).left(1) == "b":
			st.bayed[k] = String(V.at)
			nb += 1
		if not V.is_empty() and String(V.st) == "queue":
			st.queued[k] = true
		if not V.is_empty() and String(V.get("rto", "")) == "x" and not st.seq.has(k):
			st.seq[k] = int(V.seq)
		if lp.y > cs - 2.0 and not st.cross.has(k):
			st.cross[k] = w.tick
	st.maxbay = maxi(int(st.maxbay), nb)
	for i in inside.size():
		for j in range(i + 1, inside.size()):
			var d := (inside[i][0] as Vector2).distance_to(inside[j][0])
			if d < float(st.mind):
				st.mind = d
				st.mind_at = "%s/%s at %s tick %d" % [inside[i][1], inside[j][1], (inside[i][0] as Vector2).snappedf(0.1), w.tick]


func _all_apcs(w: SimWorld, tids: Array) -> Array:
	var out := []
	for tid in tids:
		var T := CnFacility.team(w, int(tid))
		if not T.is_empty():
			for a in T.apcs:
				out.append(int(a))
	return out


func _parked_in_garages(w: SimWorld, ids: Array) -> int:
	var n := 0
	for id in ids:
		var V := FacDrive7.vstate(w, id)
		if not V.is_empty() and String(V.st) == "park" and String(V.at).left(1) == "g":
			n += 1
	return n


func test_two_bays_third_waits_convoy_and_spacing() -> void:
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var t1 := _train(w, fid, "strike_team")
	var t2 := _train(w, fid, "tactical_squad")
	var ids := _all_apcs(w, [t1, t2])
	check_eq(ids.size(), 3, "a strike team (2 APCs) and a tactical squad (1 APC)")
	_quiet(w, ids)
	for i in 20:
		_step(w)
	check_eq(_parked_in_garages(w, ids), 3, "all three APCs are taken under control, parked in their garages")
	var F := CnFacility.fac(w, fid)
	var out := CnFacility.compound_rect(F).end + Vector2(-16, 6)
	_cmd(w, {"type": "cn_rollout", "team": t1, "target": out})
	for i in 30:
		_step(w)
	_cmd(w, {"type": "cn_rollout", "team": t2, "target": out + Vector2(-4, 0)})
	var stt := _new_stats()
	var T1 := CnFacility.team(w, t1)
	var T2 := CnFacility.team(w, t2)
	var ticks := 0
	for i in 3000:
		_step(w)
		_watch(w, fid, ids, stt)
		ticks += 1
		if String(T1.phase) == "out" and String(T2.phase) == "out":
			break
	print("  APCMOV7 flow: %d ticks, bays %s, queued %s, min spacing %.2f (%s), max heading step %.4f rad, gate seq %s cross %s" % [ticks, stt.bayed, stt.queued.keys(), stt.mind, stt.mind_at, stt.maxdh, stt.seq, stt.cross])
	check_eq(String(T1.phase), "out", "the strike team rolled out")
	check_eq(String(T2.phase), "out", "the tactical squad rolled out")
	check_eq(int(stt.maxbay), 2, "two APCs stood in the two staging bays at once")
	check(stt.queued.size() >= 1, "the third APC waited its turn (queue) while both bays were taken")
	check_eq(int(stt.hits), 0, "no APC body ever on a building footprint (%s)" % stt.hit_at)
	check(float(stt.mind) >= 1.75, "APCs keep >= 1.75 tiles apart (min %.2f, %s)" % [float(stt.mind), stt.mind_at])
	check(String(stt.dh_at) == "", "heading turns at most V/R per tick: %s" % stt.dh_at)
	var order: Array = stt.seq.keys()
	order.sort_custom(func(a, b): return int(stt.seq[a]) < int(stt.seq[b]))
	var crossed := order.size() == 3
	for i in range(1, order.size()):
		if not stt.cross.has(order[i]) or not stt.cross.has(order[i - 1]) or int(stt.cross[order[i]]) <= int(stt.cross[order[i - 1]]):
			crossed = false
	check(crossed, "they leave through the gate one after another in convoy order (%s, %s)" % [order, stt.cross])
	_off()


func test_return_outer_gate_wash_inner_gate_garage_nose_out() -> void:
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "strike_team")
	var ids := _all_apcs(w, [tid])
	_quiet(w, ids)
	var F := CnFacility.fac(w, fid)
	var out := CnFacility.compound_rect(F).end + Vector2(-14, 8)
	_cmd(w, {"type": "cn_rollout", "team": tid, "target": out})
	var T := CnFacility.team(w, tid)
	for i in 3000:
		_step(w)
		if String(T.phase) == "out" and Vector2(w.entities[ids[0]].pos).distance_to(out) < 4.0 and Vector2(w.entities[ids[1]].pos).distance_to(out) < 4.0:
			break
	check_eq(String(T.phase), "out", "the team rolled out")
	_cmd(w, {"type": "cn_return", "team": tid})
	var zs := {"gate_outer": CnFacility.zone(F, "gate_outer"), "apc_wash": CnFacility.zone(F, "apc_wash"), "gate_inner": CnFacility.zone(F, "gate_inner")}
	var seqs := {}
	var stt := _new_stats()
	var ticks := 0
	for i in 4000:
		_step(w)
		ticks += 1
		_watch(w, fid, ids, stt)
		for id in ids:
			var a: Dictionary = w.entities[id]
			var sq: Array = seqs.get(id, [])
			for n in zs:
				if (zs[n] as Rect2).has_point(Vector2(a.pos)) and (sq.is_empty() or sq[sq.size() - 1] != n):
					sq.append(n)
			seqs[id] = sq
		if String(T.phase) == "garage" and _parked_in_garages(w, ids) == ids.size():
			break
	print("  APCMOV7 return: %d ticks, zones %s, min spacing %.2f (%s)" % [ticks, seqs, stt.mind, stt.mind_at])
	for id in ids:
		check_eq(seqs.get(id, []), ["gate_outer", "apc_wash", "gate_inner"], "APC %d drives outer gate -> wash -> inner gate" % id)
	check_eq(String(T.phase), "garage", "the team parks in its garages")
	var C := CnFacility.conf()
	for i in ids.size():
		var V := FacDrive7.vstate(w, ids[i])
		var a: Dictionary = w.entities[ids[i]]
		var g := int(V.get("gar", -1))
		check(g >= 0 and _local(w, fid, Vector2(a.pos)).distance_to(FacDrive7.garage_park(C, g)) < 0.05, "APC %d parked in its own garage" % ids[i])
		check(g >= 0 and absf(wrapf(float(a.facing) - FacDrive7.garage_out(C, g).angle(), -PI, PI)) < 0.02, "APC %d stands nose out (backed in)" % ids[i])
	check_eq(int(stt.hits), 0, "no body on a footprint on the way home (%s)" % stt.hit_at)
	check(float(stt.mind) >= 1.75, "spacing kept on the way home (min %.2f, %s)" % [float(stt.mind), stt.mind_at])
	check(String(stt.dh_at) == "", "smooth heading on the way home: %s" % stt.dh_at)
	_off()


func test_player_orders_bays_point_garage() -> void:
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var t1 := _train(w, fid, "tactical_squad")   # two separate APCs (a strike team's pair always follows each other)
	var t2 := _train(w, fid, "tactical_squad")
	var ids := _all_apcs(w, [t1, t2])
	_quiet(w, ids)
	for i in 20:
		_step(w)
	var F := CnFacility.fac(w, fid)
	var C := CnFacility.conf()
	var a: Dictionary = w.entities[ids[0]]
	var b: Dictionary = w.entities[ids[1]]
	var g0 := int(FacDrive7.vstate(w, ids[0]).gar)
	var g1 := int(FacDrive7.vstate(w, ids[1]).gar)
	check_eq(_cmd(w, {"type": "fd7_go", "ids": ids, "to": "bays"}), "", "fd7_go bays accepted")
	var stt := _new_stats()
	for i in 1500:
		_step(w)
		_watch(w, fid, ids, stt)
		if int(stt.maxbay) == 2:
			break
	check_eq(int(stt.maxbay), 2, "both APCs drove into the staging bays")
	var out := CnFacility.compound_rect(F).end + Vector2(-14, 10)
	check_eq(_cmd(w, {"type": "fd7_go", "ids": [ids[0]], "to": "point", "target": out}), "", "fd7_go point accepted")
	Movement.order_move(w, b, Vector2(CnFacility.origin(F)) + FacDrive7.garage_park(C, g1))   # a plain move into its garage
	for i in 2500:
		_step(w)
		_watch(w, fid, ids, stt)
		var Vb0 := FacDrive7.vstate(w, ids[1])
		if Vector2(a.pos).distance_to(out) < 2.0 and not Vb0.is_empty() and String(Vb0.st) == "park" and String(Vb0.at).left(1) == "g":
			break
	check(Vector2(a.pos).distance_to(out) < 2.5, "APC 1 drove out through the gates to the point (%.1f away)" % Vector2(a.pos).distance_to(out))
	var Vb := FacDrive7.vstate(w, ids[1])
	check(not Vb.is_empty() and String(Vb.st) == "park" and String(Vb.at) == "g%d" % g1, "APC 2 drove back into its own garage (%s %s)" % [Vb.get("st", "-"), Vb.get("at", "-")])
	Movement.order_move(w, a, Vector2(CnFacility.origin(F)) + FacDrive7.garage_park(C, g0) + Vector2(0.3, 0.2))   # home from outside
	for i in 3000:
		_step(w)
		_watch(w, fid, ids, stt)
		var Va := FacDrive7.vstate(w, ids[0])
		if not Va.is_empty() and String(Va.st) == "park" and String(Va.at) == "g%d" % g0:
			break
	var Va2 := FacDrive7.vstate(w, ids[0])
	check(not Va2.is_empty() and String(Va2.st) == "park" and String(Va2.at) == "g%d" % g0, "APC 1 came back in through the gates and parked in its garage (%s %s)" % [Va2.get("st", "-"), Va2.get("at", "-")])
	check_eq(int(stt.hits), 0, "no body on a footprint (%s)" % stt.hit_at)
	check(float(stt.mind) >= 1.75, "spacing kept (min %.2f, %s)" % [float(stt.mind), stt.mind_at])
	check(String(stt.dh_at) == "", "smooth heading: %s" % stt.dh_at)
	_off()


func test_reroute_while_driving_and_stop() -> void:
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "tactical_squad")
	var ids := _all_apcs(w, [tid])
	_quiet(w, ids)
	for i in 20:
		_step(w)
	var a: Dictionary = w.entities[ids[0]]
	var F := CnFacility.fac(w, fid)
	_cmd(w, {"type": "fd7_go", "ids": ids, "to": "bays"})
	for i in 60:
		_step(w)
	check_eq(String(FacDrive7.vstate(w, ids[0]).get("st", "")), "drive", "driving to the bays")
	var out := CnFacility.compound_rect(F).end + Vector2(-8, 8)
	_cmd(w, {"type": "fd7_go", "ids": ids, "to": "point", "target": out})
	var stt := _new_stats()
	var rerouted := false
	var v_at := -1.0
	for i in 300:
		_step(w)
		_watch(w, fid, ids, stt)
		var V := FacDrive7.vstate(w, ids[0])
		if not V.is_empty() and String(V.get("rto", "")) == "x" and String(V.st) == "drive":
			rerouted = true
			v_at = float(V.v)
			break
	check(rerouted, "a new order while driving re-routes after the current segment (now heading out)")
	check(v_at > 0.1, "it keeps rolling through the re-route (v %.2f)" % v_at)
	for i in 30:
		_step(w)
		_watch(w, fid, ids, stt)
	do_cmd(w, 0, {"type": "stop", "unit_ids": ids})
	var p0 := Vector2.ZERO
	var V2 := {}
	for i in 90:
		_step(w)
		_watch(w, fid, ids, stt)
		if i == 50:
			p0 = Vector2(a.pos)
	V2 = FacDrive7.vstate(w, ids[0])
	check(not V2.is_empty() and String(V2.st) == "hold" and Vector2(a.pos).distance_to(p0) < 0.001, "stop: the APC brakes to a standstill and stays put (%s)" % [V2.get("st", "-")])
	check(String(stt.dh_at) == "" and int(stt.hits) == 0, "smooth and clear throughout (%s %s)" % [stt.dh_at, stt.hit_at])
	_cmd(w, {"type": "fd7_go", "ids": ids, "to": "garage"})
	for i in 5000:   # (heading out on the one-way gate lane it turns round outside and comes back in)
		_step(w)
		_watch(w, fid, ids, stt)
		if _parked_in_garages(w, ids) == 1:
			break
	check_eq(_parked_in_garages(w, ids), 1, "after the stop a new order takes it home to its garage")
	_off()


func _flow_hash(save_mid: bool) -> String:
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "strike_team")
	var ids := _all_apcs(w, [tid])
	_quiet(w, ids)
	var F := CnFacility.fac(w, fid)
	_cmd(w, {"type": "cn_rollout", "team": tid, "target": CnFacility.compound_rect(F).end + Vector2(-16, 6)})
	for i in 200:
		_step(w)
	if save_mid:
		var V := FacDrive7.vstate(w, ids[0])
		var V1 := FacDrive7.vstate(w, ids[1])
		check((not V.is_empty() and String(V.st) == "drive") or (not V1.is_empty() and String(V1.st) == "drive"), "saved while an APC is driving")
		var b := SimWorld.from_dict(w.to_dict().duplicate(true))
		check_eq(b.state_hash(), w.state_hash(), "loaded hash = live hash mid-drive")
		for i in 500:
			_step(w)
			_step(b)
		check_eq(b.state_hash(), w.state_hash(), "live and loaded drive identically afterwards")
	else:
		for i in 500:
			_step(w)
	_off()
	return w.state_hash()


func test_hash_twice_same() -> void:
	var h1 := _flow_hash(false)
	var h2 := _flow_hash(false)
	print("  HASH apcmov7 twice: %s / %s" % [h1, h2])
	check_eq(h1, h2, "same flow twice = same hash")


func test_save_mid_drive_round_trip() -> void:
	_flow_hash(true)


func test_no_facility_no_cost() -> void:
	var w := make_world()
	for i in 50:
		w.step()
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		FacDrive7.tick(w)
	var us := float(Time.get_ticks_usec() - t0) / 2000.0
	print("  NO-COST: FacDrive7.tick without facility %.3f us/call" % us)
	check(not w.sys_state.has(FacDrive7.KEY), "a match without a facility has no fac_drive7 state")
	check(not w.sys_state.has(FacDrive7.SUIT_KEY), "nor any suit-wash state (13.9c-25)")
	check(us < 5.0, "and the tick costs next to nothing (%.3f us)" % us)
	check(not FacDrive7.force_on, "force_on is reset (never leaks into other tests)")


# ---------------------------------------------------------------- 13.9c-22: the hardened outer APC gate
func _gates_of(w: SimWorld, fid: int) -> Array:
	return FacDrive7.gate_view(CnFacility.fac(w, fid))


## In hardened mode the wash is a sally port: once the outer gate has shut, outer and inner are never both off "closed"
## at the same time (the moment the threat appears both still stand open, the outer then closes).
var _shut_seen := false


func _sally_ok(w: SimWorld, fid: int) -> bool:
	var GT: Dictionary = CnFacility.fac(w, fid).get("gate", {})
	if GT.is_empty() or not bool(GT.hard):
		_shut_seen = false
		return true
	if String(GT.o) == "closed":
		_shut_seen = true
	return not _shut_seen or String(GT.o) == "closed" or String(GT.i) == "closed"


func test_gate_hardens_cycles_for_own_apcs_and_stands_down() -> void:
	if not FacDrive7.GATES_ON:
		print("  GATE test NOT EXECUTED: 13.9c-22 hardening is switched off (FacDrive7.GATES_ON false) until it is finished")
		return
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "tactical_squad")
	var ids := _all_apcs(w, [tid])
	_quiet(w, ids)
	for i in 20:
		_step(w)
	check_eq(_gates_of(w, fid), ["open", "open", false], "no enemy near: both APC gates stand open")
	var F := CnFacility.fac(w, fid)
	var cr := CnFacility.compound_rect(F)
	check(w.is_enemy(0, 1), "side 1 is hostile to the facility owner")
	var en := w.spawn_unit("rifleman", 1, cr.end + Vector2(-14, 9))
	var ee: Dictionary = w.entities[en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = NOFIRE
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	var states := []
	var sally := true
	for i in CnFacility.secs(FacDrive7.GATE_S) + 40:
		_step(w)
		var gv := _gates_of(w, fid)
		if states.is_empty() or states[states.size() - 1] != gv[0]:
			states.append(gv[0])
		sally = sally and _sally_ok(w, fid)
	check_eq(_gates_of(w, fid), ["hardened", "open", true], "an enemy near the base: the outer gate closes and locks (%s)" % [states])
	check(states.has("closing"), "it closes over real seconds (closing seen: %s)" % [states])
	# the player sends the APC out: inner closes, outer opens, the APC passes, the outer closes behind it, inner reopens
	var out := cr.end + Vector2(-6, 14)
	check_eq(_cmd(w, {"type": "fd7_go", "ids": ids, "to": "out", "target": out}), "", "fd7_go out accepted")
	var a: Dictionary = w.entities[ids[0]]
	var seen_open := false
	var passed_tick := -1
	var wait_at := Vector2.ZERO
	var waited := false
	for i in 2500:
		_step(w)
		sally = sally and _sally_ok(w, fid)
		var gv := _gates_of(w, fid)
		if states[states.size() - 1] != gv[0]:
			states.append(gv[0])
		var lp := _local(w, fid, Vector2(a.pos))
		if String(gv[0]) != "open" and lp.y > 22.0 and lp.y < 26.0 and absf(float(FacDrive7.vstate(w, ids[0]).get("v", 1.0))) < 0.001:
			waited = true
		if String(gv[0]) == "open":
			seen_open = true
		if passed_tick < 0 and lp.y > float(CnFacility.conf().compound) + 1.0:
			passed_tick = w.tick
		if passed_tick > 0 and String(gv[0]) == "hardened" and String(gv[1]) == "open" and w.tick > passed_tick + 30:
			break
	print("  GATE states %s, APC waited in the wash %s, passed at %d" % [states, waited, passed_tick])
	check(waited, "the APC waits in the wash (sally port) while the outer gate cycles")
	check(seen_open and passed_tick > 0, "the outer gate opened for it and it drove out")
	check_eq(_gates_of(w, fid), ["hardened", "open", true], "the outer gate closed and locked behind it, the inner reopened")
	check(sally, "outer and inner gates were never open at the same time while hardened")
	# the enemy cannot get in through the shut gate
	Movement.order_move(w, ee, cr.get_center())
	for i in 600:
		_step(w)
	check(not cr.grow(-1.0).has_point(Vector2(ee.pos)), "the enemy cannot pass the hardened gate (at %s)" % [_local(w, fid, ee.pos).snappedf(0.1)])
	# stand down once no enemy has been near for a while
	w.entities.erase(en)
	w.cache.erase("sim_index")
	for i in CnFacility.secs(FacDrive7.STAND_DOWN_S + FacDrive7.GATE_S) + 60:
		_step(w)
	check_eq(_gates_of(w, fid), ["open", "open", false], "after the threat has gone for a while the gate stands down and opens")
	_off()


## APCMOV7-4: a strike team's two APCs sent out of their garages at once (their routes share the lane to the gate column;
## the later-ordered one reaches the merge first) must not deadlock at the gate-lane entry: both drive out through the
## hardened gate (sally port: inner closes, outer opens, they pass, outer closes, inner reopens), never both gates open.
func test_two_apcs_out_of_garages_together_through_hardened_gate() -> void:
	if not FacDrive7.GATES_ON:
		print("  GATE test NOT EXECUTED: 13.9c-22 hardening is switched off (FacDrive7.GATES_ON false) until it is finished")
		return
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "strike_team")
	var ids := _all_apcs(w, [tid])
	_quiet(w, ids)
	check_eq(ids.size(), 2, "a strike team brings two APCs")
	for i in 20:
		_step(w)
	var F := CnFacility.fac(w, fid)
	var cr := CnFacility.compound_rect(F)
	var en := w.spawn_unit("rifleman", 1, cr.end + Vector2(-14, 9))
	var ee: Dictionary = w.entities[en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = NOFIRE
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	for i in CnFacility.secs(FacDrive7.GATE_S) + 60:
		_step(w)
	check_eq(_gates_of(w, fid), ["hardened", "open", true], "enemy near: the outer gate is hardened")
	check_eq(_cmd(w, {"type": "fd7_go", "ids": [ids[0], ids[1]], "to": "out", "target": cr.end + Vector2(-14, 5)}), "", "fd7_go out accepted for both")
	var sally := true
	var out_n := 0
	var tick_out := -1
	var seen_both_open := false
	for i in 4800:
		_step(w)
		sally = sally and _sally_ok(w, fid)
		var gv := _gates_of(w, fid)
		if String(gv[0]) == "open" and String(gv[1]) == "open":
			seen_both_open = true
		out_n = 0
		for id in ids:
			if _local(w, fid, Vector2(w.entities[id].pos)).y > float(CnFacility.conf().compound) + 1.0:
				out_n += 1
		if out_n == ids.size() and tick_out < 0:
			tick_out = w.tick
		if tick_out > 0 and String(gv[0]) == "hardened" and String(gv[1]) == "open" and w.tick > tick_out + 60:
			break
	print("  GATE two APCs from the garages: %d/%d out at tick %d, gates now %s, both open at once %s" % [out_n, ids.size(), tick_out, _gates_of(w, fid), seen_both_open])
	check_eq(out_n, ids.size(), "both APCs drove out (no deadlock at the gate-lane entry)")
	check(sally and not seen_both_open, "outer and inner gates were never open at the same time while hardened")
	check_eq(_gates_of(w, fid), ["hardened", "open", true], "the outer gate closed and locked behind them, the inner reopened")
	_off()


func test_gate_hardened_inbound_return() -> void:
	if not FacDrive7.GATES_ON:
		print("  GATE test NOT EXECUTED: 13.9c-22 hardening is switched off (FacDrive7.GATES_ON false) until it is finished")
		return
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var tid := _train(w, fid, "strike_team")
	var ids := _all_apcs(w, [tid])
	_quiet(w, ids)
	var F := CnFacility.fac(w, fid)
	var cr := CnFacility.compound_rect(F)
	var out := cr.end + Vector2(-14, 8)
	_cmd(w, {"type": "cn_rollout", "team": tid, "target": out})
	var T := CnFacility.team(w, tid)
	for i in 3000:
		_step(w)
		if String(T.phase) == "out" and Vector2(w.entities[ids[0]].pos).distance_to(out) < 4.0 and Vector2(w.entities[ids[1]].pos).distance_to(out) < 4.0:
			break
	var en := w.spawn_unit("rifleman", 1, cr.end + Vector2(-26, 12))
	var ee: Dictionary = w.entities[en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = NOFIRE
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	for i in CnFacility.secs(FacDrive7.GATE_S) * 3 + 60:
		_step(w)
	check_eq(String(_gates_of(w, fid)[0]), "hardened", "hardened with the team outside")
	_cmd(w, {"type": "cn_return", "team": tid})
	var sally := true
	var opened := 0
	var last := "hardened"
	for i in 4000:
		_step(w)
		sally = sally and _sally_ok(w, fid)
		var g0 := String(_gates_of(w, fid)[0])
		if g0 == "open" and last != "open":
			opened += 1
		last = g0
		if String(T.phase) == "garage" and g0 == "hardened":
			break
	check_eq(String(T.phase), "garage", "the team came home through the sally port and parked")
	check(opened >= 1 and last == "hardened", "the outer gate cycled open for them and locked again (%d openings, now %s)" % [opened, last])
	check(sally, "never both gates open")
	print("  GATE inbound: enemy at %s hp %s" % [_local(w, fid, ee.pos).snappedf(0.1), ee.get("hp")])
	w.entities.erase(en)
	_off()



# ---------------------------------------------------------------- 13.9c-25: APC entry / wash = vehicles and CN suits only
func _apc_entry_rects(w: SimWorld, fid: int) -> Array:
	var F := CnFacility.fac(w, fid)
	return [CnFacility.zone(F, "gate_outer"), CnFacility.zone(F, "apc_wash"), CnFacility.zone(F, "gate_inner")]


func _in_any(rs: Array, p: Vector2) -> bool:
	for r in rs:
		if (r as Rect2).has_point(p):
			return true
	return false


## Foot units of every team on an APC gate / wash cell right now: [[id, def, local pos], ...].
func _foot_on_entry(w: SimWorld, fid: int, rs: Array) -> Array:
	var out := []
	for e in w.entities.values():
		if e.kind == "unit" and Movement.move_class(e) == "foot" and _in_any(rs, Vector2(e.pos)):
			out.append([int(e.id), String(e.def), _local(w, fid, e.pos).snappedf(0.1)])
	return out


func test_infantry_never_through_apc_gate_or_wash() -> void:
	if not FacDrive7.GATES_ON:
		print("  13.9c-25 test NOT EXECUTED: FacDrive7.GATES_ON false")
		return
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	for i in 20:
		_step(w)
	var F := CnFacility.fac(w, fid)
	var O := Vector2(CnFacility.origin(F))
	var rs := _apc_entry_rects(w, fid)
	var gc: Vector2i = w.cell_of(CnFacility.zone(F, "apc_wash").get_center())
	check(not Movement.is_passable(w, gc, "foot", Movement.team_of(w, {"owner": 0})), "a wash cell is closed to the owner's own foot units")
	check(Movement.is_passable(w, gc, "vehicle", Movement.team_of(w, {"owner": 0})), "and open to the owner's vehicles")
	check(not Movement.is_passable(w, gc, "vehicle", Movement.team_of(w, {"owner": 1})), "and closed to another team's vehicles")
	var ids := []
	for k in 6:
		var id := w.spawn_unit("rifleman", 0, O + Vector2(12.5 + float(k % 3), 33.5 + float(k / 3)))
		w.entities[id].cd_ticks = NOFIRE
		ids.append(id)
	var inside := O + Vector2(12.5, 18.5)   # straight through the APC gates is the shortest way in
	for id in ids:
		Movement.order_move(w, w.entities[id], inside)
	var bad := []
	var arrived := 0
	for i in 3600:
		_step(w)
		var f := _foot_on_entry(w, fid, rs)
		if not f.is_empty() and bad.size() < 4:
			bad.append([w.tick, f])
		arrived = 0
		for id in ids:
			if Vector2(w.entities[id].pos).distance_to(inside) < 3.5:
				arrived += 1
		if arrived == ids.size():
			break
	print("  13.9c-25 IN: %d/%d riflemen arrived inside at tick %d (foot on the APC entry: %s)" % [arrived, ids.size(), w.tick, bad])
	check_eq(arrived, ids.size(), "the riflemen got in, round by the foot entry")
	var outside := O + Vector2(13.5, 36.5)
	for id in ids:
		Movement.order_move(w, w.entities[id], outside)
	var out_n := 0
	for i in 3600:
		_step(w)
		var f := _foot_on_entry(w, fid, rs)
		if not f.is_empty() and bad.size() < 4:
			bad.append([w.tick, f])
		out_n = 0
		for id in ids:
			if Vector2(w.entities[id].pos).distance_to(outside) < 3.5:
				out_n += 1
		if out_n == ids.size():
			break
	print("  13.9c-25 OUT: %d/%d riflemen back outside at tick %d (foot on the APC entry: %s)" % [out_n, ids.size(), w.tick, bad])
	check_eq(out_n, ids.size(), "and back out the same way")
	check(bad.is_empty(), "no foot unit ever stood on an APC gate or wash cell (%s)" % [bad])
	_off()


func _spawn_suits(w: SimWorld, fid: int, n: int) -> Array:
	var O := Vector2(CnFacility.origin(CnFacility.fac(w, fid)))
	var ids := []
	for k in n:
		var id := w.spawn_unit("g7_cns_bastion", 0, O + Vector2(9.5 + 2.0 * float(k), 37.5))
		w.entities[id].cd_ticks = NOFIRE
		ids.append(id)
	return ids


func test_suits_enter_through_wash_four_at_a_time() -> void:
	if not FacDrive7.GATES_ON:
		print("  13.9c-25 test NOT EXECUTED: FacDrive7.GATES_ON false")
		return
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	check(FacDrive7.is_suit("g7_cns_bastion") and not FacDrive7.is_suit("rifleman"), "suit defs are recognised by exo_suit / cn_suit")
	var F := CnFacility.fac(w, fid)
	var O := Vector2(CnFacility.origin(F))
	var cr := CnFacility.compound_rect(F)
	var wash := CnFacility.zone(F, "apc_wash")
	var rs := _apc_entry_rects(w, fid)
	var ids := _spawn_suits(w, fid, 5)
	var tgt := [O + Vector2(9.5, 18.5), O + Vector2(11.5, 18.5), O + Vector2(9.5, 13.5), O + Vector2(11.5, 13.5), O + Vector2(13.5, 13.5)]
	for k in ids.size():
		Movement.order_move(w, w.entities[ids[k]], tgt[k])
	var max_in := 0
	var max_wash := 0
	var fifth_waited := false
	var washed := {}
	var done := false
	for i in 4800:
		_step(w)
		var nw := FacDrive7.suits_in_wash(w, fid)
		max_in = maxi(max_in, nw)
		var nwash := 0
		var queued := 0
		for id in ids:
			var p := Vector2(w.entities[id].pos)
			if wash.has_point(p):
				nwash += 1
				washed[id] = true
			if FacDrive7.suit_state(w, id) == "qin" and nw >= FacDrive7.WASH_CAP:
				queued += 1
		max_wash = maxi(max_wash, nwash)
		fifth_waited = fifth_waited or queued > 0
		var all_in := true
		for k in ids.size():
			if Vector2(w.entities[ids[k]].pos).distance_to(tgt[k]) > 1.5:
				all_in = false
		if all_in:
			done = true
			break
	var rinsed := 0
	for id in ids:
		if int(w.entities[id].get("cn_rinsed", -1)) >= 0:
			rinsed += 1
	print("  13.9c-25 SUITS IN: done %s at tick %d, max in wash (controller) %d, max in wash rect %d, 5th waited %s, washed %d, rinsed %d" % [done, w.tick, max_in, max_wash, fifth_waited, washed.size(), rinsed])
	check(done, "all 5 suits got to their points inside")
	check(max_in <= FacDrive7.WASH_CAP and max_wash <= FacDrive7.WASH_CAP, "never more than 4 suits in the wash (%d / %d)" % [max_in, max_wash])
	check_eq(max_in, FacDrive7.WASH_CAP, "the wash took 4 at once")
	check(fifth_waited, "the 5th waited outside while the wash was full")
	check_eq(washed.size(), ids.size(), "every suit went through the wash")
	check_eq(rinsed, ids.size(), "every suit was decontaminated")
	# leaving: through the wash and the gates, never the foot entry
	var outp := O + Vector2(14.0, 40.0)
	var washed_out := {}
	for k in ids.size():
		Movement.order_move(w, w.entities[ids[k]], outp + Vector2(2.0 * float(k) - 4.0, 0.0))
	var out_n := 0
	for i in 3600:
		_step(w)
		out_n = 0
		for id in ids:
			var p := Vector2(w.entities[id].pos)
			if _in_any(rs, p):
				washed_out[id] = true
			if not cr.has_point(p) and p.y > outp.y - 2.5:
				out_n += 1
		if out_n == ids.size():
			break
	print("  13.9c-25 SUITS OUT: %d/%d outside at tick %d, through the APC entry %d" % [out_n, ids.size(), w.tick, washed_out.size()])
	check_eq(out_n, ids.size(), "all 5 suits left")
	check_eq(washed_out.size(), ids.size(), "every suit left through the APC entry")
	check(not w.sys_state.has(FacDrive7.SUIT_KEY), "the suit controller let go of them all (state gone)")
	_off()


func test_suits_wait_for_hardened_gate() -> void:
	if not FacDrive7.GATES_ON:
		print("  13.9c-25 test NOT EXECUTED: FacDrive7.GATES_ON false")
		return
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var F := CnFacility.fac(w, fid)
	var O := Vector2(CnFacility.origin(F))
	var cr := CnFacility.compound_rect(F)
	var en := w.spawn_unit("rifleman", 1, cr.end + Vector2(-26, 12))
	var ee: Dictionary = w.entities[en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = NOFIRE
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	for i in CnFacility.secs(FacDrive7.GATE_S) + 60:
		_step(w)
	check_eq(_gates_of(w, fid), ["hardened", "open", true], "enemy near: the outer gate is hardened")
	var ids := _spawn_suits(w, fid, 2)
	for k in ids.size():
		Movement.order_move(w, w.entities[ids[k]], O + Vector2(9.5 + 2.0 * float(k), 18.5))
	var sally := true
	var opened := false
	var done := false
	for i in 4800:
		_step(w)
		sally = sally and _sally_ok(w, fid)
		opened = opened or String(_gates_of(w, fid)[0]) == "open"
		done = true
		for k in ids.size():
			if Vector2(w.entities[ids[k]].pos).distance_to(O + Vector2(9.5 + 2.0 * float(k), 18.5)) > 1.5:
				done = false
		if done:
			break
	print("  13.9c-25 HARD: suits in %s at tick %d, outer opened %s, gates now %s" % [done, w.tick, opened, _gates_of(w, fid)])
	check(done, "both suits got in through the hardened gate")
	check(opened, "the outer gate cycled open for them")
	check(sally, "outer and inner were never open at once")
	for i in CnFacility.secs(FacDrive7.GATE_S) + 60:
		_step(w)
	check_eq(_gates_of(w, fid), ["hardened", "open", true], "and it closed and locked again behind them")
	_off()


## FACB7-7 + APCMOV7-4 (13.9c-20c, 13.9c-22): the mantrap doors and the decon hall are foot only (no suit, no vehicle, no
## other team's soldier); a SHUT own APC gate is still planned through for the owner's vehicles / suits (their order into the
## compound survives a hardened gate, FacDrive7 queues them) but never for another team or for foot; a suit never stands
## on a mantrap or hall cell, whether it is ordered to the staging yard or to the decon hall itself.
func test_mantrap_foot_only_and_shut_gate_planned_through() -> void:
	if not FacDrive7.GATES_ON:
		print("  13.9c-25 test NOT EXECUTED: FacDrive7.GATES_ON false")
		return
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	for i in 20:
		_step(w)
	var F := CnFacility.fac(w, fid)
	var O := Vector2(CnFacility.origin(F))
	var oi := Vector2i(CnFacility.origin(F))
	var cr := CnFacility.compound_rect(F)
	var t0 := Movement.team_of(w, {"owner": 0})
	var t1 := Movement.team_of(w, {"owner": 1})
	var fo := []   # the foot-only cells: both mantrap doors + every decon hall cell
	for m in CnFacility.conf().get("mantrap", []):
		fo.append(oi + Vector2i(int(m[0]), int(m[1])))
	var hall := CnFacility.zone(F, "decon_hall")
	for y in range(int(hall.position.y), int(hall.end.y)):
		for x in range(int(hall.position.x), int(hall.end.x)):
			fo.append(Vector2i(x, y))
	check(fo.size() >= 12, "mantrap doors + decon hall cells found (%d)" % fo.size())
	var suit: int = _spawn_suits(w, fid, 1)[0]
	var smc := Movement.move_class(w.entities[suit])
	var bad_v := 0
	var bad_f := 0
	for c in fo:
		if Movement.is_passable(w, c, smc, t0) or Movement.is_passable(w, c, smc, t1):
			bad_v += 1
		if not Movement.is_passable(w, c, "foot", t0) or Movement.is_passable(w, c, "foot", t1):
			bad_f += 1
	check_eq(bad_v, 0, "no suit / vehicle of either team can stand on a mantrap door or hall cell")
	check_eq(bad_f, 0, "the owner's foot units can, another team's cannot")
	var inner := O + Vector2(9.5, 18.5)
	check(Movement.can_reach(w, w.entities[suit], inner), "gate open: the suit can plan into the compound (APC entry)")
	var en := w.spawn_unit("rifleman", 1, cr.end + Vector2(-26, 12))
	var ee: Dictionary = w.entities[en]
	ee.order = {"type": "hold"}
	ee.cd_ticks = NOFIRE
	ee.hp = 1.0e9
	ee.max_hp = 1.0e9
	for i in CnFacility.secs(FacDrive7.GATE_S) + 60:
		_step(w)
	check_eq(_gates_of(w, fid), ["hardened", "open", true], "enemy near: the outer gate is hardened (shut and locked)")
	var wg: Vector2i = w.cell_of(CnFacility.zone(F, "gate_outer").get_center())
	check(bool(Movement.gate_at(w, wg).get("locked", false)), "the outer gate cells are a locked nav gate")
	check(not Movement.is_passable(w, wg, smc, t0), "so the step itself is blocked for the owner's suit")
	var se: Dictionary = w.entities[suit]
	check(Movement.can_reach(w, se, inner), "shut own gate: the suit can still plan into the compound")
	Movement.order_move(w, se, inner)
	check_eq(String(se.order.get("type", "")), "move", "its move order survives the hardened gate (not turned idle)")
	check(not (se.path as Array).is_empty() and Vector2((se.path as Array).back()).distance_to(inner) < 0.01, "with a path that ends at the goal")
	var es := w.spawn_unit("g7_cns_bastion", 1, O + Vector2(18.5, 40.5))
	w.entities[es].cd_ticks = NOFIRE
	check(not Movement.can_reach(w, w.entities[es], inner), "another team's armour cannot plan through the shut gate")
	var ef := w.spawn_unit("rifleman", 1, O + Vector2(14.5, 40.5))
	w.entities[ef].cd_ticks = NOFIRE
	check(not Movement.can_reach(w, w.entities[ef], inner), "another team's soldier cannot get in either")
	var of := w.spawn_unit("rifleman", 0, O + Vector2(14.5, 40.5))
	w.entities[of].cd_ticks = NOFIRE
	check(Movement.can_reach(w, w.entities[of], inner), "the owner's soldier plans in by the foot entry")
	w.entities.erase(es)
	w.entities.erase(ef)
	w.entities.erase(of)
	w.cache.clear()
	# the suit goes in (queue, gate cycle, wash) and never stands on a foot-only cell; a second suit is ordered to the hall itself
	var suit2: int = _spawn_suits(w, fid, 2)[1]
	var hall_c := hall.get_center()
	Movement.order_move(w, w.entities[suit2], hall_c)
	var on_fo := 0
	var done := false
	for i in 5400:
		_step(w)
		for id in [suit, suit2]:
			if fo.has(w.cell_of(w.entities[id].pos)):
				on_fo += 1
		if Vector2(w.entities[suit].pos).distance_to(inner) < 1.5 and cr.has_point(w.entities[suit2].pos) and FacDrive7.suit_state(w, suit2) == "":
			done = true
			break
	var p2 := Vector2(w.entities[suit2].pos)
	print("  13.9c-20c MANTRAP: suit in %s at tick %d, steps on foot-only cells %d, suit2 (ordered to the decon hall) at %s inside %s, rinsed %s / %s" % [done, w.tick, on_fo, (p2 - O).snappedf(0.1), cr.has_point(p2), w.entities[suit].get("cn_rinsed", -1), w.entities[suit2].get("cn_rinsed", -1)])
	check(done, "both suits got inside the compound")
	check_eq(on_fo, 0, "no suit ever stood on a mantrap door or decon hall cell")
	check(int(w.entities[suit].get("cn_rinsed", -1)) >= 0 and int(w.entities[suit2].get("cn_rinsed", -1)) >= 0, "both went through the wash on the way in")
	_off()


func _suit_flow_hash(save_mid: bool) -> String:
	_on()
	var s := _setup()
	var w: SimWorld = s[0]
	var fid := _facility(w, s[1])
	var O := Vector2(CnFacility.origin(CnFacility.fac(w, fid)))
	var ids := _spawn_suits(w, fid, 5)
	for k in ids.size():
		Movement.order_move(w, w.entities[ids[k]], O + Vector2(9.5 + 2.0 * float(k % 3), 18.5 - 3.0 * float(k / 3)))
	for i in 200:
		_step(w)
	if save_mid:
		check(w.sys_state.has(FacDrive7.SUIT_KEY), "saved while suits are in the wash cycle")
		var b := SimWorld.from_dict(w.to_dict().duplicate(true))
		check_eq(b.state_hash(), w.state_hash(), "loaded hash = live hash mid-wash")
		for i in 900:
			_step(w)
			_step(b)
		check_eq(b.state_hash(), w.state_hash(), "live and loaded run identically afterwards")
	else:
		for i in 900:
			_step(w)
	_off()
	return w.state_hash()


func test_suit_flow_hash_twice_and_save() -> void:
	var h1 := _suit_flow_hash(false)
	var h2 := _suit_flow_hash(false)
	print("  HASH apcmov7 suits twice: %s / %s" % [h1, h2])
	check_eq(h1, h2, "same suit flow twice = same hash")
	_suit_flow_hash(true)
