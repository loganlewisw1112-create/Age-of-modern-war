extends RefCounted
## G10 Coalition air fleet — unique silhouettes per id (post-g10.lock art amendment).
## Black / gunmetal only. No purple. Rotors only where the craft identity requires them.
## Frames: idle / flight / fire / hit. Drawn through g7_cn_lib DL7 faces at distinct scales.
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")

const FW := 80
const FH := 64
const PIVOT := Vector2i(40, 54)
const FACINGS := 4
const FRAMES_AIR := ["idle", "flight", "fire", "hit"]

const BLK := Color8(32, 34, 36)
const BLK_D := Color8(18, 18, 20)
const BLK_L := Color8(52, 54, 58)
const VOID := Color8(52, 56, 66)
const VOID_D := Color8(30, 32, 40)
const VOID_L := Color8(88, 94, 108)
const STEEL := Color8(58, 60, 64)
const STEEL_L := Color8(96, 100, 108)
const GLASS := Color8(48, 58, 64)
const GOLD := Color8(232, 186, 72)
const MUZZLE := Color8(255, 186, 72)
const HIT_R := Color8(200, 72, 48)
const TEAM := Color8(150, 150, 150)

## Distinct presence: transport biggest → CAS → silent rotor → shock → stealth drone → recon smallest.
const Z_CAS := 6.20
const Z_SILENT := 5.55
const Z_TRANSPORT := 7.35
const Z_STEALTH_D := 3.05
const Z_SHOCK_D := 3.70
const Z_RECON_D := 2.45

const AIR_IDS := [
	"x_patron_cas", "x_silent_rotor", "x_stealth_transport",
	"x_stealth_drone", "x_shock_drone", "x_recon_drone",
]

## One-line identity for reports / owner boards.
const IDENTITY := {
	"x_patron_cas": "Fixed-wing swept-delta attack CAS — no rotors, chin EO + wing guns",
	"x_silent_rotor": "Slender quiet-insert helo — main rotor disc + fenestron, stub gun pods",
	"x_stealth_transport": "Faceted stealth tilt-rotor insert craft — box cargo fuse, twin tip nacelles, H-tail, rear ramp",
	"x_stealth_drone": "Flat diamond flying-wing UCAV — serrated edges, no rotors",
	"x_shock_drone": "Compact X-frame multi-rotor striker — chin gun blister + rotor arms",
	"x_recon_drone": "Tiny high-wing spyglass — slender boom EO pod, no rotors",
}


static func draw(cv, id: String, k: int, frame: String = "idle") -> void:
	match id:
		"x_patron_cas":
			_draw_patron_cas(cv, k, frame)
		"x_silent_rotor":
			_draw_silent_rotor(cv, k, frame)
		"x_stealth_transport":
			_draw_stealth_transport(cv, k, frame)
		"x_stealth_drone":
			_draw_stealth_drone(cv, k, frame)
		"x_shock_drone":
			_draw_shock_drone(cv, k, frame)
		"x_recon_drone":
			_draw_recon_drone(cv, k, frame)
		_:
			_draw_patron_cas(cv, k, frame)


static func _R(k: int, sc: float, bank: float = 0.0, bob: float = 0.0) -> Dictionary:
	return {"a": k * PI / 2.0 + bank, "o": Vector2(PIVOT) + Vector2(0, bob), "tilt": 0.0, "bob": 0.0, "sc": sc}


static func _sort(parts: Array) -> void:
	parts.sort_custom(func(a, b): return float(a.d) < float(b.d))


static func _team(cv, c: Vector2, r: float) -> void:
	cv.team = true
	C.blob(cv, c, r, C.ramp(TEAM), true)
	cv.team = false


static func _pose_bank(frame: String) -> float:
	match frame:
		"flight":
			return 0.12
		"fire":
			return -0.06
		"hit":
			return 0.22
		_:
			return 0.0


static func _pose_bob(frame: String) -> float:
	match frame:
		"flight":
			return -1.0
		"hit":
			return 2.0
		_:
			return 0.0


static func _muzzle(cv, pt: Vector2, on: bool) -> void:
	if not on:
		return
	C.blob(cv, pt, 2.2, C.ramp(MUZZLE))
	C.blob(cv, pt + Vector2(2, -1), 1.2, C.ramp(Color8(255, 240, 180)))


