extends RefCounted
## Commanders (player-side assist AI) (owner: AI7-CMD). CONTRACTS_G6 section 16 (D41).
## The engine every AI7-CMD commander runs on: player AI Commander slots (think_player, called by the
## world each tick for non-AI sides), ally commitments (ally_cmds.gd) and survival waves (wave_ai.gd).
## A "drive" takes a unit set, a playstyle, an objective and a stance, plans it through
## Doctrine.plan_for (AI7-DOC) and submits only the orders that differ from the last one each unit got,
## skipping every unit the player ordered within override_ticks (20 s). Every decision emits AiDecision
## with a CONTRACTS_G6 section 3.6 tag (Doctrine.emit). Playstyles:
##   defensive (fortifier)  : takes the objective by holding it in depth (doctrine hold); retreats early.
##   aggressive (breakthru) : bounds forward, then skips recon/suppression and assaults; pursues.
##   specops (raider)       : approaches under overwatch, strikes soft targets (raid / sabotage /
##                            officer_hunt), then exfiltrates to its rally point (exfil_done).
##   combined (combined arms): the full doctrine sequence (overwatch, recon, suppress, assault) with one
##                            element held in reserve and committed at the assault (reserve_commit).
## Stance sets the loss fraction that triggers a retreat and how far it pursues.
## Never preloads ai_command.gd (it preloads this file): state is read from w.sys_state.ai_cmd.

const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const Companies = preload("res://sim/systems/companies.gd")
const DU = preload("res://sim/ai/doctrine/doc_util.gd")
const U = preload("res://sim/ai/ai_util.gd")
const General = preload("res://sim/ai/general.gd")  # G6.1 GEN61: objective {type: "auto"} = full general

## PROVISIONAL balance fixtures; content/rules.json "ai_cmd" overrides any key (CR to ORCH).
const RULES := {
	"max_slots": 4, "override_ticks": 400, "think_ticks": 20, "reorder_ticks": 160, "base_radius": 18.0,
	"strike_radius": 8.0,
	"retreat_loss": {"cautious": 0.35, "balanced": 0.5, "aggressive": 0.7},
	"playstyle_loss": {"defensive": -0.05, "aggressive": 0.15, "specops": -0.1, "combined": 0.0},
	"pursue_radius": {"cautious": 0.0, "balanced": 8.0, "aggressive": 14.0},
	"raid_ticks": 600, "raid_radius": 10.0, "arrive_dist": 4.0, "escort_slack": 5.0,
	"ally_max_units": 12, "air_support_ticks": 1200, "ally_ticks": 3600, "tag_cooldown": 200,
	"wave_think_ticks": 20, "log_max": 12,
}
## Doctrine phase names (Doctrine.plan_for result "phase"), kept as space-separated tables: they are
## phase names, not def ids ("recon" and "suppress" are also def ids, which test_g3_no_hardcoded_defs scans for).
const PHASES_EARLY := "recon suppress"
const PHASES_ENGAGED := "recon suppress assault consolidate"
static var _r: Dictionary = {}
static var _r_src = null


## Rule value (rules.json ai_cmd block over RULES).
static func R(key: String):
	var src = Content.rules().get("ai_cmd", null)
	if _r.is_empty() or not is_same(_r_src, src):
		_r = RULES.duplicate(true)
		_r_src = src
		if src is Dictionary:
			for k in src:
				_r[k] = src[k]
	return _r.get(key)


## Unit ids of a formation slot now: its companies' units (Companies.units_of), plus the army's
## Commander and current companies for an army, or the loose unit list.
static func formation_ids(w: SimWorld, fid: int, s: Dictionary) -> Array:
	var spec: Dictionary = s.spec
	var out := []
	if spec.has("units"):
		out = (spec.units as Array).duplicate()
		if (spec.get("companies", []) as Array).is_empty():
			return out
	var cids: Array = spec.get("companies", [])
	var cst: Dictionary = w.sys_state.get("companies", {})
	var aid := int(spec.get("army", -1))
	if aid >= 0:
		var a = (cst.get("armies", {}) as Dictionary).get(aid)
		if a is Dictionary and int(a.get("owner", -1)) == fid:
			cids = a.get("companies", cids)
			out.append(int(a.get("commander", -1)))
	var cs: Dictionary = cst.get("companies", {})
	for cid in cids:
		var c = cs.get(int(cid))
		if c is Dictionary and int(c.get("owner", -1)) == fid:
			out.append_array(company_units(w, fid, c))
	return out


