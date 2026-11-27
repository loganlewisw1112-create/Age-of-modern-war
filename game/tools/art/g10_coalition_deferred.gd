extends RefCounted
## Candidate art for the owner-deferred G10 roster. Uses the approved palette and four-facing rig.

const C = preload("res://tools/art/g7_cn_lib.gd")
const P = preload("res://tools/art/pix.gd")
const S = preload("res://tools/art/g10_coalition_samples.gd")
const DARK := Color8(32, 35, 37)
const STEEL := Color8(63, 70, 71)
const RUBBER := Color8(22, 24, 25)
const TAN := Color8(111, 103, 79)
const GLASS := Color8(41, 63, 69)
const EDGE := Color8(105, 116, 119)
const AMBER := Color8(201, 158, 80)
const TEAL := Color8(78, 149, 139)
const STRIPE := Color8(154, 152, 140)
const FRAMES := ["idle", "move", "fire", "unload"]
const VEHICLES := {
	"x_technical_mg": ["technical", "ring gun", TAN],
	"x_technical_rocket": ["technical", "rocket rack", TAN],
	"x_technical_aa": ["technical", "air search", STEEL],
	"x_technical_mortar": ["technical", "short mortar", TAN],
	"x_technical_recoilless": ["technical", "long tube", STEEL],
	"x_captured_tank": ["tracked", "turret", TAN],
	"x_refit_ifv": ["tracked", "sensor turret", STEEL],
	"x_shock_truck": ["heavy", "emitter", STEEL],
	"x_stealth_apc": ["heavy", "troop ramp", DARK],
	"x_ghost_runner": ["scout", "sensor", DARK],
	"x_exo_mule": ["scout", "cargo", TAN],
	"x_recovery_truck": ["heavy", "boom", TAN],
	"x_ghost_drone_carrier": ["heavy", "drone trays", DARK],
	"x_river_ghost": ["boat", "low gun", DARK],
	"x_mini_sub": ["sub", "periscope", DARK],
	"x_smuggler_boat": ["boat", "covered hold", TAN],
	"x_patrol_boat": ["boat", "patrol turret", STEEL],
}


static func build_vehicles(out: Dictionary) -> void:
	for id in VEHICLES:
		var style: Array = VEHICLES[id]
		S._sheet_anim(out, id, "vehicles", func(cv, side, frame): _vehicle(cv, side, frame, style), FRAMES)
		var spec: Dictionary = out.manifest.vehicles[id]
		spec.g10 = {"owner_look_approved": true, "family": style[0], "profile": style[1]}


static func _vehicle(cv, side: int, frame: String, style: Array) -> void:
	var family: String = style[0]
	var role: String = style[1]
	var paint: Color = style[2]
	var pivot := Vector2(S.PIVOT)
	var yaw := side * PI / 2.0
	var r := {"a": yaw, "o": pivot, "sc": 5.0}
	var near := 1.0 if C.depth(yaw, 0, 1) > 0.0 else -1.0
	var length := 0.79 if family == "heavy" or family == "tracked" else 0.60
	var width := 0.39 if family == "heavy" or family == "tracked" else 0.31
	if family in ["boat", "sub"]:
		_boat(cv, r, role, frame, paint, family == "sub")
		return
	C.ground_shadow(cv, pivot + Vector2(0, 2), 27.0, 9.0)
	var bogie_y := near * width * 0.95
	if family == "tracked":
		_box(cv, r, 0.0, bogie_y, 1.6, length, 0.12, 7.2, RUBBER, Vector2(0.10, 0.02))
		for n in 5:
			var tire := _point(r, (float(n) - 2.0) * 0.27, bogie_y * 1.10, 4)
			C.blob(cv, tire, 2.0, C.ramp(STEEL if (n + int(frame == "move")) % 2 else DARK))
		_box(cv, r, 0.0, 0.0, 7, length * 0.95, width, 7.8, paint, Vector2(0.18, 0.07))
		_module(cv, r, role, frame)
	else:
		var axles: Array = [-length * 0.72, length * 0.72]
		if family == "heavy":
			axles.insert(1, -length * 0.23)
		for axle in axles:
			var tire := _point(r, float(axle), bogie_y, 5.0)
			C.blob(cv, tire, 5.4, C.ramp(RUBBER))
			C.blob(cv, tire, 2.7, C.ramp(STEEL))
			cv.px(int(tire.x) + int(frame == "move"), int(tire.y), EDGE)
		_box(cv, r, 0.0, 0.0, 6, length, width, 5.0, paint, Vector2(0.04, 0.03))
		_box(cv, r, length * 0.65, 0.0, 11.0, length * 0.31, width * 0.94, 3.0, paint, Vector2(0.06, 0.04))
		var cab_h := 7.6 if family == "heavy" else 5.5
		_box(cv, r, length * 0.12, 0.0, 11.2, length * 0.34, width * 0.92, cab_h, paint, Vector2(0.08, 0.07))
		C.tube(cv, _point(r, length * 0.40, -width * 0.62, 13.7 + cab_h * 0.34),
			_point(r, length * 0.40, width * 0.62, 13.7 + cab_h * 0.34), 1.2, C.ramp(GLASS))
		var bed: float = -length * 0.64
		_box(cv, r, bed, near * width * 0.86, 10.5, length * 0.31, 0.055, 2.5, DARK)
		_box(cv, r, bed, -near * width * 0.86, 10.5, length * 0.31, 0.055, 2.5, DARK)
		_module(cv, r, role, frame, bed)
		var lamp := _point(r, length + 0.015, near * width * 0.79, 9.8)
		C.blob(cv, lamp, 1.15, C.ramp(AMBER))
	var stripe := _point(r, 0.08, near * width, 10.0)
	C.tube(cv, stripe, stripe + Vector2(2, 1), 0.9, C.ramp(STRIPE), true)


