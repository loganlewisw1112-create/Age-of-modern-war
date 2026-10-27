extends RefCounted
## G7 audio catalog (owner: AUDIO7). Presentation only: never read by the sim, never hashed.
## Data: presentation/audio/audio_lines_g7.json (voice library) + the G7 manifest merged into audio_catalog.gd.
## Pure, static mapping helpers (tested headless by tests/test_audio7.gd):
##   event_sfx(ev) -> [{id, pos?, ent?, ui?}]   G7 sim event -> sound(s) to play (positional unless ui)
##   bark_line(pers, kind, voice, n) -> line id      operator bark by personality (4 x 7 kinds x 2 texts x 2 voices)
##   hq_key(ev, player_fid) -> key | ""              Last Protocol / counter-nanite radio (HQ speaker)
##   ack_key(cmd_type) -> key | ""                   command voice acknowledgement for a counter-nanite order
##   line_for(cat, key, n) -> line id                 command / HQ / PROTOCOL line by key
##   text_of(line) / speaker_of(line) / channel(cat) / priority(cat) / cooldown(cat) / music_path(stem)

const Cat = preload("res://presentation/audio/audio_catalog.gd")
const LINES := "res://presentation/audio/audio_lines_g7.json"
const PERS := ["calm_veteran", "nervous_rookie", "joker", "hardliner"]
const BARK_KINDS := ["under_fire", "wounded", "kill", "hero", "buddy_wounded", "buddy_down", "level"]
const PROTOCOL_KEYS := ["seed_exposed", "convoy_danger", "core_plating", "core_destroyed", "creep_rising", "creep_critical",
	"countdown", "countdown_final", "tide", "weavers", "facility_threat", "relay_online", "forward_base", "team_lost",
	"extraction", "breach", "opportunity", "dome_down", "stall", "incoming", "suit_breach", "drone_lost", "generic"]
## OPSUI7 protocol_advisor.gd line key prefix (before ":") -> PROTOCOL voice key.
const ADVISOR_KEYS := {"nest": "seed_exposed", "route": "convoy_danger", "dome": "dome_down", "stall": "stall",
	"inc": "incoming", "breach": "suit_breach", "drone": "drone_lost", "core": "core_plating", "creep": "creep_rising",
	"final": "countdown_final", "tide": "tide"}
const STEMS := ["ambient", "tension", "pulse", "drums", "tide"]

## Counter-nanite / G7 command -> acknowledgement key (command voice). Commands not listed stay silent (G6.1 acks).
const ACK := {
	"cn_move": "move", "cn_deploy": "deploy", "cn_dismount": "dismount", "cn_mount": "mount", "cn_dome": "dome",
	"cn_emp": "emp", "cn_pincer": "pincer", "cn_break_contact": "break_contact", "cn_return": "return",
	"cn_evacuate": "evacuate", "cn_fire_support": "fire_support", "lp_fire_support": "fire_support",
	"lp_orbital_strike": "fire_support", "cn_relief": "relief", "cn_rollout": "rollout", "cn_hero_detonate": "hero",
	"cn_set_loadout": "loadout", "convoy_form": "convoy", "convoy_move": "convoy", "drone_take": "drone",
	"cn_panels": "generic", "cn_drill": "generic", "cn_specialize": "generic",
}

