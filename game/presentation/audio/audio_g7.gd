extends RefCounted
## G7 audio layer (owner: AUDIO7), owned by the AudioDirector (one per director). Presentation only: reads events
## and the world read-only (sys_state.cnprog7 / LastProtocol.hud / Senses7.heard), never writes the sim.
## - G7 sound effects: every G7 event in Cat7.SFX plays positionally through the director's play_at (same pool, voice
##   limits, far / fog culling as G6.1) or as a UI one-shot (player-side alerts);
## - operator barks (CnBark: personality x kind x voice; "under_fire" derived here from shots at a named operator),
##   command-voice acks for counter-nanite orders, HQ radio for Last Protocol / counter-nanite ops, PROTOCOL advisor
##   lines (protocol_say, mutable): all through the director's radio queue (one voice at a time, priorities,
##   per-category cooldowns) plus a per-team bark throttle;
## - subtitles: the director emits `subtitle` when a line starts (OPSUI7 team cam / advisor panel);
## - adaptive music (music_director.gd) fed every MUSIC_EVERY seconds;
## - drone feed: static + motor loop while the player flies a drone (DroneTaken .. Released / Recovered / LinkLost).

const Cat = preload("res://presentation/audio/audio_catalog.gd")
const Cat7 = preload("res://presentation/audio/audio_catalog7.gd")
const Music = preload("res://presentation/audio/music_director.gd")
const Buses = preload("res://presentation/audio/audio_buses.gd")
const L = preload("res://sim/ai/ai_g6_lib.gd")
const VU = preload("res://presentation/view/view_util.gd")
const SENSES_PATH := "res://sim/systems/senses7.gd"
const LP_PATH := "res://sim/systems/last_protocol.gd"

const MUSIC_EVERY := 0.25
const TEAM_BARK_GAP_S := 4.0      # one operator line per team per this many seconds (on top of category cooldowns)
const UNDER_FIRE_GAP_S := 15.0    # per team
const COMBAT_REF := 10.0          # visible shots / s that count as a full firefight
const COMBAT_SAMPLE := 40         # visibility checks per music window (cheap in a 2k fight)
const CONVOY_S := 60.0
const CONTACT_S := 25.0
const SUB_KEEP := 40

var d = null                      # the AudioDirector
var music = Music.new()
var subtitles: Array = []         # [{channel, speaker, text, team, op, cat, line, dur, at, voiced}]
var meta: Dictionary = {}         # line id -> {team, op, speaker, text} of the last queue of that line
var bark_log: Array = []          # [{at, line, pers, kind, team}] queued barks (tests / playtest)
var protocol_log: Array = []      # [{at, key, voiced}]
var drone_feed := -1              # id of the drone the player flies (-1 = none)
var lp_override: Variant = null   # playtest / tests: a LastProtocol.hud()-shaped dict used instead of the world's
var _team_bark_t: Dictionary = {}
var _team_fire_t: Dictionary = {}
var _rot := 0
var _shots := 0
var _checks := 0
var _combat := 0.0
var _convoy_until := -1.0
var _contact_t := -100.0
var _mt := 0.0
var _feed_players: Array = []
var _senses = null
var _lp = null
var _advisor_hooked := false
var _hook_t := 0.0
var _hush := 0.0                  # pre-Tide silence: battle bus hush 0..1 (eases back out after the hit)


func _init(director = null) -> void:
	d = director


func setup(on: bool) -> void:
	music.setup(d, on)
	_senses = load(SENSES_PATH) if ResourceLoader.exists(SENSES_PATH) else null
	_lp = load(LP_PATH) if ResourceLoader.exists(LP_PATH) else null


func _w():
	if d == null or d.mv == null or not d.mv.has_method("world_readable") or not d.mv.world_readable():
		return null
	return d.mv.get("_world")  # never mv.world: that getter forces a sim join


func _mine(ev: Dictionary) -> bool:
	return int(ev.get("owner", ev.get("fid", -1))) == int(d.player_fid)


# ------------------------------------------------------------------ positions
func _ent_pos(id: int) -> Variant:
	var w = _w()
	if w == null or id < 0:
		return null
	var e = w.entities.get(id)
	return null if e == null else Vector2(e.pos)