static func _hit_scar(cv, R: Dictionary, Z: float, on: bool) -> void:
	if not on:
		return
	C.blob(cv, C.fpt(R, 0.4, 1.2, 4.2), 0.55 * Z, C.ramp(HIT_R))
	C.tube(cv, C.fpt(R, -0.2, 0.6, 4.0), C.fpt(R, 1.4, 1.8, 3.6), 0.12 * Z, C.ramp(STEEL_L))


## ---------------------------------------------------------------------------
## CLOSE AIR — fixed-wing attack CAS (owner-solid role; refined for uniqueness).
## ---------------------------------------------------------------------------
static func _draw_patron_cas(cv, k: int, frame: String) -> void:
	var Z := Z_CAS
	var R := _R(k, Z, _pose_bank(frame), _pose_bob(frame))
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 1), 34.0, 10.0)
	var fire := frame == "fire"
	var hit := frame == "hit"
	var parts: Array = []
	for s in [-1.0, 1.0]:
		parts.append({"d": C.fdep(R, -1.2, s * 5.2), "k": "wing", "s": s})
		parts.append({"d": C.fdep(R, 1.2, s * 2.1) + 0.03, "k": "winggun", "s": s})
		parts.append({"d": C.fdep(R, -0.4, s * 3.6) + 0.025, "k": "bay", "s": s})
		parts.append({"d": C.fdep(R, 0.5, s * 1.35) + 0.015, "k": "intake", "s": s})
	parts.append({"d": C.fdep(R, 0.0, 0.0), "k": "fuse"})
	parts.append({"d": C.fdep(R, 5.5, 0.0) + 0.03, "k": "nose"})
	parts.append({"d": C.fdep(R, 5.5, 0.0) + 0.06, "k": "sensor"})
	parts.append({"d": C.fdep(R, 1.4, 0.0) + 0.04, "k": "canopy"})
	parts.append({"d": C.fdep(R, -5.2, 0.0) + 0.01, "k": "tail"})
	_sort(parts)
	for q in parts:
		match String(q.k):
			"wing":
				var s: float = q.s
				C.face(cv, PackedVector2Array([
					C.fpt(R, 3.85, s * 0.4, 4.5), C.fpt(R, -1.4, s * 0.55, 4.2),
					C.fpt(R, -5.6, s * 7.15, 2.55), C.fpt(R, -2.9, s * 6.85, 2.75),
				]), C.ramp(STEEL_L if s < 0.0 else VOID_L), 2, s < 0.0)
				C.face(cv, PackedVector2Array([
					C.fpt(R, 3.85, s * 0.4, 4.5), C.fpt(R, -2.9, s * 6.85, 2.75),
					C.fpt(R, -3.05, s * 6.7, 2.35), C.fpt(R, 3.65, s * 0.4, 4.1),
				]), C.ramp(BLK_L), 1, false)
				C.face(cv, PackedVector2Array([
					C.fpt(R, -2.9, s * 6.85, 2.75), C.fpt(R, -5.6, s * 7.15, 2.55),
					C.fpt(R, -5.2, s * 6.75, 2.25),
				]), C.ramp(BLK), 1, false)
			"winggun":
				var sg: float = q.s
				C.tube(cv, C.fpt(R, 1.1, sg * 1.75, 3.85), C.fpt(R, 4.55, sg * 1.9, 3.55), 0.3 * Z, C.ramp(VOID_D))
				C.tube(cv, C.fpt(R, 2.8, sg * 1.85, 3.7), C.fpt(R, 5.15, sg * 1.95, 3.45), 0.16 * Z, C.ramp(STEEL))
				_muzzle(cv, C.fpt(R, 5.25, sg * 1.95, 3.45), fire)
			"bay":
				var sb: float = q.s
				var drop := 0.55 if fire else 0.0
				C.face(cv, PackedVector2Array([
					C.fpt(R, 0.9, sb * 2.65, 3.75), C.fpt(R, -2.1, sb * 2.8, 3.45),
					C.fpt(R, -1.85, sb * 3.65, 2.85 - drop), C.fpt(R, 1.15, sb * 3.45, 3.15 - drop),
				]), C.ramp(BLK_L), 2, false)
				C.tube(cv, C.fpt(R, 0.85, sb * 3.05, 3.35 - drop * 0.5), C.fpt(R, -2.55, sb * 3.2, 3.05 - drop), 0.34 * Z, C.ramp(STEEL))
			"intake":
				var s3: float = q.s
				C.face(cv, PackedVector2Array([
					C.fpt(R, 1.65, s3 * 0.85, 4.15), C.fpt(R, -0.45, s3 * 1.2, 4.05),
					C.fpt(R, -0.65, s3 * 1.65, 4.95), C.fpt(R, 1.45, s3 * 1.4, 5.15),
				]), C.ramp(BLK), 2, false)
			"fuse":
				C.tube(cv, C.fpt(R, -5.5, 0.0, 4.05), C.fpt(R, 4.7, 0.0, 4.55), 0.95 * Z, C.ramp(BLK))
				C.tube(cv, C.fpt(R, -4.7, 0.0, 4.55), C.fpt(R, 3.5, 0.0, 5.05), 0.62 * Z, C.ramp(STEEL))
				_team(cv, C.fpt(R, -1.2, -0.85, 4.75), 0.28 * Z)
			"nose":
				C.tube(cv, C.fpt(R, 4.35, 0.0, 4.4), C.fpt(R, 6.7, 0.0, 3.95), 0.52 * Z, C.ramp(BLK_D))
			"sensor":
				C.blob(cv, C.fpt(R, 5.6, 0.0, 3.05), 0.48 * Z, C.ramp(VOID_D))
				C.blob(cv, C.fpt(R, 5.6, 0.0, 2.9), 0.28 * Z, C.ramp(GLASS))
			"canopy":
				C.blob(cv, C.fpt(R, 1.75, 0.0, 5.75), 0.55 * Z, C.ramp(GLASS))
			"tail":
				C.face(cv, PackedVector2Array([
					C.fpt(R, -4.5, -0.15, 4.35), C.fpt(R, -6.05, -0.15, 4.1),
					C.fpt(R, -6.55, -0.15, 7.25), C.fpt(R, -5.25, -0.15, 7.45),
				]), C.ramp(STEEL), 2, true)
				for s4 in [-1.0, 1.0]:
					C.face(cv, PackedVector2Array([
						C.fpt(R, -4.9, 0.0, 4.55), C.fpt(R, -6.15, 0.0, 4.3),
						C.fpt(R, -5.95, s4 * 3.15, 3.95), C.fpt(R, -5.05, s4 * 2.55, 4.2),
					]), C.ramp(VOID_L if s4 < 0.0 else BLK_L), 2, s4 < 0.0)
	_hit_scar(cv, R, Z, hit)