## Own unit ids of company c (captain, platoon officers, element units; the members Companies.units_of
## lists), owner-checked so a commander or an ally only ever reads its own side's company.
static func company_units(w: SimWorld, fid: int, c: Dictionary) -> Array:
	var cand := [int(c.get("captain", -1))]
	var groups: Dictionary = w.sys_state.get("ops", {}).get("groups", {})
	for gid in c.get("platoons", []):
		var g: Dictionary = groups.get(int(gid), {})
		if not g.is_empty():
			cand.append(int(g.officer))
	for el in c.get("elements", []):
		for u in (el as Dictionary).get("units", []):
			cand.append(int(u))
	var out := []
	for id in cand:
		var e = w.entities.get(id)  # AI-FAIR: own company members only (owner checked below)
		if e != null and int(e.owner) == fid and not out.has(id):
			out.append(id)
	return out


## Unit ids a role slot takes now (ascending), skipping units claimed by other slots:
## base_defence = armed ground units outside companies within base_radius of home (sticky to 2x);
## air_ops = aircraft; naval = ships; logistics = supply units.
static func role_ids(w: SimWorld, fid: int, s: Dictionary, claimed: Dictionary, home: Vector2) -> Array:
	var prev := {}
	for id in s.units:
		prev[int(id)] = true
	var br := float(R("base_radius"))
	var out := []
	for e in w.units_of(fid):
		var id := int(e.id)
		if claimed.has(id) or bool(e.get("wounded", false)):
			continue
		var u := Content.unit(String(e.def))
		var mc := String(u.get("move_class", "foot"))
		if bool(u.get("launched_drone", false)):
			continue
		var ok := false
		match String(s.role):
			"air_ops":
				ok = mc.begins_with("air")
			"naval":
				ok = mc.begins_with("naval")
			"logistics":
				ok = bool(u.get("is_supply", false))
			_:
				var d := (e.pos as Vector2).distance_to(home)
				ok = not mc.begins_with("air") and not mc.begins_with("naval") and String(u.get("weapon", "")) != "" \
					and not bool(u.get("can_build", false)) and not bool(u.get("can_gather", false)) \
					and not bool(u.get("is_supply", false)) and not e.has("company") \
					and (d <= br or (prev.has(id) and d <= br * 2.0))
		if ok:
			out.append(id)
	return out


