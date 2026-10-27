extends RefCounted
## G7 (CINE7): defeat by the creep meter (master scope 13.5): the camera rises from the base while the creep flows
## out of every patch it holds and swallows the map; the screen goes red, then black. About 19 s.

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "defeat_creep"
const CUES := ["cine_defeat_creep"]


static func shots(d: Dictionary) -> Array:
	var out := []
	var ctr: Vector2 = d.center
	var pts: Array = D.core_pts(d)
	pts.append(ctr)
	var fr: Array = preload("res://presentation/cine7/cine_opening.gd").frame(pts, 1.2)
	out.append(S.make(6.0, ctr + Vector2(10, 10), ctr, 0.7, 0.5, {"grade": S.g_threat(), "fade_in": 0.6,
		"cue": "cine_defeat_creep", "fx": [{"k": "flood", "field": d.creep, "grow": 6.0, "base": ctr}],
		"tele": ["CREEP COVERAGE  CRITICAL", "OUTER RING  LOST CONTACT", "ECONOMY RING  LOST CONTACT"], "tele_style": "radio", "tele_at": 0.8}))
	out.append(S.make(9.0, ctr, fr[0], 0.5, fr[1], {"grade": S.g_threat(), "fog": false, "ease": "out",
		"fx": [{"k": "flood", "field": d.creep, "grow": 30.0, "base": ctr, "from": 6.0}],
		"card": {"t": "THE CREEP TOOK EVERYTHING", "s": "There is no ground left to hold.", "style": "big", "at": 3.0, "out": 8.6}}))
	out.append(S.black(4.0, {"card": {"t": "DEFEAT", "s": "Last Protocol failed: the creep meter reached critical.", "style": "stamp", "at": 0.3, "out": 3.7},
		"fade_out": 0.6}))
	return out
