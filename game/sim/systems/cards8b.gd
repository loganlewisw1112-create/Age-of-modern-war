extends RefCounted
## G7 CARDS8B (docs/G7_REFERENCE.md 13.9c-48, owner 2026-10-29): sim side of two facility building cards.
## ARMORY + SUIT FOUNDRY (presentation/ui7/armory_card8.gd):
##   c8b_preset {building_id, role, preset}   loadout preset per team role (strike / tactical): packages + rocket mix
##                                            from rules.cards8b.presets; every team of that role picks it up the next
##                                            time it stands unlocked in its garage (CounterNanite cn_set_loadout).
##   c8b_suit_build {building_id, role}       queue one CN armoured suit of a role (bastion / breaker / aegis /
##                                            purifier) at the Suit Foundry part (Production queue_unit).
##   c8b_suit_rush {building_id}              the head suit jumps rush.frac ahead for rush.cost_mult x its cost x frac.
##   c8b_suit_repair {building_id, unit_id}   damaged suit(s) (-1 = all) join the foundry repair queue and walk to the
##                                            bay doors; the first queued suit in reach is repaired (hp_s, credits/hp).
##   c8b_upgrade {building_id, key}           weapon upgrade research (AP / incendiary rounds, optics, suppressors,
##                                            heavier plates): one at a time, time_s, then on for the side's CN units.
##                                            Effects go through LETHAL8's round model: round_mods(w, shooter) (pen /
##                                            wound / k / kill multipliers) and armour_mult(w, target) (thickness t).
## GARAGES / WORKSHOP / DECON WASH (presentation/ui7/garage_card8.gd):
##   c8b_veh_repair {building_id, team}       toggles a vehicle team in the workshop priority repair queue: the head
##                                            team parked in its garage gets the workshop crew (veh_repair.hp_s, credits).
##   c8b_veh_upgrade {building_id, team, key} armour_kit (max hp), dome_shield (APC7 dome charge), rocket_pod (extra
##                                            launcher rounds topped up in the garage), engines (e.c8mv); parked only.
##   c8b_convoy {building_id, teams, target}  the chosen parked teams (none = all parked) roll out together to target
##                                            through CNFAC7's cn_rollout (pad -> gate, fac_drive7 drives them).
##   c8b_recall {building_id}                 every team out comes home through cn_return (decon wash -> garage).
##   c8b_decon_force {building_id}            contaminated soldiers walk to the wash; contaminated teams out return.
##   c8b_decon_skip {building_id, on}         returning APCs skip the wash while the base is under fire / breached.
## State (saved, hashed): w.sys_state.cards8b = {ver, facs {"<fac>": FS}, up {"<fid>": {key: true}}}; created by the
## first command only, so a match that never uses the cards is hash-identical and tick returns after one lookup.
## Entity fields (saved with the entity): c8u {upgrade: true} on fitted APCs, c8mv (engines), c8db (dome boosted).
## Everything is deterministic: sorted ids, staggered cadence ((w.tick + fac) % think_every), no rng.

const KEY := "cards8b"
const VER := 1
const EMPTY := {}

static var _r: Dictionary = {}
static var _r_src = null
static var _suit_items: Dictionary = {}


static func R() -> Dictionary:
	var c = Content.rules().get("cards8b")
	if _r_src == null or not is_same(c, _r_src):
		_r = c if typeof(c) == TYPE_DICTIONARY else {}
		_r_src = c
		_suit_items.clear()
	return _r


static func secs(s) -> int:
	return int(round(float(s) * SimWorld.TICK_RATE))


