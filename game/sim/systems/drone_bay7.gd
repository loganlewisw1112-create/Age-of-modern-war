extends RefCounted
## G7 (DRONEBAY7, DRONEBAY7-2): the counter-nanite facility drone bay's defence drone garrison (master scope 13.9c-27)
## fighting as one networked hive (13.9c-27a: "operate like a hive mind to defend the facility at all cost").
## The drone bay is the workshop's 2nd storey (13.9c-18); its launch deck is the workshop roof (zone "drone_bay").
##  - Garrison: up to rules.g7_dronebay.cap (24, PROVISIONAL; 12 -> 24 per 13.9c-38 follow-up) defence drones in the hangar, composition `mix`:
##    interceptors (g7_cn_interceptor_drone: anti-drone gun, vs enemy drones / aircraft, and they shoot down rockets /
##    shells / strikes landing near them), gun drones (cn_gun_drone: MG, vs ground attackers) and kamikaze drones (the
##    G5 FPV strike drone a_drone_strike / b_drone_strike, flown by G5Mech: one-way, vs vehicles / heavy targets).
##  - Shared threat board (hive, every think_every ticks while threatened or drones are out): every enemy the side can
##    see in the defence ring (drones, towers, cameras, radar and Sentinels all feed fog), the Sentinels' guard-net
##    contact (Sentinels7.threat) and whoever just hit the core or a facility building (located even from beyond
##    sight), ranked by what most endangers the facility: an attacker at the core, breaching units inside the wall,
##    anti-air, heavy armour at the walls, inbound munitions / drones, then the rest (hive.prio, nearer first).
##    Incoming rockets / shells / strikes aimed at the facility (Strikes shots) are on the board too.
##  - Tasking (re-balanced every think as threats appear or die):
##    SCREEN  interceptors fly a layered screen: an outer picket on the threat axis and an inner close-in ring over the
##            facility (it rotates slowly; one ring slot covers the deck while drones come home). An air threat draws
##            the nearest screen interceptor off to intercept it (min_screen always hold the screen); an incoming rocket
##            / shell draws the nearest one to its impact point. The screen holds while the strikers engage.
##    STRIKE  gun drones in fire teams of team.size: teams go to targets by priority until each target's hp is
##            covered, spare teams converge on the top threat (focus fire). Team members orbit their target on opposite
##            sides at a standoff inside weapon range and strafe around it (teams alternate direction; several teams
##            on one target share the circle evenly and turn the same way, so they never stack), firing on the move.
##            Kamikazes go for the highest-value threat (heavy / anti-air / at the core), launched once the gun drones
##            have it under fire for kamikaze.supp_s (or after kamikaze.wait_s). On a breach they commit together: the
##            whole stock queued at once, round-robin over the threats, up to kamikaze.commit_per_heavy on a heavy one.
##    REARM   drones rotate home to rearm / recharge while others hold the line: a worn drone (battery past rotate.at
##            or hurt below rotate.hp) rotates only while at most a third of the drones in play are down and at least a
##            third stay aloft; ready drones relaunch to relieve them. A drone at its battery limit or badly hurt
##            (rotate.must_hp) always comes home.
##  - At all cost: on a breach (BaseState7 "breached" or an enemy inside the wall) the hive commits: every drone in the
##    hangar launches (launch gap x commit.gap_mult), rearm and rebuild run faster (commit.*_mult), no rotation, the
##    whole screen collapses onto the inner ring, and once an attacker stands at the core (ram.core_r) with no
##    kamikaze on it, drones ram it as a last resort (ram.max at once; the drone is spent).
##  - Automatic release (default ON, owner: "launchable either manually or automatically as a default"): while the
##    base is contested / under fire / breached (BaseState7 via CnFacility.secure_state) or the Sentinels' guard net
##    has a contact, the bay releases what the board needs (the whole screen, fire teams for the ground threat,
##    kamikazes as above). Drones take off one after another from the deck spots (launch_gap_s); once the base has
##    been quiet for clear_s they come home.
##  - Recovery: a recovering drone flies to its deck spot and lands (the entity leaves the map: it is back in the
##    hangar), then rearms / recharges for rearm_s (+ repair_s x missing hp fraction) before it is ready again.
##  - Losses are rebuilt slowly, one at a time (rebuild_s, rebuild_cost), toward `mix`. A spent kamikaze or rammer is
##    a loss.
##  - Player commands (ORCH registers in world.gd COMMANDS): dronebay_launch {issuer, building_id?, kind
##    all|interceptor|gun|kamikaze, count?, target? (map pos)}, dronebay_recall {issuer, building_id?},
##    dronebay_auto {issuer, building_id?, on}. building_id = the facility core id (default: the side's first).
##    Manual drones are not recovered by the quiet-base rule (only by battery or Recall); with no threat they hold a
##    guard formation over the compound. The hive marks its own orders (order.hive); any other order on a bay drone is
##    a player order and is left alone until the drone goes idle (Hold Position is never moved, not even recalled).
##  - The recon overwatch job stays with CnOps7 (one overwatch drone per strike team, launched from the same deck).
## API (fact dronebay.api): bays_of(w, fid) -> [fac ids]; bay(w, fac) -> Dictionary; summary(w, fac) ->
##   {fac, owner, cap, total, ready, aloft, rearming, queued, building, build_left_s, auto, lost, launched, landed,
##   rammed, intercepts, mode (calm|alert|commit),
##   board (threat count), tasks {screen, strike, rearm, ram, guard, player}, kinds {k: {ready, aloft, rearming,
##   total}}, deck: Rect2}; board(w, fac) -> [[id, prio, cls, seen_tick, inside, heavy]]; deck_spot(w, fac, i) ->
##   Vector2; intercept_strike(w, attacker_fid, at, kind) -> bool (Strikes hook); is_bay_drone(e) -> bool;
##   display_lifts(w) (render only).
## State: w.sys_state.dronebay7 = {ver, bays: {"<fac>": B}} (string keys, ints, floats and arrays only), created only
## once a CnFacility exists, so a match without the facility is hash-identical and costs one dictionary lookup per tick.
## B.board / B.mode / B.supp and each drone's task / team / slot / tgt are hive state. Drone entities carry e.dbay =
## facility id (saved with the entity). Saved and hashed with sys_state.
## Determinism: sorted ids, staggered cadence ((tick + fac) % think_every), no rng; orbit angles are pure functions of
## the tick.
## Events: DroneBayLaunched {fac, owner, id, kind, mode, target, pos}, DroneBayRecall {fac, owner, n, cause},
##   DroneBayLanded {fac, owner, id, kind}, DroneBayLost {fac, owner, id, kind}, DroneBayRebuilt {fac, owner, kind},
##   DroneBayAuto {fac, owner, on}, DroneBayIntercept {fac, owner, drone, attacker, kind, pos},
##   DroneBayHive {fac, owner, mode, was}, DroneBayRotate {fac, owner, id, kind, why}, DroneBayRamOrder {fac, owner,
##   id, target}, DroneBayRam {fac, owner, id, kind, target, pos, hits}.

const SimIndex = preload("res://sim/systems/sim_index.gd")

const KEY := "dronebay7"
const VER := 2
const DISCOVER_EVERY := 20
const KINDS := ["interceptor", "gun", "kamikaze"]
const DEFAULTS := {"cap": 24, "mix": {"interceptor": 4, "gun": 8, "kamikaze": 12}, "auto": true, "think_every": 10,
	"defence_pad": 14, "leash": 8, "launch_gap_s": 0.35, "sortie_s": 120, "rearm_s": 20, "repair_s": 30, "rebuild_s": 45,
	"rebuild_cost": {"credits": 60, "salvage": 25}, "clear_s": 6, "guard_r": 9.0, "land_r": 0.45,
	"defs": {"interceptor": "g7_cn_interceptor_drone", "gun": "cn_gun_drone"},
	"kamikaze": {"kind": "strike", "team_def": {"human_a": "a_drone_team", "human_b": "b_drone_team"}},
	"need": {"air_per_drone": 1.0, "ground_hp_per_gun": 400.0, "kamikaze_per_heavy": 1, "min_gun": 2},
	"heavy": {"armor": ["heavy", "medium", "building"], "min_hp": 900}, "intercept": {"r": 4.0, "cooldown_s": 3.0},
	"deck_spots": [[0.5, 0.35], [0.3, 0.6], [0.7, 0.6], [0.5, 0.8]], "rebuild_order": ["interceptor", "gun", "kamikaze"],
	"hive": {
		"prio": {"core": 1400, "breach": 1200, "aa": 1000, "heavy_wall": 800, "munition": 650, "air": 600, "heavy": 400,
			"ground": 300},
		"board": {"near_bonus": 150, "outside_pen": 200, "wall_r": 4.0, "heard_s": 3.0, "max": 24, "shells": 6,
			"scan_max": 64},
		"screen": {"outer_d": 7.0, "inner_frac": 0.45, "spread_deg": 28.0, "sweep_deg": 10.0, "inner_dps": 18.0,
			"lead_s": 1.0, "min_screen": 1, "deck_cover": true},
		"team": {"size": 2, "hp_per_team": 800.0, "standoff": 0.7, "orbit_dps": 50.0, "lead_s": 1.2, "guard_frac": 0.85,
			"guard_dps": 12.0},
		"kamikaze": {"supp_s": 1.5, "wait_s": 8.0, "heavy_bonus": 250, "commit_per_heavy": 4, "commit_per": 2},
		"rotate": {"at": 0.45, "hp": 0.4, "must_hp": 0.2, "keep_frac": 0.334, "down_frac": 0.334},
		"commit": {"rebuild_mult": 0.4, "rearm_mult": 0.5, "gap_mult": 0.5},
		"ram": {"core_r": 3.0, "hit_r": 0.7, "damage": 150.0, "splash": 0.8, "max": 2, "payload": "g5_drone_strike"}}}