func _where(ev: Dictionary, how: String) -> Variant:
	var v = ev.get(how)
	if typeof(v) == TYPE_VECTOR2:
		return v
	if typeof(v) == TYPE_VECTOR2I:
		return Vector2(v)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return _ent_pos(int(v))
	if typeof(v) == TYPE_ARRAY and not (v as Array).is_empty():
		var a = (v as Array)[0]
		if typeof(a) == TYPE_VECTOR2 or typeof(a) == TYPE_VECTOR2I:
			return Vector2(a)
	if ev.has("pos") and typeof(ev.pos) == TYPE_VECTOR2:
		return ev.pos
	return null


# ------------------------------------------------------------------ events
## Turret ShotFired for the special kinds: the T7Rail / T7Emp / T7Burn / T7Cone event carries the sound instead.
## CIWS7-4 (13.9c-32a): a roof CIWS fire tick (ciws7) never plays a per-round one-shot: its burst plays ciws_shot's loop.
static func skip_shot(ev: Dictionary) -> bool:
	return String(ev.get("t7", "")) in ["rail", "emp", "flame", "cone"] or bool(ev.get("ciws7", false))


## Sounds played for a G7 event (ids, for tests / log). Voices are queued separately.
func event(ev: Dictionary) -> Array:
	var t := String(ev.get("type", ""))
	var played: Array = []
	match t:
		"ShotFired":
			_on_shot(ev)
			if bool(ev.get("ciws7", false)):
				var cid := ciws_shot(ev)
				if cid != "":
					played.append(cid)
			return played
		"CnBark":
			if _mine(ev):
				bark(String(ev.get("pers", "")), String(ev.get("kind", "")), int(ev.get("voice", 0)), int(ev.get("team", -1)),
					int(ev.get("id", -1)), String(ev.get("call_sign", "")))
		"CnTeamLevel":
			if _mine(ev):
				bark("calm_veteran", "level", 0, int(ev.get("team", -1)), -1, String(ev.get("name", "")))
		"CommandApplied":
			if int(ev.get("issuer", -1)) == int(d.player_fid):
				var k := Cat7.ack_key(String(ev.get("cmd_type", "")))
				if k != "":
					queue_line(Cat7.line_for("cn_ack", k, _rot), "cn_ack", {"speaker": "Command"})
					_rot += 1
		"ConvoyFormed", "CnRollout":
			if _mine(ev):
				_convoy_until = d.now() + CONVOY_S
		"CnMove":
			if _mine(ev) and bool(ev.get("convoy", false)):
				_convoy_until = d.now() + CONVOY_S
		"DroneTaken":
			if _mine(ev):
				_feed(int(ev.get("id", -1)))
		"DroneReleased", "DroneRecovered", "DroneDetonated", "DroneLinkLost", "DroneEmpty":
			if int(ev.get("id", -2)) == drone_feed:
				_feed(-1)
		"TheTide":
			music.on_tide(d.now())
		"CoreDestroyed":
			music.sting("sting_core")
		"ReportSent":
			if _mine(ev) and String(ev.get("kind", "")) == "contact":
				_contact_t = d.now()
	var hk := Cat7.hq_key(ev, int(d.player_fid))
	if hk != "":
		var hl := Cat7.line_for("lp_hq", hk, _rot)
		queue_line(hl, Cat7.cat_of(hl), {"speaker": "HQ"})
		_rot += 1
	for s in Cat7.event_sfx(ev):
		var id := String(s.id)
		if String(s.how) == "ui":
			if t.begins_with("Drone") and not _mine(ev):
				continue
			if d.ui(id):
				played.append(id)
			continue
		var p = _where(ev, String(s.how))
		if p == null:
			continue
		var got: String = d.play_at(id, p, d._visible(p))
		if got != "":
			played.append(got)
	return played


func _on_shot(ev: Dictionary) -> void:
	if _checks < COMBAT_SAMPLE:
		_checks += 1
		var to: Vector2 = ev.get("to", Vector2.ZERO)
		if d._visible(to) and d.dist_norm(to) < 1.3:
			_shots += 1
			_contact_t = d.now()
	var w = _w()
	if w == null or not w.sys_state.has("cnprog7"):
		return
	var tid := int(ev.get("target", -1))
	var e = w.entities.get(tid)
	if e == null or int(e.owner) != int(d.player_fid):
		return
	var o: Dictionary = (w.sys_state.cnprog7.get("ops", {}) as Dictionary).get(str(tid), {})
	if o.is_empty():
		return
	var team := int(o.get("team", -1))
	if d.now() - float(_team_fire_t.get(team, -100.0)) < UNDER_FIRE_GAP_S:
		return
	_team_fire_t[team] = d.now()
	bark(String(o.get("pers", "")), "under_fire", int(o.get("voice", 0)), team, tid, String(o.get("cs", "")))


