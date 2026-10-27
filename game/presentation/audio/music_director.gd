extends RefCounted
## G7 adaptive music (owner: AUDIO7; master scope 13.2). Presentation only: reads a state summary the AudioDirector
## builds from the render-side world view + events; never writes the sim.
## Five procedurally generated stems (tools/audio/synth_g7.py): ambient / tension / pulse / drums are 8-bar loops at
## 96 BPM that start together and stay sample-locked, so layers fade in and out on the beat grid; tide is the
## dedicated finale theme (own loop) entered with a stinger.
## Modes (select(), pure, tested): planning (calm ambient) -> tension (countdown, phases, convoys rolling, recent
## contact) -> combat (drums by firefight intensity) -> silence (the seconds right before the Tide hits) -> tide.
## Pre-Tide silence: predicted from the LP countdown (the Tide fires at the countdown's final stage) and, for the
## walking-core trigger (no warning in the sim), a short silence window opened by the TheTide event itself; the Tide
## theme and its stinger hit when the window closes.
## Headless (owner director disabled): the logic runs, levels are tracked and logged, no player is ever created.

const Cat = preload("res://presentation/audio/audio_catalog.gd")
const Cat7 = preload("res://presentation/audio/audio_catalog7.gd")

const STEMS := ["ambient", "tension", "pulse", "drums", "tide"]
const SYNC := ["ambient", "tension", "pulse", "drums"]
const SILENCE_LEAD_S := 6.0     # predicted pre-Tide silence starts this long before the countdown's final stage
const TIDE_SILENCE_S := 3.5     # silence window when the Tide comes without warning (walking core)
const MIN_SILENCE_S := 1.5      # a predicted silence lasts at least this long before the hit
const RATE := {"normal": 0.35, "silence": 4.0, "tide": 1.5, "combat_in": 0.9}
const MAX_DB := 0.0

var host: Node = null            # the AudioDirector (players are added as its children when enabled)
var enabled := false
var levels: Dictionary = {}      # stem -> current 0..1
var target: Dictionary = {}      # stem -> target 0..1
var mode := "planning"
var mlog: Array = []             # [{at, mode, why}] mode changes (tests / playtest log)
var tide_hit := false
var silence_from := -1.0
var silence_until := -1.0
var stingers: Array = []         # [{at, id}]
var _players: Dictionary = {}
var _sting: AudioStreamPlayer = null
var _now := 0.0
## G7 CINE7 CR 1546: while a cinematic plays, its cue picks the stem levels (fact cine.cues); "cine_end" (or an
## unknown cue) hands back to the adaptive selection. PROVISIONAL mix per cue.
var cine_levels: Dictionary = {}
const CINE := {
	"cine_open_archive": {"ambient": 0.35, "tension": 0.0, "pulse": 0.0, "drums": 0.0, "tide": 0.0},
	"cine_open_network": {"ambient": 0.3, "tension": 0.7, "pulse": 0.45, "drums": 0.0, "tide": 0.0},
	"cine_open_order": {"ambient": 0.0, "tension": 0.0, "pulse": 0.0, "drums": 0.0, "tide": 0.0},
	"cine_open_base": {"ambient": 0.85, "tension": 0.5, "pulse": 0.3, "drums": 0.0, "tide": 0.0},
	"cine_handover": {"ambient": 0.85, "tension": 0.0, "pulse": 0.0, "drums": 0.0, "tide": 0.0},
	"cine_end_purge": {"ambient": 1.0, "tension": 0.25, "pulse": 0.0, "drums": 0.0, "tide": 0.0},
	"cine_end_pyrrhic": {"ambient": 0.5, "tension": 0.0, "pulse": 0.0, "drums": 0.0, "tide": 0.0},
	"cine_end_capture": {"ambient": 0.3, "tension": 0.6, "pulse": 0.0, "drums": 0.0, "tide": 0.0},
	"cine_end_victory": {"ambient": 0.9, "tension": 0.0, "pulse": 0.5, "drums": 0.0, "tide": 0.0},
	"cine_defeat_creep": {"ambient": 0.0, "tension": 0.0, "pulse": 0.0, "drums": 0.0, "tide": 0.7},
	"cine_defeat_countdown": {"ambient": 0.0, "tension": 0.0, "pulse": 0.7, "drums": 0.0, "tide": 0.0},
	"cine_defeat_facility": {"ambient": 0.0, "tension": 0.8, "pulse": 0.0, "drums": 0.3, "tide": 0.0},
}