static var _r: Dictionary = {}
static var _r_src = null


## Rules (content rules.g7_dronebay over DEFAULTS), cached per merged rules dictionary.
static func R() -> Dictionary:
	var c = Content.rules().get("g7_dronebay")
	if _r.is_empty() or not is_same(c, _r_src):
		var r: Dictionary = DEFAULTS.duplicate(true)
		if typeof(c) == TYPE_DICTIONARY:
			r.merge(c, true)
		_r = r
		_r_src = c
	return _r


## One section of the hive rules ({} when missing; callers give defaults).
static func _hv(sect: String) -> Dictionary:
	var h = R().get("hive", {})
	if typeof(h) != TYPE_DICTIONARY:
		return {}
	var s = (h as Dictionary).get(sect, (DEFAULTS.hive as Dictionary).get(sect, {}))
	return s if typeof(s) == TYPE_DICTIONARY else {}


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func _sv(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, 0.001), snappedf(v.y, 0.001))


# ================================================================ queries (read-only: never create state)
static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func bay(w: SimWorld, fac: int) -> Dictionary:
	var st = state(w)
	if st == null:
		return {}
	return (st.bays as Dictionary).get(str(fac), {})


## The hive's threat board of facility fac (highest priority first): [[id, prio, cls, seen_tick, inside, heavy]].
static func board(w: SimWorld, fac: int) -> Array:
	return bay(w, fac).get("board", [])


## Facility ids of side fid that have a drone bay, ascending.
static func bays_of(w: SimWorld, fid: int) -> Array:
	var out := []
	var st = state(w)
	if st == null:
		return out
	for k in st.bays:
		if int(st.bays[k].fid) == fid:
			out.append(int(k))
	out.sort()
	return out


static func is_bay_drone(e) -> bool:
	return e is Dictionary and e.has("dbay")


static func _fac(w: SimWorld, fac: int) -> Dictionary:
	return SimWorld.CnFacility.fac(w, fac)


static func deck_rect(w: SimWorld, fac: int) -> Rect2:
	var F := _fac(w, fac)
	if F.is_empty():
		return Rect2()
	return SimWorld.CnFacility.zone(F, "drone_bay")


## Deck spot i (the launch / recovery pads on the workshop roof), world tiles.
static func deck_spot(w: SimWorld, fac: int, i: int) -> Vector2:
	var r := deck_rect(w, fac)
	var spots: Array = R().deck_spots
	var s: Array = spots[posmod(i, spots.size())]
	return _sv(r.position + r.size * Vector2(float(s[0]), float(s[1])))


static func _count(B: Dictionary, kind: String) -> Dictionary:
	var c := {"ready": int((B.stock as Dictionary).get(kind, 0)), "aloft": 0, "rearming": 0, "queued": 0}
	for d in B.out.values():
		if String(d.kind) == kind:
			c.aloft += 1
	for r in B.rearm:
		if String(r[0]) == kind:
			c.rearming += 1
	for q in B.q:
		if String(q[0]) == kind:
			c.queued += 1
	c.total = int(c.ready) + int(c.aloft) + int(c.rearming) + int(c.queued)
	return c


static func total(B: Dictionary) -> int:
	var n := 0
	for k in KINDS:
		n += int(_count(B, k).total)
	return n


## Hive tasking counts of bay B: screen (interceptors on the screen or intercepting), strike (fire teams, kamikazes in
## flight), rearm (coming home + rearming on the deck), ram, guard (formation with no threat), player (player orders).
static func tasks(B: Dictionary) -> Dictionary:
	var tk := {"screen": 0, "strike": 0, "rearm": (B.rearm as Array).size(), "ram": 0, "guard": 0, "player": 0}
	for d in B.out.values():
		var t := String(d.get("task", ""))
		if int(d.rec) == 1:
			tk.rearm += 1
		elif String(d.kind) == "kamikaze" or t == "strike" or (t == "climb" and String(d.kind) == "gun"):
			tk.strike += 1
		elif t == "screen" or t == "intercept" or (t == "climb" and String(d.kind) == "interceptor"):
			tk.screen += 1
		elif t == "ram":
			tk.ram += 1
		elif t == "player" or t == "held":
			tk.player += 1
		else:
			tk.guard += 1
	return tk


## UI / test summary of one bay ({} when none).
static func summary(w: SimWorld, fac: int) -> Dictionary:
	var B := bay(w, fac)
	if B.is_empty():
		return {}
	var out := {"fac": fac, "owner": int(B.fid), "cap": int(R().cap), "auto": bool(B.auto), "ready": 0, "aloft": 0,
		"rearming": 0, "queued": 0, "total": 0, "kinds": {}, "building": "", "build_left_s": 0.0,
		"lost": int(B.get("lost", 0)), "launched": int(B.get("launched", 0)), "landed": int(B.get("landed", 0)),
		"rammed": int(B.get("rammed", 0)), "intercepts": int(B.get("intercepts", 0)), "deck": deck_rect(w, fac), "mode": String(B.get("mode", "calm")),
		"board": (B.get("board", []) as Array).size(), "tasks": tasks(B)}
	for k in KINDS:
		var c := _count(B, k)
		out.kinds[k] = c
		for f in ["ready", "aloft", "rearming", "queued", "total"]:
			out[f] = int(out[f]) + int(c[f])
	if (B.build as Array).size() == 2:
		out.building = String(B.build[0])
		out.build_left_s = snappedf(maxf(0.0, float(int(B.build[1]) - w.tick) / float(SimWorld.TICK_RATE)), 0.1)
	return out


# ================================================================ state
static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": VER, "bays": {}}
		w.sys_state[KEY] = st
	return st


static func _new_bay(w: SimWorld, fac: int, fid: int) -> Dictionary:
	var stock := {}
	for k in KINDS:
		stock[k] = int((R().mix as Dictionary).get(k, 0))
	return {"fac": fac, "fid": fid, "auto": bool(R().auto), "stock": stock, "rearm": [], "out": {}, "q": [],
		"build": [], "next_launch": 0, "quiet": w.tick, "spot_i": 0, "lost": 0, "launched": 0, "landed": 0, "icpt": {},
		"board": [], "mode": "calm", "supp": {}, "rammed": 0}


## A live facility without a bay yet (cheap: facilities are few)?
static func _bay_missing(w: SimWorld) -> bool:
	var facs: Dictionary = w.sys_state.cn_facility.get("facs", {})
	if facs.is_empty():
		return false
	var st = state(w)
	for k in facs:
		if (st == null or not (st.bays as Dictionary).has(str(int(k)))) and w.entities.has(int(k)):
			return true
	return false


