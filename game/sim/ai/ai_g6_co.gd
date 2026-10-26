extends RefCounted
## AiG6 land forces (owner: AI7-USE). CONTRACTS_G6 §8, §14, §16: the AI builds a Company HQ, trains
## companies from its faction's templates (Companies.templates_for), trains a Commander and forms an
## army of 2-4 companies; sets loadouts on its infantry near a barracks / the Company HQ by threat
## (Loadouts.loadouts_for); Human A builds an Exo-Suit Garage, fields suits and re-suits ejected
## pilots. Every command goes through the owner's command (train_company, train_commander,
## form_army, set_loadout, resuit); a stub refusal (not_implemented) parks the action for a while.

const U = preload("res://sim/ai/ai_util.gd")
const Economy = preload("res://sim/systems/economy.gd")  # cap_max_for: 200 with a built Company HQ (ECON-AIRF6-2)
const L = preload("res://sim/ai/ai_g6_lib.gd")

const HQ_ARMY := 10          # army pop before the Company HQ is worth its price
const CO_CREDITS := [1200, 2400, 3600]  # free credits (beyond the stage bank) for platoon / company / battalion
const CO_MAX := 4
const CO_GAP := 90 * SimWorld.TICK_RATE
const LOADOUT_NEAR := 8.0    # tiles from the barracks / Company HQ (EXO6 checks its own range)
const LOADOUT_BATCH := 8
const GARAGE_ARMY := 14
const PARK := 3000           # backoff after a not_implemented refusal (system still a stub)


static func _park_if_stub(st: Dictionary, w: SimWorld, key: String) -> void:
	if String(st.get("last_result", "")).find("not_implemented") >= 0:
		U.set_backoff(st, w, key, PARK)


static func _free_credits(w: SimWorld, fid: int, st: Dictionary) -> int:
	var res: Dictionary = st.get("g4", {}).get("reserve", {})
	var own := int(st.get("g4", {}).get("pre_co", 0))  # AI7-USE-4: our own banked share (ai_stage)
	return int(w.factions[fid].credits) - maxi(0, int(res.get("credits", 0)) - own)


static func manage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	if String(st.objective) == "defend":
		return
	_company_hq(w, fid, st, ctx, g)
	_companies(w, fid, st, ctx, g)
	_army(w, fid, st, ctx, g)
	_garage(w, fid, st, ctx, g)
	_loadouts(w, fid, st, ctx, g)


