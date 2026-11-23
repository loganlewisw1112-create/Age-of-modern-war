extends RefCounted
## G9 COMBAT9 (G9_SCOPE C3): persistent terrain geometry (craters / breaches) + ballistics harness per match
## family. Extends BLAST8 / Fieldworks / LETHAL8 paths. Numbers PROVISIONAL — rules.g71_combat9.

const KEY := "combat9"
const VER := 1
const Q := 1.0 / 1024.0

const TerrainMod = preload("res://sim/terrain.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Damage = preload("res://sim/systems/damage.gd")
const Ballistics8 = preload("res://sim/systems/ballistics8.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")
const Parts71 = preload("res://sim/systems/parts71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")

const MATCH_FAMILIES := ["skirmish", "last_protocol", "editor_live"]

## Sample vehicle defs exercised per family (Done-when #5).
const FAMILY_VEHICLE := {
	"skirmish": "mbt",
	"last_protocol": "m_walker",
	"editor_live": "apc",
}


static func R() -> Dictionary:
	var c = Content.rules().get("g71_combat9", {})
	return c if c is Dictionary else {}


static func enabled(w: SimWorld) -> bool:
	return bool(R().get("enabled", true))


## Match-type family for ballistics harness (skirmish default conquest, LP, editor Live).
static func match_family(w: SimWorld) -> String:
	if bool(w.cfg.get("live_mode", false)):
		return "editor_live"
	var mode := String(w.cfg.get("mode", "skirmish"))
	if mode == "last_protocol":
		return "last_protocol"
	return "skirmish"


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get(KEY)
	if s == null:
		s = {"ver": VER, "craters": [], "breaches": [], "harness": {}}
		w.sys_state[KEY] = s
	return s


static func tick(w: SimWorld) -> void:
	pass


## BLAST8 hook: large enough bursts scar the map (persistent geometry).
static func on_burst(w: SimWorld, pos: Vector2, prof: Dictionary) -> void:
	if not enabled(w):
		return
	var min_kg := float(R().get("crater_min_charge_kg", 0.45))
	if Blast8.charge(prof) < min_kg:
		return
	add_crater(w, pos, float(R().get("crater_radius_tiles", 0.45)))


## Record a crater and paint the impact cell (saved in map.terrain + sys_state.combat9.craters).
static func add_crater(w: SimWorld, pos: Vector2, radius_tiles: float = 0.45) -> void:
	var c := Vector2i(floori(pos.x), floori(pos.y))
	if not w.in_bounds(c):
		return
	var st := _st(w)
	var rec := [snappedf(pos.x, Q), snappedf(pos.y, Q), snappedf(radius_tiles, Q), w.tick]
	st.craters.append(rec)
	_paint_crater(w, c)
	w.emit("Combat9Crater", {"pos": pos, "cell": [c.x, c.y], "tick": w.tick})


static func _paint_crater(w: SimWorld, c: Vector2i) -> void:
	var code := TerrainMod.CRATER
	var i := c.y * int(w.map.w) + c.x
	var t: PackedByteArray = w.map.terrain
	var old := int(t[i])
	if old in [TerrainMod.WATER, TerrainMod.DEEP, TerrainMod.BRIDGE, TerrainMod.CHASM,
			TerrainMod.BUILDING, TerrainMod.CLIFF, TerrainMod.RIDGE, TerrainMod.CRATER]:
		return
	t[i] = code
	w.map.terrain = t
	Movement.on_terrain_changed(w)


## Field-fortification breach marker (geometry record; walls71 / fortify may call later).
static func add_breach(w: SimWorld, cell: Vector2i, kind: String = "wall") -> void:
	var st := _st(w)
	st.breaches.append([cell.x, cell.y, kind, w.tick])
	w.emit("Combat9Breach", {"cell": [cell.x, cell.y], "kind": kind, "tick": w.tick})


static func crater_count(w: SimWorld) -> int:
	return (_st(w).craters as Array).size()


static func breach_count(w: SimWorld) -> int:
	return (_st(w).breaches as Array).size()


static func crater_at(w: SimWorld, cell: Vector2i) -> bool:
	if not w.in_bounds(cell):
		return false
	return int(w.map.terrain[cell.y * int(w.map.w) + cell.x]) == TerrainMod.CRATER


## Deterministic probe: facing + weak-spot path for one vehicle class in this match family.
static func exercise_ballistics(w: SimWorld, def_id: String = "") -> Dictionary:
	var fam := match_family(w)
	if def_id == "":
		def_id = String(FAMILY_VEHICLE.get(fam, "mbt"))
	var ud: Dictionary = Content.unit(def_id)
	if ud.is_empty():
		return {"ok": false, "family": fam, "def": def_id}
	var r8 = Ballistics8.round_of("at_rocket")
	if r8 == null:
		r8 = Ballistics8.round_of("tank_cannon")
	var tgt: Dictionary = {"def": def_id, "kind": "unit", "facing": 0.0, "pos": Vector2(30, 30), "owner": 1,
		"hp": float(ud.get("hp", 500.0))}
	if ud.has("comp"):
		tgt.comp = true
	var a8: Dictionary = Ballistics8.armour_of(tgt)
	var shooter := Vector2(34, 30)
	var tiles := Ballistics8.tiles_between({"pos": shooter}, tgt)
	tgt.facing = PI
	var rear_side := Damage.hit_side(shooter, tgt)
	var rear_dmg := Ballistics8.vehicle_damage(r8, a8, tgt, tiles, rear_side, 80.0, 1.0)
	tgt.facing = 0.0
	var front_side := Damage.hit_side(shooter, tgt)
	var front_dmg := Ballistics8.vehicle_damage(r8, a8, tgt, tiles, front_side, 80.0, 1.0)
	var weak_mult := 1.0
	var weak_part := ""
	if Parts71.on(w):
		var L = Parts71.layout_of(def_id)
		if not L.is_empty():
			for p in L.parts:
				if float(p.weak) > 1.05:
					weak_part = String(p.id)
					weak_mult = float(p.weak)
					break
			if weak_part != "" and w != null:
				var uid := w.spawn_unit(def_id, 1, Vector2(30, 30))
				if uid >= 0:
					var e = w.entities[uid]
					e.facing = PI
					Parts71.adopt(w, e)
					var base := float(ud.get("hp", 500.0)) * 0.15
					var weak_dmg := Parts71.hit(w, {"pos": shooter, "owner": 0, "id": 0}, e, r8, a8, base, base, 1.0)
					weak_mult = maxf(weak_mult, weak_dmg / maxf(base, 1e-6))
					w.destroy(uid, "combat9_probe")
	var st := _st(w)
	var h: Dictionary = st.harness
	h[fam] = {
		"def": def_id,
		"front_side": front_side,
		"rear_side": rear_side,
		"front_dmg": snappedf(front_dmg, Q),
		"rear_dmg": snappedf(rear_dmg, Q),
		"weak_part": weak_part,
		"weak_mult": snappedf(weak_mult, Q),
		"tick": w.tick,
	}
	st.harness = h
	var ok := rear_side == "rear" and rear_dmg >= front_dmg
	if weak_part != "":
		ok = ok and weak_mult > 1.05
	return {
		"ok": ok,
		"family": fam,
		"def": def_id,
		"front_side": front_side,
		"rear_side": rear_side,
		"front_dmg": front_dmg,
		"rear_dmg": rear_dmg,
		"weak_mult": weak_mult,
		"weak_part": weak_part,
	}


static func harness_ok(w: SimWorld, family: String) -> bool:
	var rec: Dictionary = (_st(w).harness as Dictionary).get(family, {})
	return not rec.is_empty() and float(rec.get("rear_dmg", 0.0)) >= float(rec.get("front_dmg", 0.0))