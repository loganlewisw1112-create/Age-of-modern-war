extends Node
## App root (owner: agent E / hud-menus). Shows the skirmish menu, then hosts a match.
## Build UI in code; keep .tscn files minimal. Contract: docs/CONTRACTS.md section 7.

const MatchView = preload("res://presentation/match_view.gd")

var match_view: Node = null


func _ready() -> void:
	# STUB: start a default match immediately. Agent E replaces with the skirmish menu.
	start_match(SimWorld.default_config())
	_setup_autoshot()


func start_match(cfg: Dictionary) -> void:
	if match_view != null:
		match_view.queue_free()
	var w := SimWorld.new_match(cfg)
	match_view = MatchView.new()
	match_view.world = w
	add_child(match_view)


## Debug hook (KEEP: used by every visual agent and the orchestrator):
##   godot --path game -- --autoshot=C:/abs/out.png --autoshot-delay=4 [--autostart]
## Saves the viewport after N seconds of real time, then quits. --autostart skips the menu
## and starts a default match (agent E must honour it).
func _setup_autoshot() -> void:
	var shot := ""
	var delay := 4.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			shot = a.substr(11)
		elif a.begins_with("--autoshot-delay="):
			delay = float(a.substr(17))
	if shot == "":
		return
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot)
	print("AUTOSHOT saved ", shot)
	get_tree().quit()