static func _discover(w: SimWorld) -> void:
	var fs = w.sys_state.get("cn_facility")
	if fs == null:
		return
	var ks: Array = (fs.get("facs", {}) as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var F: Dictionary = fs.facs[k]
		if not w.entities.has(int(k)):
			continue
		var st := _st(w)
		if (st.bays as Dictionary).has(str(int(k))):
			continue
		st.bays[str(int(k))] = _new_bay(w, int(k), int(F.owner))
		var dz: Rect2 = SimWorld.CnFacility.zone(F, "drone_bay")   # AIRFIX71 (G7.1 A1): the bay's dock joins the home-pad registry
		load("res://sim/systems/pads71.gd").register(w, "dock:%d" % int(k), "drone_dock", int(F.owner), dz.get_center(), dz.size.x, int(k), 0.0, int(R().cap))
		w.emit("DroneBayReady", {"fac": int(k), "owner": int(F.owner), "cap": int(R().cap)})


# ================================================================ threat picture
## Enemy units in and around facility fac's compound that its side can see: {air: [], heavy: [], ground: [],
## ground_hp, heavy_hp} (each list ascending id). Pure read (manual launches; the hive uses the board).
static func threats(w: SimWorld, B: Dictionary) -> Dictionary:
	var out := {"air": [], "heavy": [], "ground": [], "ground_hp": 0.0, "heavy_hp": 0.0}
	var F := _fac(w, int(B.fac))
	if F.is_empty():
		return out
	var fid := int(B.fid)
	var area := SimWorld.CnFacility.compound_rect(F).grow(float(R().defence_pad))
	var hv: Dictionary = R().heavy
	var harm: Array = hv.get("armor", [])
	var units := []
	for e in SimIndex.of(w, "unit"):
		var o := int(e.owner)
		if o == fid or not w.is_enemy(fid, o) or not area.has_point(Vector2(e.pos)):
			continue
		if not w.entities.has(int(e.id)) or bool(e.get("wounded", false)):
			continue   # destroyed since the index was built / a casualty on the ground is no threat
		if not SimWorld.Fog.is_visible(w, fid, Vector2(e.pos)):
			continue
		units.append(e)
	units.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for e in units:
		var d := Content.unit(String(e.def))
		if bool(d.get("is_air", false)) and not bool(e.get("air_landed", false)):
			out.air.append(e)
		elif harm.has(String(d.get("armor", ""))) or float(e.hp) >= float(hv.get("min_hp", 900)):
			out.heavy.append(e)
			out.heavy_hp = float(out.heavy_hp) + float(e.hp)
		else:
			out.ground.append(e)
			out.ground_hp = float(out.ground_hp) + float(e.hp)
	return out


## How many of each kind a threat picture needs aloft (manual launches / API).
static func needs(T: Dictionary) -> Dictionary:
	var N: Dictionary = R().need
	var n_int := ceili(float((T.air as Array).size()) * float(N.get("air_per_drone", 1.0)))
	var n_gun := 0
	var ghp := float(T.ground_hp) + float(T.heavy_hp) * 0.25
	if not (T.ground as Array).is_empty() or not (T.heavy as Array).is_empty():
		n_gun = maxi(int(N.get("min_gun", 2)), ceili(ghp / maxf(float(N.get("ground_hp_per_gun", 400.0)), 1.0)))
	var n_kam := (T.heavy as Array).size() * int(N.get("kamikaze_per_heavy", 1))
	return {"interceptor": n_int, "gun": n_gun, "kamikaze": n_kam}


static func _is_air_cls(cls: String) -> bool:
	return cls == "air" or cls == "munition"


static func _is_aa(d: Dictionary) -> bool:
	var wid := String(d.get("weapon", ""))
	if wid == "":
		return false
	var wd := Content.weapon(wid)
	return bool(wd.get("anti_air", false)) and String(wd.get("class", "")) != "small_arms"


## The Sentinels' guard-net contact of facility fac ([pos, id] or null; Sentinels7 caches it per tick). Read only.
static func _contact(w: SimWorld, fac: int):
	if SimWorld.Sentinels7.state(w) == null:
		return null
	return SimWorld.Sentinels7.threat(w, fac)


## The hive's shared threat board for bay B (13.9c-27a): enemies the side can see in the defence ring, the Sentinels'
## contact and whoever just hit the core or a facility building (within the leash area), classified and ranked:
## [[id, prio, cls, seen_tick, inside (defence ring), heavy]], highest priority first, then id; at most board.max.
static func board_scan(w: SimWorld, B: Dictionary, contact) -> Array:
	var fac := int(B.fac)
	var F := _fac(w, fac)
	if F.is_empty():
		return []
	var fid := int(B.fid)
	var cr := SimWorld.CnFacility.compound_rect(F)
	var area := cr.grow(float(R().defence_pad))
	var lea := _area_r(w, B)
	var cand := {}
	var ctr := cr.get_center()
	var HB := _hv("board")
	# cheap pass over every unit (owner / ring / side), then only the nearest scan_max enemies are checked for sight and
	# classified (a huge fight at the wall costs the same as a raid; keys = (distance^2 x 16) << 24 | id, native sort)
	var keys := PackedInt64Array()
	for e in SimIndex.of(w, "unit"):
		var o := int(e.owner)
		if o == fid or not area.has_point(Vector2(e.pos)) or not w.is_enemy(fid, o):
			continue
		keys.append((int(Vector2(e.pos).distance_squared_to(ctr) * 16.0) << 24) | int(e.id))
	if not keys.is_empty():
		keys.sort()
		var cap := int(HB.get("scan_max", 64))
		for key in keys:
			if cand.size() >= cap:
				break
			var e = w.entities.get(int(key & 0xFFFFFF))
			if e == null or bool(e.get("wounded", false)):
				continue   # destroyed since the index was built / a casualty on the ground is no threat
			if not SimWorld.Fog.is_visible(w, fid, Vector2(e.pos)):
				continue
			cand[int(e.id)] = true
	if contact != null and contact is Array and (contact as Array).size() >= 2:
		var t = w.entities.get(int(contact[1]))
		if t != null and String(t.kind) == "unit" and w.is_enemy(fid, int(t.owner)) and lea.has_point(Vector2(t.pos)) \
				and not bool(t.get("wounded", false)):
			cand[int(t.id)] = true
	var rec := ticks(float(HB.get("heard_s", 3.0)))
	var srcs: Array = [fac]
	for pid in F.get("parts", []):
		srcs.append(int(pid))
	for sid in srcs:
		var p = w.entities.get(int(sid))
		if p == null or w.tick - int(p.get("last_hit_tick", -100000)) > rec:
			continue
		var a = w.entities.get(int(p.get("last_attacker", -1)))
		if a != null and String(a.kind) == "unit" and w.is_enemy(fid, int(a.owner)) and lea.has_point(Vector2(a.pos)):
			cand[int(a.id)] = true
	var P := _hv("prio")
	var hv: Dictionary = R().heavy
	var harm: Array = hv.get("armor", [])
	var core = w.entities.get(fac)
	var core_r := float(_hv("ram").get("core_r", 3.0))
	var wall := cr.grow(float(HB.get("wall_r", 4.0)))
	var span := maxf(cr.size.x * 0.5 + float(R().defence_pad) + float(R().leash), 1.0)
	var near := float(HB.get("near_bonus", 150))
	var outp := int(HB.get("outside_pen", 200))
	var prev := {}
	for b in B.get("board", []):
		prev[int(b[0])] = int(b[3])
	var ids: Array = cand.keys()
	ids.sort()
	var out := []
	for id in ids:
		var e: Dictionary = w.entities[id]
		var d := Content.unit(String(e.def))
		var p: Vector2 = e.pos
		var hvy := harm.has(String(d.get("armor", ""))) or float(e.hp) >= float(hv.get("min_hp", 900))
		var cls := "ground"
		if bool(d.get("is_air", false)) and not bool(e.get("air_landed", false)):
			cls = "munition" if String(d.get("weapon", "")) == "" else "air"
			hvy = false
		elif core != null and SimWorld.Combat.dist_to(p, core) <= core_r:
			cls = "core"
		elif cr.has_point(p):
			cls = "breach"
		elif _is_aa(d):
			cls = "aa"
		elif hvy:
			cls = "heavy_wall" if wall.has_point(p) else "heavy"
		var pr := int(P.get(cls, 300)) + int(near * clampf(1.0 - p.distance_to(ctr) / span, 0.0, 1.0))
		var ins := area.has_point(p)
		if not ins:
			pr -= outp
		out.append([int(id), pr, cls, int(prev.get(int(id), w.tick)), 1 if ins else 0, 1 if hvy else 0])
	out.sort_custom(func(a, b): return int(a[1]) > int(b[1]) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0])))
	var mx := int(HB.get("max", 24))
	if out.size() > mx:
		out = out.slice(0, mx)
	return out


## Incoming enemy rockets / shells / strikes landing in the defence ring (Strikes shots, read only), soonest first:
## [[at, ticks_left, n]], at most board.shells.
static func incoming(w: SimWorld, B: Dictionary) -> Array:
	var ss = w.sys_state.get("strikes")
	if ss == null or not (ss is Dictionary) or not (ss as Dictionary).has("shots") or (ss.shots as Array).is_empty():
		return []
	var F := _fac(w, int(B.fac))
	if F.is_empty():
		return []
	var area := SimWorld.CnFacility.compound_rect(F).grow(float(R().defence_pad))
	var fid := int(B.fid)
	var out := []
	for s in ss.shots:
		if not w.is_enemy(fid, int(s.owner)) or not area.has_point(Vector2(s.at)):
			continue
		out.append([Vector2(s.at), int(s.t), int(s.n)])
	out.sort_custom(func(a, b): return int(a[1]) < int(b[1]) or (int(a[1]) == int(b[1]) and int(a[2]) < int(b[2])))
	var mx := int(_hv("board").get("shells", 6))
	return out.slice(0, mx) if out.size() > mx else out


## Target for a drone of `kind` (manual launches): interceptors take air, gun drones ground (then heavy), kamikazes heavy
## (fewest kamikazes already on it). Round-robin by `n` so a group spreads over the threats. -1 when none.
static func _pick_target(B: Dictionary, T: Dictionary, kind: String, n: int) -> int:
	var lst: Array
	match kind:
		"interceptor":
			lst = T.air
		"gun":
			lst = T.ground if not (T.ground as Array).is_empty() else T.heavy
		"kamikaze":
			lst = T.heavy
			if lst.is_empty():
				return -1
			var on := _kamikaze_on(B)
			var best = null
			for e in lst:
				if best == null or int(on.get(int(e.id), 0)) < int(on.get(int(best.id), 0)):
					best = e
			return int(best.id)
	if lst.is_empty():
		return -1
	return int(lst[posmod(n, lst.size())].id)


## {target id: kamikazes flying at it or queued for it}.
static func _kamikaze_on(B: Dictionary) -> Dictionary:
	var on := {}
	for d in B.out.values():
		if String(d.kind) == "kamikaze":
			on[int(d.get("tgt", -1))] = int(on.get(int(d.get("tgt", -1)), 0)) + 1
	for q in B.q:
		if String(q[0]) == "kamikaze":
			on[int(q[1])] = int(on.get(int(q[1]), 0)) + 1
	return on