## Queues an operator bark (personality x kind x voice). Throttled per team on top of the category cooldown.
func bark(pers: String, kind: String, voice: int, team: int, op: int, call_sign: String) -> bool:
	var line := Cat7.bark_line(pers, kind, voice, _rot)
	_rot += 1
	if line == "":
		return false
	if kind != "hero" and d.now() - float(_team_bark_t.get(team, -100.0)) < TEAM_BARK_GAP_S:
		return false
	if not queue_line(line, "bark_" + kind, {"team": team, "op": op, "speaker": call_sign if call_sign != "" else "Operator"}):
		return false
	_team_bark_t[team] = d.now()
	bark_log.append({"at": snappedf(d.now(), 0.01), "line": line, "pers": pers, "kind": kind, "team": team})
	if bark_log.size() > 200:
		bark_log.pop_front()
	return true


## Queues a G7 library line (any channel) on the director's radio queue.
func queue_line(line: String, cat: String, m: Dictionary = {}) -> bool:
	if line == "" or cat == "":
		return false
	var mm := m.duplicate()
	mm.text = String(mm.get("text", Cat7.text_of(line)))
	meta[line] = mm
	return d.radio.push(line, cat, Cat7.priority(cat), d.now(), Cat7.cooldown(cat))


## PROTOCOL advisor (OPSUI7): voices the generic line for key unless the PROTOCOL voice is muted; the subtitle always
## carries the caller's full text. True when queued for voice.
func protocol_say(key: String, text: String = "") -> bool:
	if not Cat7.PROTOCOL_KEYS.has(key):
		key = "generic"
	var line := Cat7.line_for("protocol", key)
	var full := text if text != "" else Cat7.text_of(line)
	var voiced := protocol_voice_on() and queue_line(line, "protocol", {"speaker": "PROTOCOL", "text": full})
	protocol_log.append({"at": snappedf(d.now(), 0.01), "key": key, "voiced": voiced})
	if not voiced:
		subtitle({"channel": "protocol", "speaker": "PROTOCOL", "text": full, "team": -1, "op": -1, "cat": "protocol",
			"line": line, "dur": maxf(2.5, full.length() * 0.06), "at": snappedf(d.now(), 0.01), "voiced": false})
	return voiced


static func protocol_voice_on() -> bool:
	return Buses.protocol_mode() == "on"


## OPSUI7's advisor card (hud.ops7.advisor) emits advisory(line {key, kind, text, pos, tick, voice}); voice is false
## when the player muted it. Connected lazily (the HUD is built after the director).
func _hook_advisor() -> void:
	if _advisor_hooked or d == null or d.mv == null or not (d.mv is Node) or (d.mv as Node).get_parent() == null:
		return
	var hud = (d.mv as Node).get_parent().get("hud")
	var ops = hud.get("ops7") if hud != null else null
	var adv = ops.get("advisor") if ops != null else null
	if adv != null and (adv as Object).has_signal("advisory"):
		hook_advisor(adv)


func hook_advisor(adv: Object) -> void:
	if not adv.is_connected("advisory", on_advisory):
		adv.connect("advisory", on_advisory)
	_advisor_hooked = true


func on_advisory(line: Dictionary) -> void:
	var k := String(line.get("key", "")).get_slice(":", 0)
	var key := String(Cat7.ADVISOR_KEYS.get(k, "generic"))
	if bool(line.get("voice", false)):
		protocol_say(key, String(line.get("text", "")))
	else:
		protocol_log.append({"at": snappedf(d.now(), 0.01), "key": key, "voiced": false})


## The director started a radio-queue item: subtitle (G6.1 radio lines included) + which bus plays it.
func on_line_started(it: Dictionary) -> String:
	var line := String(it.get("line", ""))
	var cat := String(it.get("cat", ""))
	var ch := Cat7.channel(cat) if not Cat7.category(cat).is_empty() else "radio"
	var m: Dictionary = meta.get(line, {})
	var text := String(m.get("text", ""))
	if text == "":
		text = Cat7.text_of(line)
	if text == "":
		for ln in Cat.lib().get("lines", []):
			if String(ln.id) == line:
				text = String(ln.get("text", ""))
				break
	subtitle({"channel": ch, "speaker": String(m.get("speaker", "HQ" if ch == "radio" else ch.capitalize())), "text": text,
		"team": int(m.get("team", -1)), "op": int(m.get("op", -1)), "cat": cat, "line": line,
		"dur": Cat.duration(Cat.radio_path(line)) + 0.8, "at": snappedf(d.now(), 0.01), "voiced": true})
	return "Voice" if ch in ["protocol", "command"] else "Radio"