## ---------------------------------------------------------------------------
## Silent Rotor — quiet-insert helicopter (main rotor + fenestron). NOT a jet.
## ---------------------------------------------------------------------------
static func _draw_silent_rotor(cv, k: int, frame: String) -> void:
	var Z := Z_SILENT
	var R := _R(k, Z, _pose_bank(frame) * 0.7, _pose_bob(frame) * 0.6)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 28.0, 9.0)
	var fire := frame == "fire"
	var hit := frame == "hit"
	var spin := 0.0 if frame == "idle" else (0.55 if frame == "flight" else 0.25)
	## Rotor disc (blurred) — signature read.
	var disc_cols := [VOID_L, STEEL, BLK_L, STEEL_L]
	for i in 8:
		var ang := float(i) * PI / 4.0 + spin
		var tip := C.fpt(R, cos(ang) * 5.8, sin(ang) * 5.8, 7.4)
		C.tube(cv, C.fpt(R, 0.0, 0.0, 7.1), tip, 0.14 * Z, C.ramp(disc_cols[i % disc_cols.size()]))
	C.blob(cv, C.fpt(R, 0.0, 0.0, 7.15), 0.55 * Z, C.ramp(BLK_D))
	## Slender helo fuse + boom (not fat CAS body).
	C.tube(cv, C.fpt(R, -2.8, 0.0, 4.2), C.fpt(R, 3.6, 0.0, 4.6), 0.72 * Z, C.ramp(BLK))
	C.tube(cv, C.fpt(R, -2.2, 0.0, 4.7), C.fpt(R, 2.4, 0.0, 5.1), 0.42 * Z, C.ramp(STEEL))
	## Nose glass bubble (helo, not jet canopy).
	C.blob(cv, C.fpt(R, 3.9, 0.0, 4.9), 0.85 * Z, C.ramp(BLK_L))
	C.blob(cv, C.fpt(R, 4.15, 0.0, 5.05), 0.55 * Z, C.ramp(GLASS))
	## Tail boom + fenestron (ducted, quiet).
	C.tube(cv, C.fpt(R, -2.6, 0.0, 4.4), C.fpt(R, -7.2, 0.0, 4.8), 0.28 * Z, C.ramp(VOID))
	C.blob(cv, C.fpt(R, -7.4, 0.0, 5.1), 0.95 * Z, C.ramp(BLK_D))
	C.blob(cv, C.fpt(R, -7.4, 0.0, 5.1), 0.55 * Z, C.ramp(VOID_L))
	for i in 4:
		var fa := float(i) * PI / 2.0 + spin * 2.0
		C.tube(cv, C.fpt(R, -7.4, 0.0, 5.1), C.fpt(R, -7.4 + cos(fa) * 0.9, sin(fa) * 0.9, 5.1), 0.08 * Z, C.ramp(STEEL_L))
	## Vertical fin above fenestron.
	C.face(cv, PackedVector2Array([
		C.fpt(R, -6.4, 0.0, 4.9), C.fpt(R, -7.6, 0.0, 5.0),
		C.fpt(R, -7.5, 0.0, 7.0), C.fpt(R, -6.6, 0.0, 6.9),
	]), C.ramp(STEEL), 2, true)
	## Stub wings + gun pods (quiet→gunship).
	for s in [-1.0, 1.0]:
		C.face(cv, PackedVector2Array([
			C.fpt(R, 0.8, s * 0.3, 4.3), C.fpt(R, -1.2, s * 0.35, 4.2),
			C.fpt(R, -0.9, s * 3.4, 3.6), C.fpt(R, 0.5, s * 3.1, 3.7),
		]), C.ramp(VOID_L if s < 0.0 else BLK_L), 2, s < 0.0)
		C.tube(cv, C.fpt(R, -0.2, s * 2.6, 3.5), C.fpt(R, 1.6, s * 2.7, 3.3), 0.32 * Z, C.ramp(BLK_D))
		_muzzle(cv, C.fpt(R, 1.75, s * 2.7, 3.3), fire)
	## Skids (helo — never CAS gear).
	for s in [-1.0, 1.0]:
		C.tube(cv, C.fpt(R, -1.6, s * 1.1, 3.2), C.fpt(R, 2.2, s * 1.15, 3.1), 0.12 * Z, C.ramp(STEEL))
		C.tube(cv, C.fpt(R, -0.4, s * 0.6, 4.0), C.fpt(R, -0.4, s * 1.1, 3.25), 0.1 * Z, C.ramp(STEEL_L))
		C.tube(cv, C.fpt(R, 1.4, s * 0.6, 4.1), C.fpt(R, 1.4, s * 1.1, 3.2), 0.1 * Z, C.ramp(STEEL_L))
	_team(cv, C.fpt(R, 0.2, -0.7, 5.0), 0.22 * Z)
	_hit_scar(cv, R, Z, hit)