## G7 event -> [sound id, how]. how: "pos" (event pos), "from" / "to" (event field), "id" / "target" / "vehicle" /
## "bid" (entity position), "ui" (non-positional, player's side only).
const SFX := {
	"RocketSalvo": ["shot_rocketpod", "from"], "CnDisruptorShot": ["shot_disruptor", "from"],
	"CnHarpoon": ["shot_harpoon", "from"], "CnEmpGrenade": ["explosion_emp", "pos"], "ApcEmp": ["explosion_emp", "pos"],
	"EmpStun": ["explosion_emp", "pos"], "T7Emp": ["explosion_emp", "pos"], "T7Burn": ["shot_thermite", "pos"],
	"T7Cone": ["shot_microwave", "pos"], "T7Rail": ["shot_rail", "from"], "CnHeroDetonation": ["explosion_hero", "id"],
	"CnPurge": ["explosion_purge", "site"], "CreepPurged": ["creep_purged", "pos"], "FissurePurged": ["creep_purged", "pos"],
	"ApsIntercept": ["impact_aps", "id"], "WalkerStomp": ["impact_stomp", "pos"], "WalkerToppled": ["impact_stomp", "pos"],
	"WalkerDown": ["impact_stomp", "pos"], "CnLimpetPlanted": ["alert_limpet", "pos"], "CnLimpet": ["explosion_small", "pos"],
	"ApcDomeBroken": ["alert_dome_down", "pos"], "ApcDome": ["alert_dome_up", "id"], "DroneDetonated": ["explosion_small", "pos"],
	"DroneMunitionAway": ["explosion_small", "at"], "DroneLinkLost": ["alert_link_lost", "ui"],
	"DroneLowBattery": ["alert_lowbat", "ui"], "CnRollout": ["engine_dropship", "fac"], "CnDropshipReady": ["alert_ramp", "id"],
	"CnTeamOut": ["alert_ramp", "fac"], "CnLoading": ["alert_ramp", "fac"], "CnExtractionDrones": ["engine_dropship", "dropship"],
	"FissuresChanged": ["creep_fissure", "tiles"], "GrowthRisen": ["creep_growth", "pos"], "SeedRegrown": ["creep_spread", "pos"],
	"SeedKilled": ["creep_purged", "pos"], "PackhunterSwipe": ["threat_packhunter", "id"], "PackFormed": ["threat_spawn", "ui"],
	"BurrowerErupt": ["threat_burrower", "pos"], "BurrowerSurfaced": ["threat_burrower", "pos"], "LeechLatched": ["threat_leech", "vehicle"],
	"LeechDrill": ["threat_leech", "vehicle"], "WebSpit": ["threat_weaver", "from"], "NaniteSlug": ["threat_slug", "from"],
	"Cocooned": ["threat_cocoon", "pos"], "CocoonCut": ["threat_cocoon", "pos"], "ThreatSpawned": ["threat_spawn", "pos"],
	"CorePulse": ["core_pulse", "pos"], "CoreHit": ["core_hit", "pos"], "CorePlated": ["core_scream", "id"],
	"CoreUprooted": ["core_scream", "pos"], "CoreDestroyed": ["core_destroyed", "ui"], "CoreWalkerBlocked": ["core_scream", "pos"],
	"LpCountdownWarning": ["alert_klaxon", "ui"], "LpCountdownFinalStage": ["alert_klaxon", "ui"],
	"LpCreepWarning": ["alert_klaxon", "ui"], "TheTide": ["core_scream", "ui"],
}

## G7 events voiced by HQ on the player's radio (Last Protocol presentation + counter-nanite ops). Key -> line key.
const HQ := {
	"LpStarted": "lp_started", "LpFacilityReady": "facility_ready", "LpCountdownWarning": "countdown_warn",
	"LpCountdownFinalStage": "countdown_final", "LpCreepWarning": "creep_warn", "LpWeaversUnleashed": "weavers",
	"EscalationPhase": "escalation", "NetworkAdapted": "adapted", "CoreDestroyed": "core_destroyed",
	"CoreUprooted": "core_walking", "TheTide": "tide", "CnTeamLost": "team_lost", "CnTeamReady": "team_ready",
	"CnOverwatchWarning": "overwatch_warning", "CnReliefArrived": "relief_arrived", "CnFireSupport": "fire_support",
	"CnPurge": "purged",
}
## Events that concern the player only when ev.owner (or fid) is the player's side.
const HQ_OWNED := ["CnTeamLost", "CnTeamReady", "CnOverwatchWarning", "CnReliefArrived", "CnFireSupport", "CnPurge"]

static var _lib: Dictionary = {}
static var _text: Dictionary = {}


static func lib() -> Dictionary:
	if _lib.is_empty():
		var t := FileAccess.get_file_as_string(LINES)
		var p = JSON.parse_string(t) if t != "" else null
		_lib = p if typeof(p) == TYPE_DICTIONARY else {}
	return _lib


static func voices_per_pers() -> int:
	return maxi(int(lib().get("voices_per_pers", 2)), 1)


static func category(cat: String) -> Dictionary:
	return lib().get("categories", {}).get(cat, {})


