extends RefCounted
## G7 (CINE7): total purge ending ("world saved", master scope 13.5): every core dead, every nest burned, the creep
## nearly gone. Dawn over the last core site, the network's links go dark one by one, the camera rises over a clean
## map to the base, then the top-tier medal. About 34 s.

const S = preload("res://presentation/cine7/cine_shot.gd")
const D = preload("res://presentation/cine7/cine_data.gd")
const ID := "total_purge"
const CUES := ["cine_end_purge"]


static func shots(d: Dictionary) -> Array:
	var out := []
	var cores := D.core_pts(d)
	var last: Vector2 = cores[cores.size() - 1] if not cores.is_empty() else Vector2(d.center) + Vector2(60, -40)
	var ctr: Vector2 = d.center
	var r: Dictionary = d.result
	var pts: Array = cores.duplicate()
	pts.append(ctr)
	var fr: Array = preload("res://presentation/cine7/cine_opening.gd").frame(pts, 1.1)
	out.append(S.make(9.0, last + Vector2(5, 3), last, 0.85, 0.62, {"grade": S.g_dawn(), "fog": false, "fade_in": 1.6,
		"cue": "cine_end_purge", "fx": [{"k": "dawn", "at": last}, {"k": "purge", "pts": [last]}],
		"card": {"t": "T+ %s" % preload("res://presentation/ui7/lp_menu.gd").fmt_time(float(r.get("time_s", 0.0))), "s": "Site %d. The core is ash. The ground is ground again." % (cores.size()), "style": "date", "at": 1.5, "out": 8.4}}))
	out.append(S.make(10.0, last, fr[0], 0.62, fr[1], {"grade": S.g_dawn(), "fog": false,
		"fx": [{"k": "network", "cores": cores, "nests": d.nests, "base": ctr, "dying": true}, {"k": "purge", "pts": cores}],
		"tele": ["CREEP COVERAGE  %.1f%%" % (float(r.get("creep_final", d.creep_cov)) * 100.0), "SEED NESTS REMAINING  0",
			"DOOMSDAY SIGNAL  SILENT"], "tele_style": "log", "tele_at": 3.0}))
	out.append(S.make(8.0, fr[0], ctr + Vector2(8, 8), fr[1], 0.55, {"grade": S.g_dawn(),
		"fx": [{"k": "dawn", "at": ctr}],
		"card": {"t": "THE WORLD ENDURES", "s": "Every core destroyed. Every nest burned. The creep is gone.", "style": "big", "at": 1.0, "out": 7.4}}))
	out.append(S.black(6.5, {"card": {"t": "TOTAL PURGE", "s": "Top-tier commendation: PROTOCOL COMPLETE", "style": "medal",
		"at": 0.4, "out": 6.2, "medal": "gold"}, "fade_out": 0.8}))
	return out