static func _sect(k: String) -> Dictionary:
	var v = R().get(k, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


# ================================================================ state
static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": VER, "facs": {}, "up": {}}
		w.sys_state[KEY] = st
	return st


## Read-only facility state ({} when the cards never touched fac).
static func fs(w: SimWorld, fac: int) -> Dictionary:
	var st = state(w)
	if st == null:
		return {}
	return st.facs.get(str(fac), {})


static func _fs(w: SimWorld, fac: int) -> Dictionary:
	var st := _st(w)
	var k := str(fac)
	if not st.facs.has(k):
		st.facs[k] = {"presets": {}, "applied": {}, "rq": [], "res": {}, "vq": [], "skip": false}
	return st.facs[k]


## Upgrades the side has finished ({} when none).
static func side_up(w: SimWorld, fid: int) -> Dictionary:
	var st = state(w)
	if st == null:
		return {}
	return st.up.get(str(fid), {})


# ================================================================ lookups
static func _fac(w: SimWorld, fac: int) -> Dictionary:
	return SimWorld.CnFacility.fac(w, fac)


## The Suit Foundry part (cn_armory building) of facility F, or null.
static func armory_part(w: SimWorld, F: Dictionary):
	for pid in F.get("parts", []):
		var b = w.entities.get(int(pid))
		if b != null and String(b.def) == "cn_armory" and int(b.owner) == int(F.owner):
			return b
	return null


## Facility teams of F (CNFAC7 records), ascending id.
static func teams(w: SimWorld, F: Dictionary) -> Array:
	var out := []
	var S = w.sys_state.get("cn_facility")
	if S == null or F.is_empty():
		return out
	var ids := []
	for k in S.teams:
		if int(S.teams[k].fac) == int(F.id):
			ids.append(int(k))
	ids.sort()
	for i in ids:
		out.append(S.teams[str(i)])
	return out


static func _team(w: SimWorld, F: Dictionary, tid: int) -> Dictionary:
	var T := SimWorld.CnFacility.team(w, tid)
	return T if not T.is_empty() and int(T.fac) == int(F.id) else {}


static func team_apcs(w: SimWorld, T: Dictionary) -> Array:
	var out := []
	for aid in T.get("apcs", []):
		var a = w.entities.get(int(aid))
		if a != null:
			out.append(a)
	return out


## Role of a facility team: the CNSIM7 team kind (strike / tactical), else from the CNFAC7 kind name.
static func team_role(w: SimWorld, T: Dictionary) -> String:
	var t = SimWorld.CounterNanite.team(w, int(T.id))
	if t != null:
		return String(t.kind)
	return "strike" if String(T.kind).begins_with("strike") else "tactical"


## Production item that builds a suit of role for side fid ("" when none).
static func suit_item(w: SimWorld, fid: int, role: String) -> String:
	R()
	var fdef := String(w.factions[fid].faction_def) if w.factions.has(fid) else ""
	var ck := fdef + ":" + role
	if _suit_items.has(ck):
		return _suit_items[ck]
	var out := ""
	var P: Dictionary = Content.table("production")
	var ids: Array = P.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = P[pid]
		if String(p.get("facility", "")) != "cn_armory" or String(p.get("faction", "")) != fdef:
			continue
		var sp: Array = p.get("spawns", [])
		if not sp.is_empty() and String(Content.unit(String(sp[0])).get("cn_suit", "")) == role:
			out = String(pid)
			break
	_suit_items[ck] = out
	return out


static func is_suit(e) -> bool:
	return typeof(e) == TYPE_DICTIONARY and e.get("kind", "") == "unit" and String(Content.unit(String(e.def)).get("cn_suit", "")) != ""


static func _maxhp(e: Dictionary) -> float:
	return float(e.get("max_hp", Content.unit(String(e.def)).get("hp", 100)))


static func damaged_suits(w: SimWorld, fid: int) -> Array:
	var ids := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if int(e.owner) == fid and is_suit(e) and float(e.hp) < _maxhp(e) - 0.01:
			ids.append(int(id))
	ids.sort()
	return ids


## Owner units with nanite exposure (cn_exp) at or above decon.contaminated_at, ascending id.
static func contaminated(w: SimWorld, fid: int) -> Array:
	var thr := float(_sect("decon").get("contaminated_at", 0.01))
	var ids := []
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if int(e.owner) == fid and e.kind == "unit" and float(e.get("cn_exp", 0.0)) >= thr:
			ids.append(int(id))
	ids.sort()
	return ids


static func _pt(v):
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	if typeof(v) == TYPE_DICTIONARY and v.has("x"):
		return Vector2(float(v.x), float(v.y))
	return null


static func _scale_cost(c: Dictionary, m: float) -> Dictionary:
	var out := {}
	for k in ["credits", "salvage", "ore"]:
		var n := int(round(float(c.get(k, 0)) * m))
		if n > 0:
			out[k] = n
	return out


static func rush_cost(head: Dictionary) -> Dictionary:
	var rs := _sect("rush")
	var p := Content.production(String(head.get("item", "")))
	return _scale_cost(p.get("cost", {}), float(rs.get("cost_mult", 0.6)) * float(rs.get("frac", 0.5)))


## The loadout command a preset gives team T (packages clipped to the APCs' capacity and the lab stock).
static func preset_cmd(w: SimWorld, T: Dictionary, preset: String) -> Dictionary:
	var P: Dictionary = _sect("presets").get(preset, {})
	var cmd := {"type": "cn_set_loadout", "issuer": int(T.owner), "team_id": int(T.id), "rockets": (P.get("rockets", {}) as Dictionary).duplicate()}
	if team_role(w, T) != "strike":
		return cmd
	var cap := 0
	for a in team_apcs(w, T):
		cap += int(SimWorld.Apc7.cfg_of(String(a.def)).get("pkg_capacity", 0))
	var lab := not SimWorld.CnFacility.facilities(w, int(T.owner)).is_empty()
	var used := 0
	var cnt := {}
	var pk := []
	for k in P.get("packages", []):
		var s := int(SimWorld.CounterNanite.pkg_size(String(k)))
		if used + s > cap:
			continue
		if lab and int(SimWorld.CnFacility.stock(w, int(T.owner), String(k))) < int(cnt.get(String(k), 0)) + 1:
			continue
		used += s
		cnt[String(k)] = int(cnt.get(String(k), 0)) + 1
		pk.append(String(k))
	cmd.packages = pk
	return cmd


# ================================================================ API for LETHAL8 (ballistics8) / others
## Multipliers on the round a CN unit of a side with weapon upgrades fires: {pen, wound, k, kill} (missing = 1.0).
## EMPTY (the same constant) when nothing applies: one dictionary lookup for a side without upgrades.
static func round_mods(w: SimWorld, shooter) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null or typeof(shooter) != TYPE_DICTIONARY:
		return EMPTY
	var u = st.up.get(str(int(shooter.get("owner", -1))))
	if u == null or (u as Dictionary).is_empty() or not is_cn(shooter):
		return EMPTY
	var out := {}
	var U := _sect("upgrades")
	for k in R().get("upgrade_order", []):
		if not u.has(k):
			continue
		var rm = U.get(k, {}).get("round")
		if typeof(rm) == TYPE_DICTIONARY:
			for f in rm:
				out[f] = float(out.get(f, 1.0)) * float(rm[f])
	return out if not out.is_empty() else EMPTY


## Armour thickness multiplier for a CN suit / APC of a side with Heavier plates (1.0 otherwise).
static func armour_mult(w: SimWorld, target) -> float:
	var st = w.sys_state.get(KEY)
	if st == null or typeof(target) != TYPE_DICTIONARY:
		return 1.0
	var u = st.up.get(str(int(target.get("owner", -1))))
	if u == null or not u.has("plates") or not is_cn(target):
		return 1.0
	return float(_sect("upgrades").get("plates", {}).get("armour", 1.0))


## True when the side's Suppressors upgrade is on for this CN unit (for fog / sense: quieter shots).
static func quiet(w: SimWorld, e) -> bool:
	var st = w.sys_state.get(KEY)
	if st == null or typeof(e) != TYPE_DICTIONARY:
		return false
	var u = st.up.get(str(int(e.get("owner", -1))))
	return u != null and u.has("suppressors") and is_cn(e)


static func is_cn(e: Dictionary) -> bool:
	if int(e.get("cn_team", -1)) >= 0 or e.has("a7"):
		return true
	var d := Content.unit(String(e.get("def", "")))
	return d.has("cn_line") or String(d.get("cn_suit", "")) != ""


# ================================================================ commands
const TYPES := ["c8b_preset", "c8b_suit_build", "c8b_suit_rush", "c8b_suit_repair", "c8b_upgrade", "c8b_veh_repair",
	"c8b_veh_upgrade", "c8b_convoy", "c8b_recall", "c8b_decon_force", "c8b_decon_skip"]


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	return reason(w, cmd)


## "" when cmd can be applied now, else the refusal shown on the card (disabled button tooltip).
static func reason(w: SimWorld, cmd: Dictionary) -> String:
	var ty := String(cmd.get("type", ""))
	if not TYPES.has(ty):
		return "Unknown facility card command."
	var fid := int(cmd.get("issuer", -1))
	var F := _fac(w, int(cmd.get("building_id", -1)))
	if F.is_empty():
		return "Select your counter-nanite facility."
	if int(F.owner) != fid:
		return "Not your facility."
	var FS := fs(w, int(F.id))
	match ty:
		"c8b_preset":
			if not (R().get("roles", []) as Array).has(String(cmd.get("role", ""))):
				return "Unknown team role."
			var p := String(cmd.get("preset", ""))
			if p != "" and not _sect("presets").has(p):
				return "Unknown loadout preset."
			return ""
		"c8b_suit_build":
			var ap = armory_part(w, F)
			if ap == null:
				return "The Suit Foundry is gone."
			var item := suit_item(w, fid, String(cmd.get("role", "")))
			if item == "":
				return "Your side has no %s suit." % String(cmd.get("role", "?"))
			return SimWorld.Production.validate_command(w, {"type": "queue_unit", "issuer": fid, "building_id": int(ap.id), "item": item})
		"c8b_suit_rush":
			var ap = armory_part(w, F)
			if ap == null:
				return "The Suit Foundry is gone."
			if (ap.get("queue", []) as Array).is_empty():
				return "No suit in the build queue to rush."
			return w.can_afford(fid, rush_cost(ap.queue[0]))
		"c8b_suit_repair":
			if armory_part(w, F) == null:
				return "The Suit Foundry is gone."
			var uid := int(cmd.get("unit_id", -1))
			if uid < 0:
				var dm := damaged_suits(w, fid)
				for q in FS.get("rq", []):
					dm.erase(int(q))
				return "" if not dm.is_empty() else "No damaged suits waiting for repair."
			var e = w.entities.get(uid)
			if e == null or int(e.owner) != fid or not is_suit(e):
				return "Pick one of your armoured suits."
			if float(e.hp) >= _maxhp(e) - 0.01:
				return "That suit is not damaged."
			return "That suit is already in the repair queue." if (FS.get("rq", []) as Array).has(uid) else ""
		"c8b_upgrade":
			var k := String(cmd.get("key", ""))
			var U := _sect("upgrades")
			if not U.has(k):
				return "Unknown upgrade."
			if armory_part(w, F) == null:
				return "The Suit Foundry is gone."
			if side_up(w, fid).has(k):
				return "%s already fitted." % String(U[k].get("name", k))
			var rs: Dictionary = FS.get("res", {})
			if not rs.is_empty():
				return "The armory is already researching %s." % String(U.get(String(rs.key), {}).get("name", rs.key))
			return w.can_afford(fid, U[k].get("cost", {}))
		"c8b_veh_repair":
			var T := _team(w, F, int(cmd.get("team", -1)))
			if T.is_empty():
				return "Pick one of this facility's vehicle teams."
			if (FS.get("vq", []) as Array).has(int(T.id)):
				return ""   # toggles it off again
			for a in team_apcs(w, T):
				if float(a.hp) < _maxhp(a) - 0.01:
					return ""
			return "Those vehicles are not damaged."
		"c8b_veh_upgrade":
			var T := _team(w, F, int(cmd.get("team", -1)))
			if T.is_empty():
				return "Pick one of this facility's vehicle teams."
			var k := String(cmd.get("key", ""))
			var V := _sect("veh_upgrades")
			if not V.has(k):
				return "Unknown vehicle upgrade."
			if String(T.phase) != "garage":
				return "The vehicles must be parked in their garage."
			var aps := team_apcs(w, T)
			if aps.is_empty():
				return "No vehicle left in that team."
			var all_have := true
			for a in aps:
				if not (a.get("c8u", {}) as Dictionary).has(k):
					all_have = false
			if all_have:
				return "%s already fitted." % String(V[k].get("name", k))
			if k == "dome_shield":
				for a in aps:
					if not a.has("a7") or (SimWorld.Apc7.cfg_of(String(a.def)).get("dome", {}) as Dictionary).is_empty():
						return "These vehicles have no dome emitter."
			if k == "rocket_pod":
				for a in aps:
					if not a.has("a7") or not a.a7.has("rl"):
						return "These vehicles have no rocket launcher."
			return w.can_afford(fid, V[k].get("cost", {}))
		"c8b_convoy":
			if _pt(cmd.get("target")) == null:
				return "Pick a destination."
			var ids := convoy_teams(w, F, cmd.get("teams", []))
			if ids.is_empty():
				return "No vehicle team is parked in a garage."
			for tid in ids:
				var r := String(SimWorld.CnFacility.validate_command(w, {"type": "cn_rollout", "issuer": fid, "team": tid, "target": _pt(cmd.target)}))
				if r != "":
					return r
			return ""
		"c8b_recall":
			return "" if not out_teams(w, F).is_empty() else "No vehicle team is out."
		"c8b_decon_force":
			if SimWorld.CnFacility.zone(F, "decon").size == Vector2.ZERO:
				return "The facility has no decon wash."
			return "" if not contaminated(w, fid).is_empty() else "Nobody is contaminated."
		"c8b_decon_skip":
			return ""
	return "Unknown facility card command."


## Parked teams a convoy order takes: the listed ones that are parked, or every parked team when the list is empty.
static func convoy_teams(w: SimWorld, F: Dictionary, want) -> Array:
	var out := []
	var lst: Array = want if typeof(want) == TYPE_ARRAY else []
	for T in teams(w, F):
		if String(T.phase) != "garage" or team_apcs(w, T).is_empty():
			continue
		if lst.is_empty() or lst.has(int(T.id)) or lst.has(float(T.id)):
			out.append(int(T.id))
	return out


static func out_teams(w: SimWorld, F: Dictionary) -> Array:
	var out := []
	for T in teams(w, F):
		if String(T.phase) == "out":
			out.append(int(T.id))
	return out


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var ty := String(cmd.get("type", ""))
	var fid := int(cmd.issuer)
	var F := _fac(w, int(cmd.building_id))
	var fac := int(F.id)
	match ty:
		"c8b_preset":
			var S := _fs(w, fac)
			var role := String(cmd.role)
			var p := String(cmd.get("preset", ""))
			if p == "":
				S.presets.erase(role)
			else:
				S.presets[role] = p
			for T in teams(w, F):
				if team_role(w, T) == role:
					S.applied.erase(str(int(T.id)))
			w.emit("C8bPresetSet", {"fac": fac, "owner": fid, "role": role, "preset": p})
			_pickup(w, F, S)   # parked teams re-equip at once
		"c8b_suit_build":
			var ap = armory_part(w, F)
			var item := suit_item(w, fid, String(cmd.role))
			SimWorld.Production.apply_command(w, {"type": "queue_unit", "issuer": fid, "building_id": int(ap.id), "item": item})
			_fs(w, fac)
			w.emit("C8bSuitQueued", {"fac": fac, "owner": fid, "role": String(cmd.role), "item": item})
		"c8b_suit_rush":
			var ap = armory_part(w, F)
			var head: Dictionary = ap.queue[0]
			if not w.spend(fid, rush_cost(head), "c8b_rush"):
				return
			head.progress = minf(0.999, float(head.progress) + float(_sect("rush").get("frac", 0.5)))
			_fs(w, fac)
			w.emit("C8bSuitRushed", {"fac": fac, "owner": fid, "item": String(head.item), "progress": float(head.progress)})
		"c8b_suit_repair":
			var S := _fs(w, fac)
			var ap = armory_part(w, F)
			var ids := [int(cmd.get("unit_id", -1))] if int(cmd.get("unit_id", -1)) >= 0 else damaged_suits(w, fid)
			var spot := _repair_spot(F, ap)
			for uid in ids:
				if (S.rq as Array).has(int(uid)):
					continue
				S.rq.append(int(uid))
				var e = w.entities.get(int(uid))
				if e != null and String(e.order.get("type", "")) != "hold":
					SimWorld.Movement.order_move(w, e, spot)
			w.emit("C8bSuitRepairQueued", {"fac": fac, "owner": fid, "ids": ids})
		"c8b_upgrade":
			var k := String(cmd.key)
			var U: Dictionary = _sect("upgrades")[k]
			if not w.spend(fid, U.get("cost", {}), "c8b_upgrade:" + k):
				return
			var S := _fs(w, fac)
			S.res = {"key": k, "left": secs(U.get("time_s", 30)), "total": secs(U.get("time_s", 30))}
			w.emit("C8bUpgradeStarted", {"fac": fac, "owner": fid, "key": k})
		"c8b_veh_repair":
			var S := _fs(w, fac)
			var tid := int(cmd.team)
			if (S.vq as Array).has(tid):
				S.vq.erase(tid)
			else:
				S.vq.append(tid)
			w.emit("C8bVehRepairQueue", {"fac": fac, "owner": fid, "queue": (S.vq as Array).duplicate()})
		"c8b_veh_upgrade":
			var k := String(cmd.key)
			var V: Dictionary = _sect("veh_upgrades")[k]
			if not w.spend(fid, V.get("cost", {}), "c8b_veh:" + k):
				return
			_fs(w, fac)
			var T := _team(w, F, int(cmd.team))
			for a in team_apcs(w, T):
				fit(w, a, k)
			w.emit("C8bVehUpgraded", {"fac": fac, "owner": fid, "team": int(T.id), "key": k})
		"c8b_convoy":
			_fs(w, fac)
			var tg = _pt(cmd.target)
			var ids := convoy_teams(w, F, cmd.get("teams", []))
			for tid in ids:
				SimWorld.CnFacility.apply_command(w, {"type": "cn_rollout", "issuer": fid, "team": tid, "target": tg})
			w.emit("C8bConvoy", {"fac": fac, "owner": fid, "teams": ids, "target": [tg.x, tg.y]})
		"c8b_recall":
			_fs(w, fac)
			var ids := out_teams(w, F)
			for tid in ids:
				SimWorld.CnFacility.apply_command(w, {"type": "cn_return", "issuer": fid, "team": tid})
			w.emit("C8bRecall", {"fac": fac, "owner": fid, "teams": ids})
		"c8b_decon_force":
			_fs(w, fac)
			var wash: Vector2 = SimWorld.CnFacility.zone(F, "decon").get_center()
			var sent := []
			var back := []
			var ids := contaminated(w, fid)
			for uid in ids:
				var e: Dictionary = w.entities[uid]
				var tid := SimWorld.CounterNanite.team_of(e)
				var T := _team(w, F, tid) if tid >= 0 else {}
				if not T.is_empty() and String(T.phase) == "out":
					if not back.has(tid):
						back.append(tid)
					continue
				if T.is_empty() and not e.has("cargo") and String(e.order.get("type", "")) != "hold":
					SimWorld.Movement.order_move(w, e, wash)
					sent.append(uid)
			for tid in back:
				SimWorld.CnFacility.apply_command(w, {"type": "cn_return", "issuer": fid, "team": tid})
			w.emit("C8bDeconForced", {"fac": fac, "owner": fid, "units": sent, "teams": back})
		"c8b_decon_skip":
			var S := _fs(w, fac)
			S.skip = bool(cmd.get("on", true))
			w.emit("C8bDeconSkip", {"fac": fac, "owner": fid, "on": bool(S.skip)})


static func _repair_spot(F: Dictionary, ap) -> Vector2:
	if ap != null and ap.get("rally") != null:
		return Vector2(ap.rally)
	return SimWorld.CnFacility.zone(F, "armory").get_center()


## Fits vehicle upgrade k to APC a (idempotent).
static func fit(w: SimWorld, a: Dictionary, k: String) -> void:
	var u: Dictionary = a.get("c8u", {})
	if u.has(k):
		return
	var V: Dictionary = _sect("veh_upgrades").get(k, {})
	u[k] = true
	a.c8u = u
	match k:
		"armour_kit":
			var m := float(V.get("hp_mult", 1.25))
			var mh := _maxhp(a)
			a.max_hp = mh * m
			a.hp = float(a.hp) * m
		"engines":
			a.c8mv = float(V.get("speed_mult", 1.15))
		"dome_shield":
			_dome_boost(a)
		"rocket_pod":
			_pod_top(a)


static func _dome_boost(a: Dictionary) -> void:
	if not a.has("a7"):
		return
	var ch := float(SimWorld.Apc7.cfg_of(String(a.def)).get("dome", {}).get("charge", 1000.0))
	var m := float(_sect("veh_upgrades").get("dome_shield", {}).get("dome_mult", 1.5))
	if float(a.a7.dome) <= 0.0:
		a.erase("c8db")
	elif float(a.a7.dome) >= ch - 0.001 and not bool(a.get("c8db", false)):
		a.a7.dome = ch * m
		a.c8db = true


static func _pod_top(a: Dictionary) -> void:
	if not a.has("a7") or not a.a7.has("rl"):
		return
	var V: Dictionary = _sect("veh_upgrades").get("rocket_pod", {})
	var base := 0
	for k in a.a7.rl.load:
		base += int(a.a7.rl.load[k])
	var have := int(SimWorld.Apc7.rockets_left(a))
	var want := base + int(V.get("rounds", 6))
	if have >= base and have < want:
		var kind := String(V.get("kind", "tandem"))
		a.a7.rl.rk[kind] = int(a.a7.rl.rk.get(kind, 0)) + (want - have)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	var st = w.sys_state.get(KEY)
	if st == null:
		return
	var n := int(R().get("think_every", 20))
	var ks: Array = st.facs.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var fac := int(k)
		if (w.tick + fac) % n != 0:
			continue
		var F := _fac(w, fac)
		if F.is_empty():
			continue
		_think(w, F, st.facs[k], n)


static func _think(w: SimWorld, F: Dictionary, S: Dictionary, n: int) -> void:
	var fid := int(F.owner)
	var fac := int(F.id)
	var dt := float(n) / SimWorld.TICK_RATE
	# weapon upgrade research
	var rs: Dictionary = S.get("res", {})
	if not rs.is_empty():
		rs.left = int(rs.left) - n
		if int(rs.left) <= 0:
			var st := _st(w)
			if not st.up.has(str(fid)):
				st.up[str(fid)] = {}
			st.up[str(fid)][String(rs.key)] = true
			w.emit("C8bUpgradeDone", {"fac": fac, "owner": fid, "key": String(rs.key)})
			S.res = {}
	_stamp(w, fid)
	_pickup(w, F, S)
	var under := (_sect("decon").get("under_fire_states", ["under_fire", "breached"]) as Array).has(SimWorld.CnFacility.secure_state(w, fac))
	for T in teams(w, F):
		var ph := String(T.phase)
		for a in team_apcs(w, T):
			var u: Dictionary = a.get("c8u", {})
			if u.is_empty():
				continue
			if u.has("dome_shield"):
				_dome_boost(a)
			if u.has("rocket_pod") and ph == "garage":
				_pod_top(a)
		if ph == "returning" and bool(S.get("skip", false)) and under:
			var skipped := false
			for a in team_apcs(w, T):
				if int(a.get("cn_rinsed", -1)) < int(T.t):
					a.cn_rinsed = w.tick
					skipped = true
			if skipped:
				w.emit("C8bDeconSkipped", {"fac": fac, "owner": fid, "team": int(T.id)})
	# workshop priority repair: the first queued team parked and damaged gets the crew
	var vr := _sect("veh_repair")
	var vq: Array = S.get("vq", [])
	for tid in vq.duplicate():
		var T := _team(w, F, int(tid))
		if T.is_empty():
			vq.erase(tid)
			continue
		var dmg := []
		for a in team_apcs(w, T):
			if float(a.hp) < _maxhp(a) - 0.01:
				dmg.append(a)
		if dmg.is_empty():
			vq.erase(tid)
			w.emit("C8bVehRepaired", {"fac": fac, "owner": fid, "team": int(tid)})
			continue
		if String(T.phase) != "garage":
			continue
		var a: Dictionary = dmg[0]
		var rep := minf(float(vr.get("hp_s", 60.0)) * dt, _maxhp(a) - float(a.hp))
		var c := int(ceil(rep * float(vr.get("credits_per_hp", 0.3))))
		if c > 0 and not w.spend(fid, {"credits": c}, "c8b_veh_repair"):
			break
		a.hp = float(a.hp) + rep
		break
	# Suit Foundry repair queue: the first queued suit standing at the bay doors
	var sr := _sect("suit_repair")
	var rq: Array = S.get("rq", [])
	var spot := _repair_spot(F, armory_part(w, F))
	for uid in rq.duplicate():
		var e = w.entities.get(int(uid))
		if e == null or int(e.owner) != fid:
			rq.erase(uid)
			continue
		if float(e.hp) >= _maxhp(e) - 0.01:
			rq.erase(uid)
			w.emit("C8bSuitRepaired", {"fac": fac, "owner": fid, "id": int(uid)})
			continue
		if Vector2(e.pos).distance_to(spot) > float(sr.get("reach", 2.5)):
			continue
		var rep := minf(float(sr.get("hp_s", 40.0)) * dt, _maxhp(e) - float(e.hp))
		var c := int(ceil(rep * float(sr.get("credits_per_hp", 0.4))))
		if c > 0 and not w.spend(fid, {"credits": c}, "c8b_suit_repair"):
			break
		e.hp = float(e.hp) + rep
		break


## Teams of a role with a preset pick it up while parked unlocked in their garage.
## Weapon upgrades reach LETHAL8's ballistics through the saved entity fields it reads (fact api.rounds8): every CN
## unit of a side with researched upgrades carries e.r8up (round multipliers) / e.a8up (Heavier plates), id "c8b:..."
## so a field set by someone else (e.g. an ammo-mix id) is never overwritten. Sides without upgrades: one lookup.
static func _stamp(w: SimWorld, fid: int) -> void:
	var u = _st(w).up.get(str(fid))
	if u == null or (u as Dictionary).is_empty():
		return
	var U := _sect("upgrades")
	var rm := {}
	var am := 1.0
	var keys := []
	for k in R().get("upgrade_order", []):
		if not u.has(k):
			continue
		keys.append(String(k))
		var r = U.get(k, {}).get("round")
		if typeof(r) == TYPE_DICTIONARY:
			for f in r:
				rm[f] = float(rm.get(f, 1.0)) * float(r[f])
		am *= float(U.get(k, {}).get("armour", 1.0))
	var id := "c8b:" + ",".join(keys)
	for e in w.entities.values():
		if int(e.get("owner", -1)) != fid or not is_cn(e):
			continue
		if not rm.is_empty() and (not e.has("r8up") or (String(e.r8up.get("id", "")).begins_with("c8b:") and String(e.r8up.id) != id)):
			var r8 := rm.duplicate()
			r8.id = id
			e.r8up = r8
		if am != 1.0 and (not e.has("a8up") or (String(e.a8up.get("id", "")).begins_with("c8b:") and String(e.a8up.id) != id)):
			e.a8up = {"id": id, "t": am}


static func _pickup(w: SimWorld, F: Dictionary, S: Dictionary) -> void:
	var pr: Dictionary = S.get("presets", {})
	if pr.is_empty():
		return
	for T in teams(w, F):
		if String(T.phase) != "garage":
			continue
		var p := String(pr.get(team_role(w, T), ""))
		if p == "" or String(S.applied.get(str(int(T.id)), "")) == p:
			continue
		var t7 = SimWorld.CounterNanite.team(w, int(T.id))
		if t7 == null or bool(t7.get("locked", false)):
			continue
		var cmd := preset_cmd(w, T, p)
		if String(SimWorld.CounterNanite.validate_command(w, cmd)) != "":
			cmd.erase("packages")
			if String(SimWorld.CounterNanite.validate_command(w, cmd)) != "":
				continue
		SimWorld.CounterNanite.apply_command(w, cmd)
		S.applied[str(int(T.id))] = p
		w.emit("C8bPresetPicked", {"fac": int(F.id), "owner": int(F.owner), "team": int(T.id), "preset": p})


# ================================================================ card summaries (presentation reads; never writes)
static func armory_summary(w: SimWorld, fac: int) -> Dictionary:
	var F := _fac(w, fac)
	if F.is_empty():
		return {}
	var fid := int(F.owner)
	var S := fs(w, fac)
	var ap = armory_part(w, F)
	var q := []
	if ap != null:
		for it in ap.get("queue", []):
			q.append({"item": String(it.item), "name": String(Content.production(String(it.item)).get("name", it.item)), "progress": float(it.progress)})
	var dm := []
	for id in damaged_suits(w, fid):
		var e: Dictionary = w.entities[id]
		dm.append({"id": int(id), "name": String(Content.unit(String(e.def)).get("name", e.def)), "hp": float(e.hp), "max": _maxhp(e),
			"queued": (S.get("rq", []) as Array).has(int(id))})
	var up := {}
	for k in R().get("upgrade_order", []):
		up[k] = "on" if side_up(w, fid).has(k) else ("research" if String(S.get("res", {}).get("key", "")) == k else "")
	var rs: Dictionary = S.get("res", {})
	return {"fac": fac, "owner": fid, "armory": int(ap.id) if ap != null else -1, "presets": (S.get("presets", {}) as Dictionary).duplicate(),
		"queue": q, "damaged": dm, "up": up, "res_key": String(rs.get("key", "")),
		"res_left_s": float(rs.get("left", 0)) / SimWorld.TICK_RATE, "res_frac": 1.0 - float(rs.get("left", 0)) / maxf(1.0, float(rs.get("total", 1)))}


static func garage_summary(w: SimWorld, fac: int) -> Dictionary:
	var F := _fac(w, fac)
	if F.is_empty():
		return {}
	var fid := int(F.owner)
	var S := fs(w, fac)
	var tl := []
	for T in teams(w, F):
		var aps := []
		for a in team_apcs(w, T):
			var d := Content.unit(String(a.def))
			aps.append({"id": int(a.id), "hp": float(a.hp), "max": _maxhp(a), "fuel": float(a.get("fuel", d.get("fuel_max", 100.0))),
				"fuel_max": float(d.get("fuel_max", 100.0)), "ammo": float(a.get("ammo", d.get("ammo_max", 0))), "ammo_max": float(d.get("ammo_max", 0)),
				"rockets": int(SimWorld.Apc7.rockets_left(a)), "ups": (a.get("c8u", {}) as Dictionary).keys()})
		tl.append({"id": int(T.id), "kind": String(T.kind), "role": team_role(w, T), "phase": String(T.phase), "apcs": aps,
			"queued": (S.get("vq", []) as Array).find(int(T.id))})
	var cl := []
	for id in contaminated(w, fid):
		var e: Dictionary = w.entities[id]
		cl.append({"id": int(id), "name": String(Content.unit(String(e.def)).get("name", e.def)), "exp": float(e.get("cn_exp", 0.0))})
	return {"fac": fac, "owner": fid, "teams": tl, "contaminated": cl, "skip": bool(S.get("skip", false)),
		"state": SimWorld.CnFacility.secure_state(w, fac), "vq": (S.get("vq", []) as Array).duplicate()}
