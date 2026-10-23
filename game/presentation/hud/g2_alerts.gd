extends RefCounted
## G2 alert feed entries (owner: agent D2). hud.gd forwards every event it does not handle
## itself. Event fields: CONTRACTS_G2 section 7.

const HT = preload("res://presentation/hud/hud_theme.gd")

var _phase: Dictionary = {}     # gid -> last reported phase (OfficerReport alerts on change only)

const COMP_TEXT := {"mobility": "%s immobilized!", "weapon": "%s weapon knocked out!", "sensors": "%s sensors knocked out!"}


func _unit_name(w: SimWorld, id: int, fallback: String = "Unit") -> String:
	var e = w.entities.get(id)
	if e == null:
		return fallback
	var d: Dictionary = Content.unit(String(e.def)) if e.kind == "unit" else Content.building(String(e.def))
	var n := String(d.get("name", e.def))
	return "Tank" if String(e.def) == "mbt" else n


func _pos(w: SimWorld, id: int) -> Variant:
	var e = w.entities.get(id)
	return e.pos if e != null else null


func _owner(w: SimWorld, ev: Dictionary, id_key: String) -> int:
	if ev.has("owner"):
		return int(ev.owner)
	var e = w.entities.get(int(ev.get(id_key, -1)))
	return int(e.owner) if e != null else SimWorld.NEUTRAL


func on_event(hud, w: SimWorld, pf: int, ev: Dictionary) -> void:
	match String(ev.get("type", "")):
		"ComponentDisabled":
			var id := int(ev.get("id", -1))
			var comp := String(ev.get("component", ""))
			if _owner(w, ev, "id") == pf:
				var txt: String = COMP_TEXT.get(comp, "%s damaged: " + comp + " disabled!") % _unit_name(w, id)
				hud._push_alert(txt, HT.RED, _pos(w, id))
			elif not hud._throttled("cd_enemy", 20 * 3, w):
				hud._push_alert("Enemy %s: %s disabled." % [_unit_name(w, id, "vehicle"), comp], HT.GREEN)
		"UnitBroken":
			if _owner(w, ev, "id") == pf and not hud._throttled("broken", 20 * 3, w):
				hud._push_alert("%s broke and is retreating!" % _unit_name(w, int(ev.get("id", -1)), "A squad"), HT.YELLOW, _pos(w, int(ev.get("id", -1))))
		"UnitRallied":
			if _owner(w, ev, "id") == pf and not hud._throttled("rallied", 20 * 3, w):
				hud._push_alert("%s rallied." % _unit_name(w, int(ev.get("id", -1))), HT.GREEN)
		"OfficerReport":
			if _owner(w, ev, "officer") != pf:
				return
			var gid := str(ev.get("gid", "?"))
			var phase := String(ev.get("phase", ""))
			if String(_phase.get(gid, "")) == phase:
				return
			_phase[gid] = phase
			var reason := String(ev.get("reason", ""))
			var col: Color = HT.RED if phase == "withdraw" else (HT.AMBER if phase == "resupply" else HT.BLUE)
			hud._push_alert("Officer (group %s): %s" % [gid, reason if reason != "" else phase], col, _pos(w, int(ev.get("officer", -1))))
		"OfficerKilled":
			if int(ev.get("owner", -1)) == pf:
				_phase.erase(str(ev.get("gid", "?")))
				hud._push_alert("Officer killed! Group %s dissolved." % str(ev.get("gid", "?")), HT.RED)
		"SupplyShortage":
			if int(ev.get("faction", ev.get("owner", -1))) == pf:
				var res := String(ev.get("res", "supply"))
				if not hud._throttled("short:" + res, 20 * 15, w):
					hud._push_alert("Out of %s stock: units cannot resupply. Build a Refinery." % res, HT.YELLOW)
		"BridgeDestroyed":
			var cells: Array = ev.get("cells", [])
			var p: Variant = (Vector2(cells[0].x, cells[0].y) + Vector2(0.5, 0.5)) if not cells.is_empty() else null
			hud._push_alert("The river bridge has been destroyed!", HT.AMBER, p)
		"BridgeRepaired":
			hud._push_alert("The river bridge has been repaired.", HT.GREEN)
		"RepairBlocked":
			var uid := int(ev.get("unit_id", -1))
			var own := _owner(w, {"unit_id": uid}, "unit_id") == pf
			if not own:
				own = _owner(w, {"target_id": int(ev.get("target_id", -1))}, "target_id") == pf
			if own and not hud._throttled("repair_blocked", 20 * 5, w):
				hud._push_alert("Repair stopped: %s" % String(ev.get("reason", "blocked")).replace("_", " ").to_lower(), HT.YELLOW)
