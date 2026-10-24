extends RefCounted
## Triggers (owner: MAPIO): scenario trigger runtime. CONTRACTS_G4 section 5.
## Definitions are static map data (w.map.triggers, from the .rtsmap file):
##   {id?, name?, when: {type, ...} | [{..}, {..}] (all must hold), then: [{type, ...}] | {..}, once: true}
## when: time_reached{t (seconds) | ticks}, unit_in_region{region, owner_slot (-1/absent = anyone), count=1},
##       entity_destroyed{tag}, stage_reached{slot, stage}, units_below{slot, n} (cargo counts).
## then: message{text}, spawn{slot, def, count=1, region}, reveal{slot, region}, grant{slot, res, amount},
##       win{slot}, lose{slot}, ai_target{slot, region}.
## once (default true) fires at most once; once=false fires on every false->true edge of `when`.
## Evaluated every EVERY ticks (phase PHASE), triggers in file order, actions in list order.
## Runtime state (saved): w.sys_state.triggers = {fired: [0/1 per trigger], prev: [0/1], tags: {tag: {ids, owners}},
##   reveals: [{fid, rect}], ai_targets: {fid: Vector2}}. It exists only for file maps (MapIO.place_entities).
## Slots are map-file player slots; they map to sides through cfg.sides[i].slot (default slot i).

