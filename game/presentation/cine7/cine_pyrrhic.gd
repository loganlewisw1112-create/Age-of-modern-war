extends RefCounted
## G7 (CINE7): pyrrhic victory (master scope 13.5): the run is won but most teams or a ring were lost. A darker
## epilogue over the base (embers on the fallen rings), the cost in plain numbers, then the "Remembered" list rolls:
## every named operator who died, call sign and name. Length grows with the list (about 1 s per name, capped).

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "pyrrhic"
const CUES := ["cine_end_pyrrhic"]
const ROLL_S_PER_NAME := 1.1
const ROLL_MIN_S := 9.0
const ROLL_MAX_S := 48.0


static func roll_seconds(n: int) -> float:
	return clampf(5.0 + ROLL_S_PER_NAME * float(n), ROLL_MIN_S, ROLL_MAX_S)


static func shots(d: Dictionary) -> Array:
	var out := []
	var ctr: Vector2 = d.center
	var r: Dictionary = d.result
	var rings: Array = d.rings
	var fallen := []
	for rg in rings:
		if bool(rg.fallen):
			fallen.append((rg.rect as Rect2).get_center())
	var at: Vector2 = fallen[0] if not fallen.is_empty() else ctr + Vector2(30, 30)
	var lost := int(r.get("teams_lost", d.teams_lost))
	var tot := maxi(int(r.get("teams_total", d.teams_total)), lost)
	out.append(S.make(10.0, at + Vector2(14, 10), at, 0.5, 0.68, {"grade": S.g_dark(), "fade_in": 2.0, "cue": "cine_end_pyrrhic",
		"fx": [{"k": "embers", "at": at, "r": 26.0}, {"k": "embers", "at": ctr, "r": 40.0}],
		"tele": ["The cores are dead.", "The rings did not all hold." if int(r.get("rings_fallen", 0)) > 0 else "The rings held. The teams paid for it.",
			"Of %d teams sent out, %d came home." % [tot, tot - lost]], "tele_style": "radio", "tele_at": 2.0}))
	out.append(S.make(7.0, at, ctr + Vector2(4, 4), 0.68, 0.45, {"grade": S.g_dark(),
		"fx": [{"k": "embers", "at": ctr, "r": 40.0}],
		"card": {"t": "PYRRHIC VICTORY", "s": "The world was saved. Not all of it was saved by the living.", "style": "big", "at": 0.8, "out": 6.6}}))
	var rows: Array = d.remembered
	var rs := roll_seconds(rows.size())
	out.append(S.make(rs, ctr + Vector2(4, 4), ctr + Vector2(-6, -6), 0.45, 0.38, {"grade": S.g_dark(), "ease": "linear",
		"fx": [{"k": "embers", "at": ctr, "r": 40.0}],
		"roll": rows, "roll_head": "REMEMBERED", "roll_foot": "They held the line." if not rows.is_empty() else "No named operator was lost. The cost was counted in steel and ground.",
		"fade_out": 1.4}))
	return out
