extends RefCounted
## DL7 sample soldiers (owner: ARTCN7; G7_REFERENCE 6.4, 6.6, 6.8, 6.12): the 7 counter-nanite strike-team kits
## (sealed pale suits, amber visors) and the 7 distinct tactical-operator kits (dark tactical suits, coyote
## plates, green NVG; the 2 hunter-killers share one kit, so 8 roles = 7 sheets). One soldier per sheet,
## 8 facings x the 24 DL7 frames; act_0 / act_1 are the role's own key action.
## Not wired into content defs (later agents do); ids are sample art ids only.
const C = preload("res://tools/art/g7_cn_lib.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")

const SUIT_CN := Color8(170, 168, 152)
const PLATE_CN := Color8(74, 82, 88)
const HELM_CN := Color8(84, 92, 98)
const VISOR_CN := Color8(246, 178, 60)
const SUIT_OP := Color8(64, 70, 62)
const PLATE_OP := Color8(146, 130, 98)
const HELM_OP := Color8(86, 90, 78)
const VISOR_OP := Color8(130, 240, 150)
const BOOT := Color8(50, 52, 54)

const CROUCH := {"crouch": 0.5}
const KITS := {
	# strike team (6.4)
	"cn_team_leader": {"role": "team leader", "weapon": "carbine", "wlen": 6.5, "pack": "small", "stripe": true,
		"act": "signal", "key": "signal (arm raised)"},
	"cn_radio": {"role": "second-in-command / radio", "weapon": "carbine", "wlen": 6.5, "pack": "radio",
		"act": "handset", "key": "radio handset"},
	"cn_deploy": {"role": "deployment specialist", "weapon": "carbine", "wlen": 6.0, "pack": "package",
		"bulk": 2.7, "act": "arm", "act_pose": CROUCH, "key": "arming a strike package (kneel, lights)"},
	"cn_scanner": {"role": "scanner technician", "weapon": "carbine", "wlen": 5.0, "pack": "sensor",
		"act": "scan", "key": "scanner sweep cone"},
	"cn_ew": {"role": "EW specialist", "weapon": "jammer", "wlen": 6.0, "pack": "ew", "act": "jam",
		"key": "hive-link jamming rings"},
	"cn_gunner": {"role": "security gunner", "weapon": "shotgun", "wlen": 6.0, "pack": "small", "chest": "emp",
		"act": "throw", "key": "EMP grenade throw (wind-up, release)"},
	"cn_medic": {"role": "combat medic / engineer", "weapon": "carbine", "wlen": 5.5, "pack": "medic",
		"chest": "medic", "act": "treat", "act_pose": CROUCH, "key": "treating / welding (kneel)"},
	# tactical operators (6.6)
	"op_leader": {"role": "operator leader", "weapon": "carbine", "wlen": 6.5, "pack": "radio", "stripe": true,
		"act": "signal", "key": "signal (arm raised)"},
	"op_marksman": {"role": "designated marksman", "weapon": "dmr", "wlen": 9.5, "pack": "small",
		"act": "scope", "key": "scoped shot"},
	"op_hunter": {"role": "hunter-killer (x2)", "weapon": "harpoon", "wlen": 7.5, "pack": "hunter",
		"act": "harpoon", "key": "harpoon fired with cable"},
	"op_emp": {"role": "EMP grenadier", "weapon": "launcher", "wlen": 6.0, "pack": "small", "chest": "emp",
		"act": "launch", "key": "EMP launcher shot"},
	"op_antidrone": {"role": "anti-drone specialist", "weapon": "jammer", "wlen": 6.5, "pack": "ew",
		"act": "jam", "key": "drone jammer rings"},
	"op_purge": {"role": "purge / demolitions", "weapon": "carbine", "wlen": 6.0, "pack": "demo",
		"chest": "thermite", "act": "place", "act_pose": CROUCH, "key": "placing a thermite charge"},
	"op_medic": {"role": "combat medic", "weapon": "carbine", "wlen": 5.5, "pack": "medic", "chest": "medic",
		"act": "treat", "act_pose": CROUCH, "key": "treating a casualty (kneel)"},
}


static func kit(id: String) -> Dictionary:
	var k: Dictionary = (KITS[id] as Dictionary).duplicate(true)
	var op := id.begins_with("op_")
	k.merge({"suit": SUIT_OP if op else SUIT_CN, "plate": PLATE_OP if op else PLATE_CN,
		"helm": HELM_OP if op else HELM_CN, "visor": VISOR_OP if op else VISOR_CN, "boot": BOOT,
		"head": "nvg" if op else "sealed", "bulk": 2.4 if op else 2.6}, false)
	return k


static func build(out: Dictionary, only: Array = []) -> void:
	var ids: Array = KITS.keys()
	ids.sort()
	for id in ids:
		if not only.is_empty() and not only.has(id):
			continue
		var kt := kit(id)
		C.unit_sheet(out, "g7_" + id, "infantry", "infantry", C.INF_CELL.x, C.INF_CELL.y, C.INF_PIVOT,
			C.FRAMES_INF, func(cv, k, fname, o): FIG.draw(cv, kt, k, fname, o),
			{"sample": "soldier", "line": "operators" if id.begins_with("op_") else "strike_team",
			"role": kt.role, "key_frames": ["act_0", "act_1", "fire_s", "walk_0", "die_2"], "act": kt.key,
			"anim_strip": ["walk_0", "walk_1", "walk_2", "walk_3", "walk_4", "walk_5", "fire_s", "act_0", "act_1", "die_2"]})