func cine_cue(cue: String) -> void:
	cine_levels = (CINE.get(cue, {}) as Dictionary).duplicate()
	mlog.append({"at": snappedf(_now, 0.01), "mode": "cine" if not cine_levels.is_empty() else mode, "why": cue})


func _init() -> void:
	for s in STEMS:
		levels[s] = 0.0
		target[s] = 0.0


func setup(owner_node: Node, on: bool) -> void:
	host = owner_node
	enabled = on


## Pure layer selection. st: {lp: LastProtocol.hud() or {}, combat 0..1, convoy bool, contact bool, silence bool,
## tide bool (the Tide theme has hit)}. Returns {mode, levels: {stem: 0..1}, tension}.
static func select(st: Dictionary) -> Dictionary:
	var lv := {"ambient": 0.0, "tension": 0.0, "pulse": 0.0, "drums": 0.0, "tide": 0.0}
	if bool(st.get("silence", false)):
		return {"mode": "silence", "levels": lv, "tension": 1.0}
	if bool(st.get("tide", false)):
		lv.tide = 1.0
		return {"mode": "tide", "levels": lv, "tension": 1.0}
	var lp: Dictionary = st.get("lp", {})
	var t := 0.0
	if not lp.is_empty():
		var cd_total := maxf(float(lp.get("cd_total", 1.0)), 1.0)
		var used := 1.0 - clampf(float(lp.get("cd_left", cd_total)) / cd_total, 0.0, 1.0)
		t = maxf(float(lp.get("frac", 0.0)), used) * 0.7 + float(lp.get("phase", 0)) * 0.08
		if bool(lp.get("final_stage", false)):
			t += 0.3
		if bool(lp.get("weavers", false)):
			t += 0.1
		t = maxf(t, 0.15)
	if bool(st.get("contact", false)):
		t = maxf(t, 0.45)
	if bool(st.get("convoy", false)):
		t = maxf(t + 0.15, 0.4)
	t = clampf(t, 0.0, 1.0)
	var c := clampf(float(st.get("combat", 0.0)), 0.0, 1.0)
	lv.ambient = clampf(1.0 - 0.55 * t - 0.8 * c, 0.15, 1.0)
	lv.tension = clampf(maxf(t * 1.25, c * 0.6), 0.0, 1.0)
	lv.pulse = clampf(maxf((t - 0.5) * 2.0, (c - 0.3) * 1.2), 0.0, 1.0)
	lv.drums = clampf((c - 0.2) / 0.5, 0.0, 1.0)
	var m := "planning"
	if c >= 0.35:
		m = "combat"
	elif t >= 0.3:
		m = "tension"
	return {"mode": m, "levels": lv, "tension": t}


## Seconds until the countdown reaches its final stage (the Tide's countdown trigger); INF when not predictable.
static func eta_final_stage(lp: Dictionary, final_frac: float) -> float:
	if lp.is_empty() or bool(lp.get("final_stage", false)) or bool(lp.get("tide", false)):
		return INF
	var rate := float(lp.get("cd_rate", 0.0))
	if rate <= 0.0:
		return INF
	return (float(lp.get("cd_left", 0.0)) - final_frac * float(lp.get("cd_total", 0.0))) / rate


static func final_frac() -> float:
	var r: Dictionary = Content.rules().get("g7_lastprotocol", {})
	return float(r.get("countdown", {}).get("final_stage_frac", 0.15))


