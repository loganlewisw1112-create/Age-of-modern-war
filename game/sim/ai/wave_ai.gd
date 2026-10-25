extends RefCounted
## WaveAI (survival attacker) (owner: AI7-CMD). CONTRACTS_G6 section 15, section 16.
## Commands MODES6's survival waves (w.sys_state.waves: {attacker, defender, waves: [{index, units,
## companies, spawn, target, ...}]}) with the same doctrine as every AI (Doctrine.plan_for through the
## Commanders engine). Each wave is one drive; the doctrine escalates with the wave index (wave_tiers):
##   tier "aggressive" (waves 1-2): bound forward, then a straight assault and pursuit;
##   tier "combined"   (waves 3-5): the full combined-arms sequence with a reserve committed at the assault;
##   tier "raid"       (wave 6+)  : combined arms plus a special-ops element raiding the flank.
## Waves never retreat (no_retreat); when an objective is taken the wave moves on to the nearest enemy
## building this side has seen (fog memory: fair). Wave units carry e.ai_cmd = "wave".
## Called by AiCommand.tick for the attacker side with st = its w.ai_state[fid] (or, when it has none,
## w.sys_state.ai_cmd.wave[fid]); its state is st.waves = {ver, groups: {index: drive}, next_think}.

const Commanders = preload("res://sim/ai/commanders.gd")
const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const DU = preload("res://sim/ai/doctrine/doc_util.gd")

## [first wave index, tier] ascending; content/rules.json ai_cmd.wave_tiers overrides.
const WAVE_TIERS := [[1, "aggressive"], [3, "combined"], [6, "raid"]]


## Doctrine tier for wave idx.
static func tier_for(idx: int) -> String:
	var tiers = Commanders.R("wave_tiers")
	if not (tiers is Array):
		tiers = WAVE_TIERS
	var out := "aggressive"
	for t in tiers:
		if idx >= int(t[0]):
			out = String(t[1])
	return out


## The wave's objective: its target (MODES6: nearest defender HQ), else the defender's start point.
static func target_of(w: SimWorld, _wv: Dictionary, wave: Dictionary) -> Vector2:
	var t = wave.get("target", null)
	if t is Vector2:
		return t
	# no published target: the map centre (the attacker does not read the defender's start point)
	return Vector2(float(w.map.w) * 0.5, float(w.map.h) * 0.5)


static func _new_group(w: SimWorld, fid: int, wv: Dictionary, wave: Dictionary, idx: int, us: Array) -> Dictionary:
	var tier := tier_for(idx)
	var tgt := target_of(w, wv, wave)
	var g := Commanders.new_drive(w, "aggressive" if tier == "aggressive" else "combined", "aggressive",
		{"type": "take", "cell": tgt, "target_id": -1})
	g.no_retreat = true
	g.index = idx
	g.tier = tier
	var ids := DU.ids_of(us)
	if tier == "raid" and us.size() >= 6:
		var els := Doctrine.split(w, fid, ids)
		if els.size() >= 3:
			g.raiders = (els[els.size() - 1] as Array).duplicate()
			var cen := DU.centroid(us)
			var dir := (tgt - cen).normalized() if tgt.distance_to(cen) > 1.0 else Vector2.RIGHT
			var rc := tgt + Vector2(-dir.y, dir.x) * 8.0
			rc = Vector2(clampf(rc.x, 1.0, float(w.map.w) - 2.0), clampf(rc.y, 1.0, float(w.map.h) - 2.0))
			g.raid = Commanders.new_drive(w, "specops", "aggressive", {"type": "raid", "cell": rc, "target_id": -1})
	Commanders.tag(w, fid, g, "reserve_commit", ids, "Wave %d (%d units, %d companies, %s doctrine) commits toward (%d, %d)." % [
		idx, us.size(), (wave.get("companies", []) as Array).size(), tier, int(tgt.x), int(tgt.y)], false)
	return g


## Objective taken (consolidated / holding / nothing left to pursue): on to the nearest enemy building
## this side has seen.
static func _retarget(w: SimWorld, fid: int, g: Dictionary, us: Array) -> void:
	var ph := String((g.doc as Dictionary).get("phase", ""))
	if not (ph == "consolidate" or ph == "hold"):
		return
	var cen := DU.centroid(us)
	var best = null
	var bd := INF
	for m in DU.known_buildings(w, fid):   # last-seen memory (fog drops a building seen destroyed)
		var d := (m.pos as Vector2).distance_to(cen)
		if d < bd:
			bd = d
			best = m
	if best == null or (best.pos as Vector2).distance_to(Vector2(g.objective.cell)) <= 3.0:
		return
	g.objective.cell = Vector2(best.pos)
	g.doc = {}
	g.mode = ""
	g.mode_tick = w.tick


static func _drive_wave(w: SimWorld, fid: int, wave: Dictionary, g: Dictionary, us: Array) -> void:
	var rset := {}
	for id in g.get("raiders", []):
		rset[int(id)] = true
	var main := []
	var rus := []
	for e in us:
		if rset.has(int(e.id)) and g.has("raid"):
			rus.append(e)
		else:
			main.append(e)
	var home: Vector2 = wave.get("spawn", Vector2(g.objective.cell))
	if not main.is_empty():
		_retarget(w, fid, g, main)
		Commanders.drive(w, fid, g, DU.ids_of(main), "wave", home)
	if not rus.is_empty():
		Commanders.drive(w, fid, g.raid, DU.ids_of(rus), "wave", home)


## Command survival waves.
static func think(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary) -> void:
	var wv = w.sys_state.get("waves")
	if not (wv is Dictionary) or int(wv.get("attacker", -1)) != fid:
		return
	if not st.has("waves"):
		st["waves"] = {"ver": 1, "groups": {}, "next_think": w.tick}
	var ws: Dictionary = st.waves
	if w.tick < int(ws.next_think):
		return
	ws.next_think = w.tick + int(Commanders.R("wave_think_ticks"))
	var groups: Dictionary = ws.groups
	var live := {}
	for wave in wv.get("waves", []):
		if not (wave is Dictionary):
			continue
		var idx := int(wave.get("index", 0))
		var us := Commanders.alive(w, fid, wave.get("units", []))
		if us.is_empty():
			continue
		live[idx] = true
		if not groups.has(idx):
			groups[idx] = _new_group(w, fid, wv, wave, idx, us)
		_drive_wave(w, fid, wave, groups[idx], us)
	for k in groups.keys():
		if not live.has(int(k)):
			groups.erase(k)
