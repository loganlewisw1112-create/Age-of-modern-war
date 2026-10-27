extends Control
## G7 OPSUI7: live deployment tracker (master scope 6.11): per deploying team the arming progress (scan -> jam -> arm,
## segmented, with the current phase fill), the dome charge (ring gauge, ON / RECHARGING), time left (T-mm:ss, from
## CounterNanite.need_ticks; a stall freezes it and shows the reason) and incoming forces (visible hostiles within
## OpsData.INCOMING_R of the site: count, nearest, ETA, top kinds). Values come from OpsData.deployment(w, tid), which
## reads the same fields the sim advances (t.dep.prog / phase, a7.dome), so the tracker matches the sim exactly.
## Two forms:
##   tab (inside the operations room): tablet-drawn blocks, click one to jump the camera to the site;
##   compact lines on the PROTOCOL HUD card (protocol_advisor.gd uses collect() + lines()).
## Display only.

const S = preload("res://presentation/ui7/ops_style.gd")
const D = preload("res://presentation/ui7/ops_data.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")

const BLOCK_H := 136.0

var hub = null
var deps: Array = []          # OpsData.deployment dicts, team order
var _rects: Array = []        # [Rect2, site] for click-to-jump


func _ready() -> void:
	name = "DeployTracker"
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Deployments of side fid (team order).
static func collect(w: SimWorld, fid: int) -> Array:
	var out := []
	if w == null:
		return out
	for tid in D.team_ids(w, fid):
		var d := D.deployment(w, int(tid))
		if not d.is_empty():
			var row := D.team_row(w, int(tid))
			d.name = String(row.get("name", "Team"))
			out.append(d)
	return out


func refresh() -> void:
	var w: SimWorld = hub.world() if hub != null else null
	deps = collect(w, int(hub.pf()) if hub != null else 0)
	custom_minimum_size.y = maxf(BLOCK_H * float(maxi(deps.size(), 1)) + 8.0, 120.0)
	queue_redraw()


## Plain text lines of one deployment (tests, playtest log, compact card).
static func lines(d: Dictionary) -> Dictionary:
	var inc: Dictionary = d.get("incoming", {})
	var dm: Dictionary = d.get("dome", {})
	var dome := "no dome"
	if bool(dm.get("has", false)):
		dome = "DOME %d%% %s" % [int(round(float(dm.charge) * 100.0)), "ON" if bool(dm.on) else ("RECHARGING %ds" % int(dm.recharge_s) if bool(dm.broken) else "STANDBY")]
	var it := "no contacts"
	if int(inc.get("n", 0)) > 0:
		var ks := []
		for k in inc.kinds:
			ks.append("%dx %s" % [int(k[1]), String(k[0])])
		it = "%d INCOMING  nearest %dm  ETA %s  (%s)" % [int(inc.n), int(float(inc.nearest) * 4.0), D.fmt_s(float(inc.eta_s)), ", ".join(PackedStringArray(ks))]
	var tl := "T-%s" % D.fmt_s(float(d.get("time_left_s", 0.0)))
	if String(d.get("stalled", "")) != "":
		tl += "  STALLED: " + String(d.stall_text)
	return {"head": "%s  //  %s PACKAGE  //  GRID %s" % [String(d.get("name", "TEAM")).to_upper(), String(d.get("package", "purge")).to_upper(), String(d.get("grid", "--"))],
		"phase": "%s  %d%%   (arming %d%%)" % [String(d.get("phase_name", "")), int(round(float(d.get("phase_frac", 0.0)) * 100.0)), int(round(float(d.get("arm_frac", 0.0)) * 100.0))],
		"time": tl, "dome": dome, "incoming": it}


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	_rects = []
	if deps.is_empty():
		S.text(self, Vector2(16, 34), "NO ACTIVE DEPLOYMENTS", S.DIM, 16, true)
		S.text(self, Vector2(16, 58), "Order a team to deploy a package (cn_deploy): its arming, dome and incoming forces show here.", S.DIM, 13)
		return
	var y := 4.0
	for d in deps:
		var b := Rect2(8.0, y, r.size.x - 16.0, BLOCK_H - 10.0)
		_rects.append([b, d.site])
		_block(b, d)
		y += BLOCK_H


func _block(b: Rect2, d: Dictionary) -> void:
	var L := lines(d)
	var stalled := String(d.get("stalled", "")) != ""
	draw_rect(b, Color(S.PHOS, 0.05))
	draw_rect(b, Color(S.PHOS, 0.35), false, 1.0)
	S.unit_icon(self, b.position + Vector2(20, 18), "strike", S.OWN, 8.0)
	S.text(self, b.position + Vector2(40, 23), String(L.head), S.PHOS, 14, true)
	# segmented arming bar: scan | jam | arm
	var gx := b.position.x + 12.0
	var gw := b.size.x - 150.0
	var gy := b.position.y + 36.0
	var ph := String(d.get("phase", "scan"))
	var ix := D.PHASES.find(ph)
	for i in 3:
		var seg := Rect2(gx + (gw / 3.0) * float(i) + 2.0, gy, gw / 3.0 - 4.0, 16.0)
		var fill := 0.0
		if ph == "hero" or i < ix:
			fill = 1.0
		elif i == ix:
			fill = float(d.get("phase_frac", 0.0))
		draw_rect(seg, Color(S.PHOS, 0.10))
		draw_rect(Rect2(seg.position, Vector2(seg.size.x * fill, seg.size.y)), Color(S.RED if stalled and i == ix else S.AMBER, 0.85))
		draw_rect(seg, Color(S.PHOS, 0.5), false, 1.0)
		S.text(self, seg.position + Vector2(5, 12), String(D.PHASE_NAME[D.PHASES[i]]), S.SCREEN if fill >= 0.45 else Color(S.PHOS, 0.8), 11, true)
	S.text(self, Vector2(gx, gy + 34.0), String(L.phase), S.PHOS, 13)
	S.text(self, Vector2(gx, gy + 54.0), String(L.time), S.RED if stalled else S.AMBER, 15, true)
	S.text(self, Vector2(gx, gy + 72.0), String(L.incoming), S.HOSTILE if int(d.incoming.get("n", 0)) > 0 else S.DIM, 13)
	# dome ring gauge
	var c := Vector2(b.end.x - 64.0, b.position.y + 58.0)
	var dm: Dictionary = d.get("dome", {})
	draw_arc(c, 34.0, 0.0, TAU, 48, Color(S.PHOS, 0.18), 6.0)
	if bool(dm.get("has", false)):
		var col := S.CYAN if bool(dm.on) else (S.RED if bool(dm.broken) else S.AMBER)
		draw_arc(c, 34.0, -PI * 0.5, -PI * 0.5 + TAU * float(dm.charge), 48, col, 6.0)
	S.text(self, c + Vector2(-S.text_w("DOME", 11) * 0.5, -4.0), "DOME", S.DIM, 11)
	var pct := "%d%%" % int(round(float(dm.get("charge", 0.0)) * 100.0)) if bool(dm.get("has", false)) else "--"
	S.text(self, c + Vector2(-S.text_w(pct, 14, true) * 0.5, 13.0), pct, S.PHOS, 14, true)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and hub != null:
		for it in _rects:
			if (it[0] as Rect2).has_point(ev.position):
				hub.jump_to(Vector2(it[1]), [])
				accept_event()
				return
