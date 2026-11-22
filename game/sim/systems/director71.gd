extends RefCounted
## G7.1 C1 / C2 / C3 stub (Last Protocol only). The dread meter: how hard the hive is pressing.
## Time is the spine (the ~60 min ramp). Creep, fallen rings and lost teams pull it up.
## Tide assault gaps stretch while dread is low (a breather) and return to the written base at full dread.
## Assaults split onto a main face and a feint face. Late dread peels a logistics strike onto rear targets
## (FARP / radar / power / hospital / depot). Wounded machines retreat to the hive spawn, heal, and return.
## Adapt buckets counter the weapons that kill Machines most. Siege band (and mixed) can spawn C3 stubs
## (gorilla brute / siege walker). The first siege-band crossing fires LpBreakingPoint once.
## Phase timing is unchanged. Numbers are provisional.

const Q := 1.0 / 1024.0


static func rules() -> Dictionary:
	var c = Content.rules().get("g71_director", {})
	return c if c is Dictionary else {}


static func pressure(frac: float, rings: int, creep: float, losses: int) -> float:
	var r := rules()
	var t := clampf(frac, 0.0, 1.0) * float(r.get("time_w", 0.70))
	var c := clampf(creep, 0.0, 1.0) * float(r.get("creep_w", 0.15))
	var g := clampf(float(maxi(rings, 0)) * float(r.get("ring_w", 0.20)), 0.0, float(r.get("ring_cap", 0.40)))
	var l := clampf(float(maxi(losses, 0)) * float(r.get("loss_w", 0.02)), 0.0, float(r.get("loss_cap", 0.15)))
	return clampf(snappedf(t + c + g + l, Q), 0.0, 1.0)


## "probe" early, "mixed" around the middle, "siege" near the peak. Labels only.
static func band(dread: float) -> String:
	var r := rules()
	if dread >= float(r.get("siege_at", 0.85)):
		return "siege"
	if dread >= float(r.get("mixed_at", 0.45)):
		return "mixed"
	return "probe"


## Tide assault gap in seconds. Longer while dread is low (a breather), the written base once dread is at 1.
static func interval_s(base_s: float, dread: float) -> float:
	var start := float(rules().get("breath_at_start", 1.6))
	var k := clampf(dread, 0.0, 1.0)
	return snappedf(maxf(base_s, 1.0) * (start + (1.0 - start) * k), Q)


## Main face = busiest of the 8 sectors (ties: lowest index). Feint = opposite face by default;
## if that face is empty and another sector is busy, use the second busiest instead.
## sectors is an Array of 8 ints (LpDefence.scan().sectors). Returns {main, feint, feint_frac}.
static func pick_push(sectors: Array) -> Dictionary:
	var main := 0
	var best := -1
	var second := -1
	var second_n := -1
	for i in mini(sectors.size(), 8):
		var n := int(sectors[i])
		if n > best or (n == best and i < main):
			if best >= 0 and main != i:
				second = main
				second_n = best
			best = n
			main = i
		elif n > second_n:
			second = i
			second_n = n
	var feint := (main + 4) % 8
	# Prefer a live second face only when the opposite is empty and that face actually has threat.
	if second_n > 0 and second != main and second != feint and sectors.size() >= 8 and int(sectors[feint]) <= 0:
		feint = second
	return {"main": main, "feint": feint, "feint_frac": float(rules().get("feint_frac", 0.25))}


## True once dread reaches the late-logistics band (defaults near siege).
static func logistics_ready(dread: float) -> bool:
	return dread >= float(rules().get("logistics_at", 0.75))


## Building def ids / flags the late strike peels onto (ammo, power, radar, fuel, FARPs, aid).
static func is_logistics_def(def_id: String) -> bool:
	var d: Dictionary = Content.building(def_id)
	if d.is_empty():
		return false
	if bool(d.get("farp", false)) or d.has("radar") or bool(d.get("hospital", false)):
		return true
	var tags: Array = rules().get("logistics_defs", ["generator", "depot", "a_radar_station", "a_hospital", "a_g71_farp", "a_repair_bay"])
	return tags.has(def_id)


## Sorted list of {id, pos} for living logistics buildings on the human side.
static func pick_logistics(buildings: Array) -> Array:
	var out := []
	for b in buildings:
		if not bool(b.get("built", true)):
			continue
		if int(b.get("hp", 1)) <= 0:
			continue
		if not is_logistics_def(String(b.get("def", ""))):
			continue
		out.append({"id": int(b.id), "pos": Vector2(b.pos)})
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


