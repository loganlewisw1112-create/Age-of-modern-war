extends RefCounted
## G10 patron contracts, favour, merc loyalty, heat / false-flag. Numbers PROVISIONAL.
## Uses Market/World credit spend only — does not edit market.gd pricing.

const KEY := "patron10"
const VER := 1
const Coalition10 = preload("res://sim/systems/coalition10.gd")
const Territory9 = preload("res://sim/systems/territory9.gd")
const Market = preload("res://sim/systems/market.gd")


static func R() -> Dictionary:
	var c = Content.rules().get("g10_patron", {})
	return c if c is Dictionary else {}


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {
			"ver": VER,
			"factions": {},
			"loyalty": {},
			"active": {},
			"next_pay": {},
		}
	return w.sys_state[KEY]


static func _side(w: SimWorld, fid: int) -> Dictionary:
	var s := _st(w)
	var key := str(fid)
	if not (s.factions as Dictionary).has(key):
		s.factions[key] = {
			"favour": 0,
			"offers": {},
			"accepted": [],
			"surgical_successes": 0,
			"heat": 0,
			"evidence": [],
			"grudges": [],
			"tier_access": "recon",
			"support": null,
		}
	return s.factions[key]


static func favour(w: SimWorld, fid: int) -> int:
	if not Coalition10.active(w, fid) and not w.sys_state.has(KEY):
		return 0
	return int(_side(w, fid).get("favour", 0))


static func heat(w: SimWorld, fid: int) -> int:
	if not w.sys_state.has(KEY):
		return 0
	return int(_side(w, fid).get("heat", 0))


static func add_favour_from_territory(w: SimWorld, fid: int) -> int:
	var score := Territory9.territory_score(w, fid)
	var gain := score * int(R().get("favour_per_territory", 2))
	var side := _side(w, fid)
	side.favour = int(side.favour) + gain
	_sync_coalition(w, fid, side)
	return gain


static func add_favour_loot(w: SimWorld, fid: int, amount: int = 1) -> void:
	var side := _side(w, fid)
	side.favour = int(side.favour) + maxi(amount, 1) * int(R().get("favour_per_loot", 1))
	_sync_coalition(w, fid, side)


static func _sync_coalition(w: SimWorld, fid: int, side: Dictionary) -> void:
	if not Coalition10.active(w, fid):
		return
	var cs := Coalition10._side(w, fid)
	if cs.is_empty():
		return
	cs.patron_favour = int(side.favour)
	cs.contracts = (side.get("accepted", []) as Array).map(func(rec): return String(rec.contract_id))
	Coalition10._refresh_layer(cs)


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	if not Coalition10.active(w, fid):
		return "Patron contracts are Coalition-only."
	var contract := String(cmd.get("contract", ""))
	if not catalog().has(contract):
		return "Unknown patron contract."
	if not w.buildings_of(fid, "x_patron_office").any(func(b): return bool(b.built)):
		return "Build a Patron Office to accept contracts."
	var side: Dictionary = w.sys_state.get(KEY, {}).get("factions", {}).get(str(fid), {})
	for record in side.get("accepted", []):
		if String(record.contract_id) == contract and w.tick < int(record.until):
			return "This contract is already active."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var reason := accept(w, int(cmd.issuer), String(cmd.contract))
	if reason != "":
		w.emit("CoalitionActionDenied", {"fid": int(cmd.issuer), "reason": reason})


static func catalog() -> Dictionary:
	return R().get("contracts", {})


static func offer(w: SimWorld, fid: int, contract_id: String) -> Dictionary:
	var cat: Dictionary = catalog()
	var row: Dictionary = cat.get(String(contract_id), {})
	if row.is_empty():
		return {"ok": false, "reason": "Unknown contract."}
	var side := _side(w, fid)
	var gate := _gate_reason(side, row)
	if gate != "":
		return {"ok": false, "reason": gate, "contract_id": contract_id}
	var offer := {
		"contract_id": String(contract_id),
		"tier": String(row.get("tier", "recon")),
		"cost": (row.get("cost", {}) as Dictionary).duplicate(),
		"favour": int(row.get("favour", 0)),
		"duration_ticks": int(row.get("duration_ticks", 200)),
		"support": String(row.get("support", "")),
		"offered_tick": w.tick,
	}
	side.offers[String(contract_id)] = offer
	w.emit("Patron10Offer", {"fid": fid, "contract_id": contract_id, "tier": offer.tier})
	return {"ok": true, "offer": offer}