## Every think (cheap): ejected pilots re-suit at a garage.
static func manage_units(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var gdef := L.rdef(w, fid, "exo_garage")
	if gdef == "" or U.blocked(st, w, "g6:resuit"):
		return
	var garage = L.facility(ctx, gdef, 99)
	if garage == null:
		return
	for e in ctx.units:
		var suit := String(e.get("pilot_of", ""))
		if suit == "":
			continue
		if U.submit(w, fid, st, {"type": "resuit", "building_id": int(garage.id), "pilot_id": int(e.id), "suit": suit}, "g6:resuit"):
			L.bump(g, "resuit_req")
			U.log_line(st, w, "g6: re-suit pilot %d (%s)" % [int(e.id), suit])
		else:
			_park_if_stub(st, w, "g6:resuit")
		return


static func _company_hq(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var hq := L.rdef(w, fid, "company_hq")
	if hq == "" or L.count_def(ctx, hq) > 0 or int(ctx.army_pop) < HQ_ARMY or not bool(ctx.get("g6_spend", true)):
		g.erase("hq_want")
		return
	# AI7-USE-4: ai_stage banks this price (credits never piled up to 750 while units were bought:
	# d4 soaks, hq_req=0 / co_why=no_hq on every Stage 8+ side); the build itself is bank-exempt
	var hc: Dictionary = Content.building(hq).get("cost", {})
	g.hq_want = {"credits": int(hc.get("credits", 0)) + L.MIN_CREDITS, "salvage": int(hc.get("salvage", 0)), "ore": int(hc.get("ore", 0))}
	if L.build_at(w, fid, st, ctx, hq, Vector2(-1, -1), "g6:build:hq"):
		L.bump(g, "hq_req")
		U.log_line(st, w, "g6: build Company HQ %s" % hq)


## Line combat templates first (rifle / conscript / swarm, then mechanised / shock / walker, then
## armour), specialists (air assault, spec ops, artillery, engineers) last; stable within a rank.
const CO_PREFER := ["rifle", "conscript", "swarm", "mech", "shock", "walker", "armor", "hunter"]
const FIX_ROLES := ["depot", "power"]  # _ROLES-style role names for the Company HQ deploy fix (not def ids)


static func _by_doctrine(temps: Array) -> Array:
	var ranked := []
	for i in temps.size():
		var id := _template_id(temps[i])
		var r := CO_PREFER.size()
		for j in CO_PREFER.size():
			if id.find(String(CO_PREFER[j])) >= 0:
				r = j
				break
		ranked.append([r, i])
	ranked.sort()
	var out := []
	for x in ranked:
		out.append(temps[int(x[1])])
	return out


static func _template_id(t) -> String:
	if t is Dictionary:
		return String(t.get("id", ""))
	return String(t)


## AI7-USE-4: the bank request (ai_stage reads st.g6.use.co_want): platoon credits for the first two
## companies (none in training), then the Commander's 600 (d4 + diag b: HQ built, co_why=no_fit free<1200).
static func _co_want(w: SimWorld, fid: int, ctx: Dictionary, g: Dictionary, have: int) -> void:
	var training := false
	for t in w.sys_state.get("companies", {}).get("training", []):
		if int(t.get("owner", -1)) == fid:
			training = true
	if have < 2 and not training:
		var cp := _cheapest_platoon(w, fid)  # a platoon is 26-66 pop / 3230-7910 cr (diag_company.gd)
		g.co_want = cp if not cp.is_empty() else {"credits": int(CO_CREDITS[0])}
	elif have >= 2 and not training and _commanders(w, fid, ctx).is_empty():
		g.co_want = {"credits": 600}
	elif g.has("co_want"):
		g.erase("co_want")


## AI7-USE-4: the cheapest platoon plan of this side's templates (credits / salvage / ore), {} if none.
static func _cheapest_platoon(w: SimWorld, fid: int) -> Dictionary:
	var C := L.sys("companies")
	var best := {}
	for t0 in L.callf(C, "templates_for", [fid, w], []):
		var tid := _template_id(t0)
		var t: Dictionary = L.callf(C, "template", [w, fid, tid], {})
		if tid == "" or t.is_empty():
			continue
		var pl: Dictionary = L.callf(C, "plan", [w, fid, t, "platoon", not tid.begins_with("custom:")], {})
		var c: Dictionary = pl.get("cost", {})
		if not c.is_empty() and (best.is_empty() or int(c.get("credits", 0)) < int(best.credits)):
			best = {"credits": int(c.get("credits", 0)), "salvage": int(c.get("salvage", 0)), "ore": int(c.get("ore", 0))}
	return best


## Trains the next company at the Company HQ: the first template of the faction this side may train,
## rotating through the list; platoon size first, company / battalion when the credits allow.
static func _companies(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var hq := L.rdef(w, fid, "company_hq")
	if hq == "" or not bool(ctx.get("g6_spend", true)) or U.blocked(st, w, "g6:company"):
		g.co_why = "gate"
		g.erase("co_want")
		return
	var b = L.facility(ctx, hq, 1)
	if b == null:
		g.co_why = "no_hq"
		g.erase("co_want")
		return
	var have := (L.callf(L.sys("companies"), "companies_of", [w, fid], []) as Array).size()
	g.co_ok = have
	_co_want(w, fid, ctx, g, have)
	if have >= CO_MAX or w.tick - int(g.get("co_t", -1000000)) < CO_GAP:
		return
	for t in w.sys_state.get("companies", {}).get("training", []):  # one company in training at a time
		if int(t.get("owner", -1)) == fid and String(t.get("kind", "company")) != "commander":
			g.co_why = "training " + String(t.get("status", ""))
			if String(t.get("status", "")) == "LOW_POWER":  # the trained company waits on power: add a plant
				var pw := U.role(w, fid, "power")
				if pw != "" and L.build_at(w, fid, st, ctx, pw, Vector2(-1, -1), "g6:build:power"):
					U.set_backoff(st, w, "g6:build:power", 30 * SimWorld.TICK_RATE)
					U.log_line(st, w, "g6: build %s (company training on low power)" % pw)
			return
	var C := L.sys("companies")
	var temps: Array = _by_doctrine(L.callf(C, "templates_for", [fid, w], []))  # an int fid needs w (ARMY6)
	if temps.is_empty():
		g.co_why = "no_templates"
		return
	var free := _free_credits(w, fid, st)
	# the company spawns whole when its supply fits (ARMY6 SUPPLY_CAP); _context counts training pop
	# as queued, so unit production leaves room and Econ builds supply up to the cap maximum
	var f: Dictionary = w.factions[fid]
	var room_max := Economy.cap_max_for(w, fid) - int(f.pop) - int(ctx.get("queued_pop", 0))
	var room_now := int(f.pop_cap) - int(f.pop) - int(ctx.get("queued_pop", 0))
	var tid := ""
	var size := ""
	var fits_now := true
	var pop_need := 0
	for room in [room_now, room_max]:  # a company that fits the supply now, else one Econ must house
		for j in temps.size():  # rotate through the templates; the first that fits credits and supply
			var cand := _template_id(temps[(int(g.co_req) + j) % temps.size()])
			var t: Dictionary = L.callf(C, "template", [w, fid, cand], {})
			if cand == "" or t.is_empty():
				continue
			for i in [2, 1, 0]:
				if free < int(CO_CREDITS[i]) or (i > 0 and have < i):
					continue
				var sz: String = ["platoon", "company", "battalion"][i]
				var pl: Dictionary = L.callf(C, "plan", [w, fid, t, sz, not cand.begins_with("custom:")], {})
				if pl.is_empty() or int(pl.get("pop", 999)) > room or w.can_afford(fid, pl.get("cost", {})) != "":
					continue
				size = sz
				pop_need = int(pl.get("pop", 0))
				break
			if size != "":
				tid = cand
				break
		if tid != "":
			break
		fits_now = false
	if tid == "":
		g.co_why = "no_fit free=%d room=%d" % [free, room_max]
		return
	if not fits_now:
		# G6.1 (ORCH): train_company now refuses a company that could not deploy (owner bug 2026-10-26), so the
		# AI raises its supply cap first instead of queueing a company that waits on the cap.
		g.co_why = "need_supply room=%d" % room_now
		var dp := U.role(w, fid, "depot")
		if dp != "" and not U.blocked(st, w, "g6:build:depot") and L.build_at(w, fid, st, ctx, dp, Vector2(-1, -1), "g6:build:depot"):
			U.set_backoff(st, w, "g6:build:depot", 20 * SimWorld.TICK_RATE)
			U.log_line(st, w, "g6: build %s (room for a company)" % dp)
		return
	# G6.1 (INTEG61): train_company also refuses while the Company HQ lacks power (Companies.deploy_reason);
	# ask the same question first and fix the cause (power plant, else a depot) instead of submitting a refusal.
	var why := String(L.callf(C, "deploy_reason", [w, fid, b, pop_need], ""))
	if why != "":
		var fp: Dictionary = w.factions[fid]
		var low_power := int(fp.power_use) > int(fp.power_prod)
		var role: String = FIX_ROLES[1 if low_power else 0]  # role names (U.role resolves the def below)
		g.co_why = "deploy %s" % role
		var bd := U.role(w, fid, role)
		if bd != "" and not U.blocked(st, w, "g6:build:" + role) and L.build_at(w, fid, st, ctx, bd, Vector2(-1, -1), "g6:build:" + role):
			U.set_backoff(st, w, "g6:build:" + role, 20 * SimWorld.TICK_RATE)
			U.log_line(st, w, "g6: build %s (company HQ: %s)" % [bd, why.left(48)])
		return
	g.co_why = ""
	if U.submit(w, fid, st, {"type": "train_company", "building_id": int(b.id), "template": tid, "size": size}, "g6:company"):
		L.bump(g, "co_req")
		g.co_t = w.tick
		U.log_line(st, w, "g6: train company %s (%s)" % [tid, size])
	else:
		_park_if_stub(st, w, "g6:company")


static func _commanders(w: SimWorld, fid: int, ctx: Dictionary) -> Array:
	var out := []
	var ids: Array = L.callf(L.sys("companies"), "commanders_of", [w, fid], [])
	for id in ids:
		var e = w.entities.get(int(id))  # AI-FAIR: own Commander ids from Companies.commanders_of(w, fid)
		if e != null:
			out.append(e)
	if out.is_empty() and not L.api(L.sys("companies"), "commanders_of"):
		for e in ctx.units:
			if String(e.get("rank_role", "")) == "commander":
				out.append(e)
	return out


## A Commander once two companies stand, then an army of every company not yet in one (2-4).
static func _army(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var cos: Array = (L.callf(L.sys("companies"), "companies_of", [w, fid], []) as Array)
	if cos.size() < 2:
		return
	var cmdrs := _commanders(w, fid, ctx)
	var hq := L.rdef(w, fid, "company_hq")
	if cmdrs.is_empty():
		var b = L.facility(ctx, hq, 1) if hq != "" else null
		if b != null and _free_credits(w, fid, st) >= 600 and not U.blocked(st, w, "g6:commander"):
			if U.submit(w, fid, st, {"type": "train_commander", "building_id": int(b.id)}, "g6:commander"):
				L.bump(g, "cmdr_req")
				U.set_backoff(st, w, "g6:commander", 60 * SimWorld.TICK_RATE)
				U.log_line(st, w, "g6: train a Commander")
			else:
				_park_if_stub(st, w, "g6:commander")
		return
	var free_cos := []
	for c in cos:
		var a = c.get("army", "")
		if a == null or str(a) == "" or str(a) == "-1":
			free_cos.append(c.get("id"))
	if free_cos.size() < 2 or U.blocked(st, w, "g6:army"):
		return
	for cm in cmdrs:
		if not (L.callf(L.sys("companies"), "army_of", [w, int(cm.id)], {}) as Dictionary).is_empty():
			continue
		var ids := free_cos.slice(0, 4)
		if U.submit(w, fid, st, {"type": "form_army", "commander_id": int(cm.id), "company_ids": ids}, "g6:army"):
			L.bump(g, "army_req")
			U.log_line(st, w, "g6: form army under %d with %s" % [int(cm.id), str(ids)])
		else:
			_park_if_stub(st, w, "g6:army")
		return


## Human A: the Exo-Suit Garage once there is a real army, then suits by threat (AA suit with air seen).
static func _garage(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	var gdef := L.rdef(w, fid, "exo_garage")
	if gdef == "" or int(ctx.army_pop) < GARAGE_ARMY:
		return
	if L.count_def(ctx, gdef) == 0:
		if L.build_at(w, fid, st, ctx, gdef, Vector2(-1, -1), "g6:build:garage"):
			L.bump(g, "garage_req")
			U.log_line(st, w, "g6: build %s" % gdef)
		return
	var items := []
	for pid in Content.ids("production"):
		var p := Content.production(String(pid))
		if String(p.get("facility", "")) == gdef and U.available(w, fid, String(pid)):
			items.append(String(pid))
	if items.is_empty():
		return
	var suits := 0
	for e in ctx.units:
		if String(Content.production(L.item_for(w, fid, String(e.def))).get("facility", "")) == gdef:
			suits += 1
	if suits >= 2 + int(ctx.army_pop) / 30:
		return
	var air := int(st.get("g4", {}).get("enemy_air_seen", 0)) > 0
	var pick := String(items[int(g.suit_req) % items.size()])
	for it in items:
		var ud := U.ud(String((Content.production(String(it)).get("spawns", [""]) as Array)[0]))
		var aa := bool(ud.get("anti_air_low", false)) or bool(ud.get("anti_air_high", false))
		if aa == air:
			pick = String(it)
			break
	if L.queue_item(w, fid, st, ctx, pick, "g6:suit"):
		L.bump(g, "suit_req")
		U.log_line(st, w, "g6: queue exo suit %s" % pick)


## Infantry on the standard loadout near a barracks / the Company HQ gets one by threat: anti-tank
## when enemy armour was seen, else exo / plates / assault (Machine: weapon / armour modules).
static func _loadouts(w: SimWorld, fid: int, st: Dictionary, ctx: Dictionary, g: Dictionary) -> void:
	if U.blocked(st, w, "g6:loadout") or _free_credits(w, fid, st) < 400:
		return
	var homes := []
	var inf_item := U.role(w, fid, "infantry")
	var bar := String(Content.production(inf_item).get("facility", "")) if inf_item != "" else ""
	var hq := L.raw_def(U.fac(w, fid), "company_hq")
	for b in ctx.buildings:
		# AI7-USE-5: only buildings EXO6 accepts (valley d5: the Machine's infantry facility is no
		# loadout building; 257 set_loadout requests, every one rejected)
		if b.built and (String(b.def) == bar or String(b.def) == hq) \
				and bool(L.callf(L.sys("loadouts"), "is_loadout_building", [String(b.def)], true)):
			homes.append(b)
	if homes.is_empty():
		return
	var armour := int(st.get("enemy_vehicles_seen", 0)) >= 4
	var prefs := ["at", "mod_weapon", "assault"] if armour else ["exo", "plates", "assault", "mod_armor", "breacher"]
	for h in homes:
		var hp := Vector2(h.pos)
		var ids := []
		var pick := ""
		for e in ctx.units:
			if ctx.busy.has(int(e.id)) or Vector2(e.pos).distance_to(hp) > LOADOUT_NEAR:
				continue
			var cur := String(L.callf(L.sys("loadouts"), "of", [e], ""))
			if cur != "" and cur != "standard":
				continue
			var opts: Array = L.callf(L.sys("loadouts"), "loadouts_for", [fid, String(e.def)], [])
			if opts.is_empty():
				continue
			var want := ""
			for p in prefs:
				if opts.has(p):
					want = String(p)
					break
			if want == "" or (pick != "" and want != pick):
				continue
			pick = want
			ids.append(int(e.id))
			if ids.size() >= LOADOUT_BATCH:
				break
		if ids.is_empty():
			continue
		if U.submit(w, fid, st, {"type": "set_loadout", "unit_ids": ids, "loadout": pick, "building_id": int(h.id)}, "g6:loadout"):
			L.bump(g, "loadout_req")
			U.set_backoff(st, w, "g6:loadout", 20 * SimWorld.TICK_RATE)
			U.log_line(st, w, "g6: loadout %s on %d units" % [pick, ids.size()])
		else:
			_park_if_stub(st, w, "g6:loadout")
		return
