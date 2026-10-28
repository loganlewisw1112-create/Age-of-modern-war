extends RefCounted
## G5 visual rules (owner: VIEW5). Pure functions on content + the merged ArtCatalog manifest, shared by
## entity_layer / batch_art / fx_layer / lod_icons and tests/test_view5.gd. They read only the render
## snapshot's data (never the live world), so they are safe while a sim step is in flight.
## No class_name: preload it.

const ALT_DEFAULT := {"jet": 46.0, "vtol": 34.0, "heli": 26.0, "micro": 14.0}
const DRONE_ALT := 14.0
const STRIP_KINDS := ["start", "mid", "end"]

static var _alt: Dictionary = {}   # def -> [altitude px, bob px]
static var _wake: Dictionary = {}  # def -> has an ART-NAV wake sheet (VIEW5-2)


static func unit_spec(def_id: String) -> Dictionary:
	var man: Dictionary = ArtCatalog.manifest()
	return man.get("infantry", {}).get(def_id, man.get("vehicles", {}).get(def_id, {}))


## [altitude px at full height, bob px] for a G5 aircraft / launched drone (manifest altitude / bob
## win; ART-U5 drones carry them, ART-AIR may). Defaults by aircraft type.
static func alt_spec(def_id: String) -> Array:
	var c = _alt.get(def_id)
	if c != null:
		return c
	var spec := unit_spec(def_id)
	var ud: Dictionary = Content.unit(def_id)
	var ac := String(ud.get("aircraft", ""))
	var drone := bool(ud.get("launched_drone", false))
	var a := float(spec.get("altitude", 0.0))
	if a <= 0.0:
		a = DRONE_ALT if drone else float(ALT_DEFAULT.get(ac, 30.0))
	var bob := float(spec.get("bob", 1.0 if (drone or ac == "heli" or ac == "micro") else 0.0))
	c = [a, bob]
	_alt[def_id] = c
	return c


## Screen lift (px) of an aircraft at altitude fraction alt (snap.air[id].alt) at anim time t.
static func lift_px(def_id: String, alt: float, id: int, t: float) -> float:
	if alt <= 0.0:
		return 0.0
	var s := alt_spec(def_id)
	return float(s[0]) * alt + float(s[1]) * sin(t * 3.0 + float(id) * 0.7) * alt


## Frame column of special state `state` in a sheet with columns `frames`: manifest specials[def][state]
## names the column (ART-U5), else a column called like the state; -1 = the sheet has none.
static func special_col(def_id: String, frames: Array, state: String) -> int:
	var sp = ArtCatalog.manifest().get("specials", {}).get(def_id, {})
	var fname := state
	if sp is Dictionary and sp.has(state):
		fname = String(sp[state])
	return frames.find(fname)


## Wounded pose effect for human infantry whose sheet has no wounded column (G1-G4 infantry).
static func wounded_fx(faction_def: String) -> String:
	return "g5_wounded_b" if faction_def == "human_b" else "g5_wounded_a"


## Sheet {file, mask} for a squad at squad_alive `alive` (alive_sheets["n"] when 0 < n < size).
static func squad_sheet(spec: Dictionary, alive: int) -> Dictionary:
	var al = spec.get("alive_sheets")
	if alive > 0 and al is Dictionary and (al as Dictionary).has(str(alive)):
		return al[str(alive)]
	return {"file": String(spec.get("file", "")), "mask": String(spec.get("mask", ""))}


## ART-BLD variant family of a building def ("" | lvl | rot | water). G6 (VIEW6): g6_bld defs carry the
## same family under `g6` (every G6 building is "rot": rot_<f>, _damaged, _build_<n>, optional _fire).
const Traverse7 = preload("res://sim/systems/traverse7.gd")   # G7 TURRET7B: rot-only turret quarter turns
## G7 TURRET7B: wall-turret mount normals (WallTurret7.DIRS: E, S, W, N) as world angles for the head aim step.
const WT_N := [0.0, PI * 0.5, PI, -PI * 0.5]


static func variant_of(b: Dictionary) -> String:
	var g = b.get("g5")
	if not (g is Dictionary):
		g = b.get("g6")
	return String(g.get("variants", "")) if g is Dictionary else ""