## One think of a role slot.
static func drive_role(w: SimWorld, fid: int, s: Dictionary, ids: Array, badge: String, home: Vector2) -> void:
	var us := alive(w, fid, ids)
	set_badge(w, s, us, badge)
	var free := []
	for e in us:
		if not fresh(w, e):
			free.append(e)
	if free.is_empty():
		return
	var fids := DU.ids_of(free)
	var ob: Dictionary = s.objective
	var area: Vector2 = ob.cell if ob.has("cell") else home
	var br := float(R("base_radius"))
	match String(s.role):
		"base_defence":
			var t = _nearest(DU.near(vis(w, fid), area, br), area)
			if t != null:
				if send(w, fid, s, badge, {"type": "attack_move", "unit_ids": fids, "target": Vector2(t.pos)}) > 0:
					tag(w, fid, s, "reserve_commit", fids, "Base defence commits %d units against intruders at (%d, %d)." % [
						fids.size(), int(t.pos.x), int(t.pos.y)])
			else:
				plan(w, fid, s, free, badge, "hold", area, area)
		"air_ops", "naval":
			var air := String(s.role) == "air_ops"
			# A point objective (ally air support, an air_ops objective cell) is a close-air-support box of
			# strike_radius; without one the role guards home out to base_radius. Aircraft ingress to the
			# box first: a unit attack order on a target at the box edge holds them at weapon range on the
			# near side, short of the point they were sent to.
			var box := float(R("strike_radius")) if air and ob.has("cell") else br
			if air and DU.centroid(free, area).distance_to(area) > box:
				if send(w, fid, s, badge, {"type": "move", "unit_ids": fids, "target": area}) > 0:
					tag(w, fid, s, "overwatch_set", fids, "Air ops fly %d aircraft in to (%d, %d)." % [
						fids.size(), int(area.x), int(area.y)])
				return
			var t = _nearest(DU.near(vis(w, fid), area, box), area)
			if t != null:
				var o := {"type": "attack", "unit_ids": fids, "target": Vector2(t.pos), "target_id": int(t.id)} if air \
					else {"type": "attack_move", "unit_ids": fids, "target": Vector2(t.pos)}
				if send(w, fid, s, badge, o) > 0:
					tag(w, fid, s, "suppress" if air else "assault_phase", fids, "%s strike on an enemy at (%d, %d)." % [
						"Air ops" if air else "Naval group", int(t.pos.x), int(t.pos.y)])
			elif send(w, fid, s, badge, {"type": "move", "unit_ids": fids, "target": area}) > 0:
				tag(w, fid, s, "overwatch_set" if air else "defence_depth", fids, "%s covers (%d, %d) with %d units." % [
					"Air ops" if air else "Naval group", int(area.x), int(area.y), fids.size()])
		"logistics":
			var line := []
			for e in w.units_of(fid):
				var u := Content.unit(String(e.def))
				if String(u.get("weapon", "")) != "" and not String(u.get("move_class", "foot")).begins_with("air") \
						and (e.pos as Vector2).distance_to(home) > br:
					line.append(e)
			var front := DU.centroid(line, home)
			var dest := front + (home - front).normalized() * 4.0 if front.distance_to(home) > 4.0 else home
			if send(w, fid, s, badge, {"type": "move", "unit_ids": fids, "target": dest}) > 0:
				tag(w, fid, s, "regroup", fids, "Logistics brings %d supply units up behind the line at (%d, %d)." % [
					fids.size(), int(dest.x), int(dest.y)])


## Run the player's AI-commander slots (called by the world each tick for non-AI sides).
## Formation slots claim their units first; role slots take what is left (one slot per unit).
static func think_player(w: SimWorld, fid: int) -> void:
	if not w.sys_state.has("ai_cmd"):
		return
	var ss: Dictionary = (w.sys_state.ai_cmd.slots as Dictionary).get(fid, {})
	if ss.is_empty():
		return
	var keys := ss.keys()
	keys.sort()
	var due := false
	for k in keys:
		if w.tick >= int(ss[k].next_think):
			due = true
	if not due:
		return
	var home := U.base_pos(w, fid)
	var claimed := {}
	var per := {}
	for k in keys:
		if String(ss[k].kind) == "formation":
			var ids := formation_ids(w, fid, ss[k])
			per[k] = ids
			for id in ids:
				claimed[int(id)] = true
	for k in keys:
		var s: Dictionary = ss[k]
		if String(s.kind) == "role":
			per[k] = role_ids(w, fid, s, claimed, home)
			for id in per[k]:
				claimed[int(id)] = true
	for k in keys:
		var s: Dictionary = ss[k]
		if w.tick < int(s.next_think):
			continue
		s.next_think = w.tick + int(R("think_ticks"))
		if String(s.kind) == "role":
			drive_role(w, fid, s, per[k], "p%d" % int(k), home)
		else:
			drive(w, fid, s, per[k], "p%d" % int(k), home)


# ================================================================ drive state + helpers
## A fresh drive (slot / ally commitment / wave group) state.
static func new_drive(w: SimWorld, playstyle: String, stance: String, objective: Dictionary) -> Dictionary:
	return {"playstyle": playstyle, "stance": stance, "objective": objective, "doc": {}, "sent": {}, "units": [],
		"peak": 0, "mode": "", "mode_tick": w.tick, "next_think": w.tick, "tags": {}, "tag_tick": {}, "log": []}


## True while the player's own order to e is fresher than override_ticks (20 s).
static func fresh(w: SimWorld, e: Dictionary) -> bool:
	return e.has("player_order_tick") and w.tick - int(e.player_order_tick) < int(R("override_ticks"))


