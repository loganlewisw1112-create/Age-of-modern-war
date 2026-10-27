extends RefCounted
## G7 (CINE7): defeat by the doomsday countdown (master scope 13.5): the last seconds count down on black, then the
## base in the wide shot as the signal fires: a white flash, shock rings rolling across the map, bleached silence.
## About 18 s.

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "defeat_countdown"
const CUES := ["cine_defeat_countdown"]


static func shots(d: Dictionary) -> Array:
	var out := []
	var ctr: Vector2 = d.center
	var cores := D.core_pts(d)
	var pts: Array = cores.duplicate()
	pts.append(ctr)
	var fr: Array = preload("res://presentation/cine7/cine_opening.gd").frame(pts, 1.15)
	out.append(S.black(5.0, {"cue": "cine_defeat_countdown", "count": {"from": 5.0}, "tele": ["DOOMSDAY SIGNAL  ARMED"],
		"tele_style": "flash"}))
	out.append(S.make(8.0, ctr + Vector2(6, 6), fr[0], 0.55, fr[1], {"grade": S.g_bleach(), "fog": false, "flash": 1.2,
		"ease": "out", "fx": [{"k": "shock", "pts": cores, "r1": 140.0}, {"k": "core_glow", "pts": cores}]}))
	out.append(S.black(5.0, {"card": {"t": "THE PROTOCOL FIRED", "s": "The countdown reached zero.", "style": "big", "at": 0.6, "out": 4.6},
		"fade_out": 0.6}))
	return out
