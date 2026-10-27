extends RefCounted
## G7 playtest flow (owner: THREAT7): Machine threat units in a real match (human_a vs machine, cfg.creep).
## 1. a packhunter pack forms and flanks a two-vehicle convoy from several sides;
## 2. a leech latches onto a strike APC and wrecks its parts;
## 3. a Weaver cocoons a soldier.
## The Machine side is not AI-run here, so the pack's think step is driven by the flow (Threats7._think).
## New threat sheets (assets/art/g7_threats2, g7_threats) are not wired into the entity layer yet (CR to LOOK7/ORCH):
## the units draw with the view's fallback until then.

const T = preload("res://sim/systems/threats7.gd")


func _steps(w: SimWorld, n: int, types: Array, think: Array = []) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if types.has(String(ev.type)):
				out.append(ev)
		if w.tick % 20 == 0:
			for id in think:
				if w.entities.has(int(id)):
					T._think(w, T.st(w), w.entities[int(id)])
	return out


func _show(pt, at: Vector2, secs: float = 0.8) -> void:
	pt._mv().center_camera_on(at)
	await pt._wait(secs)


func _hold(w: SimWorld, id: int) -> void:
	var e: Dictionary = w.entities[id]
	e.order = {"type": "hold"}
	SimWorld.HotState.touch(w, id)
	SimWorld.HotState.set_cd(w, id, 100000)


func run(pt) -> void:
	var cfg := SimWorld.default_config()
	cfg.sides[1].faction = "machine"
	cfg.sides[1].ai = false
	cfg.creep = true
	cfg.victory = "endless"
	var started: bool = pt.main.start_match(cfg)
	pt._log("threat7_match_started", started, "machine vs human_a, cfg.creep")
	if not started:
		return
	await pt._wait(1.5)
	var mv = pt._mv()
	var w: SimWorld = pt._w()
	mv.join_sim()
	var ex: PackedByteArray = w.fog[0].explored
	ex.fill(1)
	w.fog[0].explored = ex
	var hb = null
	for b in w.buildings_of(0):
		if hb == null or int(b.id) < int(hb.id):
			hb = b
	pt._log("threat7_human_base", hb != null, "")
	if hb == null:
		return
	var mid := Vector2(float(w.map.w), float(w.map.h)) * 0.5
	var at: Vector2 = hb.pos + (mid - Vector2(hb.pos)).normalized() * 14.0
	# 1. packhunters flank a convoy
	var convoy := []
	for i in 2:
		convoy.append(w.spawn_unit("mbt", 0, at + Vector2(float(i) * 3.0, 0)))
	for id in convoy:
		_hold(w, id)
	var pack := []
	for i in 5:
		pack.append(T.spawn(w, "g7_m_packhunter", 1, at + Vector2(-4.0 + float(i) * 0.8, 9.0)))
	var evs := _steps(w, 25, ["PackFormed", "PackhunterSwipe"], pack)
	var goals := []
	for id in pack:
		if w.entities.has(int(id)) and w.entities[int(id)].t7.get("goto") != null:
			goals.append(Vector2(w.entities[int(id)].t7.goto))
	var spread := goals.size() >= 3
	for i in goals.size():
		for j in range(i + 1, goals.size()):
			spread = spread and goals[i].distance_to(goals[j]) > 1.5
	var pk := 0
	for id in pack:
		if w.entities.has(int(id)):
			pk = maxi(pk, int(w.entities[int(id)].t7.get("pk", 0)))
	pt._log("threat7_pack_flank", pk > 0 and spread,
		"pack formed, %d separate flank goals" % goals.size())
	await _show(pt, at + Vector2(0, 3))
	await pt._shot("threat7_pack_flank")
	_steps(w, 200, [], pack)
	await _show(pt, at)
	await pt._shot("threat7_pack_contact")
	# 2. a leech on a strike APC
	var ap := at + Vector2(-12, -8)
	var apc := w.spawn_unit("g7_cn_strike_apc", 0, ap)
	SimWorld.Apc7.init_apc(w, w.entities[apc])
	_hold(w, apc)
	var le := T.spawn(w, "g7_m_leech", 1, ap + Vector2(1.0, 0))
	evs = _steps(w, 260, ["LeechLatched", "PartWrecked", "LeechDrill"])
	var latched := evs.filter(func(e): return String(e.type) == "LeechLatched").size()
	var drills := evs.filter(func(e): return String(e.type) == "LeechDrill").size()
	pt._log("threat7_leech", latched >= 1 and drills >= 1, "latched=%d drills=%d mg_front=%.2f" % [latched, drills,
		T.part(w.entities[apc], "mg_front") if w.entities.has(apc) else -1.0])
	await _show(pt, ap)
	await pt._shot("threat7_leech_on_apc")
	# 3. a Weaver cocoons a soldier
	T.allow_weavers(w, true)
	var wp := at + Vector2(10, -10)
	var wv := T.spawn(w, "g7_m_weaver", 1, wp)
	var sol := w.spawn_unit("rifleman", 0, wp + Vector2(4, 0))
	_hold(w, sol)
	evs = _steps(w, 40, ["Cocooned", "WebSpit"])
	pt._log("threat7_weaver_cocoon", wv >= 0 and evs.filter(func(e): return String(e.type) == "Cocooned").size() == 1
		and w.entities.has(sol) and T.cocooned(w.entities[sol]), "weaver=%d" % wv)
	await _show(pt, wp)
	await pt._shot("threat7_weaver_cocoon")