## ---------------------------------------------------------------------------
## Stealth Transport — LARGE faceted tilt-rotor INSERT craft (NOT a flying-wing blob).
## Reads as: long cargo tube + stub high-wing + twin tip nacelles + twin-boom H-tail.
## Distinct vs CAS (delta jet), silent helo (main rotor disc), drones (tiny).
## ---------------------------------------------------------------------------
static func _draw_stealth_transport(cv, k: int, frame: String) -> void:
	var Z := Z_TRANSPORT
	var R := _R(k, Z, _pose_bank(frame) * 0.4, _pose_bob(frame) * 0.3)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 2), 38.0, 12.0)
	var fire := frame == "fire"
	var hit := frame == "hit"
	var open := frame == "unload"
	var tilt := 0.08 if frame == "idle" else (1.05 if frame == "flight" else 0.6)
	## LONG cargo tube fuselage — professional insert craft, not a blended wing mass.
	C.tube(cv, C.fpt(R, -5.8, 0.0, 3.75), C.fpt(R, 5.0, 0.0, 4.15), 0.88 * Z, C.ramp(BLK))
	C.tube(cv, C.fpt(R, -5.2, 0.0, 4.35), C.fpt(R, 4.2, 0.0, 4.85), 0.52 * Z, C.ramp(VOID))
	## Flat cargo roof ridge (breaks "blob" silhouette).
	C.tube(cv, C.fpt(R, -4.6, 0.0, 5.15), C.fpt(R, 3.4, 0.0, 5.45), 0.22 * Z, C.ramp(STEEL))
	## Faceted lower chines only (narrow — keep fuse readable as a tube).
	for s in [-1.0, 1.0]:
		C.face(cv, PackedVector2Array([
			C.fpt(R, 4.2, s * 0.4, 3.95), C.fpt(R, -5.0, s * 0.5, 3.6),
			C.fpt(R, -4.8, s * 1.35, 3.15), C.fpt(R, 3.9, s * 1.2, 3.4),
		]), C.ramp(VOID_L if s < 0.0 else BLK_L), 2, s < 0.0)
	## Crew cockpit step (blunt, glazed — not CAS needle).
	C.tube(cv, C.fpt(R, 4.4, 0.0, 4.2), C.fpt(R, 6.8, 0.0, 4.0), 0.62 * Z, C.ramp(BLK_D))
	C.blob(cv, C.fpt(R, 6.05, 0.0, 4.85), 0.58 * Z, C.ramp(BLK_L))
	C.blob(cv, C.fpt(R, 6.25, 0.0, 5.0), 0.4 * Z, C.ramp(GLASS))
	## Troop windows along the tube.
	for i in 5:
		var ff := -3.8 + float(i) * 1.5
		C.blob(cv, C.fpt(R, ff, 0.85, 4.55), 0.18 * Z, C.ramp(GLASS))
		C.blob(cv, C.fpt(R, ff, -0.85, 4.55), 0.18 * Z, C.ramp(GLASS))
	## Stub HIGH wing (thin bar — clearly NOT a flying wing).
	for s in [-1.0, 1.0]:
		C.face(cv, PackedVector2Array([
			C.fpt(R, 0.9, s * 0.25, 5.35), C.fpt(R, -1.6, s * 0.3, 5.2),
			C.fpt(R, -1.1, s * 4.85, 4.55), C.fpt(R, 0.45, s * 4.6, 4.7),
		]), C.ramp(STEEL_L if s < 0.0 else VOID_L), 2, s < 0.0)
		C.tube(cv, C.fpt(R, -0.2, s * 0.4, 5.25), C.fpt(R, -0.35, s * 4.5, 4.7), 0.16 * Z, C.ramp(STEEL))
	## Twin tip tilt-nacelles — ONE proprotor pod per wingtip (not a 4-fan cluster).
	for s in [-1.0, 1.0]:
		var nz := 4.75 + sin(tilt) * 0.65
		var nf := -0.4 + cos(tilt) * 0.4
		C.tube(cv, C.fpt(R, -0.35, s * 4.4, 4.7), C.fpt(R, nf, s * 4.85, nz), 0.35 * Z, C.ramp(BLK_D))
		## Single long nacelle cylinder.
		C.tube(cv, C.fpt(R, nf - 0.75, s * 4.9, nz), C.fpt(R, nf + 1.35, s * 4.9, nz + 0.08), 0.58 * Z, C.ramp(BLK))
		C.blob(cv, C.fpt(R, nf + 1.4, s * 4.9, nz + 0.12), 0.42 * Z, C.ramp(VOID_D))
		C.blob(cv, C.fpt(R, nf - 0.8, s * 4.9, nz), 0.4 * Z, C.ramp(STEEL))
		## Thin prop — two blades only (idle) / edge streak (flight). Never a filled radar disc.
		if frame == "idle" or frame == "hit" or open:
			C.tube(cv, C.fpt(R, nf + 1.35, s * 4.9 - 1.5, nz + 0.15), C.fpt(R, nf + 1.35, s * 4.9 + 1.5, nz + 0.15),
				0.1 * Z, C.ramp(STEEL_L))
			C.tube(cv, C.fpt(R, nf + 1.35 - 1.15, s * 4.9, nz + 0.15), C.fpt(R, nf + 1.35 + 1.15, s * 4.9, nz + 0.15),
				0.1 * Z, C.ramp(STEEL))
			C.blob(cv, C.fpt(R, nf + 1.35, s * 4.9, nz + 0.15), 0.22 * Z, C.ramp(BLK_D))
		else:
			C.tube(cv, C.fpt(R, nf + 1.25, s * 4.9, nz - 1.2), C.fpt(R, nf + 1.45, s * 4.9, nz + 1.35),
				0.16 * Z, C.ramp(STEEL_L))
	## Twin boom → tall H-tail sticking well aft of the cargo tube.
	for s in [-1.0, 1.0]:
		C.tube(cv, C.fpt(R, -5.0, s * 0.7, 4.25), C.fpt(R, -8.4, s * 1.85, 4.6), 0.2 * Z, C.ramp(VOID_L))
		C.face(cv, PackedVector2Array([
			C.fpt(R, -7.5, s * 1.7, 4.45), C.fpt(R, -8.7, s * 1.85, 4.4),
			C.fpt(R, -8.55, s * 1.85, 7.55), C.fpt(R, -7.55, s * 1.7, 7.3),
		]), C.ramp(STEEL_L), 2, true)
		## Fin tip highlight so H-tail reads at strip scale.
		C.blob(cv, C.fpt(R, -8.1, s * 1.8, 7.2), 0.22 * Z, C.ramp(STEEL_L))
	C.tube(cv, C.fpt(R, -8.25, -1.85, 6.2), C.fpt(R, -8.25, 1.85, 6.2), 0.2 * Z, C.ramp(STEEL_L))
	## Rear cargo ramp.
	var ramp_z := 2.2 if open else 3.45
	C.face(cv, PackedVector2Array([
		C.fpt(R, -5.4, -1.15, 3.7), C.fpt(R, -5.4, 1.15, 3.7),
		C.fpt(R, -6.95, 1.0, ramp_z), C.fpt(R, -6.95, -1.0, ramp_z),
	]), C.ramp(STEEL if open else BLK_L), 2, false)
	if open:
		C.face(cv, PackedVector2Array([
			C.fpt(R, -5.55, -0.9, 3.95), C.fpt(R, -5.55, 0.9, 3.95),
			C.fpt(R, -6.4, 0.75, 4.65), C.fpt(R, -6.4, -0.75, 4.65),
		]), C.ramp(Color8(118, 96, 64)), 1, false)
	## Tricycle gear (idle) — grounds it as a real insert craft.
	if frame == "idle" or frame == "hit" or open:
		C.tube(cv, C.fpt(R, 4.6, 0.0, 3.5), C.fpt(R, 4.6, 0.0, 2.2), 0.12 * Z, C.ramp(STEEL))
		C.blob(cv, C.fpt(R, 4.6, 0.0, 2.05), 0.28 * Z, C.ramp(BLK_D))
		for s in [-1.0, 1.0]:
			C.tube(cv, C.fpt(R, -2.4, s * 0.9, 3.4), C.fpt(R, -2.4, s * 1.1, 2.15), 0.12 * Z, C.ramp(STEEL))
			C.blob(cv, C.fpt(R, -2.4, s * 1.1, 2.0), 0.3 * Z, C.ramp(BLK_D))
	## Side door guns when fire.
	if fire:
		for s in [-1.0, 1.0]:
			C.tube(cv, C.fpt(R, -0.6, s * 1.55, 3.85), C.fpt(R, 1.8, s * 1.85, 3.45), 0.22 * Z, C.ramp(BLK_D))
			_muzzle(cv, C.fpt(R, 1.95, s * 1.85, 3.45), true)
	_team(cv, C.fpt(R, 0.6, -1.15, 4.75), 0.26 * Z)
	_hit_scar(cv, R, Z * 0.65, hit)


