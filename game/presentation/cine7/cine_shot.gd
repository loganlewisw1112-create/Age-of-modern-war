extends RefCounted
## G7 (CINE7): the shot format every cinematic module returns (a plain dictionary per shot, played in order by
## cine_director.gd). Positions are world tiles; zoom is the Camera2D zoom (1.0 = normal play zoom).
##   dur        seconds
##   cam        [from: Vector2, to: Vector2] camera path (ease in-out); omitted on a black shot
##   zoom       [z0, z1]
##   ease       "inout" (default) | "out" | "in" | "linear"
##   black      true: no world (black backdrop, text only)
##   grade      {sat 0..1, tint Color, dark 0..1, scan 0..1, grain 0..1, vig 0..1, bleach 0..1} screen grade
##   fx         [{k: kind, ...}] world-space effects (cine_fx.gd): core_glow, outbreak, network, rings, flood, shock,
##              blasts, contain, dawn, embers, purge
##   card       {t, s, style big|title|stamp|caption|date|medal, at, out} title card
##   tele       [String] teletype lines (typed one after another), tele_style "flash"|"radio"|"log"
##   count      {from: float seconds} big countdown digits (counts to zero over the shot)
##   roll       [rows] Remembered roll (credits scroll); roll_head String
##   cue        music cue posted at shot start (fact cine.cues; AUDIO7 group "cine7_music")
##   fade_in / fade_out  seconds from / to black; flash  seconds of white at the start
##   fog        false: the fog layer is hidden for this shot (display only)
##   hand_over  true: the letterbox opens and the HUD returns during this shot

const DEFAULT_GRADE := {"sat": 1.0, "tint": Color(1, 1, 1, 0), "dark": 0.0, "scan": 0.0, "grain": 0.04, "vig": 0.35,
	"bleach": 0.0}


static func make(dur: float, from: Vector2, to: Vector2, z0: float, z1: float, extra: Dictionary = {}) -> Dictionary:
	var s := {"dur": dur, "cam": [from, to], "zoom": [z0, z1], "ease": "inout", "grade": DEFAULT_GRADE.duplicate(),
		"fx": [], "fade_in": 0.0, "fade_out": 0.0}
	for k in extra:
		if k == "grade":
			var g: Dictionary = DEFAULT_GRADE.duplicate()
			g.merge(extra.grade, true)
			s.grade = g
		else:
			s[k] = extra[k]
	return s


static func black(dur: float, extra: Dictionary = {}) -> Dictionary:
	var s := {"dur": dur, "black": true, "grade": DEFAULT_GRADE.duplicate(), "fx": [], "fade_in": 0.0, "fade_out": 0.0}
	s.merge(extra, true)
	return s


static func total(shots: Array) -> float:
	var t := 0.0
	for s in shots:
		t += float(s.get("dur", 0.0))
	return t


static func ease_t(kind: String, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match kind:
		"linear":
			return t
		"out":
			return 1.0 - pow(1.0 - t, 3.0)
		"in":
			return t * t * t
	return t * t * (3.0 - 2.0 * t)


## Camera state of a shot at local time t: {pos: Vector2 tile, zoom: float}.
static func cam_at(s: Dictionary, t: float) -> Dictionary:
	if bool(s.get("black", false)) or not s.has("cam"):
		return {}
	var u := ease_t(String(s.get("ease", "inout")), t / maxf(float(s.dur), 0.001))
	var a: Vector2 = s.cam[0]
	var b: Vector2 = s.cam[1]
	var z0 := float(s.zoom[0])
	var z1 := float(s.zoom[1])
	# zoom eases geometrically so push-ins feel even
	return {"pos": a.lerp(b, u), "zoom": z0 * pow(z1 / maxf(z0, 0.0001), u)}


## Archival feed look (the first outbreak: recovered surveillance, green mono with scan lines).
static func g_archive() -> Dictionary:
	return {"sat": 0.0, "tint": Color(0.45, 1.0, 0.6, 0.55), "dark": 0.15, "scan": 0.7, "grain": 0.22, "vig": 0.6}


static func g_cold() -> Dictionary:
	return {"sat": 0.35, "tint": Color(0.55, 0.7, 1.0, 0.35), "dark": 0.25, "scan": 0.15, "grain": 0.1, "vig": 0.55}


static func g_threat() -> Dictionary:
	return {"sat": 0.45, "tint": Color(1.0, 0.35, 0.3, 0.32), "dark": 0.3, "scan": 0.25, "grain": 0.12, "vig": 0.65}


static func g_live() -> Dictionary:
	return {"sat": 1.0, "tint": Color(1.0, 0.92, 0.8, 0.08), "dark": 0.0, "scan": 0.0, "grain": 0.03, "vig": 0.35}


static func g_dawn() -> Dictionary:
	return {"sat": 1.1, "tint": Color(1.0, 0.78, 0.5, 0.28), "dark": 0.0, "scan": 0.0, "grain": 0.03, "vig": 0.3}


static func g_dark() -> Dictionary:
	return {"sat": 0.25, "tint": Color(0.5, 0.58, 0.75, 0.3), "dark": 0.4, "scan": 0.0, "grain": 0.12, "vig": 0.75}


static func g_contain() -> Dictionary:
	return {"sat": 0.5, "tint": Color(0.4, 0.95, 1.0, 0.3), "dark": 0.2, "scan": 0.2, "grain": 0.08, "vig": 0.55}


static func g_fire() -> Dictionary:
	return {"sat": 0.6, "tint": Color(1.0, 0.55, 0.25, 0.3), "dark": 0.25, "scan": 0.0, "grain": 0.1, "vig": 0.7}


static func g_bleach() -> Dictionary:
	return {"sat": 0.2, "tint": Color(1, 1, 1, 0.2), "dark": 0.0, "scan": 0.0, "grain": 0.15, "vig": 0.4, "bleach": 0.55}