static func priority(cat: String) -> int:
	return int(category(cat).get("priority", 10))


static func cooldown(cat: String) -> float:
	return float(category(cat).get("cooldown_s", 6.0))


static func channel(cat: String) -> String:
	return String(category(cat).get("channel", "radio"))


static func has_line(line: String) -> bool:
	return line != "" and Cat.radio_path(line) != ""


## Operator bark: personality x kind x voice; n rotates the texts. Unknown personality -> calm_veteran. "" = none.
static func bark_line(pers: String, kind: String, voice: int, n: int) -> String:
	if not PERS.has(pers):
		pers = "calm_veteran"
	var texts: Array = lib().get("barks", {}).get(pers, {}).get(kind, [])
	if texts.is_empty():
		return ""
	var v := posmod(voice, voices_per_pers())
	for k in texts.size():
		var id := "b7_%s_%s_%d_v%d" % [pers, kind, posmod(n + k, texts.size()), v]
		if has_line(id):
			return id
	return ""


## Command / HQ / PROTOCOL line of category cat with key (n rotates among equal keys). Falls back to key "generic".
static func line_for(cat: String, key: String, n: int = 0) -> String:
	var hits: Array = []
	var gen: Array = []
	for ln in lib().get("lines", []):
		if String(ln.get("cat", "")) == cat or (cat == "lp_hq" and String(ln.get("cat", "")) == "lp_hq_low"):
			if String(ln.get("key", "")) == key and has_line(String(ln.id)):
				hits.append(String(ln.id))
			elif String(ln.get("key", "")) == "generic" and has_line(String(ln.id)):
				gen.append(String(ln.id))
	var arr := hits if not hits.is_empty() else gen
	return "" if arr.is_empty() else String(arr[posmod(n, arr.size())])


## The category of a library line id ("" for unknown); barks -> "bark_<kind>".
static func cat_of(line: String) -> String:
	if line.begins_with("b7_"):
		for k in BARK_KINDS:
			if line.contains("_" + k + "_"):
				return "bark_" + k
		return ""
	for ln in lib().get("lines", []):
		if String(ln.id) == line:
			return String(ln.cat)
	return ""


## Subtitle text of a library line.
static func text_of(line: String) -> String:
	if _text.is_empty():
		for ln in lib().get("lines", []):
			_text[String(ln.id)] = String(ln.text)
		for pers in lib().get("barks", {}):
			for kind in lib().barks[pers]:
				var texts: Array = lib().barks[pers][kind]
				for i in texts.size():
					for v in voices_per_pers():
						_text["b7_%s_%s_%d_v%d" % [pers, kind, i, v]] = String(texts[i])
	return String(_text.get(line, ""))


static func speaker_of(line: String) -> String:
	if line.begins_with("b7_"):
		return "operator"
	for ln in lib().get("lines", []):
		if String(ln.id) == line:
			return String(ln.speaker)
	return ""


static func ack_key(cmd_type: String) -> String:
	return String(ACK.get(cmd_type, ""))


## HQ radio key for a G7 event heard on side player_fid ("" = not voiced).
static func hq_key(ev: Dictionary, player_fid: int) -> String:
	var t := String(ev.get("type", ""))
	if not HQ.has(t):
		return ""
	if HQ_OWNED.has(t) and int(ev.get("owner", ev.get("fid", -1))) != player_fid:
		return ""
	if t == "LpStarted" and int(ev.get("fid", player_fid)) != player_fid:
		return ""
	if t == "CnPurge" and bool(ev.get("hero", false)):
		return ""
	return String(HQ[t])


## Sounds of one G7 event: [{id, how, key}] where how/key say where it plays (see SFX). [] = none.
static func event_sfx(ev: Dictionary) -> Array:
	var t := String(ev.get("type", ""))
	if not SFX.has(t):
		return []
	var row: Array = SFX[t]
	var id := String(row[0])
	if t == "ApcDome":
		id = "alert_dome_up" if bool(ev.get("on", false)) else "alert_dome_down"
	if t == "BurrowerSurfaced" and String(ev.get("why", "")) == "":
		id = "threat_burrower"
	return [{"id": id, "how": String(row[1])}]


static func music_path(stem: String) -> String:
	return String(Cat.manifest().get("music", {}).get(stem, ""))
