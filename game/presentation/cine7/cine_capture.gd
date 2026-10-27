extends RefCounted
## G7 (CINE7): the captured core, the secret alternate win (master scope 13.5, 13.8): the last core EMP-locked and
## held inside barrier packages instead of destroyed. Containment rings close around it, the lab's log runs, and the
## origin file opens when the Machine origin site was found (otherwise it says where to look). About 32 s.

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "capture_core"
const CUES := ["cine_end_capture"]


static func shots(d: Dictionary) -> Array:
	var out := []
	var cores := D.core_pts(d)
	var at: Vector2 = cores[cores.size() - 1] if not cores.is_empty() else Vector2(d.center) + Vector2(50, -30)
	for c in d.cores:
		if bool(c.get("walking", false)):
			at = Vector2(c.pos)
	var origin := bool(d.get("origin_found", false))
	out.append(S.make(11.0, at + Vector2(9, 6), at, 0.55, 1.05, {"grade": S.g_contain(), "fog": false, "fade_in": 1.4,
		"cue": "cine_end_capture", "fx": [{"k": "contain", "at": at}, {"k": "core_glow", "pts": [at], "dim": true}],
		"tele": ["EMP LOCK  HOLDING", "BARRIER FIELD  CLOSED", "CORE ACTIVITY  0.3%  AND FALLING"], "tele_style": "log", "tele_at": 2.0}))
	out.append(S.make(9.0, at, at + Vector2(-3, -3), 1.05, 1.2, {"grade": S.g_contain(), "fog": false,
		"fx": [{"k": "contain", "at": at}],
		"card": {"t": "SPECIMEN SECURED", "s": "For the first time, we can ask it what it is.", "style": "title", "at": 1.0, "out": 8.4}}))
	var tl: Array = ["ORIGIN FILE  //  UNSEALED", "It was never a weapon. It was a builder.", "Someone told it to finish the job."] if origin \
		else ["ORIGIN FILE  //  INCOMPLETE", "The answer is out there, where it first woke.", "Find the origin site."]
	out.append(S.black(8.0, {"tele": tl, "tele_style": "log",
		"card": {"t": "THE CAPTURED CORE", "s": "Hidden ending", "style": "stamp", "at": 5.5, "out": 7.8}, "fade_out": 0.6}))
	return out