## Building art state for the ART-BLD state_rules: lvl_<n> (hangar level), rot_<f> (field facing_i),
## water_<d> (shore side), each with _damaged under 50% hp and build_<0..2> while under construction
## (a hangar still being bought into a slot, air_build > 0, shows build_1). Falls back to built.
static func building_state(states: Dictionary, e: Dictionary, variant: String) -> String:
	var dmg := float(e.get("hp", 1.0)) < 0.5
	var base := ""
	match variant:
		"lvl":
			base = "lvl_%d" % clampi(int(e.get("level", 0)), 0, 3)
		"rot":
			base = "rot_%d" % posmod(int(e.get("facing_i", 0)), 4)
		"water":
			base = "water_%d" % posmod(int(e.get("water_d", 0)), 4)
	var ab := float(e.get("air_build", 0.0))
	if not bool(e.get("built", true)) or ab > 0.0:
		var n := clampi(int(float(e.get("progress", 0.0)) * 3.0), 0, 2)
		if ab > 0.0 and bool(e.get("built", true)):
			n = 1
		if base != "" and variant != "lvl" and states.has(base + "_build_%d" % n):
			return base + "_build_%d" % n
		if states.has("build_%d" % n):
			return "build_%d" % n
	# G7 TURRET7B (13.9c-30): turret heads are drawn on the SIMULATED turret bearing (render_snap static "tb", world
	# radians, sim/systems/traverse7.gd) so the barrel visibly swings onto its target before it fires: aim_<k>[_fire]
	# heads (yaw k * 45 deg) and wall-turret heads rot_<m>_a<n> (n - 1 = aim step across the 180 deg front of mount
	# normal m). Shown damaged or not (a hurt turret still traverses); build states above keep priority.
	var tb = e.get("tb")
	if tb != null and bool(e.get("built", true)):
		var fire := int(e.get("firing", 0)) > 0
		# G7 CIWS7 (13.9c-32): rotary CIWS frames cw<k>_<el>[_s|_fire], cw<k>_r (drum swap), cw<k>_x (dry): yaw k from tb,
		# elevation band el / phase ph from the sim frame code facing_i = el * 8 + ph (sim/systems/ciws7.gd)
		if states.has("cw0_1"):
			var kc := posmod(roundi(float(tb) / (PI / 4.0)), 8)
			var vc := int(e.get("facing_i", 0))
			var el := clampi(vc / 8, 0, 2)
			var ph := posmod(vc, 8)
			if ph == 3 and states.has("cw%d_r" % kc):
				return "cw%d_r" % kc
			if ph == 4 and states.has("cw%d_x" % kc):
				return "cw%d_x" % kc
			if fire and states.has("cw%d_%d_fire" % [kc, el]):
				return "cw%d_%d_fire" % [kc, el]
			if ph == 1 and states.has("cw%d_%d_s" % [kc, el]):
				return "cw%d_%d_s" % [kc, el]
			if states.has("cw%d_%d" % [kc, el]):
				return "cw%d_%d" % [kc, el]
		if states.has("aim_0"):
			var k := posmod(roundi(float(tb) / (PI / 4.0)), 8)
			if fire and states.has("aim_%d_fire" % k):
				return "aim_%d_fire" % k
			if states.has("aim_%d" % k):
				return "aim_%d" % k
		elif base != "" and states.has(base + "_a1"):
			var m := posmod(int(e.get("facing_i", 0)), 4)
			var rel := wrapf(float(tb) - float(WT_N[m]), -PI, PI)
			var a := clampi(roundi((rel + PI * 0.5) / (PI / 8.0)), 0, 8) + 1
			if fire and states.has(base + "_a%d_fire" % a):
				return base + "_a%d_fire" % a
			if states.has(base + "_a%d" % a):
				return base + "_a%d" % a
		elif variant == "rot":
			var ri: int = Traverse7.rot_aim_index(String(e.get("def", "")), float(tb))   # rot-only G6 turrets: coarse quarter turns
			if ri >= 0 and states.has("rot_%d" % ri):
				base = "rot_%d" % ri
	var fi4 := int(e.get("facing_i", 0)) / 4  # G7 WTUR7 CR 3641: wall-turret head aim frames rot_<m>_a<n>[_fire]
	if fi4 > 0 and base != "" and not dmg and bool(e.get("built", true)) and states.has(base + "_a%d" % fi4):
		if int(e.get("firing", 0)) > 0 and states.has(base + "_a%d_fire" % fi4):
			return base + "_a%d_fire" % fi4
		return base + "_a%d" % fi4
	if base != "":
		# G6 (VIEW6): the 14 G6 turrets carry rot_<f>_fire (kit action art: muzzle flash / missile /
		# beam), shown while the snapshot static has `firing` (the sim's shot counter) and hp >= 50%
		if int(e.get("firing", 0)) > 0 and not dmg and states.has(base + "_fire"):
			return base + "_fire"
		if dmg and states.has(base + "_damaged"):
			return base + "_damaged"
		if states.has(base):
			return base
	if dmg and states.has("damaged"):
		return "damaged"
	return "built"