func subtitle(info: Dictionary) -> void:
	subtitles.append(info)
	if subtitles.size() > SUB_KEEP:
		subtitles.pop_front()
	d.subtitle.emit(info)


# ------------------------------------------------------------------ music + drone feed
func music_state() -> Dictionary:
	var lp: Dictionary = {}
	var w = _w()
	if lp_override != null:
		lp = lp_override
	elif w != null and _lp != null and w.sys_state.has("lp") and L.api(_lp, "hud"):
		lp = _lp.hud(w)
	if w != null and _senses != null and w.sys_state.has("senses7") and L.api(_senses, "heard"):
		for h in _senses.heard(w, int(d.player_fid)):
			if float(h.get("age", 99.0)) < 8.0:
				_contact_t = maxf(_contact_t, d.now() - float(h.age))
				break
	var tide := 0.0
	if w != null and w.sys_state.has("atmo71"):
		tide = float(w.sys_state.atmo71.get("tide_song", 0.0))
	return {"lp": lp, "combat": _combat, "convoy": d.now() < _convoy_until, "contact": d.now() - _contact_t < CONTACT_S,
		"tide_song": tide}


func tick(dt: float) -> void:
	_mt += dt
	_hook_t += dt
	_ciws_tick()
	if _hook_t >= 2.0:
		_hook_t = 0.0
		_hook_advisor()
	if _mt < MUSIC_EVERY:
		return
	var win := _mt
	_mt = 0.0
	var inst := clampf(float(_shots) / win / COMBAT_REF, 0.0, 1.0)
	_combat = move_toward(_combat, inst, (2.0 if inst > _combat else 0.08) * win)
	_shots = 0
	_checks = 0
	music.update(d.now(), win, music_state())
	_hush = move_toward(_hush, 1.0 if music.mode == "silence" else 0.0, win * (4.0 if music.mode == "silence" else 0.5))
	if d.enabled:
		Buses.set_hush(_hush)


## Combat intensity feed for tests / playtests (shots per second seen near the camera).
func set_combat(v: float) -> void:
	_combat = clampf(v, 0.0, 1.0)


func _feed(id: int) -> void:
	drone_feed = id
	if not d.enabled:
		return
	if id >= 0 and _feed_players.is_empty():
		for sid in ["ui_drone_feed", "engine_drone"]:
			var vars := Cat.variants(sid)
			if vars.is_empty():
				continue
			var p := AudioStreamPlayer.new()
			p.bus = "UI" if sid == "ui_drone_feed" else "Battle"
			p.stream = Cat.stream(String(vars[0]), true)
			p.volume_db = -10.0 if sid == "ui_drone_feed" else -14.0
			d.add_child(p)
			p.play()
			_feed_players.append(p)
	elif id < 0:
		for p in _feed_players:
			(p as Node).queue_free()
		_feed_players.clear()


# ------------------------------------------------------------------ CIWS7-4: the roof CIWS "BRRRT" (13.9c-32a)
## Owner: "CIWS turrets need to have that signatture phlanx BBRRRRTTTTTTTTTT shooting sound". A mount's burst plays ONE
## positional loop (shot_ciws7_brrt: 70 reports a second fused into a tearing buzz) from its first round to its last:
## every ciws7 ShotFired of that mount extends the burst by its rounds / CIWS_RPS (an intercept burst: lay + 60
## rounds); CIWS_GAP_S without a round = the burst is over: the loop fades out and, when the mount has no target left
## (or no world to ask), the spin-down (last rounds ringing out + the barrel cluster whining down) plays. The spin-up
## whine plays when the sim starts spinning a mount's barrels (its spin counter leaves 0). Same voice limits (mixer
## request, gun category), far swap (shot_ciws7_brrt_far: a muffled distant rumble) and far / fog culling as every
## battle sound; at most CIWS_VOICES loops at once. Presentation only: reads events + sys_state.ciws7 read-only.
const CIWS_LOOP_ID := "shot_ciws7_brrt"
const CIWS_UP_ID := "shot_ciws7_spinup"
const CIWS_DOWN_ID := "shot_ciws7_spindown"
const CIWS_RPS := 50.0            # rounds a second of the sim (rate_rpm 3000 / 60): sizes a burst from its rounds
const CIWS_GAP_S := 0.08          # this long past the last round's end = the burst is over (fire ticks are 0.05 s)
const CIWS_RES_S := 1.5           # voice reservation per burst (= burst_max_s)
const CIWS_VOICES := 4
const CIWS_FAR_START := 1.25      # = AudioDirector.FAR_START
const CIWS_MAX_DN := 3.5          # = AudioDirector.MAX_DN
var ciws_active: Dictionary = {}  # shooter id -> {id, end, at, pos, vis, player}
var ciws_log: Array = []          # [{at, sid, ev: start | stop | spinup | spindown, id}] (tests / playtest evidence)
var _ciws_sp: Dictionary = {}     # mount id (str) -> spin ticks seen at the last poll