static func _module(cv, r: Dictionary, role: String, frame: String, bed := 0.0) -> void:
	var f := bed
	var muzzle := Vector2.ZERO
	match role:
		"ring gun", "low gun", "patrol turret", "turret", "sensor turret":
			var turret := role in ["turret", "sensor turret", "patrol turret"]
			var height := 15.0 if turret else 12.2
			_box(cv, r, f, 0.0, height, 0.23 if turret else 0.11, 0.17 if turret else 0.10, 4.2, STEEL, Vector2(0.06, 0.04))
			muzzle = _point(r, f + (0.93 if role == "turret" else 0.52), 0, height + 2.6)
			C.tube(cv, _point(r, f + 0.08, 0, height + 2.6), muzzle, 1.9 if role == "turret" else 1.15, C.ramp(DARK))
			if role == "sensor turret":
				C.blob(cv, _point(r, f, 0.13, height + 5.6), 1.45, C.ramp(TEAL))
		"rocket rack", "air search", "short mortar", "long tube":
			_box(cv, r, f, 0.0, 12, 0.20, 0.16, 3.2, DARK)
			var tip := 21.5 if role in ["air search", "short mortar"] else 19.5
			var reach := 0.13 if role == "short mortar" else (0.66 if role == "long tube" else 0.46)
			var radius := 2.0 if role in ["rocket rack", "long tube"] else 1.55
			for lateral in ([-0.085, 0.085] if role in ["rocket rack", "air search"] else [0.0]):
				muzzle = _point(r, f + reach, lateral, tip)
				C.tube(cv, _point(r, f - 0.19, lateral, 15.6), muzzle, radius, C.ramp(STEEL))
				C.blob(cv, muzzle, radius * 0.72, C.ramp(RUBBER))
			if role == "air search":
				C.tube(cv, _point(r, f, -0.18, 23), _point(r, f, 0.18, 23), 1.05, C.ramp(TEAL))
		"troop ramp":
			_box(cv, r, f, 0, 11.3, 0.32, 0.30, 6, DARK, Vector2(0.07, 0.07))
			var lowered := frame == "unload"
			C.tube(cv, _point(r, f - 0.30, -0.22, 10.5), _point(r, f - 0.30, 0.22, 10.5), 2.2, C.ramp(EDGE))
			if lowered:
				C.face(cv, PackedVector2Array([_point(r, f - 0.30, -0.22, 10.5), _point(r, f - 0.30, 0.22, 10.5),
					_point(r, f - 0.62, 0.22, 2), _point(r, f - 0.62, -0.22, 2)]), C.ramp(STEEL), 2)
		"boom", "periscope", "sensor", "emitter":
			_box(cv, r, f, 0.0, 11.2, 0.16, 0.19, 3.5, STEEL)
			muzzle = _point(r, f - (0.56 if role == "boom" else 0.08), 0, 25.5 if role == "boom" else 20.5)
			C.tube(cv, _point(r, f, 0, 13), muzzle, 1.6, C.ramp(TEAL if role == "emitter" else STEEL))
			C.blob(cv, muzzle, 1.3, C.ramp(AMBER if role == "boom" else TEAL))
		_:
			for lateral in [-0.12, 0.12]:
				_box(cv, r, f, lateral, 11.5, 0.22, 0.095, 3.1, TAN if role == "cargo" else STEEL)
				C.blob(cv, _point(r, f, lateral, 15), 1.0, C.ramp(TEAL))
	if frame == "fire" and muzzle != Vector2.ZERO:
		C.blob(cv, muzzle, 2.2, C.ramp(AMBER))


