extends RefCounted
## G7 playtest flow vis7 (VIS7): the counter-nanite / threat display. A strike team and a tactical squad against a
## heavy walker: dome up soaking the walker's fire, pop-out launchers raising and ripple-firing salvos (backblast,
## trails, canister impacts), .50 pods firing, the walker toppling (fall in the push direction, impact, lying with legs
## thrashing, righting itself), toppled again and blown up (blast sheet, fireballs, debris, smoke column). Then every
## threat state (burrowed ripple, disguised mimic, latched leech, cocooned soldier, slugs / swipes), the world reaction
## area (abandoned vehicles, beacons, camp, the dam, warped vs recovering ground) and the minimap creep. Shots at zoom
## 0.6 / 1.2 / 2.4. The sim paths are CNSIM7's / THREAT7's real APIs (Apc7.fire_salvo, Apc7.topple, Threats7.spawn);
## only the timing is scripted so every state shows up in a few minutes.

const H = preload("res://tests/test_machine_g6.gd")
const CN = preload("res://sim/systems/counter_nanite.gd")
const Apc7 = preload("res://sim/systems/apc7.gd")
const Threats7 = preload("res://sim/systems/threats7.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Vis7Layer = preload("res://presentation/view/vis7_layer.gd")
const Minimap = preload("res://presentation/hud/minimap.gd")

var seen: Dictionary = {}   # event type -> count
var shooters: Dictionary = {}   # ShotFired shooter id -> count
var peak: Dictionary = {}   # vis7 draw counter -> max per frame seen
var L = null


func _on_events(e: Array) -> void:
	for ev in e:
		var t := String(ev.get("type", ""))
		seen[t] = int(seen.get(t, 0)) + 1
		if t == "ShotFired":
			shooters[int(ev.get("shooter", -1))] = int(shooters.get(int(ev.get("shooter", -1)), 0)) + 1


func _zoom(pt, z: float) -> void:
	var cam = pt._mv().get("camera")
	if cam != null and cam.has_method("set_zoom_level"):
		cam.set_zoom_level(z)


func _layer(pt):
	var mv = pt._mv()
	var l = mv.get("vis7_layer")
	if l == null:
		for c in mv.get_children():
			if c.get_script() == Vis7Layer:
				l = c
	if l == null:   # not wired by ORCH yet (CR seq 1393): attach it the same way
		l = Vis7Layer.new()
		l.name = "Vis7Layer"
		l.z_index = 2
		mv.add_child(l)
		var el = mv.get("entity_layer")
		if el is Node:
			mv.move_child(l, (el as Node).get_index() + 1)
		l.setup(mv)
		mv.world_events.connect(l.on_events)
	return l


## Shot plus the peak per-frame vis7 counters over the next few frames.
func _snap(pt, name: String) -> void:
	await pt._shot(name)
	for k in L.counts:
		peak[k] = maxi(int(peak.get(k, 0)), int(L.counts[k]))


func _sample(pt, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await pt._wait(0.05)
		for k in L.counts:
			peak[k] = maxi(int(peak.get(k, 0)), int(L.counts[k]))


var _bb0 := 0


## Centre on the launcher that fired last (the newest backblast fx), so the pod, cone and smoke are in frame.
func _frame_last_salvo(pt) -> void:
	var best = null
	for f in L._fx:
		if String(f.k) == "backblast" and (best == null or float(f.t0) > float(best.t0)):
			best = f
	if best != null:
		pt._mv().center_camera_on(Vector2(best.p) + Vector2(-0.6, -0.6))


## True once this salvo's RocketSalvo reached the layer (the previous salvo's lingering backblast does not count).
func _salvo_drawn() -> bool:
	return int(L.totals.get("backblast", 0)) > _bb0


func _pop_and_fire(pt, w: SimWorld, a: Dictionary, tgt: Dictionary, pref: Array) -> int:
	a.a7.rl.eng = 99
	a.a7.rl.st = 1
	a.a7.rl.cd = 0
	if int(a.a7.rl.tube) <= 0:   # scripted timing: the pod may have emptied itself on the walker already
		a.a7.rl.tube = 6
	Apc7._rl_render(w, a)
	await _sample(pt, 0.7)
	pt._mv().join_sim()
	a.a7.rl.st = 2
	Apc7._rl_render(w, a)
	await _sample(pt, 0.4)
	pt._mv().join_sim()
	if not w.entities.has(int(tgt.id)):
		return 0
	return Apc7.fire_salvo(w, a, tgt, pref)


func run(pt) -> void:
	var mv = pt._mv()
	mv.join_sim()
	if Content.unit("g7_cn_strike_apc").is_empty():
		Content._merge_fragment_dir("res://content/g7")
	var w: SimWorld = pt._w()
	var h = H.new()
	var me := int(mv.player_fid)
	var foe := 1 if me == 0 else 0
	var c: Vector2i = h._open(w, 20)
	var cf := Vector2(c) + Vector2(0.5, 0.5)
	mv.world_events.connect(_on_events)
	var keys := w.entities.keys()
	keys.sort()
	for id in keys:
		var e = w.entities.get(id)
		if e != null and e.kind == "unit" and w.is_enemy(me, int(e.owner)) and Vector2(e.pos).distance_to(cf) <= 50.0:
			w.destroy(int(id), "playtest")
	var done: Array = w.factions[me].research.done
	if not done.has("g7_counter_nanite"):
		done.append("g7_counter_nanite")
	L = _layer(pt)
	pt._log("vis7_layer", L != null, "vis7 layer attached (wired by match_view: %s, entity_layer x7 hook: %s)" % [str(mv.get("vis7_layer") != null),
		str("x7" in mv.entity_layer)])

	# ---------------------------------------------------------------- A. strike team vs a heavy walker
	var spawn := cf + Vector2(-6.0, 4.0)
	var rs := CN.spawn_team(w, me, "strike_team", spawn)
	var r1 := CN.spawn_team(w, me, "tactical_squad", spawn + Vector2(0.0, 5.0))
	if rs.is_empty() or r1.is_empty():
		pt._log("vis7_spawn", false, "strike team / tactical squad did not spawn")
		return
	var a: Dictionary = w.entities[int(rs.apcs[0])]
	var a2: Dictionary = w.entities[int(rs.apcs[1])] if (rs.apcs as Array).size() > 1 and w.entities.has(int(rs.apcs[1])) else a
	var b: Dictionary = w.entities[int(r1.apcs[0])]
	var wc := Movement.nearest_free_cell(w, Vector2i(floori(cf.x + 0.0), floori(cf.y - 1.0)), "vehicle")   # inside launcher range (9) of the parked strike APC
	var wk: Dictionary = h._unit(w, "m_walker", foe, Vector2(wc) + Vector2(0.5, 0.5))
	wk.order = {"type": "hold"}
	wk.facing = (spawn - Vector2(wk.pos)).angle()
	var wid := int(wk.id)
	a.order = {"type": "hold"}   # the dome only holds while the APC is stopped: park it, then raise
	Movement.stop_path(a)
	Apc7.set_dome(w, a, true)
	mv.center_camera_on((Vector2(a.pos) + Vector2(wk.pos)) * 0.5)
	_zoom(pt, 1.2)
	mv.speed = 1.0
	var dch := -1.0
	for k in 16:   # re-raise every 0.5 s until the bubble is in the snapshot and drawn (up to 8 s)
		await _sample(pt, 0.5)
		mv.join_sim()
		if not w.entities.has(int(a.id)):
			break
		var ea: Dictionary = w.entities[int(a.id)]
		if not bool(ea.a7.dome_on):
			ea.order = {"type": "hold"}
			Movement.stop_path(ea)
			Apc7.set_dome(w, ea, true)
		dch = float(mv.snap.get("g7u", {}).get(int(a.id), {}).get("dome", -1.0))
		if dch >= 0.0 and int(peak.get("dome", 0)) >= 1 and k >= 3:
			break
	await _snap(pt, "vis7_01_dome_soak_z12")
	pt._log("vis7_dome", int(peak.get("dome", 0)) >= 1 and dch >= 0.0, "dome bubble drawn (peak %d), charge %.2f, walker shots %d, dome stops %d" % [int(peak.get("dome", 0)), dch,
		int(seen.get("ShotFired", 0)), int(seen.get("ApcDomeStop", 0))])
	# salvos: strike APC raises the pod and ripple-fires; the second strike APC and the tactical APC follow
	_bb0 = int(L.totals.get("backblast", 0))
	var n1: int = await _pop_and_fire(pt, w, a, wk, ["tandem", "emp"])
	await pt._wait_until(_salvo_drawn, 2.0)
	await _sample(pt, 0.15)   # the RocketSalvo event reaches the view with the next sim step
	await _snap(pt, "vis7_02_salvo_ripple_z12")
	await _sample(pt, 0.25)
	await _snap(pt, "vis7_03_salvo_trails_z12")
	var a_2: Dictionary = a2 if a2 != a else b
	_zoom(pt, 2.4)
	mv.join_sim()
	mv.center_camera_on(Vector2(a_2.pos))   # frame the APC that fires this salvo (pod up, backblast)
	_bb0 = int(L.totals.get("backblast", 0))
	var n2: int = await _pop_and_fire(pt, w, a_2, wk, ["thermite", "disruptor"])
	await pt._wait_until(_salvo_drawn, 2.0)
	_frame_last_salvo(pt)
	await _sample(pt, 0.15)
	await _snap(pt, "vis7_04_pod_backblast_z24")
	var bbs: Array = []
	for f in L._fx:
		if String(f.k) == "backblast":
			bbs.append("p=%s fa=%.2f age=%.2f pod_scr=%s" % [str(f.p), float(f.fa), L.t - float(f.t0), str(L._pod(Vector2(f.p), float(f.fa)))])
	pt._log("vis7_bb_probe", true, "apc %s at %s scr %s; vr %s zoom %.2f; fx %d; backblasts: %s" % [str(a_2.id), str(a_2.pos), str(L.scr(Vector2(a_2.pos))), str(L._vr), L._zoom, L._fx.size(), " | ".join(bbs)])
	mv.join_sim()
	var n3: int = await _pop_and_fire(pt, w, b, wk, ["he_frag", "tandem"])
	_zoom(pt, 0.6)
	await _sample(pt, 0.2)
	await _snap(pt, "vis7_05_salvo_far_z06")
	pt._log("vis7_salvos", n1 > 0 and n2 > 0 and int(peak.get("rocket", 0)) >= 1 and int(peak.get("backblast", 0)) >= 1,
		"salvos fired %d / %d / %d; rockets peak %d, backblasts %d, impacts %d, ripple frames %d, raise %d" % [n1, n2, n3, int(peak.get("rocket", 0)),
		int(peak.get("backblast", 0)), int(peak.get("rk_hit", 0)), int(peak.get("apc_rk_fire", 0)), int(peak.get("apc_rk_raise", 0))])
	# .50 pods: let the APCs engage on their own for a few seconds (gun sheet fire / reload frames)
	mv.join_sim()
	var gun_apc: Dictionary = a if w.entities.has(int(a.id)) else b
	var apc_ids := [int(a.id), int(a2.id), int(b.id)]
	shooters.clear()   # only shots from now on count
	peak.erase("apc_fire")
	peak.erase("apc_fire_r")
	for k in 2:   # targets inside .50 range of the parked APC
		Threats7.spawn(w, "g7_m_spitter", foe, Vector2(gun_apc.pos) + Vector2(3.0 + k * 0.9, -2.5 + k * 1.6))
	_zoom(pt, 1.8)
	mv.center_camera_on(Vector2(gun_apc.pos) + Vector2(1.5, -1.0))
	var apc_shot := func() -> bool:
		for sid in apc_ids:
			if shooters.has(sid):
				return true
		return false
	var fired: bool = await pt._wait_until(apc_shot, 10.0)
	await _sample(pt, 0.3)
	await _snap(pt, "vis7_06_gun_pods_z18")
	pt._log("vis7_guns", int(peak.get("apc_fire", 0)) + int(peak.get("apc_fire_r", 0)) >= 1, "APC ShotFired seen %s; .50 fire frames peak %d front / %d rear, reload %d" % [str(fired), int(peak.get("apc_fire", 0)),
		int(peak.get("apc_fire_r", 0)), int(peak.get("apc_reload", 0)) + int(peak.get("apc_reload_r", 0))])
	# CN operator kit shots (display events; the operator AI fires these during a real pincer, see pt7_cnsim7)
	mv.join_sim()
	if w.entities.has(wid):
		L.on_events([{"type": "CnHarpoon", "id": int(b.id), "target": wid, "from": b.pos, "to": wk.pos},
			{"type": "CnLimpetPlanted", "id": int(b.id), "target": wid, "pos": wk.pos},
			{"type": "CnDisruptorShot", "id": int(a.id), "target": wid, "from": a.pos, "to": wk.pos},
			{"type": "ApcPanel", "id": int(a2.id), "kind": "interceptors", "pos": a2.pos}])
	_zoom(pt, 1.2)
	mv.center_camera_on(Vector2(wk.pos))
	await _sample(pt, 0.15)
	await _snap(pt, "vis7_07_harpoon_limpet_disruptor_z12")
	# the topple: fall in the push direction, impact, down with legs thrashing, righting
	mv.join_sim()
	if not w.entities.has(wid):
		pt._log("vis7_topple", false, "walker died before the topple")
		return
	Apc7.topple(w, wk)
	await _sample(pt, 0.35)
	await _snap(pt, "vis7_08_topple_falling_z12")
	await _sample(pt, 0.9)
	await _snap(pt, "vis7_09_topple_impact_z12")
	_zoom(pt, 2.4)
	await _sample(pt, 1.5)
	await _snap(pt, "vis7_10_topple_down_z24")
	var rose: bool = await pt._wait_until(func(): return String(pt._mv().snap.get("g7u", {}).get(wid, {}).get("topple", "")) == "rise", 20.0)
	await _sample(pt, 0.5)
	await _snap(pt, "vis7_11_topple_rise_z24")
	pt._log("vis7_topple", int(peak.get("topple", 0)) >= 1 and int(peak.get("impact", 0)) >= 1 and int(peak.get("exposed", 0)) >= 1 and rose and bool(L._hook),
		"topple frames swapped inside entity_layer (x7 hook %s, drawn once), peak %d, impact %d, exposed / legs %d, rise reached %s; events toppled %d down %d righted %d" % [str(L._hook), int(peak.get("topple", 0)),
		int(peak.get("impact", 0)), int(peak.get("exposed", 0)), str(rose), int(seen.get("WalkerToppled", 0)), int(seen.get("WalkerDown", 0)),
		int(seen.get("WalkerRighted", 0))])
	# toppled again and blown up while it lies there
	await pt._wait_until(func(): return not pt._mv().snap.get("g7u", {}).get(wid, {}).has("topple") or String(pt._mv().snap.g7u[wid].topple) == "stagger", 6.0)
	mv.join_sim()
	if w.entities.has(wid):
		Apc7.topple(w, w.entities[wid])
	await _sample(pt, 1.8)
	mv.join_sim()
	_zoom(pt, 1.2)
	mv.center_camera_on(Vector2(w.entities[wid].pos) if w.entities.has(wid) else Vector2(wk.pos))
	if w.entities.has(wid):
		w.destroy(wid, "playtest")
	await pt._wait_until(func(): return int(seen.get("WalkerBlownUp", 0)) > 0, 3.0)
	await _sample(pt, 0.15)
	await _snap(pt, "vis7_12_blown_up_flash_z12")
	await _sample(pt, 0.45)
	await _snap(pt, "vis7_13_blown_up_fire_z12")
	await _sample(pt, 1.6)
	await _snap(pt, "vis7_14_blown_up_smoke_z12")
	pt._log("vis7_blown_up", int(seen.get("WalkerBlownUp", 0)) >= 1 and int(peak.get("wblast", 0)) >= 1,
		"WalkerBlownUp %d, blast drawn peak %d" % [int(seen.get("WalkerBlownUp", 0)), int(peak.get("wblast", 0))])
	await _threats(pt, w, h, me, foe, cf, b)
	await _world(pt, w, cf)


func _threats(pt, w: SimWorld, h, me: int, foe: int, cf: Vector2, b: Dictionary) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var c2 := cf + Vector2(-2.0, -10.0)
	var bur := Threats7.spawn(w, "g7_m_burrower", foe, c2 + Vector2(-4.0, 0.0))
	var mim := Threats7.spawn(w, "g7_m_mimic", foe, c2 + Vector2(-1.0, -2.0))
	var lee := Threats7.spawn(w, "g7_m_leech", foe, Vector2(b.pos) + Vector2(1.2, 0.0))
	Threats7.allow_weavers(w, true)
	var sol: Array = []
	for k in 3:
		sol.append(h._unit(w, "g7_cn_gunner", me, c2 + Vector2(3.0 + k * 0.8, 1.0)))
	var wv := Threats7.spawn(w, "g7_m_weaver", foe, c2 + Vector2(7.0, -1.0))
	var sp := Threats7.spawn(w, "g7_m_spitter", foe, c2 + Vector2(5.0, 3.5))
	mv.center_camera_on(c2 + Vector2(1.0, 0.0))
	_zoom(pt, 1.2)
	peak.erase("mound")
	peak.erase("mimic")
	await pt._wait_until(func(): return int(seen.get("Cocooned", 0)) > 0 and int(seen.get("LeechLatched", 0)) > 0, 20.0)
	await _sample(pt, 1.0)
	await _snap(pt, "vis7_15_threats_z12")
	_zoom(pt, 2.4)
	mv.center_camera_on(c2 + Vector2(-3.0, -1.0))
	await _sample(pt, 0.5)
	await _snap(pt, "vis7_16_burrow_mimic_z24")
	mv.join_sim()
	mv.center_camera_on(Vector2(b.pos) if w.entities.has(int(b.id)) else c2)
	await _sample(pt, 0.8)
	await _snap(pt, "vis7_17_leech_on_hull_z24")
	pt._log("vis7_threats", int(peak.get("mound", 0)) >= 1 and int(peak.get("mimic", 0)) >= 1,
		"spawned burrower %d mimic %d leech %d weaver %d spitter %d; drawn: mound %d mimic %d leech %d cocoon %d slug %d claw %d web %d; events latched %d cocooned %d slugs %d" % [
		bur, mim, lee, wv, sp, int(peak.get("mound", 0)), int(peak.get("mimic", 0)), int(peak.get("leech", 0)), int(peak.get("cocoon", 0)),
		int(peak.get("slug", 0)), int(peak.get("claw", 0)), int(peak.get("webline", 0)), int(seen.get("LeechLatched", 0)), int(seen.get("Cocooned", 0)),
		int(seen.get("NaniteSlug", 0))])
	pt._log("vis7_cocoon", int(seen.get("Cocooned", 0)) == 0 or int(peak.get("cocoon", 0)) >= 1, "cocoons drawn %d for %d Cocooned events" % [
		int(peak.get("cocoon", 0)), int(seen.get("Cocooned", 0))])


func _world(pt, w: SimWorld, cf: Vector2) -> void:
	var mv = pt._mv()
	mv.join_sim()
	var c3 := cf + Vector2(14.0, 8.0)
	var s: Dictionary = Creep.enable(w)
	var cs := int(s.cs)
	var v: PackedByteArray = s.v
	var n := 0
	for cy in int(s.ch):
		for cx in int(s.cw):
			var p := Vector2((float(cx) + 0.5) * cs, (float(cy) + 0.5) * cs)
			if p.distance_to(c3) <= 11.0 and v[cy * int(s.cw) + cx] < 255:
				v[cy * int(s.cw) + cx] = 255
				n += 1
	s.v = v
	s.on_n = int(s.on_n) + n
	# world traces + a dam strip (the LP map data shape, injected next to the creep for the shot)
	var lp: Dictionary = w.map.get("lp", {})
	var ci := Vector2i(floori(c3.x), floori(c3.y))
	lp["world"] = {"animals": [{"pos": c3 + Vector2(-12, 6), "kind": "deer", "n": 5}],
		"vehicles": [{"cell": ci + Vector2i(-3, -2), "kind": "car", "rot": 0.4}, {"cell": ci + Vector2i(2, 1), "kind": "truck", "rot": 1.9},
			{"cell": ci + Vector2i(-13, 2), "kind": "van", "rot": 2.6}, {"cell": ci + Vector2i(-12, -2), "kind": "bus", "rot": 0.1}],
		"camps": [{"cell": ci + Vector2i(-9, 6), "tents": 3}],
		"beacons": [{"cell": ci + Vector2i(0, -4), "lost_squad": true}, {"cell": ci + Vector2i(-11, 4)}]}
	var dam: Array = []
	for y in range(ci.y - 14, ci.y - 2):
		for x in range(ci.x - 22, ci.x - 19):
			dam.append(Vector2i(x, y))
	lp["dam"] = {"cell": dam[dam.size() / 2], "cells": dam, "flood": Rect2i(ci.x - 19, ci.y - 14, 8, 12)}
	w.map["lp"] = lp
	var wl = mv.get("world7_layer")
	if wl != null:
		wl._setup_traces()
	await _sample(pt, 1.0)
	mv.join_sim()
	if wl != null and wl._cw > 0:   # prime the warp age (display state; a real match reaches it after minutes of creep)
		for k in wl._age.size():
			if k < wl._v.size() and int(wl._v[k]) >= int(wl._on):
				wl._age[k] = wl.WARP_FULL_S
	Creep.purge(w, c3 + Vector2(6.0, 0.0), 6.0)
	await _sample(pt, 2.0)
	mv.center_camera_on(c3 + Vector2(-6.0, -2.0))
	_zoom(pt, 1.0)
	await _sample(pt, 1.5)
	await _snap(pt, "vis7_18_world_traces_z10")
	_zoom(pt, 2.0)
	mv.center_camera_on(c3 + Vector2(-19.0, -8.0))
	await _sample(pt, 0.5)
	await _snap(pt, "vis7_19_dam_z20")
	mv.center_camera_on(c3 + Vector2(1.0, -2.0))
	await _sample(pt, 0.5)
	await _snap(pt, "vis7_20_creep_vehicle_beacon_z20")
	_zoom(pt, 0.6)
	mv.center_camera_on(c3)
	await _sample(pt, 2.0)
	await _snap(pt, "vis7_21_minimap_creep_z06")
	var mm = _find_minimap(mv.get_tree().root)
	pt._log("vis7_world", wl != null and wl.traces != null and (wl._vehicles as Array).size() == 4,
		"world7 traces %d vehicles %d beacons, dam %d cells, creep cells painted %d" % [(wl._vehicles as Array).size() if wl != null else 0,
		(wl._beacons as Array).size() if wl != null else 0, dam.size(), n])
	pt._log("vis7_minimap", mm != null and int(mm.creep_cells) > 0, "minimap creep cells %d" % (int(mm.creep_cells) if mm != null else -1))


func _find_minimap(n: Node):
	if n.get_script() == Minimap:
		return n
	for c in n.get_children():
		var r = _find_minimap(c)
		if r != null:
			return r
	return null