## ---------------------------------------------------------------------------
## Stealth Drone — flat diamond flying-wing UCAV (no rotors).
## ---------------------------------------------------------------------------
static func _draw_stealth_drone(cv, k: int, frame: String) -> void:
	var Z := Z_STEALTH_D
	var R := _R(k, Z, _pose_bank(frame), _pose_bob(frame) * 0.5)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 1), 16.0, 6.0)
	var fire := frame == "fire"
	var hit := frame == "hit"
	## Diamond planform — serrated trailing edge.
	C.face(cv, PackedVector2Array([
		C.fpt(R, 4.8, 0.0, 3.6), C.fpt(R, 0.2, 4.6, 3.2),
		C.fpt(R, -4.2, 2.4, 2.9), C.fpt(R, -3.4, 0.0, 3.0),
		C.fpt(R, -4.2, -2.4, 2.9), C.fpt(R, 0.2, -4.6, 3.2),
	]), C.ramp(BLK), 2, false)
	C.face(cv, PackedVector2Array([
		C.fpt(R, 4.2, 0.0, 3.9), C.fpt(R, 0.0, 3.6, 3.5),
		C.fpt(R, -3.0, 0.0, 3.4), C.fpt(R, 0.0, -3.6, 3.5),
	]), C.ramp(VOID), 1, false)
	## Serrations on TE.
	for s in [-1.0, 1.0]:
		for i in 3:
			var ff := -3.6 + float(i) * 0.7
			C.face(cv, PackedVector2Array([
				C.fpt(R, ff, s * 1.6, 3.0), C.fpt(R, ff - 0.5, s * 2.2, 2.85),
				C.fpt(R, ff + 0.2, s * 2.5, 2.9),
			]), C.ramp(BLK_D), 1, false)
	## Flush dorsal intake + belly bay.
	C.blob(cv, C.fpt(R, 0.6, 0.0, 4.15), 0.45 * Z, C.ramp(BLK_D))
	C.tube(cv, C.fpt(R, 0.8, 0.0, 2.7), C.fpt(R, -1.6, 0.0, 2.6), 0.35 * Z, C.ramp(STEEL if fire else BLK_L))
	if fire:
		C.tube(cv, C.fpt(R, -0.2, 0.0, 2.5), C.fpt(R, -2.8, 0.0, 2.3), 0.22 * Z, C.ramp(STEEL_L))
		_muzzle(cv, C.fpt(R, -2.9, 0.0, 2.3), true)
	## Tiny EO bump (not chin ball of CAS).
	C.blob(cv, C.fpt(R, 3.6, 0.0, 3.1), 0.28 * Z, C.ramp(GLASS))
	_team(cv, C.fpt(R, -0.4, 1.4, 3.5), 0.16 * Z)
	_hit_scar(cv, R, Z, hit)