static func _gate_reason(side: Dictionary, row: Dictionary) -> String:
	var need_tier := String(row.get("requires_tier", ""))
	var access := String(side.get("tier_access", "recon"))
	var tier := String(row.get("tier", "recon"))
	if tier == "atrocity" or tier == "false_flag":
		var need_n := int(row.get("requires_surgical_successes", R().get("surgical_required_for_atrocity", 2)))
		if int(side.get("surgical_successes", 0)) < need_n:
			return "Requires %d successful Surgical contracts." % need_n
	if need_tier != "":
		var order := ["recon", "surgical", "atrocity", "false_flag"]
		if order.find(access) < order.find(need_tier) and access != need_tier:
			# Allow if surgical successes unlock atrocity path.
			if not (need_tier == "surgical" and int(side.get("surgical_successes", 0)) >= 1):
				if access == "recon" and need_tier == "surgical" and int(side.get("surgical_successes", 0)) < 1:
					return "Complete a Recon contract first."
	return ""


static func accept(w: SimWorld, fid: int, contract_id: String) -> String:
	var side := _side(w, fid)
	var cid := String(contract_id)
	var offer: Dictionary = side.offers.get(cid, {})
	var cat: Dictionary = catalog()
	var row: Dictionary = cat.get(cid, {})
	if offer.is_empty():
		# Implicit offer if gated catalog row exists.
		var o2 := offer(w, fid, cid)
		if not bool(o2.get("ok", false)):
			return String(o2.get("reason", "No offer."))
		offer = o2.offer
	var gate := _gate_reason(side, row)
	if gate != "":
		return gate
	var cost: Dictionary = offer.get("cost", row.get("cost", {}))
	var err := w.can_afford(fid, cost)
	if err != "":
		return err
	if not w.spend(fid, cost, "patron:%s" % cid):
		return "Cannot pay."
	# Keep ordinary Market pricing untouched; only ledger spend.
	var _black := Market.black_catalog()
	side.favour = int(side.favour) + int(offer.get("favour", 0))
	_sync_coalition(w, fid, side)
	var dur := int(offer.get("duration_ticks", 200))
	var until := w.tick + dur
	var rec := {
		"contract_id": cid,
		"tier": String(offer.get("tier", "recon")),
		"until": until,
		"support": String(offer.get("support", "")),
		"paid": true,
		"pay_due": w.tick + int(R().get("pay_window_ticks", 300)),
	}
	side.accepted.append(rec)
	side.offers.erase(cid)
	# Advance tier access on recon/surgical accept.
	var tier := String(rec.tier)
	if tier == "recon":
		side.tier_access = "surgical"
	elif tier == "surgical":
		side.tier_access = "surgical"
		side.surgical_successes = int(side.surgical_successes) + 1
		if int(side.surgical_successes) >= int(R().get("surgical_required_for_atrocity", 2)):
			side.tier_access = "atrocity"
	elif tier == "atrocity":
		_add_heat(w, fid, int(R().get("heat_per_atrocity", 15)))
	elif tier == "false_flag":
		_false_flag(w, fid, cid)
	side.support = {
		"kind": String(rec.support),
		"until": until,
		"contract_id": cid,
	}
	_st(w).next_pay[str(fid)] = int(rec.pay_due)
	# Spawn timed merc if configured.
	if String(row.get("unit", "")) != "" and not Content.unit(String(row.unit)).is_empty():
		var hq = null
		for b in w.buildings_of(fid):
			hq = b
			break
		var pos := Vector2(8, 8)
		if hq != null:
			pos = Vector2(float(hq.pos.x), float(hq.pos.y)) + Vector2(2, 0)
		var uid := w.spawn_unit(String(row.unit), fid, pos)
		set_loyalty(w, uid, 70)
		rec["unit_id"] = uid
		# Keep accepted rec updated with unit id.
		if not (side.accepted as Array).is_empty():
			side.accepted[side.accepted.size() - 1] = rec
	_sync_coalition(w, fid, side)
	w.emit("Patron10Accept", {"fid": fid, "contract_id": cid, "until": until, "tier": tier})
	return ""


static func _add_heat(w: SimWorld, fid: int, amount: int) -> void:
	var side := _side(w, fid)
	side.heat = int(side.heat) + maxi(amount, 0)
	# Heat raises alert readiness flags — never free HP/damage.
	side["alert"] = {
		"dogs": int(side.heat) >= 10,
		"aa": int(side.heat) >= 20,
		"thermal": int(side.heat) >= 15,
		"heat": int(side.heat),
	}
	w.emit("Patron10Heat", {"fid": fid, "heat": int(side.heat), "alert": side.alert})


static func note_ghost_overuse(w: SimWorld, fid: int) -> void:
	_add_heat(w, fid, int(R().get("heat_per_ghost_overuse", 5)))


static func note_execution(w: SimWorld, fid: int) -> void:
	_add_heat(w, fid, int(R().get("heat_per_execution", 10)))