const Victory = preload("res://sim/systems/victory.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Movement = preload("res://sim/systems/movement.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")

const EVERY := 5
const PHASE := 2
const MAX_SPAWN := 200
const WHEN_TYPES := ["time_reached", "unit_in_region", "entity_destroyed", "stage_reached", "units_below"]
const THEN_TYPES := ["message", "spawn", "reveal", "grant", "win", "lose", "ai_target"]


static func init_state(w: SimWorld, tags: Dictionary) -> void:
	var n := (w.map.get("triggers", []) as Array).size()
	var z := []
	z.resize(n)
	z.fill(0)
	w.sys_state["triggers"] = {"fired": z.duplicate(), "prev": z.duplicate(), "tags": tags,
		"reveals": [], "ai_targets": {}}


static func state(w: SimWorld):
	return w.sys_state.get("triggers")


## Scenario attack point for the AI (ai_target action), or null.
static func ai_target(w: SimWorld, fid: int):
	var st = state(w)
	if st == null:
		return null
	return st.ai_targets.get(fid)


static func fid_of_slot(w: SimWorld, slot: int) -> int:
	var sides: Array = w.cfg.get("sides", [])
	for i in sides.size():
		if int(sides[i].get("slot", i)) == slot:
			return i
	return SimWorld.NEUTRAL


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = state(w)
	if st == null:
		return
	if not st.reveals.is_empty() and (w.tick % Fog.RECOMPUTE_EVERY == 1 or w.tick % Fog.RECOMPUTE_EVERY == 3):
		for rv in st.reveals:
			_apply_reveal(w, int(rv.fid), rv.rect)
	if w.tick % EVERY != PHASE or w.match_state.get("ended", false):
		return
	var defs: Array = w.map.get("triggers", [])
	for i in mini(defs.size(), (st.fired as Array).size()):
		var d = defs[i]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var once := bool(d.get("once", true))
		if once and int(st.fired[i]) == 1:
			continue
		var now := _when(w, d.get("when", []))
		var was := int(st.prev[i]) == 1
		st.prev[i] = 1 if now else 0
		if not now or (not once and was):
			continue
		st.fired[i] = 1
		w.emit("TriggerFired", {"trigger": i, "name": String(d.get("name", d.get("id", "")))})
		var acts = d.get("then", [])
		if typeof(acts) == TYPE_DICTIONARY:
			acts = [acts]
		for a in acts:
			if typeof(a) == TYPE_DICTIONARY:
				_act(w, i, a)
		if w.match_state.get("ended", false):
			return


static func _when(w: SimWorld, cond) -> bool:
	if typeof(cond) == TYPE_DICTIONARY:
		return _cond(w, cond)
	if typeof(cond) != TYPE_ARRAY or (cond as Array).is_empty():
		return false
	for c in cond:
		if typeof(c) != TYPE_DICTIONARY or not _cond(w, c):
			return false
	return true


static func _rect_of(w: SimWorld, rid) -> Variant:
	return Victory.region_rect(w, String(rid))


static func _cond(w: SimWorld, c: Dictionary) -> bool:
	match String(c.get("type", "")):
		"time_reached":
			var at := int(c.ticks) if c.has("ticks") else roundi(float(c.get("t", 0)) * SimWorld.TICK_RATE)
			return w.tick >= at
		"unit_in_region":
			var rect = _rect_of(w, c.get("region", ""))
			if rect == null:
				return false
			var slot := int(c.get("owner_slot", -1))
			var fid := fid_of_slot(w, slot) if slot >= 0 else SimWorld.NEUTRAL
			if slot >= 0 and fid == SimWorld.NEUTRAL:
				return false
			var need := maxi(1, int(c.get("count", 1)))
			var n := 0
			for e in SimIndex.of(w, "unit"):
				if (fid == SimWorld.NEUTRAL or int(e.owner) == fid) and SimIndex.alive(w, e) and (rect as Rect2i).has_point(w.cell_of(e.pos)):
					n += 1
					if n >= need:
						return true
			return false
		"entity_destroyed":
			var tg: Dictionary = state(w).tags.get(String(c.get("tag", "")), {})
			if tg.is_empty():
				return false
			for id in tg.ids:
				if Victory._tag_alive(w, int(id)):
					return false
			return true
		"stage_reached":
			var fid := fid_of_slot(w, int(c.get("slot", -1)))
			return fid != SimWorld.NEUTRAL and int(w.factions[fid].stage) >= int(c.get("stage", 9))
		"units_below":
			var fid := fid_of_slot(w, int(c.get("slot", -1)))
			if fid == SimWorld.NEUTRAL:
				return false
			var n := 0
			for e in w.units_of(fid):
				n += 1 + (e.cargo as Array).size() if e.has("cargo") else 1
			return n < int(c.get("n", 1))
	return false


# ================================================================ actions
static func _act(w: SimWorld, ti: int, a: Dictionary) -> void:
	var ty := String(a.get("type", ""))
	var fid := fid_of_slot(w, int(a.get("slot", -1)))
	match ty:
		"message":
			w.emit("TriggerMessage", {"trigger": ti, "text": String(a.get("text", "")), "slot": int(a.get("slot", -1))})
		"spawn":
			if fid == SimWorld.NEUTRAL:
				return
			_spawn(w, fid, String(a.get("def", "")), clampi(int(a.get("count", 1)), 1, MAX_SPAWN), a.get("region", ""))
		"reveal":
			var rect = _rect_of(w, a.get("region", ""))
			if fid == SimWorld.NEUTRAL or rect == null:
				return
			state(w).reveals.append({"fid": fid, "rect": rect})
			_apply_reveal(w, fid, rect)
		"grant":
			var res := String(a.get("res", "credits"))
			var amt := int(a.get("amount", 0))
			if fid != SimWorld.NEUTRAL and SimWorld.LEDGER_KEYS.has(res) and amt > 0:
				w.credit(fid, {res: amt}, "trigger")
		"win":
			if fid != SimWorld.NEUTRAL:
				Victory.force_win(w, fid)
		"lose":
			if fid != SimWorld.NEUTRAL:
				Victory.eliminate_side(w, fid)
		"ai_target":
			var rect = _rect_of(w, a.get("region", ""))
			if fid != SimWorld.NEUTRAL and rect != null:
				state(w).ai_targets[fid] = Vector2((rect as Rect2i).position) + Vector2((rect as Rect2i).size) * 0.5
				w.emit("AiTargetSet", {"faction": fid, "region": String(a.region)})


## Spawns count units of def for fid on free cells of the region (row-major from its centre ring
## outwards; falls back to the side's spawn). Buildings: one, complete, at the region origin.
static func _spawn(w: SimWorld, fid: int, def: String, count: int, rid) -> void:
	var rect = _rect_of(w, rid)
	if not Content.building(def).is_empty():
		var o: Vector2i = (rect as Rect2i).position if rect != null else Vector2i(w.factions[fid].spawn)
		w.spawn_building(def, fid, o, true)
		return
	if Content.unit(def).is_empty():
		return
	var mc := String(Movement.udef(def).mc)
	var centre: Vector2i = (rect as Rect2i).get_center() if rect != null else Vector2i(w.factions[fid].spawn) + Vector2i(0, 4)
	var r := maxi((rect as Rect2i).size.x, (rect as Rect2i).size.y) if rect != null else 8
	var placed := 0
	for d in r + 1:
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d or placed >= count:
					continue
				var c := centre + Vector2i(dx, dy)
				if rect != null and not (rect as Rect2i).has_point(c):
					continue
				if not w.in_bounds(c) or not Movement.is_passable(w, c, mc):
					continue
				w.spawn_unit(def, fid, Vector2(c) + Vector2(0.5, 0.5))
				placed += 1
	if placed < count:
		w.emit("TriggerSpawnShort", {"faction": fid, "def": def, "wanted": count, "placed": placed})


static func _apply_reveal(w: SimWorld, fid: int, rect) -> void:
	var mw := int(w.map.w)
	var r: Rect2i = (rect as Rect2i).intersection(Rect2i(0, 0, mw, int(w.map.h)))
	for m in Fog.team_members(w, fid):
		var f = w.fog.get(m)
		if f == null:
			continue
		var vis: PackedByteArray = f.visible
		var ex: PackedByteArray = f.explored
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				vis[y * mw + x] = 1
				ex[y * mw + x] = 1
		f.visible = vis
		f.explored = ex


# ================================================================ validation (editor / MapIO.validate)
## Checks one condition/action/victory term's references. ctx = {regions: {id: true}, slots: {slot: true},
## tags: {tag: true}}. Returns "" or a reason.
static func check_refs(d: Dictionary, ctx: Dictionary) -> String:
	if d.has("region") and not ctx.get("regions", {}).has(String(d.region)):
		return "unknown region '%s'" % d.region
	for k in ["slot", "owner_slot"]:
		if d.has(k) and not (k == "owner_slot" and int(d[k]) < 0) and not ctx.get("slots", {}).has(int(d[k])):
			return "no player in slot %s" % str(d[k])
	if d.has("tag") and not ctx.get("tags", {}).has(String(d.tag)):
		return "no placed entity has tag '%s'" % d.tag
	if d.has("def") and Content.unit(String(d.def)).is_empty() and Content.building(String(d.def)).is_empty():
		return "unknown unit or building '%s'" % d.def
	if d.has("res") and not SimWorld.LEDGER_KEYS.has(String(d.res)):
		return "unknown resource '%s'" % d.res
	return ""


## Returns a list of messages (empty = all triggers are well formed).
static func validate_defs(defs, ctx: Dictionary) -> Array:
	var out := []
	if typeof(defs) != TYPE_ARRAY:
		return ["Triggers must be a list."]
	var i := 0
	for d in defs:
		i += 1
		if typeof(d) != TYPE_DICTIONARY:
			out.append("Trigger %d is not an object." % i)
			continue
		var label := "Trigger %d (%s)" % [i, String(d.get("name", d.get("id", "")))]
		var conds = d.get("when", [])
		if typeof(conds) == TYPE_DICTIONARY:
			conds = [conds]
		if typeof(conds) != TYPE_ARRAY or (conds as Array).is_empty():
			out.append("%s has no condition." % label)
		else:
			for c in conds:
				var ty := String(c.get("type", "")) if typeof(c) == TYPE_DICTIONARY else ""
				if not WHEN_TYPES.has(ty):
					out.append("%s: unknown condition '%s'." % [label, ty])
				elif check_refs(c, ctx) != "":
					out.append("%s: %s." % [label, check_refs(c, ctx)])
		var acts = d.get("then", [])
		if typeof(acts) == TYPE_DICTIONARY:
			acts = [acts]
		if typeof(acts) != TYPE_ARRAY or (acts as Array).is_empty():
			out.append("%s has no action." % label)
		else:
			for a in acts:
				var ty := String(a.get("type", "")) if typeof(a) == TYPE_DICTIONARY else ""
				if not THEN_TYPES.has(ty):
					out.append("%s: unknown action '%s'." % [label, ty])
				elif check_refs(a, ctx) != "":
					out.append("%s: %s." % [label, check_refs(a, ctx)])
	return out


# Triggers own no commands (scaffold interface kept for the command bus contract).
static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "Triggers take no commands."


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass
