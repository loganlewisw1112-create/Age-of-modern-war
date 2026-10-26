extends RefCounted
## General war effort (owner: GEN61). G6.1: what an auto general (general.gd) does beyond the battle:
##   budget       the player grants a slot credits / salvage / ore per minute and/or a lump sum
##                (set_ai_commander budget field, or set_ai_budget). The general spends ONLY that: every
##                purchase is pre-validated through the owner system and the cost is booked against the
##                slot's budget before it is submitted, so the slot never spends past its grant.
##   replacements trains replacement companies at the side's Company HQ (train_company, the normal command
##                path) when the slot is depleted; a company that forms from its order joins the slot.
##   fire support calls strikes the side owns (Strikes: strike units in the slot, the side's batteries) on
##                belief targets; respects cooldowns / range (Strikes.strike_error) and never fires
##                danger-close (an own unit within danger_close of the aim point).
##   logistics    supply trucks in the slot go to station resupply at the rally point while it refits.
## State: slot S.budget = {rate {credits, salvage, ore} per minute, lump {..}, spent {..}, since (tick the
##   current rate started), banked {..} (earned before the last rate change)}; S.gen.train [{tid, tick,
##   max_cid}], S.gen.fire_tick. Saved and hashed with the slot. Amounts are ints.

const L = preload("res://sim/ai/ai_g6_lib.gd")
const Companies = preload("res://sim/systems/companies.gd")
const RES := ["credits", "salvage", "ore"]
const RULES := {"war_ticks": 100, "fire_ticks": 100, "replace_strength": 0.7, "danger_close": 7.0,
	"train_wait": 2400, "max_training": 1}


static func W(key: String):
	var ac = Content.rules().get("ai_cmd", null)
	var src = ac.get("war", null) if ac is Dictionary else null
	if src is Dictionary and src.has(key):
		return src[key]
	return RULES.get(key)


## A budget dict from a command field: {credits_pm?, salvage_pm?, ore_pm?, lump?: {credits?, salvage?, ore?}}.
## Missing / malformed -> a zero budget.
static func parse_budget(w: SimWorld, v) -> Dictionary:
	var b := {"rate": {}, "lump": {}, "spent": {}, "banked": {}, "since": w.tick}
	for k in RES:
		b.rate[k] = 0
		b.lump[k] = 0
		b.spent[k] = 0
		b.banked[k] = 0
	if v is Dictionary:
		for k in RES:
			b.rate[k] = maxi(0, int(v.get(k + "_pm", 0)))
		var lp = v.get("lump", {})
		if lp is Dictionary:
			for k in RES:
				b.lump[k] = maxi(0, int(lp.get(k, 0)))
	return b


## Validation message for a budget field ("" = fine).
static func budget_error(v) -> String:
	if v == null:
		return ""
	if not (v is Dictionary):
		return "Budget must be per-minute amounts and/or a lump sum."
	for k in RES:
		if int(v.get(k + "_pm", 0)) < 0:
			return "Budget amounts cannot be negative."
	var lp = v.get("lump", {})
	if not (lp is Dictionary):
		return "Budget lump sum must list credits, salvage and ore."
	for k in RES:
		if int(lp.get(k, 0)) < 0:
			return "Budget amounts cannot be negative."
	return ""


## Earned so far of resource k (banked + lump + rate x minutes since).
static func earned(w: SimWorld, b: Dictionary, k: String) -> int:
	var ticks := maxi(0, w.tick - int(b.since))
	return int(b.banked.get(k, 0)) + int(b.lump.get(k, 0)) + int(b.rate.get(k, 0)) * ticks / (60 * SimWorld.TICK_RATE)


## Budget left of resource k.
static func left(w: SimWorld, b: Dictionary, k: String) -> int:
	return earned(w, b, k) - int(b.spent.get(k, 0))


## {credits, salvage, ore} left for the slot ({} when it has no budget).
static func budget_left(w: SimWorld, s: Dictionary) -> Dictionary:
	var b = s.get("budget", null)
	if not (b is Dictionary):
		return {}
	var out := {}
	for k in RES:
		out[k] = left(w, b, k)
	return out


## Replaces the rate / adds a lump while keeping what was earned and spent.
static func update_budget(w: SimWorld, s: Dictionary, v) -> void:
	var nb := parse_budget(w, v)
	var b = s.get("budget", null)
	if b is Dictionary:
		for k in RES:
			nb.banked[k] = earned(w, b, k)
			nb.spent[k] = int(b.spent.get(k, 0))
	s.budget = nb


static var _gs: Script = null


## general.gd, loaded lazily (it preloads this file).
static func Gen() -> Script:
	if _gs == null:
		_gs = load("res://sim/ai/general.gd")
	return _gs


## True when the slot's budget covers cost (resources outside RES must be 0).
static func affordable(w: SimWorld, s: Dictionary, cost: Dictionary) -> bool:
	var b = s.get("budget", null)
	if not (b is Dictionary):
		return false
	for k in cost:
		var need := int(cost[k])
		if need <= 0:
			continue
		if not RES.has(String(k)) or left(w, b, String(k)) < need:
			return false
	return true


static func book(s: Dictionary, cost: Dictionary) -> void:
	var b: Dictionary = s.budget
	for k in cost:
		if RES.has(String(k)):
			b.spent[k] = int(b.spent.get(k, 0)) + int(cost[k])


static func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in RES:
		if int(cost.get(k, 0)) > 0:
			parts.append("%d %s" % [int(cost[k]), k])
	return ", ".join(parts) if not parts.is_empty() else "free"


## Companies that formed from the slot's own train orders join the slot.
static func adopt(w: SimWorld, fid: int, s: Dictionary) -> void:
	var g: Dictionary = s.gen
	var tr: Array = g.get("train", [])
	if tr.is_empty():
		return
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	var claimed := {}
	var ss: Dictionary = (w.sys_state.ai_cmd.slots as Dictionary).get(fid, {})
	for k in ss:
		for cid in (ss[k] as Dictionary).spec.get("companies", []):
			claimed[int(cid)] = true
	var keys := cs.keys()
	keys.sort()
	var keep := []
	for t in tr:
		var got := -1
		for cid in keys:
			var c: Dictionary = cs[cid]
			if int(c.get("owner", -1)) == fid and int(cid) > int(t.max_cid) and not claimed.has(int(cid)) \
					and String(c.get("template", "")) == String(t.tid):
				got = int(cid)
				break
		if got >= 0:
			claimed[got] = true
			var spec: Dictionary = s.spec
			if not spec.has("companies"):
				spec.companies = []
			spec.companies.append(got)
			Gen().log_line(w, s, "War effort: replacement company %d joined (%d units)." % [got, C_units(w, fid, cs[got])])
		elif w.tick - int(t.tick) < int(W("train_wait")):
			keep.append(t)
	g.train = keep


static func C_units(w: SimWorld, fid: int, c: Dictionary) -> int:
	return (Gen().C().company_units(w, fid, c) as Array).size()


## Trains a replacement company at the side's Company HQ when the slot is depleted and its budget allows.
static func replace(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String) -> void:
	var g: Dictionary = s.gen
	if (g.get("train", []) as Array).size() >= int(W("max_training")):
		return
	var mine: float = Gen().own_power(us)
	if mine >= float(s.get("peak_power", mine)) * float(W("replace_strength")) and not us.is_empty():
		return
	var hq := Companies.hq_of(w, fid)
	if hq.is_empty():
		return
	var tids := []
	var cs: Dictionary = w.sys_state.get("companies", {}).get("companies", {})
	for cid in (s.spec as Dictionary).get("companies", []):
		var c = cs.get(int(cid))
		if c is Dictionary and not tids.has(String(c.get("template", ""))):
			tids.append(String(c.template))
	for t in Companies.templates_for(fid, w):
		if not tids.has(String(t)):
			tids.append(String(t))
	for tid in tids:
		var t := Companies.template(w, fid, String(tid))
		if t.is_empty():
			continue
		for size in ["company", "platoon"]:
			var cmd := {"type": "train_company", "issuer": fid, "building_id": int(hq.id), "template": String(tid),
				"size": size}
			if Companies.validate_command(w, cmd) != "":
				continue
			var pl := Companies.plan(w, fid, t, size, not String(tid).begins_with("custom:"))
			var cost: Dictionary = pl.cost
			if not affordable(w, s, cost):
				continue
			cmd.ai_cmd = badge
			if not bool(w.submit(cmd).ok):
				return
			book(s, cost)
			var st: Dictionary = w.sys_state.get("companies", {})
			if not g.has("train"):
				g.train = []
			g.train.append({"tid": String(tid), "tick": w.tick, "max_cid": int(st.get("next_cid", 1)) - 1})
			Gen().log_line(w, s, "War effort: training a replacement %s (%s) for %s." % [size, String(tid), _cost_text(cost)])
			w.emit("AiGeneralSpend", {"fid": fid, "slot": int(s.get("slot", -1)), "what": "train_company",
				"cost": cost.duplicate(), "left": budget_left(w, s)})
			return