# ================================================================ launch / recover
## Reserve a drone of `kind` from the hangar into the launch queue. False when none ready.
static func _queue(B: Dictionary, kind: String, tgt: int, mode: String, at = null) -> bool:
	if int(B.stock.get(kind, 0)) <= 0:
		return false
	B.stock[kind] = int(B.stock[kind]) - 1
	var px := -1.0
	var py := -1.0
	if at != null:
		px = snappedf(Vector2(at).x, 0.001)
		py = snappedf(Vector2(at).y, 0.001)
	B.q.append([kind, tgt, mode, px, py])
	return true


static func _drone_def(w: SimWorld, B: Dictionary, kind: String) -> String:
	return String((R().defs as Dictionary).get(kind, ""))


## Takes the next queued drone off the deck. Returns the drone id or -1.
static func _launch_next(w: SimWorld, B: Dictionary) -> int:
	var it: Array = B.q.pop_front()
	var kind := String(it[0])
	var tgt := int(it[1])
	var mode := String(it[2])
	var fac := int(B.fac)
	var fid := int(B.fid)
	var si := int(B.spot_i)
	B.spot_i = (si + 1) % (R().deck_spots as Array).size()
	var at := deck_spot(w, fac, si)
	var did := -1
	if kind == "kamikaze":
		var t = w.entities.get(tgt)
		if t == null or not w.is_enemy(fid, int(t.owner)):
			B.stock[kind] = int(B.stock.get(kind, 0)) + 1   # target gone before take-off: back in the hangar
			return -1
		var K: Dictionary = R().kamikaze
		var fdef := String(w.factions[fid].get("faction_def", "human_a"))
		var tdef := String((K.get("team_def", {}) as Dictionary).get(fdef, "a_drone_team"))
		if Content.unit(tdef).is_empty():
			tdef = "a_drone_team"
		# G5Mech flies and detonates it (same call the stealth dropship's extraction drones use)
		var pseudo := {"id": fac, "def": tdef, "owner": fid, "pos": at, "drone_charges": 2}
		did = SimWorld.G5Mech._launch(w, pseudo, String(K.get("kind", "strike")), tgt, _sv(Vector2(t.pos)))
	else:
		var def_id := _drone_def(w, B, kind)
		if Content.unit(def_id).is_empty():
			return -1
		did = w.spawn_unit(def_id, fid, at)
		var e: Dictionary = w.entities[did]
		e.facing = snappedf(-PI / 2.0, 0.001)
		var t = w.entities.get(tgt) if tgt >= 0 else null
		if t != null and w.is_enemy(fid, int(t.owner)):
			e.order = {"type": "attack", "target_id": tgt, "hive": 1}
			e.target = -1
		else:
			var goal: Vector2
			var mine := float(it[3]) >= 0.0
			if mine:
				goal = Vector2(float(it[3]), float(it[4]))
			else:
				goal = _guard_point(w, B, si)
			goal = _clamp_map(w, goal)
			SimWorld.Movement.order_move(w, e, goal)
			e.order = {"type": "attack_move", "target": goal, "engaged": false}
			if not mine:
				e.order["hive"] = 1   # climb-out: the hive tasks it at its next think (a player point is the player's)
	if did < 0 or not w.entities.has(did):
		return -1
	w.entities[did].dbay = fac
	B.out[str(did)] = {"id": did, "kind": kind, "t0": w.tick, "mode": mode, "tgt": tgt, "spot": si, "rec": 0,
		"task": "strike" if kind == "kamikaze" else "climb", "team": -1, "slot": -1}
	B.launched = int(B.get("launched", 0)) + 1
	w.emit("DroneBayLaunched", {"fac": fac, "owner": fid, "id": did, "kind": kind, "mode": mode, "target": tgt, "pos": at})
	return did


static func _clamp_map(w: SimWorld, p: Vector2) -> Vector2:
	return _sv(Vector2(clampf(p.x, 0.5, float(w.map.w) - 0.5), clampf(p.y, 0.5, float(w.map.h) - 0.5)))


## Guard station i: a ring of guard_r around the compound centre (climb-out point of a drone with no task yet).
static func _guard_point(w: SimWorld, B: Dictionary, i: int) -> Vector2:
	var F := _fac(w, int(B.fac))
	var c := SimWorld.CnFacility.compound_rect(F).get_center()
	var a := float(i) * TAU / 4.0 + PI / 4.0
	return c + Vector2(cos(a), sin(a)) * (SimWorld.CnFacility.compound_rect(F).size.x * 0.5 + float(R().guard_r) * 0.3)


## Flies a hive drone to pt, firing on the move (order.bk: Combat fires at e.target / the nearest foe in range without
## stopping). Re-orders only when the point moved or the drone stopped, so a steady orbit costs no repaths.
static func _fly(w: SimWorld, e: Dictionary, pt: Vector2, tid: int) -> void:
	pt = _clamp_map(w, pt)
	var o: Dictionary = e.get("order", {})
	var cur = o.get("target", null)
	if String(o.get("type", "")) != "move" or not o.has("hive") or not bool(e.get("moving", false)) \
			or not (cur is Vector2) or Vector2(cur).distance_to(pt) > 0.75:
		SimWorld.Movement.order_move(w, e, pt)
		if String((e.order as Dictionary).get("type", "")) == "move":
			e.order["hive"] = 1
			e.order["bk"] = true
			SimWorld.Combat.note_bk(w, int(e.id))
	if tid >= 0:
		e.target = tid


static func _recall_drone(w: SimWorld, B: Dictionary, d: Dictionary, e: Dictionary, why: String = "recall") -> void:
	if String(d.kind) == "kamikaze":
		return   # committed: an FPV kamikaze flies one way
	d.rec = 1
	d.task = "rearm"
	var goal := deck_spot(w, int(B.fac), int(d.spot))
	SimWorld.Movement.order_move(w, e, goal)
	e.target = -1
	if why == "rotate" or why == "damaged" or why == "battery":
		w.emit("DroneBayRotate", {"fac": int(B.fac), "owner": int(B.fid), "id": int(d.id), "kind": String(d.kind), "why": why})


static func _land(w: SimWorld, B: Dictionary, d: Dictionary, e: Dictionary) -> void:
	var kind := String(d.kind)
	var hpf := clampf(float(e.hp) / maxf(float(e.get("max_hp", e.hp)), 1.0), 0.0, 1.0)
	var sec := float(R().rearm_s) + float(R().repair_s) * (1.0 - hpf)
	if String(B.get("mode", "calm")) == "commit":
		sec *= float(_hv("commit").get("rearm_mult", 0.5))   # at all cost: turn the drones round as fast as possible
	var t := ticks(sec)
	B.rearm.append([kind, w.tick + t])
	B.out.erase(str(int(e.id)))
	B.landed = int(B.get("landed", 0)) + 1
	var id := int(e.id)
	var pos: Vector2 = e.pos
	w.entities.erase(id)   # back inside the hangar (no wreck, no loss)
	w.emit("EntityDestroyed", {"id": id, "kind": "unit", "def": e.def, "owner": e.owner, "pos": pos, "cause": "dronebay_landed",
		"killer_owner": SimWorld.NEUTRAL, "squad": -1})
	w.emit("DroneBayLanded", {"fac": int(B.fac), "owner": int(B.fid), "id": id, "kind": kind, "pos": pos, "rearm_s": snappedf(float(t) / SimWorld.TICK_RATE, 0.1)})


# ================================================================ per-bay think (the hive)
static func _area_r(w: SimWorld, B: Dictionary) -> Rect2:
	var F := _fac(w, int(B.fac))
	return SimWorld.CnFacility.compound_rect(F).grow(float(R().defence_pad) + float(R().leash))


static func _think(w: SimWorld, B: Dictionary) -> void:
	var fac := int(B.fac)
	var bs := SimWorld.CnFacility.secure_state(w, fac)
	var out: Dictionary = B.out
	var contact = _contact(w, fac)
	var brd: Array = board_scan(w, B, contact)   # the facility always watches its defence ring (cheap early-outs)
	B.board = brd
	if not brd.is_empty():
		B.quiet = w.tick
	var commit := bs == "breached"
	for b in brd:
		if String(b[2]) == "core" or String(b[2]) == "breach":
			commit = true
			break
	var mode := "commit" if commit else ("alert" if not brd.is_empty() else "calm")
	var was := String(B.get("mode", "calm"))
	if mode != was:
		B.mode = mode
		if mode == "commit":
			_hurry(w, B)
		w.emit("DroneBayHive", {"fac": fac, "owner": int(B.fid), "mode": mode, "was": was})
	# --- automatic release: the base is threatened, or a threat is seen inside the defence ring (meet it before the wall)
	var near := false
	for b in brd:
		if int(b[4]) == 1:
			near = true
			break
	if bool(B.auto) and not brd.is_empty() and (bs != "secure" or near or commit):
		_release(w, B, brd, commit)
	# --- the drones aloft
	if not out.is_empty():
		var quiet := w.tick - int(B.quiet) >= ticks(float(R().clear_s))
		_task(w, B, brd, commit, quiet)
	var supp: Dictionary = B.supp
	if not supp.is_empty():
		var onb := {}
		for b in brd:
			onb[str(int(b[0]))] = true
		for k in supp.keys():
			if not onb.has(k):
				supp.erase(k)


