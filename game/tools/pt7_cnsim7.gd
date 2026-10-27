extends RefCounted
## G7 playtest flow cnsim7 (CNSIM7): the Counter-Nanite Protocol unlocked (debug), a full strike team (20 soldiers in
## two strike APCs) plus two tactical operator squads spawned inside their APCs, the whole group moving as one
## motorcade (cn_move -> SQUAD7's Convoy) past a Machine walker group (contact, manned .50 mounts), a purge deployment
## with the dome up over painted creep (scan -> jam -> arm -> purge, engineers' hold), then a second deployment with
## the dome knocked out (stalls dome_down) finished by a hero detonation (call sign into the Remembered list).
## Shots of each + a 10-shot 0.3 s strip of the convoy. CN commands go through w.submit once ORCH registers them
## (CR change_request.cn_commands), else straight through CounterNanite / Apc7 validate+apply (same code path).

const H = preload("res://tests/test_machine_g6.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const Apc7 = preload("res://sim/systems/apc7.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Movement = preload("res://sim/systems/movement.gd")
const PD = preload("res://sim/systems/progression_data.gd")

var evs: Array = []


func _on_events(e: Array) -> void:
	for ev in e:
		var t := String(ev.get("type", ""))
		if t.begins_with("Cn") or t.begins_with("Apc") or t.begins_with("Aps") or t.begins_with("Mount"):
			evs.append(ev)


func _ev(t: String, key: String = "", val = null) -> Dictionary:
	for ev in evs:
		if String(ev.type) == t and (key == "" or ev.get(key) == val):
			return ev
	return {}


func _cmd(pt, cmd: Dictionary) -> String:
	var mv = pt._mv()
	mv.join_sim()
	var w: SimWorld = pt._w()
	cmd.issuer = int(mv.player_fid)
	if SimWorld.COMMANDS.has(String(cmd.type)):
		return String(w.submit(cmd).get("reason", ""))
	var sys = Apc7 if String(cmd.type) in ["cn_dome", "cn_emp", "cn_panels"] else CN
	var why: String = sys.validate_command(w, cmd)
	if why == "":
		sys.apply_command(w, cmd)
	return why


## Paints full creep over the creep cells within r of center and seeds a nest there (CREEP7 API).
func _paint_creep(w: SimWorld, center: Vector2, r: float) -> int:
	var s: Dictionary = Creep.enable(w)
	var cs := int(s.cs)
	var v: PackedByteArray = s.v
	var n := 0
	for cy in int(s.ch):
		for cx in int(s.cw):
			var p := Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			if p.distance_to(center) <= r and v[cy * int(s.cw) + cx] < 255:
				v[cy * int(s.cw) + cx] = 255
				n += 1
	s.v = v
	s.on_n = int(s.on_n) + n
	Creep.add_nest(w, center, 4, 2.0)
	return n


func _apc_pos(w: SimWorld, t: Dictionary) -> Vector2:
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			return Vector2(a.pos)
	return Vector2.ZERO


func _zoom(pt, z: float) -> void:
	var cam = pt._mv().get("camera")
	if cam != null and cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.unit("g7_cn_strike_apc").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := 1 if me == 0 else 0
	var c: Vector2i = h._open(w, 18)
	var cf := Vector2(c) + Vector2(0.5, 0.5)
	mv.world_events.connect(_on_events)
	var cleared := 0
	var keys := w.entities.keys()
	keys.sort()
	for id in keys:
		var e = w.entities.get(id)
		if e != null and e.kind == "unit" and w.is_enemy(me, int(e.owner)) and Vector2(e.pos).distance_to(cf) <= 45.0:
			w.destroy(int(id), "playtest")
			cleared += 1
	# 0. the unlock (debug): the research is marked done for the player side
	var done: Array = w.factions[me].research.done
	if not done.has("g7_counter_nanite"):
		done.append("g7_counter_nanite")
	pt._log("cnsim7_unlock", PD.has_research(w, me, "g7_counter_nanite"),
		"g7_counter_nanite researched (debug), faction %s, ground %s, %d enemy units cleared" % [String(w.factions[me].get("faction_def", "")), str(c), cleared])

	# 1. the full group spawns inside its APCs
	var spawn := cf + Vector2(-14.0, 12.0)
	var rs := CN.spawn_team(w, me, "strike_team", spawn)
	var r1 := CN.spawn_team(w, me, "tactical_squad", spawn + Vector2(-4.0, -3.0))
	var r2 := CN.spawn_team(w, me, "tactical_squad", spawn + Vector2(4.0, 3.0))
	var ok_spawn := not rs.is_empty() and not r1.is_empty() and not r2.is_empty()
	pt._log("cnsim7_spawn", ok_spawn and (rs.members as Array).size() == 20 and (rs.apcs as Array).size() == 2 and (r1.members as Array).size() == 8,
		"strike team %s, tactical %s / %s" % [str(rs.get("members", []).size()), str(r1.get("members", []).size()), str(r2.get("members", []).size())])
	if not ok_spawn:
		return
	var t: Dictionary = CN.team(w, int(rs.team))
	var inside := 0
	for mid in t.members:
		if not w.entities.has(int(mid)) and CN.alive(w, int(mid)):
			inside += 1
	pt._log("cnsim7_inside_apcs", inside == 20, "%d/20 strike soldiers ride inside the APCs; leader id %d" % [inside, int(t.leader)])
	var lo := _cmd(pt, {"type": "cn_set_loadout", "team_id": int(t.id), "packages": ["purge", "purge", "purge", "purge"]})
	await pt._wait(0.3)
	mv.join_sim()
	pt._log("cnsim7_loadout", lo == "", "cn_set_loadout 4x purge before leaving: '%s' -> %s" % [lo, str(CN.loadout(w, int(t.id)))])
	mv.center_camera_on(spawn)
	_zoom(pt, 1.0)
	mv.speed = 1.0
	await pt._wait(1.0)
	await pt._shot("cnsim7_01_spawn")

	# 2. motorcade past a Machine walker group (contact on the flank)
	var site1 := cf + Vector2(6.0, -6.0)
	var foes := []
	for k in 4:
		var fc := Movement.nearest_free_cell(w, Vector2i(floori(cf.x) + (k % 2) * 2, floori(cf.y) + 6 + (k / 2) * 2), "vehicle")
		var fe: Dictionary = h._unit(w, "m_walker", foe, Vector2(fc) + Vector2(0.5, 0.5))
		fe.order = {"type": "hold"}
		foes.append(int(fe.id))
	var hp0 := 0.0
	for fid in foes:
		hp0 += float(w.entities[fid].hp)
	var mvr := _cmd(pt, {"type": "cn_move", "team_id": int(t.id), "target": site1, "escort_teams": [int(r1.team), int(r2.team)]})
	await pt._wait(0.3)
	mv.join_sim()
	pt._log("cnsim7_convoy_order", mvr == "" and int(t.conv) >= 0, "cn_move '%s', convoy id %d" % [mvr, int(t.conv)])
	_zoom(pt, 0.85)
	for k in 10:
		mv.join_sim()
		mv.center_camera_on(_apc_pos(w, t))
		await pt._shot("cnsim7_strip_%02d" % k)
		await pt._wait(0.3)
	var contact: bool = await pt._wait_until(func():
		var hp := 0.0
		for fid in foes:
			var fe = pt._w().entities.get(fid)
			hp += 0.0 if fe == null else float(fe.hp)
		return hp < hp0 - 1.0 and not _ev("ApcPanel", "kind", "smoke").is_empty(), 25.0)
	mv.join_sim()
	mv.center_camera_on(_apc_pos(w, t))
	await pt._shot("cnsim7_02_convoy_contact")
	var hp1 := 0.0
	var dead := 0
	for fid in foes:
		var fe = w.entities.get(fid)
		hp1 += 0.0 if fe == null else float(fe.hp)
		dead += 1 if fe == null else 0
	var manned := 0
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		manned += 0 if a == null else int(a.a7.get("manned", 0))
	var smoke := _ev("ApcPanel", "kind", "smoke")
	pt._log("cnsim7_convoy_contact", contact and CN.live_apcs(w, t).size() == 2 and manned >= 2,
		"mounts engaged: walkers hp %.0f -> %.0f (%d/4 destroyed; .50 small_arms vs heavy armour x0.05), crew smoke on APC %s, strike APCs alive %d/2, manned .50 mounts %d/4" % [hp0, hp1, dead, str(smoke.get("id", "none")), CN.live_apcs(w, t).size(), manned])
	await _deploys(pt, t, foes, site1, cf + Vector2(10.0, 10.0))


func _deploys(pt, t: Dictionary, foes: Array, site1: Vector2, site2: Vector2) -> void:
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	var through: bool = await pt._wait_until(func(): return _apc_pos(pt._w(), t).distance_to(site1) <= 6.0, 30.0)
	mv.join_sim()
	pt._log("cnsim7_convoy_through", through and CN.live_apcs(w, t).size() == 2, "motorcade reached the site past the contact: %s, strike APCs %d/2" % [through, CN.live_apcs(w, t).size()])
	for fid in foes:   # contact over: the walkers left on the flank are removed so the deployment scene is readable
		if w.entities.has(fid):
			w.destroy(fid, "playtest")
	# 3. a deployment with the dome up purges painted creep
	var painted := _paint_creep(w, site1, 8.0)
	var dr := _cmd(pt, {"type": "cn_deploy", "team_id": int(t.id), "target": site1, "package": "purge"})
	pt._log("cnsim7_deploy_order", dr == "", "cn_deploy purge at %s: '%s' (%d creep cells painted)" % [str(site1), dr, painted])
	mv.speed = 2.0
	var armed: bool = await pt._wait_until(func(): return not _ev("CnDeployPhase", "phase", "arm").is_empty(), 60.0)
	await pt._wait_until(func():
		for aid in t.apcs:
			if Apc7.dome_up(pt._w().entities.get(int(aid))):
				return true
		return false, 20.0)
	mv.join_sim()
	mv.speed = 1.0
	mv.center_camera_on(site1)
	_zoom(pt, 1.1)
	await pt._wait(0.5)
	await pt._shot("cnsim7_03_deploy_dome_up")
	var domes := 0
	for aid in t.apcs:
		domes += 1 if Apc7.dome_up(w.entities.get(int(aid))) else 0
	pt._log("cnsim7_deploy_armed", armed and domes >= 1, "reached arm phase %s, domes up %d, hold placed %d" % [armed, domes, (t.hold as Array).size()])
	mv.speed = 2.0
	var purged: bool = await pt._wait_until(func(): return not _ev("CnPurge").is_empty(), 60.0)
	mv.join_sim()
	mv.speed = 1.0
	var cv := Creep.at(w, Vector2i(floori(site1.x), floori(site1.y)))
	await pt._wait(0.5)
	await pt._shot("cnsim7_04_purged")
	pt._log("cnsim7_purge", purged and cv < 0.5, "CnPurge %s, creep at site %.2f, cleared %s cells" % [purged, cv, str(_ev("CnPurge").get("cleared", -1))])

	# 4. second deployment with the dome knocked out -> stall -> hero detonation
	await pt._wait_until(func(): return CN.live_members(pt._w(), t).size() > 0 and t.dep == null, 15.0)
	_paint_creep(w, site2, 7.0)
	var m2 := _cmd(pt, {"type": "cn_move", "team_id": int(t.id), "target": site2})
	mv.speed = 2.0
	await pt._wait_until(func(): return _apc_pos(pt._w(), t).distance_to(site2) <= 6.0, 40.0)
	mv.join_sim()
	for aid in t.apcs:
		var a = w.entities.get(int(aid))
		if a != null:
			Apc7.set_dome(w, a, false)
			a.a7.dome = 0.0
			a.a7.dome_cd = w.tick + 100000
	var d2 := _cmd(pt, {"type": "cn_deploy", "team_id": int(t.id), "target": site2, "package": "purge"})
	var stalled: bool = await pt._wait_until(func(): return not _ev("CnDeployStalled", "reason", "dome_down").is_empty(), 60.0)
	mv.join_sim()
	mv.speed = 1.0
	mv.center_camera_on(site2)
	await pt._shot("cnsim7_05_stalled_dome_down")
	pt._log("cnsim7_dome_down_stall", m2 == "" and d2 == "" and stalled, "move '%s', deploy '%s', stalled on dome_down %s" % [m2, d2, stalled])
	var hr := _cmd(pt, {"type": "cn_hero_detonate", "team_id": int(t.id)})
	await pt._wait(1.5)
	mv.join_sim()
	var hev := _ev("CnHeroDetonation")
	await pt._shot("cnsim7_06_hero_window")
	var boom: bool = await pt._wait_until(func(): return not _ev("CnPurge", "hero", true).is_empty(), 20.0)
	mv.join_sim()
	await pt._wait(0.4)
	await pt._shot("cnsim7_07_hero_blast")
	var rem: Array = w.sys_state.get("cn7", {}).get("remembered", [])
	var hid := int(hev.get("id", -1))
	pt._log("cnsim7_hero", hr == "" and boom and rem.size() >= 1 and not w.entities.has(hid),
		"cn_hero_detonate '%s', call sign '%s', blast %s, Remembered %s" % [hr, String(hev.get("call_sign", "")), boom, str(rem)])
	pt._log("cnsim7_team_after", CN.live_apcs(w, t).size() == 2, "strike APCs %d/2, soldiers alive %d/20, leader %d" % [CN.live_apcs(w, t).size(), CN.live_members(w, t).size(), int(t.leader)])