## True when no unit of fid's team is within r of p (danger-close check).
static func clear_of_friends(w: SimWorld, fid: int, p: Vector2, r: float) -> bool:
	var team := int(w.factions[fid].team)
	var fids := w.factions.keys()
	fids.sort()
	for f in fids:
		if int(w.factions[f].team) != team:
			continue
		for e in w.units_of(int(f)):
			if (e.pos as Vector2).distance_to(p) <= r:
				return false
	return true


## Calls the side's strikes (slot strike units, the side's batteries) on believed enemy groups.
static func fire_support(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String) -> void:
	var Sk := L.sys("strikes")
	if Sk == null or not L.api(Sk, "kind_of") or not L.api(Sk, "strike_error"):
		return
	var strikers := []
	for e in us:
		if String(Sk.call("kind_of", e)) != "" and not Gen().C().fresh(w, e):
			strikers.append(e)
	for b in w.buildings_of(fid):
		if String(Sk.call("kind_of", b)) != "":
			strikers.append(b)
	if strikers.is_empty():
		return
	var cl: Array = Gen().clusters(Gen().belief(w, fid))
	cl.sort_custom(func(a, b):
		var va := float(a.value) * float(a.power)
		var vb := float(b.value) * float(b.power)
		if va != vb:
			return va > vb
		return int(a.ids[0]) < int(b.ids[0]))
	var dc := float(W("danger_close"))
	for e in strikers:
		for c in cl:
			var p: Vector2 = c.pos
			var cell := [floori(p.x), floori(p.y)]
			var aim := Vector2(cell[0], cell[1]) + Vector2(0.5, 0.5)
			if String(Sk.call("strike_error", w, e, aim)) != "" or not clear_of_friends(w, fid, aim, dc):
				continue
			var cmd := {"type": "strike", "issuer": fid, "cell": cell, "ai_cmd": badge}
			if e.kind == "building":
				cmd.building_id = int(e.id)
			else:
				cmd.unit_ids = [int(e.id)]
			if not bool(w.submit(cmd).ok):
				continue
			Gen().tag(w, fid, s, "suppress", [int(e.id)], "Fire support: strike on %d enemies at (%d, %d), no friendlies within %d." % [
				int(c.n), cell[0], cell[1], int(dc)])
			w.emit("AiFireSupport", {"fid": fid, "slot": int(s.get("slot", -1)), "src": int(e.id), "cell": Vector2i(cell[0], cell[1])})
			break


## Supply trucks in the slot hold station resupply at the rally point while it refits.
static func logistics(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, rally: Vector2) -> void:
	var op: Dictionary = s.gen.op
	if op.is_empty() or String(op.type) != "refit" or int(s.gen.get("resup_op", -1)) == int(op.id):
		return
	s.gen.resup_op = int(op.id)
	for e in us:
		if not bool(Content.unit(String(e.def)).get("is_supply", false)) or Gen().C().fresh(w, e):
			continue
		var cmd := {"type": "set_auto_resupply", "issuer": fid, "unit_id": int(e.id), "mode": "station",
			"center": [floori(rally.x), floori(rally.y)], "ai_cmd": badge}
		if bool(w.submit(cmd).ok):
			Gen().log_line(w, s, "Logistics: supply truck %d on station resupply at (%d, %d)." % [int(e.id), int(rally.x), int(rally.y)])


## One war-effort pass for an auto general (called from General.think every think).
static func tick(w: SimWorld, fid: int, s: Dictionary, us: Array, badge: String, rally: Vector2, slot: int) -> void:
	var g: Dictionary = s.gen
	adopt(w, fid, s)
	if w.tick >= int(g.get("war_tick", 0)):
		g.war_tick = w.tick + int(W("war_ticks"))
		replace(w, fid, s, us, badge)
	if w.tick >= int(g.get("fire_tick", 0)):
		g.fire_tick = w.tick + int(W("fire_ticks"))
		fire_support(w, fid, s, us, badge)
	logistics(w, fid, s, us, badge, rally)