## Starts (or extends) mount ev.shooter's burst loop. Returns the loop id started ("" when extended / culled).
func ciws_shot(ev: Dictionary) -> String:
	var sid := int(ev.get("shooter", -1))
	var p: Vector2 = ev.get("from", Vector2.ZERO)
	var now: float = d.now()
	var dur := maxf(float(ev.get("rounds", 1)) / CIWS_RPS, 0.05) + maxf(float(ev.get("lay_ticks", 0)), 0.0) / 20.0
	var a = ciws_active.get(sid)
	if a != null:
		a.end = maxf(float(a.end), now + dur)
		return ""
	if ciws_active.size() >= CIWS_VOICES:
		return ""
	var vis: bool = d._visible(p)
	var dn: float = d.dist_norm(p)
	if dn > CIWS_MAX_DN:
		return ""
	var id := CIWS_LOOP_ID
	var g := 0.0
	if not vis or dn > CIWS_FAR_START:
		id = Cat.far_of(id)
		g = -6.0 if not vis else -clampf((dn - CIWS_FAR_START) * 2.5, 0.0, 12.0)
	var vars := Cat.variants(id)
	if id == "" or vars.is_empty() or not d.mixer.request(id, Cat.category(id), now, maxf(dur, CIWS_RES_S)):
		return ""
	var path := String(vars[d.mixer.next_variant(id, vars.size())])
	var pl: AudioStreamPlayer2D = null
	if d.enabled:
		pl = AudioStreamPlayer2D.new()
		pl.bus = "Battle"
		pl.attenuation = 1.0
		pl.panning_strength = 1.0
		pl.stream = Cat.stream(path, true)
		pl.position = VU.iso(p)
		pl.volume_db = g
		pl.max_distance = d._hear_px()
		d.add_child(pl)
		pl.play()
	d.counts[id] = int(d.counts.get(id, 0)) + 1
	ciws_active[sid] = {"id": id, "end": now + dur, "at": now, "pos": p, "vis": vis, "player": pl}
	ciws_log.append({"at": now, "sid": sid, "ev": "start", "id": id})
	if ciws_log.size() > 200:
		ciws_log = ciws_log.slice(ciws_log.size() - 100)
	return id


func _ciws_tick() -> void:
	var now: float = d.now()
	var w = _w()
	var st = w.sys_state.get("ciws7") if w != null else null
	for sid in ciws_active.keys():
		var a: Dictionary = ciws_active[sid]
		if now <= float(a.end) + CIWS_GAP_S:
			continue
		ciws_active.erase(sid)
		var pl = a.get("player")
		if pl != null and is_instance_valid(pl):
			var tw: Tween = (pl as Node).create_tween()
			tw.tween_property(pl, "volume_db", float((pl as AudioStreamPlayer2D).volume_db) - 30.0, 0.06)
			tw.tween_callback((pl as Node).queue_free)
		ciws_log.append({"at": now, "sid": int(sid), "ev": "stop", "id": String(a.id)})
		var M = (st.m as Dictionary).get(str(sid)) if st != null else null
		if M == null or int(M.get("t", -1)) < 0:
			var got: String = d.play_at(CIWS_DOWN_ID, a.pos, bool(a.vis))
			ciws_log.append({"at": now, "sid": int(sid), "ev": "spindown", "id": got})
	if st == null:
		return
	for k in (st.m as Dictionary):
		var sp := int(st.m[k].get("sp", 0))
		var was := int(_ciws_sp.get(k, 0))
		_ciws_sp[k] = sp
		if was == 0 and sp > 0 and not ciws_active.has(int(k)):
			var b = w.entities.get(int(k))
			if b == null:
				continue
			var p: Vector2 = b.get("c7m", b.pos)
			var got: String = d.play_at(CIWS_UP_ID, p, d._visible(p))
			ciws_log.append({"at": now, "sid": int(k), "ev": "spinup", "id": got})