static func _boat(cv, r: Dictionary, role: String, frame: String, paint: Color, submerged: bool) -> void:
	if frame == "move":
		for lateral in [-0.22, 0.22]:
			C.tube(cv, _point(r, -0.76, lateral, 0.2), _point(r, -1.13, lateral * 1.4, 0.2), 0.8, C.ramp(TEAL))
	var beam := 0.20 if submerged else 0.31
	var deck := 4.3 if submerged else 8.1
	_box(cv, r, -0.09, 0, 1.0, 0.63, beam, deck, paint, Vector2(0.06, 0.09))
	C.face(cv, PackedVector2Array([_point(r, 0.45, -beam, deck), _point(r, 0.84, 0, deck + 0.9),
		_point(r, 0.45, beam, deck)]), C.ramp(paint), 3)
	_box(cv, r, 0.13, 0, deck, 0.18, beam * 0.72, 4.0 if submerged else 6.0, GLASS, Vector2(0.07, 0.03))
	if submerged:
		C.tube(cv, _point(r, -0.09, 0.0, deck), _point(r, -0.09, 0.0, deck + 9.0), 1.1, C.ramp(STEEL))
		C.blob(cv, _point(r, -0.09, 0.0, deck + 9.0), 1.2, C.ramp(TEAL))
	else:
		_module(cv, r, role, frame, -0.43)
	C.tube(cv, _point(r, -0.50, 0, deck + 0.76), _point(r, -0.32, 0, deck + 0.76), 0.9, C.ramp(STRIPE), true)


static func _point(r: Dictionary, f: float, side: float, h: float) -> Vector2:
	return C.fpt(r, 9.05 * f, 9.05 * side, 0) + Vector2(0, -h)


static func _box(cv, r: Dictionary, f: float, side: float, h: float, hx: float, hy: float, hz: float,
		paint: Color, slope := Vector2.ZERO) -> void:
	var yaw: float = r.a
	var p := Vector2(f, side).rotated(yaw)
	C.box(cv, r.o, Vector3(p.x, p.y, h), hx, hy, hz, yaw, C.ramp(paint), 3, true, false, slope)



const BUILDINGS := {
	"x_safehouse": ["row house", TAN, AMBER],
	"x_tunnel_entrance": ["vent vault", TAN, TEAL],
	"x_cache": ["storage yard", TAN, AMBER],
	"x_weld_shop": ["work bay", STEEL, AMBER],
	"x_black_market": ["awning market", TAN, TEAL],
	"x_broker_exchange": ["exchange", TAN, TEAL],
	"x_patron_office": ["office", STEEL, AMBER],
	"x_disguised_workshop": ["work bay", TAN, TEAL],
	"x_bunker_hatch": ["outcrop", STEEL, AMBER],
	"x_underground_barracks": ["barracks hatch", STEEL, TEAL],
	"x_underground_factory": ["freight hatch", DARK, AMBER],
	"x_ghost_complex": ["campus hatch", DARK, TEAL],
	"x_forward_repair": ["repair yard", STEEL, AMBER],
	"x_vault_core": ["vault hatch", DARK, TEAL],
}