## Breach: the drones already rearming and the drone being rebuilt are hurried (commit multipliers).
static func _hurry(w: SimWorld, B: Dictionary) -> void:
	var CM := _hv("commit")
	var rm := float(CM.get("rearm_mult", 0.5))
	for r in B.rearm:
		r[1] = w.tick + ceili(float(maxi(int(r[1]) - w.tick, 0)) * rm)
	if (B.build as Array).size() == 2:
		B.build[1] = w.tick + ceili(float(maxi(int(B.build[1]) - w.tick, 0)) * float(CM.get("rebuild_mult", 0.4)))


## Drones of each kind aloft and not coming home, plus queued on the deck.
static func _active(B: Dictionary) -> Dictionary:
	var a := {"interceptor": 0, "gun": 0, "kamikaze": 0}
	for d in B.out.values():
		if int(d.rec) == 0:
			a[String(d.kind)] = int(a[String(d.kind)]) + 1
	for q in B.q:
		a[String(q[0])] = int(a[String(q[0])]) + 1
	return a


## What the board needs in the air: the whole screen on any threat, fire teams for the ground threat, kamikazes timed
## with the suppression; on a breach every drone in the hangar.
static func _release(w: SimWorld, B: Dictionary, brd: Array, commit: bool) -> void:
	var act := _active(B)
	var TM := _hv("team")
	var tsz := maxi(1, int(TM.get("size", 2)))
	var want := {"interceptor": int(B.stock.get("interceptor", 0)), "gun": 0}
	if commit:
		want.gun = int(B.stock.get("gun", 0))
	else:
		var ghp := 0.0
		var ng := 0
		for b in brd:
			if int(b[4]) == 1 and not _is_air_cls(String(b[2])):
				var t = w.entities.get(int(b[0]))
				if t != null:
					ghp += float(t.hp)
					ng += 1
		if ng > 0:
			var teams := maxi(1, ceili(ghp / maxf(float(TM.get("hp_per_team", 800.0)), 1.0)))
			want.gun = teams * tsz - int(act.gun)
	# interleaved (interceptor, gun, interceptor, ...) so the screen and the first fire team are up early
	var more := true
	while more:
		more = false
		for k in ["interceptor", "gun"]:
			if int(want[k]) > 0 and _queue(B, k, -1, "auto"):
				want[k] = int(want[k]) - 1
				more = true
	_release_kamikazes(w, B, brd, commit)


