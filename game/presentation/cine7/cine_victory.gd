extends RefCounted
## G7 (CINE7): plain victory (every core destroyed, creep pushed under the line, but not a total purge or a pyrrhic
## win). The last core site, the network's links go dark, the camera comes home over the base. About 24 s.

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "victory"
const CUES := ["cine_end_victory"]


static func shots(d: Dictionary) -> Array:
	var out := []
	var cores := D.core_pts(d)
	var last: Vector2 = cores[cores.size() - 1] if not cores.is_empty() else Vector2(d.center) + Vector2(60, -40)
	var ctr: Vector2 = d.center
	var pts: Array = cores.duplicate()
	pts.append(ctr)
	var fr: Array = preload("res://presentation/cine7/cine_opening.gd").frame(pts, 1.1)
	out.append(S.make(8.0, last + Vector2(4, 4), fr[0], 0.8, fr[1], {"grade": S.g_cold(), "fog": false, "fade_in": 1.2,
		"cue": "cine_end_victory", "fx": [{"k": "network", "cores": cores, "nests": d.nests, "base": ctr, "dying": true},
			{"k": "creep_field", "field": d.creep}],
		"tele": ["ALL THREE CORES  DESTROYED", "DOOMSDAY SIGNAL  SILENT"], "tele_style": "log", "tele_at": 1.5}))
	out.append(S.make(9.0, fr[0], ctr + Vector2(6, 6), fr[1], 0.6, {"grade": S.g_live(),
		"card": {"t": "VICTORY", "s": "The cores are dead. The creep is held below the line.", "style": "big", "at": 2.0, "out": 8.4}}))
	out.append(S.make(5.0, ctr + Vector2(6, 6), Vector2(d.facility), 0.6, 0.75, {"grade": S.g_live(), "fade_out": 1.2,
		"card": {"t": "BASTION STANDS", "s": "", "style": "caption", "at": 0.6, "out": 4.4}}))
	return out