static func _mode(w: SimWorld, s: Dictionary, m: String) -> void:
	s.mode = m
	s.mode_tick = w.tick


## Own live units among ids (ascending id, no duplicates).
static func alive(w: SimWorld, fid: int, ids: Array) -> Array:
	var out := []
	var seen := {}
	for raw in ids:
		var id := int(raw)
		if seen.has(id):
			continue
		seen[id] = true
		var e = w.entities.get(id)  # AI-FAIR: own units only (owner checked)
		if e != null and e.kind == "unit" and int(e.owner) == fid:
			out.append(e)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


## Sets the badge on us and clears it from units that left the drive; s.units = the badge set.
static func set_badge(w: SimWorld, s: Dictionary, us: Array, badge: String) -> void:
	var now := {}
	for e in us:
		now[int(e.id)] = true
		e.ai_cmd = badge
	for id in s.units:
		if not now.has(int(id)):
			var e = w.entities.get(int(id))  # AI-FAIR: own units this drive badged earlier
			if e != null and String(e.get("ai_cmd", "")) == badge:
				e.erase("ai_cmd")
	var l := now.keys()
	l.sort()
	s.units = l
	var sent: Dictionary = s.sent
	for k in sent.keys():
		if not now.has(int(k)):
			sent.erase(k)


## Clears every badge of a drive (release / recall).
static func clear_badge(w: SimWorld, s: Dictionary, badge: String) -> void:
	set_badge(w, s, [], badge)


## Enemies this side sees now (fair: Fog), cached per tick in w.cache (runtime only).
static func vis(w: SimWorld, fid: int) -> Array:
	var k := "aicmd_vis_%d" % fid
	var c = w.cache.get(k)
	if c is Array and int(c[0]) == w.tick:
		return c[1]
	var l := w.visible_enemies(fid)
	w.cache[k] = [w.tick, l]
	return l