## Kamikaze candidates: [value, id, seen_tick], best first. Heavy / anti-air / core targets inside the defence ring
## (every ground threat on a breach); value = priority + heavy bonus.
static func _kam_targets(w: SimWorld, brd: Array, commit: bool) -> Array:
	var hb := float(_hv("kamikaze").get("heavy_bonus", 250))
	var out := []
	for b in brd:
		var cls := String(b[2])
		if _is_air_cls(cls) or int(b[4]) == 0 or not w.entities.has(int(b[0])):
			continue
		if not commit and int(b[5]) == 0 and cls != "aa" and cls != "core":
			continue
		out.append([float(b[1]) + hb * float(b[5]), int(b[0]), int(b[3]), int(b[5])])
	out.sort_custom(func(a, b): return float(a[0]) > float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	return out


static func _release_kamikazes(w: SimWorld, B: Dictionary, brd: Array, commit: bool) -> void:
	if int(B.stock.get("kamikaze", 0)) <= 0:
		return
	var K := _hv("kamikaze")
	var per := maxi(1, int((R().need as Dictionary).get("kamikaze_per_heavy", 1)))
	var on := _kamikaze_on(B)
	var supp: Dictionary = B.supp
	if commit:
		# WATCH7-3 (13.9c-27a "hive mind ... defend the facility at all cost"): on a breach the kamikazes commit TOGETHER:
		# the whole stock is queued at once, dealt round-robin over the threats best first (every threat gets one before
		# any gets a second), up to commit_per_heavy on a heavy / big target and commit_per on the rest; the launch
		# gap is already halved under commit, so they leave the deck as one wave instead of one per target over time.
		# Once every target holds its cap the rest still go, round-robin (every drone in the hangar launches).
		var kt := _kam_targets(w, brd, true)
		var cph := maxi(per, int(K.get("commit_per_heavy", 4)))
		var cpl := maxi(per, int(K.get("commit_per", 2)))
		var more := true
		var capped := true   # first up to the per-target caps, then the rest of the stock round-robin (all of it goes)
		while (more or capped) and int(B.stock.get("kamikaze", 0)) > 0 and not kt.is_empty():
			if not more:
				capped = false
			more = false
			for c in kt:
				if int(B.stock.get("kamikaze", 0)) <= 0:
					break
				var tid := int(c[1])
				if capped and int(on.get(tid, 0)) >= (cph if int(c[3]) > 0 else cpl):
					continue
				if _queue(B, "kamikaze", tid, "auto"):
					on[tid] = int(on.get(tid, 0)) + 1
					more = true
		return
	for c in _kam_targets(w, brd, commit):
		if int(B.stock.get("kamikaze", 0)) <= 0:
			break
		var tid := int(c[1])
		if int(on.get(tid, 0)) >= per:
			continue
		var ok := commit
		if not ok and supp.has(str(tid)):
			ok = w.tick - int(supp[str(tid)]) >= ticks(float(K.get("supp_s", 1.5)))   # the gun drones have it under fire
		if not ok:
			ok = w.tick - int(c[2]) >= ticks(float(K.get("wait_s", 8.0)))
		if ok and _queue(B, "kamikaze", tid, "auto"):
			on[tid] = int(on.get(tid, 0)) + 1


static func _hpf(e: Dictionary) -> float:
	return clampf(float(e.hp) / maxf(float(e.get("max_hp", e.hp)), 1.0), 0.0, 1.0)


static func _range_of(e: Dictionary) -> float:
	return float(SimWorld.Combat.stats(e).get("range", 4.0))


## Tasks every drone aloft from the board: hard limits (battery / badly hurt) first, then player orders are left
## alone, rotation (a third at a time), rams at the core (breach), the screen and the fire teams.
static func _task(w: SimWorld, B: Dictionary, brd: Array, commit: bool, quiet: bool) -> void:
	var out: Dictionary = B.out
	var ids: Array = out.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	var sortie := ticks(float(R().sortie_s))
	var RT := _hv("rotate")
	var ints := []
	var guns := []
	var returning := 0
	for k in ids:
		var d: Dictionary = out[k]
		var e = w.entities.get(int(d.id))
		if e == null:
			continue   # handled in _sweep
		var kind := String(d.kind)
		if kind == "kamikaze":
			d.task = "strike"
			_retarget_kamikaze(w, B, d, brd)
			continue
		if int(d.rec) == 1:
			d.task = "rearm"
			returning += 1
			continue
		var o: Dictionary = e.get("order", {})
		var ot := String(o.get("type", "idle"))
		if ot == "hold":
			d.task = "held"
			continue   # player Hold Position: never moved
		if String(d.get("task", "")) == "ram" and w.entities.has(int(d.get("tgt", -1))) and o.has("hive"):
			continue   # committed: terminal guidance in _sweep
		var used := w.tick - int(d.t0)
		if used >= sortie or _hpf(e) < float(RT.get("must_hp", 0.2)):
			_recall_drone(w, B, d, e, "battery" if used >= sortie else "damaged")
			returning += 1
			continue
		if ot != "idle" and not o.has("hive"):
			d.task = "player"
			continue   # a fresh player order: left alone until it goes idle
		if brd.is_empty() and quiet and String(d.mode) == "auto":
			_recall_drone(w, B, d, e, "quiet")
			returning += 1
			continue
		if kind == "interceptor":
			ints.append([d, e])
		else:
			guns.append([d, e])
	if not commit and not brd.is_empty():
		returning = _rotate(w, B, ints, guns, returning, sortie, RT)
	if commit:
		_assign_rams(w, B, brd, ints, guns, sortie)
	_screen(w, B, brd, ints, commit, returning)
	_teams(w, B, brd, guns)


## Soft rotation: the most worn drones go home to rearm while at most down_frac of the drones in play are down
## (coming home + rearming) and at least keep_frac stay aloft; the release relaunches ready drones to relieve them.
static func _rotate(w: SimWorld, B: Dictionary, ints: Array, guns: Array, returning: int, sortie: int, RT: Dictionary) -> int:
	var rearming := (B.rearm as Array).size()
	var in_play := ints.size() + guns.size() + returning + rearming
	if in_play < 2:
		return returning
	var keep := ceili(float(in_play) * float(RT.get("keep_frac", 0.334)))
	var down_cap := maxi(1, floori(float(in_play) * float(RT.get("down_frac", 0.334))))
	var cands := []
	for pair in ints + guns:
		var d: Dictionary = pair[0]
		var e: Dictionary = pair[1]
		var u := float(w.tick - int(d.t0)) / float(maxi(sortie, 1))
		var hp := _hpf(e)
		if u >= float(RT.get("at", 0.45)) or hp < float(RT.get("hp", 0.4)):
			cands.append([u + (1.0 - hp), int(d.id), pair])
	if cands.is_empty():
		return returning
	cands.sort_custom(func(a, b): return float(a[0]) > float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	var gone := {}
	for c in cands:
		var active := ints.size() + guns.size() - gone.size()
		if active - 1 < keep or returning + rearming + 1 > down_cap:
			break
		var pair: Array = c[2]
		_recall_drone(w, B, pair[0], pair[1], "rotate")
		gone[int(c[1])] = true
		returning += 1
	if not gone.is_empty():
		for lst in [ints, guns]:
			for i in range(lst.size() - 1, -1, -1):
				if gone.has(int(lst[i][0].id)):
					lst.remove_at(i)
	return returning


## Last resort at the core (breach): an attacker at the core with no kamikaze on it draws a rammer (a gun drone
## first, the most worn; an interceptor only when no gun drone is up), at most ram.max at once.
static func _assign_rams(w: SimWorld, B: Dictionary, brd: Array, ints: Array, guns: Array, sortie: int) -> void:
	var RM := _hv("ram")
	var mx := int(RM.get("max", 2))
	var on := {}
	var n := 0
	for d in B.out.values():
		if String(d.get("task", "")) == "ram" and int(d.rec) == 0:
			on[int(d.get("tgt", -1))] = true
			n += 1
	var kam := _kamikaze_on(B)
	for b in brd:
		if n >= mx:
			break
		if String(b[2]) != "core":
			continue
		var tid := int(b[0])
		if on.has(tid) or int(kam.get(tid, 0)) > 0 or not w.entities.has(tid):
			continue
		var pool: Array = guns if not guns.is_empty() else ints
		if pool.is_empty():
			break
		var bi := 0
		var bs := -1.0
		for i in pool.size():
			var s := (1.0 - _hpf(pool[i][1])) + float(w.tick - int(pool[i][0].t0)) / float(maxi(sortie, 1))
			if s > bs + 0.000001:
				bs = s
				bi = i
		var pair: Array = pool[bi]
		pool.remove_at(bi)
		var d: Dictionary = pair[0]
		d.task = "ram"
		d.tgt = tid
		_fly(w, pair[1], Vector2(w.entities[tid].pos), tid)
		on[tid] = true
		n += 1
		w.emit("DroneBayRamOrder", {"fac": int(B.fac), "owner": int(B.fid), "id": int(d.id), "target": tid})


## The interceptor screen: intercepts first (air threats by priority draw the nearest interceptor; min_screen hold),
## incoming rockets / shells draw the nearest of the rest to their impact point, the others fly the outer picket on
## the threat axis and the inner close-in ring over the facility (one ring slot covers the deck while drones land).
static func _screen(w: SimWorld, B: Dictionary, brd: Array, ints: Array, commit: bool, returning: int) -> void:
	if ints.is_empty():
		return
	var SC := _hv("screen")
	var F := _fac(w, int(B.fac))
	var cr := SimWorld.CnFacility.compound_rect(F)
	var c := cr.get_center()
	var half := cr.size.x * 0.5
	var free := ints.duplicate()
	var max_i := ints.size() if commit else maxi(0, ints.size() - int(SC.get("min_screen", 1)))
	var n_i := 0
	for b in brd:
		if n_i >= max_i or free.is_empty():
			break
		if not _is_air_cls(String(b[2])):
			continue
		var t = w.entities.get(int(b[0]))
		if t == null:
			continue
		var tp: Vector2 = t.pos
		var bi := 0
		for i in range(1, free.size()):
			if Vector2(free[i][1].pos).distance_squared_to(tp) < Vector2(free[bi][1].pos).distance_squared_to(tp):
				bi = i
		var pair: Array = free[bi]
		free.remove_at(bi)
		var d: Dictionary = pair[0]
		var e: Dictionary = pair[1]
		d.task = "intercept"
		d.tgt = int(t.id)
		var o: Dictionary = e.get("order", {})
		if String(o.get("type", "")) != "attack" or int(o.get("target_id", -1)) != int(t.id):
			e.order = {"type": "attack", "target_id": int(t.id), "hive": 1}
			e.target = -1
		n_i += 1
	# incoming rockets / shells: the nearest screen interceptor moves under the impact point to shoot it down
	if free.size() > int(SC.get("min_screen", 1)) or commit:
		for s in incoming(w, B):
			if free.size() <= (0 if commit else int(SC.get("min_screen", 1))):
				break
			var at: Vector2 = s[0]
			var bi := 0
			for i in range(1, free.size()):
				if Vector2(free[i][1].pos).distance_squared_to(at) < Vector2(free[bi][1].pos).distance_squared_to(at):
					bi = i
			var pair: Array = free[bi]
			free.remove_at(bi)
			pair[0].task = "intercept"
			pair[0].tgt = -1
			_fly(w, pair[1], at, -1)
	var n := free.size()
	if n == 0:
		return
	var axis = _axis(w, brd, c)
	var n_out := 0 if commit or axis == null else n / 2
	var n_in := n - n_out
	var t := float(w.tick) / float(SimWorld.TICK_RATE) + float(SC.get("lead_s", 1.0))
	var r_out := half + float(SC.get("outer_d", 7.0))
	var r_in := maxf(half * float(SC.get("inner_frac", 0.45)), 2.0)
	var spread := deg_to_rad(float(SC.get("spread_deg", 28.0)))
	var sweep := deg_to_rad(float(SC.get("sweep_deg", 10.0)))
	var w_in := deg_to_rad(float(SC.get("inner_dps", 18.0)))
	var cover := returning > 0 and bool(SC.get("deck_cover", true))
	for i in n:
		var pair: Array = free[i]
		var d: Dictionary = pair[0]
		var pt: Vector2
		if i < n_out:
			var a := float(axis) + (float(i) - float(n_out - 1) * 0.5) * spread + sweep * sin(t * 0.6 + float(i))
			pt = c + Vector2.from_angle(a) * r_out
			d.slot = i
		else:
			var j := i - n_out
			if j == 0 and cover and n_in > 1:
				pt = deck_rect(w, int(B.fac)).get_center()   # covers the drones coming home to the deck
			else:
				pt = c + Vector2.from_angle(float(j) * TAU / float(n_in) + t * w_in) * r_in
			d.slot = 100 + j
		d.task = "screen"
		d.tgt = -1
		_fly(w, pair[1], pt, -1)


## Threat axis from the compound centre: priority-weighted direction of the top threats (null when none).
static func _axis(w: SimWorld, brd: Array, c: Vector2):
	var s := Vector2.ZERO
	var n := 0
	for b in brd:
		var t = w.entities.get(int(b[0]))
		if t == null:
			continue
		var v := Vector2(t.pos) - c
		if v.length() > 0.01:
			s += v.normalized() * float(b[1])
		n += 1
		if n >= 4:
			break
	if s.length() < 0.001:
		return null
	return s.angle()


## Gun-drone fire teams: teams go to ground targets by priority until each target's hp is covered, spare teams
## converge on the top threat. Members orbit their target on opposite sides at a standoff inside weapon range and
## strafe round it (targets alternate the direction; teams sharing a target split the circle evenly), firing at it.
## With no ground threat they help against air threats; with none at all they fly a guard ring over the walls.
static func _teams(w: SimWorld, B: Dictionary, brd: Array, guns: Array) -> void:
	if guns.is_empty():
		return
	var TM := _hv("team")
	var F := _fac(w, int(B.fac))
	var cr := SimWorld.CnFacility.compound_rect(F)
	var c := cr.get_center()
	var tnow := float(w.tick) / float(SimWorld.TICK_RATE) + float(TM.get("lead_s", 1.0))
	var tg := []
	for b in brd:
		if int(b[4]) == 1 and not _is_air_cls(String(b[2])) and w.entities.has(int(b[0])):
			tg.append(b)
	if tg.is_empty():
		for b in brd:
			if _is_air_cls(String(b[2])) and int(b[4]) == 1 and w.entities.has(int(b[0])):
				tg.append(b)
	if tg.is_empty():
		var rg := cr.size.x * 0.5 * float(TM.get("guard_frac", 0.85))
		var wg := deg_to_rad(float(TM.get("guard_dps", 12.0)))
		for i in guns.size():
			var a := float(i) * TAU / float(guns.size()) + PI / float(guns.size()) - tnow * wg
			guns[i][0].task = "guard"
			guns[i][0].tgt = -1
			_fly(w, guns[i][1], c + Vector2.from_angle(a) * rg, -1)
		return
	var tsz := maxi(1, int(TM.get("size", 2)))
	var nt := maxi(1, guns.size() / tsz)
	var hp_team := maxf(float(TM.get("hp_per_team", 800.0)), 1.0)
	var alloc := []
	var ti := 0
	for j in tg.size():
		var need := maxi(1, ceili(float(w.entities[int(tg[j][0])].hp) / hp_team))
		while ti < nt and need > 0:
			alloc.append(j)
			need -= 1
			ti += 1
	while ti < nt:
		alloc.append(0)   # converge: spare teams join the top threat (focus fire)
		ti += 1
	var w_orb := deg_to_rad(float(TM.get("orbit_dps", 50.0)))
	var supp: Dictionary = B.supp
	for i in guns.size():
		var team := mini(i / tsz, nt - 1)
		var mem := i - team * tsz
		var size_t := tsz if team < nt - 1 else guns.size() - (nt - 1) * tsz
		var tid := int(tg[int(alloc[team])][0])
		var tp: Vector2 = w.entities[tid].pos
		var rank := 0      # this team's place among the teams sharing its target
		var n_on := 0      # teams on this target
		for k in nt:
			if int(alloc[k]) == int(alloc[team]):
				if k < team:
					rank += 1
				n_on += 1
		var d: Dictionary = guns[i][0]
		var e: Dictionary = guns[i][1]
		var rng := _range_of(e)
		var rad := clampf(rng * float(TM.get("standoff", 0.7)), 2.0, maxf(rng - 0.5, 2.0))
		var dirn := 1.0 if int(alloc[team]) % 2 == 0 else -1.0   # teams on one target circle the same way (never cross)
		var a := (c - tp).angle() + float(rank) * PI / float(maxi(n_on, 1)) + float(mem) * TAU / float(maxi(size_t, 1)) 				+ dirn * tnow * w_orb
		d.task = "strike"
		d.tgt = tid
		d.team = team
		d.slot = mem
		_fly(w, e, tp + Vector2.from_angle(a) * rad, tid)
		if Vector2(e.pos).distance_to(tp) <= rng and not supp.has(str(tid)):
			supp[str(tid)] = w.tick   # under the fire team's guns: the kamikaze timing starts here


## A kamikaze whose target died picks the board's highest-value ground threat (nearest among equals) instead of diving
## on an empty spot.
static func _retarget_kamikaze(w: SimWorld, B: Dictionary, d: Dictionary, brd: Array) -> void:
	if w.entities.has(int(d.get("tgt", -1))):
		return
	var gs = w.sys_state.get("g5mech")
	if gs == null:
		return
	var r = (gs.drones as Dictionary).get(int(d.id))
	if r == null or String(r.get("phase", "fly")) != "fly":
		return
	var hb := float(_hv("kamikaze").get("heavy_bonus", 250))
	var p: Vector2 = w.entities[int(d.id)].pos
	var best = null
	var bv := -INF
	for b in brd:
		if _is_air_cls(String(b[2])):
			continue
		var u = w.entities.get(int(b[0]))
		if u == null:
			continue
		var v := float(b[1]) + hb * float(b[5]) - p.distance_to(Vector2(u.pos)) * 2.0
		if best == null or v > bv:
			best = u
			bv = v
	if best == null:
		return
	r.target = int(best.id)
	r.goal = _sv(Vector2(best.pos))
	d.tgt = int(best.id)


## A rammer reached its target at the core: it hits like a light warhead (ram.damage, ram.splash) and is spent.
static func _ram(w: SimWorld, B: Dictionary, d: Dictionary, e: Dictionary, t: Dictionary) -> void:
	var RM := _hv("ram")
	var s: Dictionary = SimWorld.G4bMech._wpn(String(RM.get("payload", "g5_drone_strike"))).duplicate()
	s.damage = float(RM.get("damage", 150.0))
	s.splash = float(RM.get("splash", 0.8))
	var at := _sv(Vector2(t.pos))
	var hits: int = SimWorld.G5Mech._impact(w, e, at, s)
	var id := int(e.id)
	B.out.erase(str(id))
	(B.icpt as Dictionary).erase(str(id))
	B.lost = int(B.get("lost", 0)) + 1
	B.rammed = int(B.get("rammed", 0)) + 1
	w.entities.erase(id)
	w.emit("EntityDestroyed", {"id": id, "kind": "unit", "def": e.def, "owner": e.owner, "pos": at, "cause": "dronebay_ram",
		"killer_owner": SimWorld.NEUTRAL, "squad": -1})
	w.emit("DroneBayRam", {"fac": int(B.fac), "owner": int(B.fid), "id": id, "kind": String(d.kind), "target": int(t.id),
		"pos": at, "hits": hits})


## Every tick (cheap): launches off the deck, landings, rams, losses, rearm and rebuild timers.
static func _sweep(w: SimWorld, B: Dictionary) -> void:
	var fac := int(B.fac)
	var fid := int(B.fid)
	var out: Dictionary = B.out
	var commit := String(B.get("mode", "calm")) == "commit"
	if not out.is_empty():
		var ids: Array = out.keys()
		ids.sort_custom(func(a, b): return int(a) < int(b))
		var lr := float(R().land_r)
		for k in ids:
			var d: Dictionary = out[k]
			var e = w.entities.get(int(d.id))
			if e == null:
				out.erase(k)
				B.lost = int(B.get("lost", 0)) + 1
				(B.icpt as Dictionary).erase(k)
				w.emit("DroneBayLost", {"fac": fac, "owner": fid, "id": int(d.id), "kind": String(d.kind)})
				continue
			if int(d.rec) == 1:
				var spot := deck_spot(w, fac, int(d.spot))
				var dist := Vector2(e.pos).distance_to(spot)
				if dist <= lr or (dist <= 1.2 and not bool(e.get("moving", false))):
					_land(w, B, d, e)
				elif not bool(e.get("moving", false)) and (w.tick + int(d.id)) % 20 == 0:
					SimWorld.Movement.order_move(w, e, spot)   # nudged off its path: fly home again
			elif String(d.get("task", "")) == "ram":
				var t = w.entities.get(int(d.get("tgt", -1)))
				if t == null or not (e.order as Dictionary).has("hive"):
					d.task = ""   # target gone / a player order: back to the hive's tasking
				elif Vector2(e.pos).distance_to(Vector2(t.pos)) <= float(_hv("ram").get("hit_r", 0.7)):
					_ram(w, B, d, e, t)
				elif (w.tick + int(d.id)) % 4 == 0:
					_fly(w, e, Vector2(t.pos), int(t.id))
	if not (B.q as Array).is_empty() and w.tick >= int(B.next_launch):
		_launch_next(w, B)
		var gap := float(R().launch_gap_s) * (float(_hv("commit").get("gap_mult", 0.5)) if commit else 1.0)
		B.next_launch = w.tick + ticks(gap)
	if not (B.rearm as Array).is_empty():
		var keep := []
		for r in B.rearm:
			if w.tick >= int(r[1]):
				B.stock[String(r[0])] = int(B.stock.get(String(r[0]), 0)) + 1
				w.emit("DroneBayRearmed", {"fac": fac, "owner": fid, "kind": String(r[0])})
			else:
				keep.append(r)
		B.rearm = keep
	if (B.build as Array).size() == 2:
		if w.tick >= int(B.build[1]):
			var kind := String(B.build[0])
			B.stock[kind] = int(B.stock.get(kind, 0)) + 1
			B.build = []
			w.emit("DroneBayRebuilt", {"fac": fac, "owner": fid, "kind": kind})
	elif ((w.tick + fac) % (5 if commit else SimWorld.TICK_RATE) == 0) and total(B) < int(R().cap):
		_start_rebuild(w, B)


static func _start_rebuild(w: SimWorld, B: Dictionary) -> void:
	var mix: Dictionary = R().mix
	var kind := ""
	for k in R().rebuild_order:
		if int(_count(B, String(k)).total) < int(mix.get(String(k), 0)):
			kind = String(k)
			break
	if kind == "":
		kind = "gun"   # mix below cap: fill with gun drones
	var cost: Dictionary = R().rebuild_cost
	if not w.spend(int(B.fid), cost, "dronebay_rebuild"):
		return
	var sec := float(R().rebuild_s)
	if String(B.get("mode", "calm")) == "commit":
		sec *= float(_hv("commit").get("rebuild_mult", 0.4))
	B.build = [kind, w.tick + ticks(sec)]
	w.emit("DroneBayRebuilding", {"fac": int(B.fac), "owner": int(B.fid), "kind": kind, "eta_s": snappedf(sec, 0.1)})


# ================================================================ display (render snapshot; pure read)
const DECK_PX := 103.6      # the launch deck: 10.57 m (fac_life7 DECK_Z, its display drone's deck spot) x 9.8 px/m
const DECK_CLIMB_PX := 14.0  # hover height over the deck before a drone leaves it / as it settles
const DECK_FADE := 3.0       # tiles past the deck edge over which the drawn height eases back to normal flight


## {drone id: minimum drawn lift in px} for bay drones on / over / just off their launch deck, so they take off from
## and land on the workshop roof instead of floating in front of the 2-storey building. Display only (RenderSnap g7u
## "bz"); never written into the sim.
static func display_lifts(w: SimWorld) -> Dictionary:
	var out := {}
	var st = state(w)
	if st == null:
		return out
	for k in st.bays:
		var B: Dictionary = st.bays[k]
		if (B.out as Dictionary).is_empty():
			continue
		var r := deck_rect(w, int(k))
		if r.size == Vector2.ZERO:
			continue
		for dk in B.out:
			var d: Dictionary = B.out[dk]
			var e = w.entities.get(int(d.id))
			if e == null:
				continue
			var p: Vector2 = e.pos
			var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
			var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
			var dist := sqrt(dx * dx + dy * dy)
			if dist >= DECK_FADE:
				continue
			var hov := DECK_CLIMB_PX
			if dist <= 0.0:   # over the deck: sits on its spot, lifts off / settles within ~1 tile of it
				var spot := deck_spot(w, int(k), int(d.spot))
				hov = DECK_CLIMB_PX * clampf(p.distance_to(spot), 0.0, 1.0)
			out[int(e.id)] = snappedf((DECK_PX + hov) * (1.0 - dist / DECK_FADE), 0.1)
	return out


## Display only (an optional overlay, CR to ORCH / LOOK7): the hive's formations of side fid as draw primitives in world
## tiles: {"rings": [[centre: Vector2, radius: float]], "links": [[from: Vector2, to: Vector2, task: String]]}: the inner
## screen ring over each facility with screen drones up, and a link from every striking / intercepting / ramming drone
## to its target. Pure read; both lists empty without a bay.
static func display_hive(w: SimWorld, fid: int) -> Dictionary:
	var out := {"rings": [], "links": []}
	var st = state(w)
	if st == null:
		return out
	var ks: Array = (st.bays as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var B: Dictionary = st.bays[k]
		if int(B.fid) != fid or (B.out as Dictionary).is_empty():
			continue
		var F := _fac(w, int(k))
		if F.is_empty():
			continue
		var cr := SimWorld.CnFacility.compound_rect(F)
		var ring := false
		for d in B.out.values():
			var e = w.entities.get(int(d.id))
			if e == null or int(d.rec) == 1:
				continue
			var t := String(d.get("task", ""))
			if t == "screen" and int(d.get("slot", 0)) >= 100:
				ring = true
			elif t == "strike" or t == "intercept" or t == "ram":
				var tg = w.entities.get(int(d.get("tgt", -1)))
				if tg != null:
					out.links.append([Vector2(e.pos), Vector2(tg.pos), t])
		if ring:
			out.rings.append([cr.get_center(), maxf(cr.size.x * 0.5 * float(_hv("screen").get("inner_frac", 0.45)), 2.0)])
	return out


# ================================================================ interception hook (strikes, CR to DRONE7)
## True when an airborne interceptor of an enemy of attacker_fid is within intercept.r of `at` and ready: it shoots
## the incoming rocket / shell / strike down (then waits cooldown_s).
static func intercept_strike(w: SimWorld, attacker_fid: int, at: Vector2, kind: String) -> bool:
	var st = state(w)
	if st == null:
		return false
	var I: Dictionary = R().intercept
	var r2 := float(I.get("r", 4.0)) * float(I.get("r", 4.0))
	var bks: Array = (st.bays as Dictionary).keys()
	bks.sort_custom(func(a, b): return int(a) < int(b))
	for bk in bks:
		var B: Dictionary = st.bays[bk]
		if not w.is_enemy(attacker_fid, int(B.fid)) or (B.out as Dictionary).is_empty():
			continue
		var ids: Array = B.out.keys()
		ids.sort_custom(func(a, b): return int(a) < int(b))
		for k in ids:
			var d: Dictionary = B.out[k]
			if String(d.kind) != "interceptor":
				continue
			var e = w.entities.get(int(d.id))
			if e == null or Vector2(e.pos).distance_squared_to(at) > r2:
				continue
			if w.tick < int((B.icpt as Dictionary).get(k, 0)):
				continue
			B.icpt[k] = w.tick + ticks(float(I.get("cooldown_s", 3.0)))
			B.intercepts = int(B.get("intercepts", 0)) + 1
			w.emit("DroneBayIntercept", {"fac": int(B.fac), "owner": int(B.fid), "drone": int(d.id), "attacker": attacker_fid,
				"kind": kind, "pos": _sv(at)})
			return true
	return false


# ================================================================ commands
static func _bay_for(w: SimWorld, cmd: Dictionary) -> Dictionary:
	var fid := int(cmd.get("issuer", -1))
	if cmd.has("building_id"):
		var B := bay(w, int(cmd.building_id))
		return B if not B.is_empty() and int(B.fid) == fid else {}
	var l := bays_of(w, fid)
	return {} if l.is_empty() else bay(w, int(l[0]))


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var t := String(cmd.get("type", ""))
	if not ["dronebay_launch", "dronebay_recall", "dronebay_auto"].has(t):
		return "Unknown command."
	var B := _bay_for(w, cmd)
	if B.is_empty():
		return "Needs a Counter-Nanite facility drone bay."
	match t:
		"dronebay_launch":
			var k := String(cmd.get("kind", "all"))
			if k != "all" and not KINDS.has(k):
				return "Unknown drone kind."
			var ready := 0
			for kk in KINDS:
				if k == "all" or k == kk:
					ready += int(B.stock.get(kk, 0))
			if ready <= 0:
				return "No drones ready in the bay."
		"dronebay_recall":
			if (B.out as Dictionary).is_empty() and (B.q as Array).is_empty():
				return "No drones out."
		"dronebay_auto":
			if not cmd.has("on"):
				return "Missing on."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	if validate_command(w, cmd) != "":
		return
	var B := _bay_for(w, cmd)
	match String(cmd.type):
		"dronebay_launch":
			_manual_launch(w, B, cmd)
		"dronebay_recall":
			var n := (B.q as Array).size()
			for it in B.q:
				B.stock[String(it[0])] = int(B.stock.get(String(it[0]), 0)) + 1
			B.q = []
			var ids: Array = B.out.keys()
			ids.sort_custom(func(a, b): return int(a) < int(b))
			for k in ids:
				var d: Dictionary = B.out[k]
				var e = w.entities.get(int(d.id))
				if e != null and String(d.kind) != "kamikaze" and int(d.rec) == 0:
					_recall_drone(w, B, d, e, "player")
					n += 1
			w.emit("DroneBayRecall", {"fac": int(B.fac), "owner": int(B.fid), "n": n, "cause": "player"})
		"dronebay_auto":
			B.auto = bool(cmd.on)
			w.emit("DroneBayAuto", {"fac": int(B.fac), "owner": int(B.fid), "on": bool(B.auto)})


static func _manual_launch(w: SimWorld, B: Dictionary, cmd: Dictionary) -> void:
	var kind := String(cmd.get("kind", "all"))
	var cnt := int(cmd.get("count", 99))
	var at = null
	if cmd.has("target"):
		var tv = cmd.target
		if tv is Vector2:
			at = tv
		elif tv is Array and (tv as Array).size() == 2:
			at = Vector2(float(tv[0]), float(tv[1]))
	var T := threats(w, B)
	# kamikazes need a target: the nearest enemy to the ordered point, else the heaviest threat at the base
	var kt := -1
	if at != null:
		var best = null
		for u in SimIndex.of(w, "unit"):
			if not w.entities.has(int(u.id)):
				continue
			if w.is_enemy(int(B.fid), int(u.owner)) and Vector2(u.pos).distance_to(Vector2(at)) <= 6.0 \
					and not bool(Content.unit(String(u.def)).get("is_air", false)):
				if best == null or Vector2(u.pos).distance_squared_to(Vector2(at)) < Vector2(best.pos).distance_squared_to(Vector2(at)) \
						or (Vector2(u.pos).distance_squared_to(Vector2(at)) == Vector2(best.pos).distance_squared_to(Vector2(at)) and int(u.id) < int(best.id)):
					best = u
		if best != null:
			kt = int(best.id)
	n_launch(w, B, kind, cnt, at, kt, T)


static func n_launch(w: SimWorld, B: Dictionary, kind: String, cnt: int, at, kt: int, T: Dictionary) -> void:
	var n := 0
	var order: Array = KINDS if kind == "all" else [kind]
	for k in order:
		if kind == "all" and k == "kamikaze":
			continue   # "launch all" sends the reusable drones; kamikazes go only on an explicit order
		while n < cnt and int(B.stock.get(k, 0)) > 0:
			var tg := -1
			if k == "kamikaze":
				tg = kt if kt >= 0 else _pick_target(B, T, "kamikaze", n)
				if tg < 0:
					tg = _pick_target(B, T, "gun", n)
				if tg < 0:
					break
			elif at == null:
				tg = _pick_target(B, T, k, n)
			if not _queue(B, k, tg, "manual", at):
				break
			n += 1
	w.emit("DroneBayManualLaunch", {"fac": int(B.fac), "owner": int(B.fid), "kind": kind, "n": n})


# ================================================================ tick
## Test / A-B switch only (DET7-2: before / after comparison of the raise-tick bay discovery). Never saved; true in a real match.
static var eager_discover := true


static func tick(w: SimWorld) -> void:
	if not w.sys_state.has("cn_facility"):
		return
	# DET7: a facility gets its bay the tick it is raised (CnFacility runs earlier in the tick), not at the next
	# tick % DISCOVER_EVERY: until then dronebay_* commands were rejected ("Needs a Counter-Nanite facility drone bay")
	# and an "auto off" given right after the facility rose never took. Facilities are few: a key check per tick.
	if w.tick % DISCOVER_EVERY == 0 or (eager_discover and _bay_missing(w)):
		_discover(w)
	var st = state(w)
	if st == null:
		return
	var t0 := Time.get_ticks_usec() if SimIndex.profiling else 0   # bench only (.plan/db7_ab.gd); never touches state
	var bays: Dictionary = st.bays
	var ks: Array = bays.keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	var every := maxi(1, int(R().think_every))
	for k in ks:
		var B: Dictionary = bays[k]
		var F := _fac(w, int(k))
		if F.is_empty() or not w.entities.has(int(k)):
			for d in B.out.values():   # the facility is gone: its drones fly on, unmanaged
				var e = w.entities.get(int(d.id))
				if e != null:
					e.erase("dbay")
			bays.erase(k)
			w.emit("DroneBayLost", {"fac": int(k), "owner": int(B.fid), "id": -1, "kind": "bay"})
			continue
		if not B.has("board"):   # a bay saved before the hive (VER 1)
			B.board = []
			B.mode = "calm"
			B.supp = {}
			B.rammed = 0
		if (w.tick + int(k)) % every == 0:
			_think(w, B)
		_sweep(w, B)
	if SimIndex.profiling:
		SimIndex.pt("dronebay7", t0)
