extends RefCounted
## G10 Task 20 — Blackout, Hollow Ground, Mirror Fortress, Dead Radio only.
## Hollow Ground reuses Tunnels10.collapse / hollow_tell (MECH public API).

const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Tunnels10 = preload("res://sim/systems/tunnels10.gd")

const KEY := "coalition_dark10"
const VER := 1
const SELECTED := ["blackout", "hollow_ground", "mirror_fortress", "dead_radio"]


static func R() -> Dictionary:
	var c = Content.rules().get("g10_dark", {})
	return c if c is Dictionary else {}


static func selected_options() -> Array:
	var s: Array = R().get("selected", SELECTED)
	return s.duplicate() if s is Array else SELECTED.duplicate()


static func commands() -> Array:
	return selected_options()


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	if not Coalition10.active(w, fid) or int(w.factions.get(fid, {}).get("stage", 0)) < 8:
		return "Dark operations require a Stage 8 Coalition side."
	var option := String(cmd.get("option", ""))
	if option not in selected_options():
		return "Unknown dark operation."
	var building = w.entities.get(int(cmd.get("building", -1)))
	if building == null or building.kind != "building" or not bool(building.built):
		return "Choose a completed building."
	var owner := int(building.owner)
	match option:
		"blackout", "dead_radio":
			if not w.is_enemy(fid, owner) or not SimWorld.Fog.entity_visible(w, fid, building):
				return "Choose a visible enemy building."
			if option == "blackout" and not _intel_ok(w, fid):
				return "Blackout needs EW or intel."
		"hollow_ground":
			if owner != fid or String(building.def) != "x_tunnel_entrance":
				return "Choose one of your tunnel entrances."
		"mirror_fortress":
			if owner != fid:
				return "Choose one of your own structures."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var id := int(cmd.building)
	var b: Dictionary = w.entities[id]
	var fid := int(cmd.issuer)
	match String(cmd.option):
		"blackout":
			blackout(w, fid, Rect2i(Vector2i(b.cell) - Vector2i(2, 2), Vector2i(5, 5)))
		"hollow_ground":
			hollow_ground(w, fid, id)
		"mirror_fortress":
			mirror_signature(w, id)
		"dead_radio":
			var lines: Array = R().get("dead_radio", {}).get("lines", {}).keys()
			lines.sort()
			if not lines.is_empty():
				dead_radio(w, fid, int(b.owner), String(lines[0]))


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {
			"ver": VER,
			"blackouts": [],
			"hollow": {},
			"mirrors": {},
			"radio": [],
			"aar": [],
			"next_mirror": 1,
			"next_radio": 1,
		}
	return w.sys_state[KEY]