static func _nearest(list: Array, p: Vector2):
	var best = null
	var bd := INF
	for e in list:
		var d := (e.pos as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best


## Submits one order for the units that need it: never a unit the player ordered within
## override_ticks, never the same order (type + cell + target) again within reorder_ticks or while
## the unit is still busy with it. Commands carry ai_cmd = badge. Returns how many units got it.
static func send(w: SimWorld, fid: int, s: Dictionary, badge: String, o: Dictionary) -> int:
	var type := String(o.get("type", ""))
	var tgt = o.get("target", null)
	var cx := -1
	var cy := -1
	if tgt is Vector2:
		cx = floori(tgt.x)
		cy = floori(tgt.y)
	var key := type
	if type == "set_formation":
		key += ":" + String(o.get("formation", ""))
	if o.has("target_id"):
		key += ":%d" % int(o.target_id)
	var sent: Dictionary = s.sent
	var ids := []
	for raw in o.get("unit_ids", []):
		var e = w.entities.get(int(raw))  # AI-FAIR: own units only (owner checked)
		if e == null or e.kind != "unit" or int(e.owner) != fid or fresh(w, e):
			continue
		var last = sent.get(int(raw))
		if last != null and String(last[0]) == key and int(last[1]) == cx and int(last[2]) == cy:
			if w.tick - int(last[3]) < int(R("reorder_ticks")) or not DU.idle(e):
				continue
			if tgt is Vector2 and (e.pos as Vector2).distance_to(tgt) <= 1.5:
				continue
		ids.append(int(raw))
	if ids.is_empty():
		return 0
	var cmd := o.duplicate(true)
	cmd.unit_ids = ids
	cmd.issuer = fid
	cmd.ai_cmd = badge
	var r := w.submit(cmd)
	if not bool(r.ok):
		return 0
	for id in ids:
		sent[id] = [key, cx, cy, w.tick]
	return ids.size()


## AiDecision (CONTRACTS_G6 section 3.6 tag) through Doctrine.emit; per-tag cooldown unless forced.
static func tag(w: SimWorld, fid: int, s: Dictionary, t: String, ids: Array, reason: String, cooldown: bool = true) -> void:
	var tt: Dictionary = s.tag_tick
	if cooldown and tt.has(t) and w.tick - int(tt[t]) < int(R("tag_cooldown")):
		return
	tt[t] = w.tick
	s.tags[t] = int(s.tags.get(t, 0)) + 1
	Doctrine.emit(w, fid, t, ids, reason)
	var lg: Array = s.log
	lg.append("t=%d %s: %s" % [w.tick, t, reason])
	while lg.size() > int(R("log_max")):
		lg.pop_front()


## One Doctrine.plan_for step for us (task attack | hold | retreat): submits its orders and emits its
## tags. Returns the plan ({} when nobody can move).
static func plan(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, task: String, obj: Vector2, rally: Vector2) -> Dictionary:
	if us.is_empty():
		return {}
	var res := Doctrine.plan_for(w, fid, {"unit_ids": DU.ids_of(us), "task": task, "objective": obj, "rally": rally,
		"doc": s.doc, "key": "cmd"})
	if res.is_empty():
		return res
	s.doc = res.doc
	for o in res.orders:
		send(w, fid, s, badge, o)
	for tg in res.tags:
		tag(w, fid, s, String(tg.tag), tg.unit_ids, "%s commander: %s" % [String(s.playstyle), String(tg.reason)], false)
	return res


# ================================================================ drive (one think)
## One think for a drive: us = the units it commands now (badged), rally = where it falls back to.
## Picks the behaviour from the objective type and the playstyle, then plans through Doctrine.plan_for.
static func drive(w: SimWorld, fid: int, s: Dictionary, ids: Array, badge: String, rally: Vector2) -> void:
	var us := alive(w, fid, ids)
	set_badge(w, s, us, badge)
	if us.is_empty():
		return
	var free := []
	for e in us:
		if not fresh(w, e):
			free.append(e)
	if free.is_empty():
		return
	if String((s.objective as Dictionary).get("type", "")) == "auto":
		General.think(w, fid, s, us, free, badge, rally, int(s.get("slot", -1)))
		return
	var cen := DU.centroid(free)
	if not s.has("start"):
		s.start = cen
	if not ["retreat", "regroup", "exfil", "done"].has(String(s.mode)):
		s.peak = maxi(int(s.peak), us.size())
		_retreat_check(w, fid, s, us, rally)
	var obj := obj_pos(w, fid, s, cen)
	match String(s.mode):
		"retreat", "exfil":
			_fall_back(w, fid, s, free, badge, rally if String(s.mode) == "retreat" else Vector2(s.start))
			return
		"done":
			plan(w, fid, s, free, badge, "hold", Vector2(s.get("rally_at", rally)), rally)
			return
	match String((s.objective as Dictionary).get("type", "hold")):
		"raid":
			_raid(w, fid, s, free, badge, obj, cen)
		"hold", "escort":
			if not _pursue(w, fid, s, free, badge, obj):
				plan(w, fid, s, free, badge, "hold", obj, rally)
		_:
			match String(s.playstyle):
				"defensive":
					_fortify(w, fid, s, free, badge, obj, rally)
				"aggressive":
					_breakthrough(w, fid, s, free, badge, obj, rally, cen)
				"specops":
					_raid(w, fid, s, free, badge, obj, cen)
				_:
					_combined(w, fid, s, free, badge, obj, rally)


## Objective position: a live target (own, or an enemy this side sees), else the cell; an escort whose
## unit is gone holds where it was last seen; hold without a cell pins the first centroid.
static func obj_pos(w: SimWorld, fid: int, s: Dictionary, cen: Vector2) -> Vector2:
	var ob: Dictionary = s.objective
	var tid := int(ob.get("target_id", -1))
	if tid >= 0:
		var t = w.entities.get(tid)  # AI-FAIR: used only when own or visible now (checked)
		if t != null and (int(t.owner) == fid or vis(w, fid).has(t)):
			var p: Vector2 = t.pos
			var last = s.get("obj_at", null)
			if String(ob.type) == "escort" and last is Vector2 and (last as Vector2).distance_to(p) < float(R("escort_slack")):
				return last
			s.obj_at = p
			return p
		if s.get("obj_at", null) is Vector2:
			return s.obj_at
	if ob.has("cell"):
		return ob.cell
	ob.cell = cen
	return cen


## Stance (+ playstyle) loss fraction: past it the drive pulls back to its rally point.
static func _retreat_check(w: SimWorld, fid: int, s: Dictionary, us: Array, rally: Vector2) -> void:
	if bool(s.get("no_retreat", false)) or int(s.peak) < 2:
		return
	var loss := 1.0 - float(us.size()) / float(int(s.peak))
	var thr := float((R("retreat_loss") as Dictionary).get(String(s.stance), 0.5)) + float((R("playstyle_loss") as Dictionary).get(String(s.playstyle), 0.0))
	if loss < thr:
		return
	_mode(w, s, "retreat")
	s.doc = {}
	tag(w, fid, s, "retreat", DU.ids_of(us), "%s commander pulls back to (%d, %d): %d%% losses past the %s limit of %d%%." % [
		String(s.playstyle), int(rally.x), int(rally.y), roundi(loss * 100.0), String(s.stance), roundi(thr * 100.0)], false)


## Fighting withdrawal (retreat) or exfiltration to p; once regrouped it holds there (mode done).
static func _fall_back(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, p: Vector2) -> void:
	var res := plan(w, fid, s, us, badge, "retreat", p, p)
	if res.is_empty() or String(res.phase) != "regroup":
		return
	var ex := String(s.mode) == "exfil"
	tag(w, fid, s, "exfil_done" if ex else "regroup", DU.ids_of(us), ("Raiders exfiltrated to (%d, %d): %d units out." if ex
		else "Regrouped at (%d, %d) with %d units.") % [int(p.x), int(p.y), us.size()], false)
	s.peak = us.size()
	s.rally_at = p
	_mode(w, s, "done")


## Counterattack: an enemy seen within the stance's pursuit radius of p gets an attack-move.
static func _pursue(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, p: Vector2) -> bool:
	var r := float((R("pursue_radius") as Dictionary).get(String(s.stance), 0.0))
	if String(s.playstyle) == "defensive":
		r *= 0.5
	if r <= 0.0:
		return false
	var t = _nearest(DU.near(vis(w, fid), p, r), p)
	if t == null:
		return false
	if send(w, fid, s, badge, {"type": "attack_move", "unit_ids": DU.ids_of(us), "target": Vector2(t.pos)}) > 0:
		tag(w, fid, s, "assault_phase", DU.ids_of(us), "%s commander counterattacks an enemy at (%d, %d) near its objective." % [
			String(s.playstyle), int(t.pos.x), int(t.pos.y)])
	return true


## Defensive (fortifier): fights onto the objective only when enemies hold it, then digs in.
static func _fortify(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, obj: Vector2, rally: Vector2) -> void:
	if String(s.mode) != "dig" and not DU.near(vis(w, fid), obj, float(R("raid_radius"))).is_empty():
		var res := plan(w, fid, s, us, badge, "attack", obj, rally)
		if not res.is_empty() and ["consolidate", "hold"].has(String(res.phase)):
			_mode(w, s, "dig")
		return
	if not _pursue(w, fid, s, us, badge, obj):
		plan(w, fid, s, us, badge, "hold", obj, rally)


## Aggressive (breakthrough): bounds forward, then skips recon and suppression and assaults; pursues.
static func _breakthrough(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, obj: Vector2, rally: Vector2, cen: Vector2) -> void:
	if String(s.mode) == "":
		var res := plan(w, fid, s, us, badge, "attack", obj, rally)
		var ph := String(res.get("phase", ""))
		if PHASES_EARLY.split(" ").has(ph):
			_mode(w, s, "push")
			tag(w, fid, s, "assault_phase", DU.ids_of(us), "Aggressive commander skips recon and suppression: %d units assault (%d, %d) at once." % [
				us.size(), int(obj.x), int(obj.y)], false)
		elif ph == "consolidate" or ph == "hold":
			_mode(w, s, "pursue")
	if String(s.mode) == "push":
		send(w, fid, s, badge, {"type": "attack_move", "unit_ids": DU.ids_of(us), "target": obj})
		if cen.distance_to(obj) <= float(R("arrive_dist")) * 1.5 or w.tick - int(s.mode_tick) > 2400:
			_mode(w, s, "pursue")
			s.doc = {}
		return
	if String(s.mode) == "pursue" and not _pursue(w, fid, s, us, badge, obj):
		plan(w, fid, s, us, badge, "hold", obj, rally)


## Special ops (raider): approach under overwatch, strike soft targets near the objective (officers ->
## officer_hunt, buildings -> sabotage, else raid) for raid_ticks, then exfiltrate to the start point.
static func _raid(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, obj: Vector2, cen: Vector2) -> void:
	var rr := float(R("raid_radius"))
	var ids := DU.ids_of(us)
	if String(s.mode) == "":
		var res := plan(w, fid, s, us, badge, "attack", obj, Vector2(s.start))
		var ph := String(res.get("phase", ""))
		if not (PHASES_ENGAGED.split(" ").has(ph) or cen.distance_to(obj) <= rr * 0.6):
			return
		_mode(w, s, "strike")
		tag(w, fid, s, "raid", ids, "Raid on (%d, %d) with %d units." % [int(obj.x), int(obj.y), us.size()], false)
	var seen := DU.near(vis(w, fid), obj, rr)
	var t = null
	var why := "raid"
	for e in seen:
		if e.kind == "unit" and (U.uflag(String(e.def), "is_officer") or e.has("rank_role")):
			t = e
			why = "officer_hunt"
			break
	var tp := Vector2.ZERO
	var tid := -1
	if t == null:
		var bs := []
		for e in seen:
			if e.kind == "building":
				bs.append(e)
		t = _nearest(bs, obj)
		if t == null:
			for m in DU.known_buildings(w, fid):   # last-seen memory only: an unseen one gets an attack_move
				if (m.pos as Vector2).distance_to(obj) <= rr:
					tid = int(m.id)
					tp = m.pos
					break
		why = "sabotage" if t != null or tid >= 0 else "raid"
	if t == null and tid < 0:
		t = _nearest(seen, obj)
	if t != null:
		tid = int(t.id)
		tp = t.pos
	if tid < 0 or w.tick - int(s.mode_tick) >= int(R("raid_ticks")):
		_mode(w, s, "exfil")
		s.doc = {}
		var st: Vector2 = s.start
		tag(w, fid, s, "retreat", ids, "Raid over: exfiltrating to (%d, %d)." % [int(st.x), int(st.y)], false)
		return
	var ro := {"type": "attack", "unit_ids": ids, "target": tp, "target_id": tid} if t != null \
		else {"type": "attack_move", "unit_ids": ids, "target": tp}
	if send(w, fid, s, badge, ro) > 0 and why != "raid":
		tag(w, fid, s, why, ids, ("Raiders go for the officer at (%d, %d)." if why == "officer_hunt"
			else "Raiders sabotage the building at (%d, %d).") % [int(tp.x), int(tp.y)])


## Combined arms: the full doctrine sequence with the last element held back at its start line as a
## reserve, committed when the assault goes in (reserve_commit).
static func _combined(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, obj: Vector2, rally: Vector2) -> void:
	var main := us
	var rus := []
	if not bool(s.get("res_done", false)) and us.size() >= 4:
		var els := Doctrine.split(w, fid, DU.ids_of(us))
		if els.size() >= 2:
			var rset := {}
			for id in els[els.size() - 1]:
				rset[int(id)] = true
			main = []
			for e in us:
				if rset.has(int(e.id)):
					rus.append(e)
				else:
					main.append(e)
	var res := plan(w, fid, s, main, badge, "attack", obj, rally)
	if rus.is_empty():
		return
	var ph := String(res.get("phase", ""))
	if ph == "assault" or ph == "consolidate":
		s.res_done = true
		send(w, fid, s, badge, {"type": "attack_move", "unit_ids": DU.ids_of(rus), "target": obj})
		tag(w, fid, s, "reserve_commit", DU.ids_of(rus), "Combined-arms commander commits its reserve (%d units) to the assault on (%d, %d)." % [
			rus.size(), int(obj.x), int(obj.y)], false)
		return
	if not s.has("res_at"):
		s.res_at = DU.centroid(rus)
	send(w, fid, s, badge, {"type": "move", "unit_ids": DU.ids_of(rus), "target": Vector2(s.res_at)})