## Burnt-out cells (w.map.burnt via the snapshot) as {cell index: true}.
static func burnt_cells(arr: PackedByteArray) -> Dictionary:
	var out := {}
	for i in arr.size():
		if arr[i] != 0:
			out[i] = true
	return out


## Runway tiles of one snapshot airfield (snap.airfields[bid]) from the ART-BLD airfield block:
## [[world pos, file, pivot Vector2], ...] in draw order (segments, links, then crater / closed
## overlays on closed strips). Empty when the field has no strips or the art has not landed.
static func strip_tiles(bid: int, af: Dictionary) -> Array:
	var out: Array = []
	var blk: Dictionary = ArtCatalog.manifest().get("airfield", {})
	var style = (blk.get("styles", {}) as Dictionary).get(String(af.get("def", "")))
	var strips: Array = af.get("strips", [])
	if style == null or strips.is_empty():
		return out
	var fi := int(af.get("facing_i", 0))
	var seg: Dictionary = (blk.get("segments", {}) as Dictionary).get(String(style), {}).get(str(fi), {})
	if seg.is_empty():
		return out
	var n := maxi(2, int(af.get("strip_len", 10)))
	var rep_s := float(Content.rules().get("g5_air", {}).get("crater_repair_s", 15.0))
	var over: Array = []
	for k in strips.size():
		var s: Dictionary = strips[k]
		var a: Vector2 = s.a
		var axis: Vector2 = ((s.b as Vector2) - a) / float(n)
		var perp := Vector2(-axis.y, axis.x).normalized()
		for i in n:
			var kind: String = "start" if i == 0 else ("end" if i == n - 1 else "mid")
			_tile(out, seg.get(kind), a + axis * (float(i) + 0.5))
		if k > 0:
			# 1-tile link between strip k-1 and k (perp offset size/2 + 4k - 0.5 from the apron centre)
			for i in mini(n, int(af.get("size", n))):
				_tile(out, seg.get("link"), a + axis * (float(i) + 0.5) - perp * 2.0)
		if not bool(s.get("open", true)):
			var ci := clampi(n / 3 + (bid * 7 + k * 3) % maxi(1, n / 3), 1, n - 2)
			var lst: Array = blk.get("craters_repair" if float(s.get("crater_t", 0.0)) < rep_s * 0.5 else "craters", [])
			if lst.is_empty():
				lst = blk.get("craters", [])
			if not lst.is_empty():
				_tile(over, lst[(bid + k) % lst.size()], a + axis * (float(ci) + 0.5))
			var cl = (blk.get("closed", {}) as Dictionary).get(str(fi))
			_tile(over, cl, a + axis * 1.5)
			_tile(over, cl, a + axis * (float(n) - 1.5))
	out.append_array(over)
	return out


static func _tile(out: Array, spec, p: Vector2) -> void:
	if spec is Dictionary and spec.has("file"):
		var pv: Array = spec.get("pivot", [0, 0])
		out.append([p, String(spec.file), Vector2(float(pv[0]), float(pv[1]))])


## ART-AIR animation pair for state "air" | "move": the frame columns listed in spec.anim[state]
## (e.g. rotor blur idle / idle_b), [] when the sheet has none.
static func anim_cols(spec: Dictionary, frames: Array, state: String) -> Array:
	var out: Array = []
	var an = spec.get("anim")
	if an is Dictionary and (an as Dictionary).get(state) is Array:
		for f in an[state]:
			var k := frames.find(String(f))
			if k >= 0:
				out.append(k)
	return out


## G5 (VIEW5-2, ART-NAV): terrain codes an amphibian swims on (water, shallow, deep).
const WATER_CODES := [4, 9, 10]


static func on_water(terr: PackedByteArray, p: Vector2, mw: int) -> bool:
	if terr.is_empty() or mw <= 0:
		return false
	var ti := floori(p.y) * mw + floori(p.x)
	return ti >= 0 and ti < terr.size() and WATER_CODES.has(int(terr[ti]))


## Sink sheet column (sink_0 .. sink_{n-1}) for sink timer fraction k (1 = just sunk, 0 = gone).
static func sink_col(k: float, n: int) -> int:
	var m := maxi(1, n if n > 0 else 4)
	return clampi(int((1.0 - clampf(k, 0.0, 1.0)) * m), 0, m - 1)


## True when def `d` has an ART-NAV wake sheet (vehicles[def].wake): fx_layer then skips its line wake.
static func has_wake_sheet(d: String) -> bool:
	var v = _wake.get(d)
	if v == null:
		v = unit_spec(d).get("wake") is Dictionary
		_wake[d] = v
	return v