## ---------------------------------------------------------------------------
## Shock Drone — compact X-frame multi-rotor with chin gun (HAS rotors).
## ---------------------------------------------------------------------------
static func _draw_shock_drone(cv, k: int, frame: String) -> void:
	var Z := Z_SHOCK_D
	var R := _R(k, Z, _pose_bank(frame) * 0.8, _pose_bob(frame) * 0.7)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 1), 14.0, 5.0)
	var fire := frame == "fire"
	var hit := frame == "hit"
	var spin := 0.2 if frame == "idle" else 0.7
	## Central armored pod (boxy — not flying wing).
	C.tube(cv, C.fpt(R, -1.4, 0.0, 3.6), C.fpt(R, 1.8, 0.0, 3.9), 0.95 * Z, C.ramp(BLK))
	C.tube(cv, C.fpt(R, -1.0, 0.0, 4.1), C.fpt(R, 1.2, 0.0, 4.4), 0.55 * Z, C.ramp(STEEL))
	## Chin gun blister.
	C.blob(cv, C.fpt(R, 1.6, 0.0, 2.9), 0.55 * Z, C.ramp(BLK_D))
	C.tube(cv, C.fpt(R, 1.5, 0.0, 2.85), C.fpt(R, 3.4, 0.0, 2.7), 0.22 * Z, C.ramp(STEEL))
	_muzzle(cv, C.fpt(R, 3.55, 0.0, 2.7), fire)
	## X arms + open rotors at tips (multi-rotor identity).
	var arms := [[1.0, 1.0], [1.0, -1.0], [-1.0, 1.0], [-1.0, -1.0]]
	for a in arms:
		var sx: float = a[0]
		var sy: float = a[1]
		C.tube(cv, C.fpt(R, 0.0, 0.0, 4.0), C.fpt(R, sx * 2.6, sy * 2.6, 4.2), 0.18 * Z, C.ramp(VOID_L))
		C.blob(cv, C.fpt(R, sx * 2.8, sy * 2.8, 4.35), 0.42 * Z, C.ramp(BLK_D))
		for i in 3:
			var ang := float(i) * TAU / 3.0 + spin + sx * 0.3
			C.tube(cv, C.fpt(R, sx * 2.8, sy * 2.8, 4.4),
				C.fpt(R, sx * 2.8 + cos(ang) * 1.5, sy * 2.8 + sin(ang) * 1.5, 4.4),
				0.1 * Z, C.ramp(STEEL_L))
	## Side rocket tubes when fire.
	if fire:
		for s in [-1.0, 1.0]:
			C.tube(cv, C.fpt(R, -0.4, s * 1.3, 3.5), C.fpt(R, 1.2, s * 1.4, 3.4), 0.28 * Z, C.ramp(VOID_D))
			C.blob(cv, C.fpt(R, 1.3, s * 1.4, 3.4), 0.18 * Z, C.ramp(MUZZLE))
	_team(cv, C.fpt(R, -0.6, -0.8, 4.3), 0.18 * Z)
	_hit_scar(cv, R, Z, hit)