static func build_buildings(out: Dictionary) -> void:
	var rules: Dictionary = Content.rules().get("g10_buildings", {})
	for id in BUILDINGS:
		var footprint := float(Content.building(id).get("size", 2))
		var spec := {"size": footprint, "states": {}, "g5": {"variants": "rot"}, "g10": {"owner_look_approved": true}}
		var hatch: bool = id in rules.get("hatch_surface_defs", [])
		var fw := ceili(64 * footprint) + 24
		var fh := ceili(32 * footprint) + 44
		var pivot := Vector2(fw * 0.5, fh - 16.0 - 16.0 * footprint)
		spec.pivot = [pivot.x, pivot.y]
		var style: Array = BUILDINGS[id]
		for face in 4:
			for state in ["", "_hidden", "_damaged", "_build_0", "_build_1", "_build_2"]:
				var name := "rot_%d%s" % [face, state]
				var cv = P.Canvas.new(fw, fh)
				_building(cv, pivot, face, footprint, style, hatch, state)
				C.selout(cv)
				var stem := "buildings/%s/%s" % [id, name]
				out.images[stem + ".png"] = cv.img
				out.images[stem + "_mask.png"] = cv.mask
				spec.states[name] = {"file": stem + ".png", "mask": stem + "_mask.png"}
				if face == 0:
					if state.is_empty():
						spec.states.built = spec.states[name]
						C.icon(out, id, cv.img, fw, fh, 0)
					elif state.begins_with("_build_"):
						spec.states[state.trim_prefix("_")] = spec.states[name]
		out.manifest.buildings[id] = spec


static func _building(cv, pivot: Vector2, face: int, footprint: float, style: Array, hatch: bool, state: String) -> void:
	var r := {"a": face * PI * 0.5, "o": pivot, "sc": 5.0}
	var span := (footprint - 0.18) * 0.5
	var paint: Color = style[1]
	var accent: Color = style[2]
	var profile: String = style[0]
	var hidden := state == "_hidden"
	var damaged := state == "_damaged"
	_box(cv, r, 0, 0, 0, span, span, 3.0, TAN.darkened(0.35), Vector2(0.08, 0.08))
	if state == "_build_0":
		return
	if state == "_build_1" or state == "_build_2":
		var ht := 6.0 if state == "_build_1" else 15.0
		for sign_step in [-1.0, 1.0]:
			_box(cv, r, 0, sign_step * span * 0.65, 3, span * 0.72, 0.10, ht, TAN)
		return
	if hatch:
		_hatch(cv, r, span, profile, paint, accent, hidden, damaged)
	else:
		_facility(cv, r, span, profile, paint, accent, hidden, damaged)


static func _hatch(cv, r: Dictionary, span: float, profile: String, paint: Color, accent: Color, hidden: bool, damaged: bool) -> void:
	var collar := span * (0.78 if profile == "freight hatch" else 0.56)
	_box(cv, r, 0, 0, 3, span * 0.83, span * 0.76, 2, TAN, Vector2(0.18, 0.18))
	if hidden:
		for side in [-0.55, 0.3, 0.65]:
			_box(cv, r, side * span, -side * span * 0.6, 4, 0.17, 0.16, 4.0, TAN.lightened(0.08), Vector2(0.07, 0.05))
		_box(cv, r, -span * 0.44, span * 0.64, 4, 0.12, 0.09, 6, STEEL, Vector2(0.03, 0.03))
		return
	_box(cv, r, 0, 0, 4, collar, span * 0.40, 4.0, paint, Vector2(0.08, 0.07))
	if damaged:
		_box(cv, r, 0.02, 0.02, 8, collar * 0.64, span * 0.26, 0.2, RUBBER)
		_box(cv, r, -collar * 0.42, -span * 0.08, 8, collar * 0.41, span * 0.16, 3, STEEL, Vector2(0.08, 0.06))
	else:
		_box(cv, r, 0, 0, 8, collar * 0.83, span * 0.30, 1, DARK)
		C.tube(cv, _point(r, 0, -span * 0.29, 9), _point(r, 0, span * 0.29, 9), 0.9, C.ramp(EDGE))
		for side in [-0.86, 0.86]:
			C.blob(cv, _point(r, collar * side, span * 0.33, 8.8), 1.7, C.ramp(accent))
	if profile in ["campus hatch", "vault hatch", "barracks hatch"]:
		_box(cv, r, -span * 0.65, -span * 0.53, 4, span * 0.12, span * 0.17, 8, paint)