static func _false_flag(w: SimWorld, fid: int, contract_id: String) -> void:
	var side := _side(w, fid)
	var ev := {
		"contract_id": contract_id,
		"tick": w.tick,
		"attributable": true,
		"exposure": 40 + (w.tick % 17),
	}
	(side.evidence as Array).append(ev)
	# Deterministic diplomacy/grudge toward first non-Coalition foe.
	var foe := -1
	for other in w.factions:
		if int(other) == fid:
			continue
		if String(w.factions[other].get("faction_def", "")) != Coalition10.FACTION_ID:
			foe = int(other)
			break
	if foe >= 0:
		var grudge := {"from": foe, "to": fid, "reason": "false_flag", "tick": w.tick, "weight": 1 + (w.tick % 5)}
		(side.grudges as Array).append(grudge)
		w.emit("Patron10FalseFlag", {"fid": fid, "foe": foe, "evidence": ev, "grudge": grudge})
	_add_heat(w, fid, int(R().get("heat_per_atrocity", 15)) / 2)


static func set_loyalty(w: SimWorld, unit_id: int, value: int) -> void:
	_st(w).loyalty[str(unit_id)] = clampi(value, 0, 100)


static func loyalty(w: SimWorld, unit_id: int) -> int:
	if not w.sys_state.has(KEY):
		return 100
	return int(_st(w).loyalty.get(str(unit_id), 100))


static func settle_pay(w: SimWorld, fid: int) -> void:
	var s := _st(w)
	var side := _side(w, fid)
	var due := int(s.next_pay.get(str(fid), 0))
	var late := due > 0 and w.tick > due
	var drop := int(R().get("late_loyalty_drop", 25))
	var keys: Array = (s.loyalty as Dictionary).keys()
	keys.sort()
	for k in keys:
		var uid := int(k)
		var e = w.entities.get(uid)
		if e == null or int(e.get("owner", -1)) != fid:
			continue
		if late:
			s.loyalty[k] = maxi(0, int(s.loyalty[k]) - drop)
		else:
			# On-time pay top-up.
			s.loyalty[k] = mini(100, int(s.loyalty[k]) + 5)
		_resolve_loyalty_outcome(w, fid, uid, int(s.loyalty[k]))
	if late:
		side.tier_access = "recon"
		side.surgical_successes = maxi(0, int(side.surgical_successes) - 1)
		w.emit("Patron10LatePay", {"fid": fid, "drop": drop})
	else:
		s.next_pay[str(fid)] = w.tick + int(R().get("pay_window_ticks", 300))
		w.emit("Patron10Paid", {"fid": fid})


static func _on_home_ground(w: SimWorld, fid: int, unit_id: int) -> bool:
	var e = w.entities.get(unit_id)
	if e == null:
		return false
	var cell := Vector2i(int(floor(float(e.pos.x))), int(floor(float(e.pos.y))))
	var rec = Territory9._st(w).cells.get("%d,%d" % [cell.x, cell.y], {})
	return int(rec.get("fid", -1)) == fid


static func _resolve_loyalty_outcome(w: SimWorld, fid: int, unit_id: int, loy: int) -> void:
	var threshold := int(R().get("desert_loyalty_lte", 20))
	if loy > threshold:
		return
	var e = w.entities.get(unit_id)
	if e == null:
		return
	# Fanatic home-ground immunity.
	if bool(R().get("fanatic_home_immunity", true)) and bool(e.get("fanatic", false)) and _on_home_ground(w, fid, unit_id):
		w.emit("Patron10LoyalHold", {"id": unit_id, "fid": fid, "loyalty": loy})
		return
	# Deterministic desert vs switch from unit id + tick.
	var roll := ((w.tick * 31) + unit_id * 17) % 100
	if roll < 50:
		w.destroy(unit_id, "deserted")
		w.emit("Patron10Desert", {"id": unit_id, "fid": fid, "loyalty": loy})
	else:
		var foe := -1
		for other in w.factions:
			if int(other) != fid:
				foe = int(other)
				break
		if foe >= 0:
			e.owner = foe
			w.emit("Patron10Switch", {"id": unit_id, "from": fid, "to": foe, "loyalty": loy})
		else:
			w.destroy(unit_id, "deserted")


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var s := _st(w)
	var fkeys: Array = (s.factions as Dictionary).keys()
	fkeys.sort()
	for fk in fkeys:
		var side: Dictionary = s.factions[fk]
		# Expire timed support.
		var sup = side.get("support", null)
		if typeof(sup) == TYPE_DICTIONARY and w.tick >= int(sup.get("until", 0)):
			side.support = null
			w.emit("Patron10SupportExpired", {"fid": int(fk), "contract_id": String(sup.get("contract_id", ""))})
		# Drop finished contracts from accepted list.
		var keep: Array = []
		for rec in side.get("accepted", []):
			if w.tick < int(rec.get("until", 0)):
				keep.append(rec)
		var expired := keep.size() != (side.accepted as Array).size()
		side.accepted = keep
		if expired:
			_sync_coalition(w, int(fk), side)