## The Tide event arrived (sim TheTide): open the silence window unless a predicted one is already running.
func on_tide(now: float) -> void:
	if tide_hit:
		return
	if silence_from >= 0.0 and now - silence_from >= MIN_SILENCE_S:
		silence_until = now        # predicted silence has run long enough: hit now
	elif silence_from >= 0.0:
		silence_until = silence_from + MIN_SILENCE_S
	else:
		silence_from = now
		silence_until = now + TIDE_SILENCE_S
		_mark(now, "silence", "tide event (no warning)")


## One update: st as in select() minus silence/tide (owned here). dt in seconds.
func update(now: float, dt: float, st: Dictionary) -> void:
	_now = now
	var lp: Dictionary = st.get("lp", {})
	if bool(lp.get("tide", false)) and not tide_hit and (silence_from < 0.0 or silence_until == INF):
		on_tide(now)   # the hud already says Tide (event missed, e.g. joined late): same path as the event
	if not tide_hit and silence_from < 0.0 and eta_final_stage(lp, final_frac()) <= SILENCE_LEAD_S:
		silence_from = now
		silence_until = INF      # held until the TheTide event closes it (on_tide)
		_mark(now, "silence", "countdown final stage in %.1f s" % eta_final_stage(lp, final_frac()))
	if not tide_hit and silence_from >= 0.0 and now >= silence_until:
		tide_hit = true
		stingers.append({"at": snappedf(now, 0.01), "id": "sting_tide"})
		_play_sting("sting_tide")
	var s := st.duplicate()
	s.silence = silence_from >= 0.0 and not tide_hit
	s.tide = tide_hit
	var sel := select(s)
	target = sel.levels
	if not cine_levels.is_empty():
		target = cine_levels   # G7 CINE7: a cinematic owns the mix until cine_end
	if String(sel.mode) != mode:
		_mark(now, String(sel.mode), "")
	var rate := float(RATE.normal)
	if mode == "silence":
		rate = float(RATE.silence)
	elif mode == "tide":
		rate = float(RATE.tide)
	for k in STEMS:
		var r := rate
		if mode == "combat" and k == "drums" and float(target[k]) > float(levels[k]):
			r = float(RATE.combat_in)
		levels[k] = move_toward(float(levels[k]), float(target[k]), r * dt)
	if enabled:
		_apply()


func _mark(now: float, m: String, why: String) -> void:
	mode = m
	mlog.append({"at": snappedf(now, 0.01), "mode": m, "why": why})
	if mlog.size() > 100:
		mlog.pop_front()


func sting(id: String) -> void:
	stingers.append({"at": snappedf(_now, 0.01), "id": id})
	_play_sting(id)


func _play_sting(id: String) -> void:
	if not enabled or host == null:
		return
	var p := Cat7.music_path(id)
	if p == "":
		return
	if _sting == null:
		_sting = AudioStreamPlayer.new()
		_sting.bus = "Music"
		host.add_child(_sting)
	_sting.stream = Cat.stream(p)
	_sting.play()


func _apply() -> void:
	if host == null:
		return
	if _players.is_empty():
		for k in STEMS:
			var path := Cat7.music_path(k)
			if path == "":
				continue
			var p := AudioStreamPlayer.new()
			p.bus = "Music"
			p.stream = Cat.stream(path, true)
			p.volume_db = -80.0
			host.add_child(p)
			_players[k] = p
		for k in SYNC:
			if _players.has(k):
				(_players[k] as AudioStreamPlayer).play()
	for k in _players:
		var p: AudioStreamPlayer = _players[k]
		var lv := float(levels[k])
		p.volume_db = MAX_DB + (linear_to_db(lv) if lv > 0.001 else -80.0)
		if k == "tide":
			if lv > 0.001 and not p.playing:
				p.play()
			elif lv <= 0.001 and p.playing:
				p.stop()


func players_created() -> int:
	return _players.size() + (1 if _sting != null else 0)