static func _facility(cv, r: Dictionary, span: float, profile: String, paint: Color, accent: Color, hidden: bool, damaged: bool) -> void:
	var high := profile in ["row house", "office", "exchange"]
	var height := 32.0 if high else 19.0
	var hx := span * 0.62
	var hy := span * (0.53 if high else 0.65)
	if profile in ["storage yard", "repair yard"]:
		height *= 0.72
	_box(cv, r, -span * 0.19, 0, 3, hx, hy, height, paint, Vector2(0.04, 0.04))
	_box(cv, r, -span * 0.19, 0, 3 + height, hx * 1.06, hy * 1.06, 3.2, DARK, Vector2(0.08, 0.08))
	if high:
		_box(cv, r, -span * 0.21, 0, 6.2 + height, hx * 0.96, hy * 0.83, 8, paint, Vector2(0.13, hy * 0.78))
	for side in [-1.0, 1.0]:
		var near := C.depth(float(r.a), 0, side) > 0.0
		if near:
			for x in [-0.61, -0.25, 0.11]:
				C.tube(cv, _point(r, x * span, side * hy, height * 0.67),
					_point(r, (x + 0.16) * span, side * hy, height * 0.67), 2.0, C.ramp(GLASS))
	var entry := span * 0.43
	var canopy := profile in ["awning market", "work bay", "repair yard"]
	_box(cv, r, entry, 0, 3, span * 0.18, hy * 0.41, 12 if canopy else 8, DARK, Vector2(0.04, 0.05))
	if canopy:
		_box(cv, r, entry + span * 0.14, 0, 15, span * 0.24, hy * 0.65, 2.4, paint, Vector2(0.04, 0.04))
	if hidden:
		_box(cv, r, entry, hy * 1.18, 3, span * 0.12, span * 0.10, 5, TAN)
	else:
		C.tube(cv, _point(r, entry + span * 0.2, -hy * 0.39, 12), _point(r, entry + span * 0.2, hy * 0.39, 12),
			1.4, C.ramp(accent), true)
		_box(cv, r, -span * 0.45, hy * 0.55, height + 6.0, span * 0.10, span * 0.09, 4.0, STEEL)
		C.blob(cv, _point(r, -span * 0.45, hy * 0.55, height + 15), 1.6, C.ramp(accent))
	if damaged:
		C.face(cv, PackedVector2Array([_point(r, -span * 0.6, -hy * 0.5, height + 9),
			_point(r, 0, -hy * 0.62, height + 9), _point(r, -span * 0.31, 0, height + 10)]), C.ramp(RUBBER), 1)


static func write_contact(out: Dictionary, look_path: String) -> void:
	var path := ProjectSettings.globalize_path(look_path)
	DirAccess.make_dir_recursive_absolute(path)
	var rows := VEHICLES.keys()
	var sheet := Image.create(125 + 4 * S.FW, rows.size() * (S.FH + 4) + 22, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(49, 54, 46))
	S._label(sheet, "VEHICLE CANDIDATES", 5, 5)
	for i in rows.size():
		var id: String = rows[i]
		var spec: Dictionary = out.manifest.vehicles[id]
		var img: Image = out.images[spec.file]
		var y := 20 + i * (S.FH + 4)
		S._label(sheet, id.trim_prefix("x_").replace("_", " ").to_upper(), 4, y + 27)
		for side in 4:
			sheet.blend_rect(img, Rect2i(0, side * S.FH, S.FW, S.FH), Vector2i(125 + side * S.FW, y))
	sheet.save_png(path.path_join("g101_deferred_vehicles.png"))
	var structures := Image.create(480, 14 * 122 + 20, false, Image.FORMAT_RGBA8)
	structures.fill(Color8(49, 54, 46))
	S._label(structures, "STRUCTURE CANDIDATES  /  COVER  /  REVEALED  /  DAMAGED", 5, 5)
	rows = BUILDINGS.keys()
	for i in rows.size():
		var id: String = rows[i]
		var spec: Dictionary = out.manifest.buildings[id]
		var y := 20 + i * 122
		S._label(structures, id.trim_prefix("x_").replace("_", " ").to_upper(), 5, y + 8)
		for col in 3:
			var state: String = ["rot_0_hidden", "rot_0", "rot_0_damaged"][col]
			var img: Image = (out.images[spec.states[state].file] as Image).duplicate()
			var bounds := img.get_used_rect()
			img = img.get_region(bounds)
			var scale_factor := minf(136.0 / img.get_width(), 104.0 / img.get_height())
			img.resize(maxi(1, roundi(img.get_width() * scale_factor)), maxi(1, roundi(img.get_height() * scale_factor)), Image.INTERPOLATE_NEAREST)
			structures.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(12 + col * 155, y + 16))
	structures.save_png(path.path_join("g101_deferred_structures.png"))