## ---------------------------------------------------------------------------
## Recon Drone — tiny high-wing spy with boom EO (smallest; no rotors).
## ---------------------------------------------------------------------------
static func _draw_recon_drone(cv, k: int, frame: String) -> void:
	var Z := Z_RECON_D
	var R := _R(k, Z, _pose_bank(frame) * 0.5, _pose_bob(frame) * 0.4)
	C.ground_shadow(cv, Vector2(PIVOT) + Vector2(0, 1), 10.0, 4.0)
	var fire := frame == "fire"
	var hit := frame == "hit"
	## Slender stick fuselage (pencil — not diamond, not X-frame).
	C.tube(cv, C.fpt(R, -3.6, 0.0, 3.5), C.fpt(R, 3.2, 0.0, 3.7), 0.32 * Z, C.ramp(BLK))
	C.tube(cv, C.fpt(R, -3.0, 0.0, 3.75), C.fpt(R, 2.4, 0.0, 3.95), 0.18 * Z, C.ramp(STEEL))
	## High straight wing (sailplane read).
	for s in [-1.0, 1.0]:
		C.face(cv, PackedVector2Array([
			C.fpt(R, 0.6, s * 0.15, 3.9), C.fpt(R, -0.8, s * 0.15, 3.85),
			C.fpt(R, -0.4, s * 5.2, 3.4), C.fpt(R, 0.5, s * 5.0, 3.45),
		]), C.ramp(VOID_L if s < 0.0 else BLK_L), 2, s < 0.0)
	## Twin boom → H-tail (recon signature).
	for s in [-1.0, 1.0]:
		C.tube(cv, C.fpt(R, -0.6, s * 0.9, 3.6), C.fpt(R, -4.4, s * 1.1, 3.7), 0.12 * Z, C.ramp(VOID))
		C.face(cv, PackedVector2Array([
			C.fpt(R, -4.0, s * 1.0, 3.7), C.fpt(R, -4.8, s * 1.05, 3.65),
			C.fpt(R, -4.75, s * 1.05, 5.2), C.fpt(R, -4.1, s * 1.0, 5.15),
		]), C.ramp(STEEL), 1, true)
	C.tube(cv, C.fpt(R, -4.5, -1.1, 4.6), C.fpt(R, -4.5, 1.1, 4.6), 0.1 * Z, C.ramp(STEEL_L))
	## Long EO boom under nose (spyglass).
	C.tube(cv, C.fpt(R, 2.6, 0.0, 3.4), C.fpt(R, 4.8, 0.0, 2.6), 0.14 * Z, C.ramp(STEEL))
	C.blob(cv, C.fpt(R, 5.0, 0.0, 2.45), 0.38 * Z, C.ramp(VOID_D))
	C.blob(cv, C.fpt(R, 5.05, 0.0, 2.35), 0.22 * Z, C.ramp(GLASS))
	## Tiny defensive gun only when fire (recon is not a gunship).
	if fire:
		C.tube(cv, C.fpt(R, 0.8, 0.0, 3.2), C.fpt(R, 2.0, 0.0, 3.1), 0.12 * Z, C.ramp(BLK_D))
		_muzzle(cv, C.fpt(R, 2.1, 0.0, 3.1), true)
	_team(cv, C.fpt(R, -0.2, -0.4, 4.0), 0.12 * Z)
	_hit_scar(cv, R, Z, hit)