static func board(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		return {}
	var s := _st(w)
	return {
		"blackouts": (s.blackouts as Array).size(),
		"hollow": (s.hollow as Dictionary).size(),
		"mirrors": (s.mirrors as Dictionary).size(),
		"radio": (s.radio as Array).size(),
		"aar": (s.aar as Array).size(),
		"selected": selected_options(),
	}


static func _intel_ok(w: SimWorld, fid: int) -> bool:
	var cfg: Dictionary = R().get("blackout", {})
	var grades: Array = cfg.get("min_intel_grades", ["pattern", "fix", "keyhole"])
	var b: Dictionary = Coalition10.board(w, fid)
	if grades.has(String(b.get("intel_grade", ""))):
		return true
	var ev: Dictionary = {}
	if w.sys_state.has(Coalition10.KEY):
		var side = (w.sys_state[Coalition10.KEY].get("factions", {}) as Dictionary).get(str(fid), {})
		if side is Dictionary:
			ev = side.get("evidence", {}) as Dictionary
	var ekey := String(cfg.get("ew_evidence_key", "ew"))
	if int(ev.get(ekey, 0)) >= 1:
		return true
	var ew_defs: Array = cfg.get("ew_defs", [])
	for eid in w.entities:
		var e = w.entities[eid]
		if e == null or String(e.get("kind", "")) != "unit":
			continue
		if int(e.get("owner", -1)) != fid:
			continue
		if ew_defs.has(String(e.get("def", ""))):
			return true
	return false


static func blackout(w: SimWorld, fid: int, target: Rect2i) -> String:
	if not Coalition10.active(w, fid):
		return "Coalition only."
	if not _intel_ok(w, fid):
		return "Blackout needs EW or intel."
	if target.size.x <= 0 or target.size.y <= 0:
		return "Invalid target."
	var cfg: Dictionary = R().get("blackout", {})
	var warn := int(cfg.get("warn_ticks", 30))
	var dur := int(cfg.get("duration_ticks", 120))
	var s := _st(w)
	var hits: Array = []
	var notified := {}
	for eid in w.entities:
		var e = w.entities[eid]
		if e == null or String(e.get("kind", "")) != "building":
			continue
		if not w.is_enemy(fid, int(e.get("owner", -1))):
			continue
		var cell: Vector2i = e.cell if e.has("cell") else w.cell_of(e.pos)
		if not target.has_point(cell):
			continue
		hits.append(int(eid))
		notified[int(e.owner)] = true
	hits.sort()
	s.blackouts.append({
		"fid": fid,
		"rect": {"x": target.position.x, "y": target.position.y, "w": target.size.x, "h": target.size.y},
		"warn_until": w.tick + warn,
		"end_tick": w.tick + warn + dur,
		"active": false,
		"permanent": false,
		"targets": hits.duplicate(),
		"cuts": (cfg.get("cuts", ["power", "comms"]) as Array).duplicate(),
	})
	w.emit("Dark10BlackoutArmed", {"fid": fid, "warn": warn, "target_fids": notified.keys(), "pos": Vector2(target.get_center()), "n": hits.size()})
	return ""


static func blackout_active(w: SimWorld, building_id: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	for row in _st(w).blackouts:
		if not bool(row.get("active", false)) or w.tick >= int(row.get("end_tick", 0)):
			continue
		if (row.get("targets", []) as Array).has(building_id):
			return true
	return false


static func blackout_power_cut(w: SimWorld, building_id: int) -> bool:
	return blackout_active(w, building_id)


static func blackout_comms_cut(w: SimWorld, building_id: int) -> bool:
	return blackout_active(w, building_id)


static func blackout_permanent_any(w: SimWorld) -> bool:
	if not w.sys_state.has(KEY):
		return false
	for row in _st(w).blackouts:
		if bool(row.get("permanent", false)):
			return true
		if bool(row.get("active", false)) and w.tick > int(row.get("end_tick", 0)) + 999999:
			return true
	return false


## Arm Hollow Ground: readable tell via Tunnels10.hollow_tell, then collapse API unless countered.
static func hollow_ground(w: SimWorld, fid: int, entrance_id: int) -> String:
	if not Coalition10.active(w, fid):
		return "Coalition only."
	var e = w.entities.get(entrance_id)
	if e == null or String(e.get("kind", "")) != "building":
		return "Not an entrance."
	if String(e.get("def", "")) != "x_tunnel_entrance":
		return "Not a tunnel entrance."
	if Tunnels10.is_collapsed(w, entrance_id):
		return "Already collapsed."
	var cfg: Dictionary = R().get("hollow_ground", {})
	var tell_t := int(cfg.get("tell_ticks", 40))
	# Ensure tunnels state exists (public API), then seed tell record hollow_tell reads.
	Tunnels10.set_dead_zone(w, entrance_id, false)
	var ts: Dictionary = w.sys_state[Tunnels10.KEY]
	var tells: Dictionary = ts.get("tells", {})
	tells[str(entrance_id)] = {
		"until": w.tick + tell_t,
		"cause": "hollow_ground",
		"sound": true,
		"terrain": true,
	}
	ts.tells = tells
	var s := _st(w)
	s.hollow[str(entrance_id)] = {
		"fid": fid,
		"until": w.tick + tell_t,
		"cause": String(cfg.get("collapse_cause", "hollow_ground")),
		"countered": false,
	}
	w.emit("Dark10HollowArmed", {"fid": fid, "entrance": entrance_id, "tell": tell_t})
	return ""


static func hollow_counter(w: SimWorld, fid: int, entrance_id: int, unit_id: int) -> String:
	var s := _st(w)
	var key := str(entrance_id)
	if not (s.hollow as Dictionary).has(key):
		return "No Hollow Ground armed."
	var u = w.entities.get(unit_id)
	if u == null or String(u.get("kind", "")) != "unit":
		return "Missing unit."
	if int(u.get("owner", -1)) != fid:
		return "Not your unit."
	var cfg: Dictionary = R().get("hollow_ground", {})
	var roles: Array = cfg.get("counter_roles", [])
	var defs: Array = cfg.get("counter_defs", [])
	var def_id := String(u.get("def", ""))
	var role := String(u.get("role", ""))
	if role == "" and not Content.unit(def_id).is_empty():
		role = String(Content.unit(def_id).get("role", ""))
	var ok := defs.has(def_id) or roles.has(role)
	if not ok:
		return "Need engineer or scout."
	(s.hollow as Dictionary).erase(key)
	if w.sys_state.has(Tunnels10.KEY):
		var tells: Dictionary = w.sys_state[Tunnels10.KEY].get("tells", {})
		tells.erase(key)
		w.sys_state[Tunnels10.KEY].tells = tells
	w.emit("Dark10HollowCountered", {"fid": fid, "entrance": entrance_id, "unit": unit_id})
	return ""


static func mirror_signature(w: SimWorld, building_id: int) -> Dictionary:
	var out := {
		"ok": false,
		"decoy": false,
		"second_base": false,
		"kind": "",
		"id": -1,
		"revealed": false,
		"reason": "",
	}
	var e = w.entities.get(building_id)
	if e == null or String(e.get("kind", "")) != "building":
		out.reason = "Not a building."
		return out
	var fid := int(e.get("owner", -1))
	if not Coalition10.active(w, fid):
		out.reason = "Coalition only."
		return out
	var cfg: Dictionary = R().get("mirror_fortress", {})
	if bool(cfg.get("second_base", false)):
		out.reason = "Mirror must not grant a second base."
		return out
	var kinds: Array = cfg.get("decoy_kinds", ["hatch", "signature"])
	var kind := String(kinds[0]) if not kinds.is_empty() else "hatch"
	var s := _st(w)
	var mid := int(s.next_mirror)
	s.next_mirror = mid + 1
	var rec := {
		"id": mid,
		"source": building_id,
		"fid": fid,
		"kind": kind,
		"decoy": true,
		"second_base": false,
		"revealed": false,
		"tick": w.tick,
	}
	s.mirrors[str(mid)] = rec
	out.ok = true
	out.decoy = true
	out.second_base = false
	out.kind = kind
	out.id = mid
	out.revealed = false
	w.emit("Dark10Mirror", {"id": mid, "source": building_id, "kind": kind})
	return out


static func mirror_reveal(w: SimWorld, mirror_id: int, how: String) -> String:
	var s := _st(w)
	var key := str(mirror_id)
	if not (s.mirrors as Dictionary).has(key):
		return "Unknown mirror."
	var cfg: Dictionary = R().get("mirror_fortress", {})
	var allowed: Array = cfg.get("reveal_on", ["recon", "damage"])
	var h := String(how)
	if not allowed.has(h):
		return "Reveal needs recon or damage."
	var rec: Dictionary = s.mirrors[key]
	rec.revealed = true
	rec["reveal_how"] = h
	rec["reveal_tick"] = w.tick
	w.emit("Dark10MirrorReveal", {"id": mirror_id, "how": h})
	return ""


static func mirror_is_decoy(w: SimWorld, mirror_id: int) -> bool:
	if not w.sys_state.has(KEY):
		return false
	var rec = (_st(w).mirrors as Dictionary).get(str(mirror_id), null)
	return rec is Dictionary and bool(rec.get("decoy", false)) and not bool(rec.get("revealed", false))


static func dead_radio(w: SimWorld, fid: int, target_fid: int, line_id: String) -> String:
	if not Coalition10.active(w, fid):
		return "Coalition only."
	if not w.factions.has(target_fid):
		return "Invalid target faction."
	var cfg: Dictionary = R().get("dead_radio", {})
	if bool(cfg.get("issues_commands", false)):
		return "Dead Radio must not issue commands."
	if bool(cfg.get("turns_operators", false)):
		return "Dead Radio must not turn operators."
	var lines: Dictionary = cfg.get("lines", {})
	var lid := String(line_id)
	if not lines.has(lid):
		return "Unknown line."
	var text := String(lines[lid])
	var anomaly := String(cfg.get("anomaly_tell", "carrier_drift"))
	var s := _st(w)
	var rid := int(s.next_radio)
	s.next_radio = rid + 1
	var entry := {
		"id": rid,
		"fid": fid,
		"target_fid": target_fid,
		"line_id": lid,
		"text": text,
		"anomaly": anomaly,
		"tick": w.tick,
		"command": null,
		"turned_operators": false,
	}
	s.radio.append(entry)
	s.aar.append({
		"kind": "dead_radio",
		"id": rid,
		"fid": fid,
		"target_fid": target_fid,
		"line_id": lid,
		"anomaly": anomaly,
		"tick": w.tick,
		"attribution": "coalition_dead_radio",
	})
	w.emit("Dark10DeadRadio", {"id": rid, "fid": fid, "target_fid": target_fid, "text": text, "anomaly": anomaly})
	return ""


static func dead_radio_issued_command(w: SimWorld) -> bool:
	if not w.sys_state.has(KEY):
		return false
	for row in _st(w).radio:
		if row.get("command", null) != null:
			return true
	return false


static func dead_radio_turned_operators(w: SimWorld) -> bool:
	if not w.sys_state.has(KEY):
		return false
	for row in _st(w).radio:
		if bool(row.get("turned_operators", false)):
			return true
	return false


static func aar_log(w: SimWorld) -> Array:
	if not w.sys_state.has(KEY):
		return []
	return (_st(w).aar as Array).duplicate(true)


static func has_unselected_dark(w: SimWorld = null) -> bool:
	var forbidden: Array = R().get("unselected_forbidden", [])
	var sel := selected_options()
	for id in sel:
		if forbidden.has(String(id)):
			return true
	var rules_blob := JSON.stringify(R())
	for bad in forbidden:
		var token := String(bad)
		if sel.has(token):
			continue
		if rules_blob.find(token) >= 0:
			# listed only under unselected_forbidden — ok
			pass
	# Commands surface must equal selected set.
	for c in commands():
		if not SELECTED.has(String(c)):
			return true
		if forbidden.has(String(c)):
			return true
	if w != null and w.sys_state.has(KEY):
		var blob := JSON.stringify(_st(w))
		for bad in forbidden:
			if blob.find('"%s"' % String(bad)) >= 0:
				return true
	return false


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var s := _st(w)
	# Blackout warn → active → expire (never permanent).
	var keep_bo: Array = []
	for row in s.blackouts:
		if w.tick >= int(row.get("warn_until", 0)) and not bool(row.get("active", false)):
			if w.tick < int(row.get("end_tick", 0)):
				row.active = true
				row.permanent = false
				w.emit("Dark10BlackoutActive", {"fid": int(row.get("fid", -1)), "n": (row.get("targets", []) as Array).size()})
		if w.tick >= int(row.get("end_tick", 0)):
			row.active = false
			row.permanent = false
			w.emit("Dark10BlackoutEnded", {"fid": int(row.get("fid", -1))})
			continue
		keep_bo.append(row)
	s.blackouts = keep_bo
	# Hollow Ground: tell window then Tunnels10.collapse.
	var hollow_keys: Array = (s.hollow as Dictionary).keys()
	hollow_keys.sort()
	for hk in hollow_keys:
		var rec: Dictionary = s.hollow[hk]
		if bool(rec.get("countered", false)):
			(s.hollow as Dictionary).erase(hk)
			continue
		if w.tick < int(rec.get("until", 0)):
			continue
		var entrance_id := int(hk)
		if not Tunnels10.is_collapsed(w, entrance_id):
			Tunnels10.collapse(w, entrance_id, String(rec.get("cause", "hollow_ground")))
		(s.hollow as Dictionary).erase(hk)