static func hp_frac(e: Dictionary) -> float:
	var mx := float(e.get("hp_max", e.get("max_hp", 0.0)))
	if mx <= 0.0:
		var d: Dictionary = Content.unit(String(e.get("def", "")))
		mx = float(d.get("hp", 1.0))
	return clampf(float(e.get("hp", 0.0)) / maxf(mx, 1.0), 0.0, 1.0)


static func needs_retreat(frac: float) -> bool:
	return frac <= float(rules().get("retreat_hp", 0.35))


static func ready_return(frac: float) -> bool:
	return frac >= float(rules().get("regrow_hp", 0.70))


## True the first time dread crosses the siege band. Sets s.break_point so it fires once.
static func note_breaking(s: Dictionary, dread: float) -> bool:
	if bool(s.get("break_point", false)):
		return false
	if band(dread) != "siege":
		return false
	s.break_point = true
	return true


## Map a weapon class / id onto an adapt bucket (armour / emp / smoke / disperse).
static func kill_bucket(cls: String, weapon: String = "") -> String:
	var key := cls.strip_edges().to_lower()
	if key == "" and weapon != "":
		key = weapon.strip_edges().to_lower()
	var map: Dictionary = rules().get("adapt_map", {
		"mg": "armour", "hmg": "armour", "rifle": "armour", "autocannon": "armour", "cannon": "armour",
		"laser": "smoke", "beam": "smoke", "rail": "smoke", "railgun": "smoke",
		"missile": "disperse", "rocket": "disperse", "artillery": "disperse", "mortar": "disperse",
		"drone": "emp", "anti_drone": "emp", "emp": "emp", "flak": "emp",
	})
	if map.has(key):
		return String(map[key])
	for tok in ["laser", "beam", "rail", "missile", "rocket", "drone", "emp", "mg", "cannon"]:
		if key.find(tok) >= 0 and map.has(tok):
			return String(map[tok])
	return "armour"


## Record one Machine death cause into s.adapt {bucket: count}.
static func note_kill(s: Dictionary, cls: String, weapon: String = "") -> String:
	var b := kill_bucket(cls, weapon)
	if not s.has("adapt") or not (s.adapt is Dictionary):
		s.adapt = {}
	s.adapt[b] = int(s.adapt.get(b, 0)) + 1
	return b


## Def ids to spawn with the next Tide push. Empty while dread is still probing.
## counter (armour/emp/smoke/disperse) peels an extra unit onto the roster when known.
static func siege_roster(dread: float, counter: String = "") -> Array:
	var b := band(dread)
	var out: Array = []
	if b == "siege":
		out = Array(rules().get("siege_spawn", ["g71_m_brute", "g71_m_siege_walker"]))
	elif b == "mixed":
		out = Array(rules().get("siege_spawn_mixed", ["g71_m_brute"]))
	else:
		return []
	var bonus = rules().get("adapt_spawn", {
		"armour": "g71_m_brute",
		"emp": "g71_m_glass_stalker",
		"smoke": "g71_m_turret_eater",
		"disperse": "g71_m_sapper",
	})
	if bonus is Dictionary and counter != "" and bonus.has(counter):
		var extra := String(bonus[counter])
		if extra != "" and not Content.unit(extra).is_empty():
			out = out.duplicate()
			out.append(extra)
	return out


## Overmind radio line for a key (breaking_point / adapt_* / probe). Empty when unknown.
static func overmind_line(key: String) -> String:
	var lines = rules().get("overmind_lines", {})
	if not (lines is Dictionary):
		return ""
	return String(lines.get(key, ""))


## Highest adapt bucket (ties: armour, emp, smoke, disperse order). Empty board -> "".
static func counter_for(s: Dictionary) -> String:
	var a = s.get("adapt", {})
	if not (a is Dictionary) or (a as Dictionary).is_empty():
		return ""
	var order := ["armour", "emp", "smoke", "disperse"]
	var best := ""
	var n := -1
	for k in order:
		var v := int(a.get(k, 0))
		if v > n:
			n = v
			best = k
	return best if n > 0 else ""


static func apply(s: Dictionary, frac: float, rings: int, creep: float, losses: int) -> float:
	var d := pressure(frac, rings, creep, losses)
	if not s.has("dread") or not is_equal_approx(float(s.dread), d):
		s.dread = d
	return d
