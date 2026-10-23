class_name ArtCatalog
extends RefCounted
## STUB (owner: agent C / art). Loads generated PNGs from res://assets/generated/.
## Contract: docs/CONTRACTS.md §7 ArtCatalog. Missing art returns a magenta placeholder.

static var _placeholder: Texture2D = null


static func load_all() -> void:
	pass


static func _ph() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


static func terrain_texture(code: int, variant: int) -> Texture2D:
	return _ph()


static func terrain_variants(code: int) -> int:
	return 1


static func decor(code: int, cell: Vector2i) -> Dictionary:
	return {}


static func entity_sprite(e: Dictionary, team_color: Color, anim_time: float) -> Dictionary:
	return {"texture": _ph(), "offset": Vector2(-8, -16), "flip_h": false}


static func effect_frames(name: String) -> Array:
	return [_ph()]


static func icon(id: String) -> Texture2D:
	return _ph()


static func selection_ring(size_tiles: float) -> Texture2D:
	return _ph()


static func fog_tile(kind: String) -> Texture2D:
	return _ph()
