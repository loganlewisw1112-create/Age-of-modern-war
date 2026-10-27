extends RefCounted
## G7 (CINE7): defeat when the facility falls with no team left in the field (master scope 13.5): the camera pushes
## in on the Counter-Nanite facility through smoke and secondary blasts while the radio calls go unanswered.
## About 18 s.

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "defeat_facility"
const CUES := ["cine_defeat_facility"]


static func shots(d: Dictionary) -> Array:
	var out := []
	var fac: Vector2 = d.facility
	out.append(S.make(9.0, fac + Vector2(14, 8), fac + Vector2(2, 1), 0.5, 0.85, {"grade": S.g_fire(), "fade_in": 0.6,
		"cue": "cine_defeat_facility", "fx": [{"k": "blasts", "at": fac, "r": 9.0, "n": 14}, {"k": "embers", "at": fac, "r": 16.0}],
		"tele": ["BASTION, BASTION, THIS IS OVERWATCH. RESPOND.", "...", "BASTION, RESPOND.", "NO TEAMS IN THE FIELD.  NO ANSWER."],
		"tele_style": "radio", "tele_at": 1.0}))
	out.append(S.make(5.0, fac + Vector2(2, 1), fac, 0.85, 1.0, {"grade": S.g_fire(), "fx": [{"k": "blasts", "at": fac, "r": 7.0, "n": 8},
		{"k": "embers", "at": fac, "r": 16.0}], "fade_out": 0.8,
		"card": {"t": "THE FACILITY FELL", "s": "No team was left to carry the protocol.", "style": "big", "at": 0.6, "out": 4.6}}))
	out.append(S.black(3.5, {"card": {"t": "DEFEAT", "s": "", "style": "stamp", "at": 0.3, "out": 3.2}, "fade_out": 0.5}))
	return out
