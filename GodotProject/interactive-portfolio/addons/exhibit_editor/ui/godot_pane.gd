@tool
extends "preview_pane.gd"

# A preview of one of the game's own scenes: ui_exhibit.tscn or Entry.tscn. The picture is the
# PreviewStage that godot_preview.gd keeps up to date from the preview helper.

const GodotPreview := preload( "../preview/godot/godot_preview.gd" )
const Stage := preload( "../preview/godot/preview_stage.gd" )

var _preview : GodotPreview
var _pane_id : String
var _stage : Stage

# `sized` adds the boxes for the screen size the scene is laid out at. A 3D scene has no use for them.
func _init(preview: GodotPreview, pane_id: String, pane_title: String, sized: bool) -> void:
	super()
	_preview = preview
	_pane_id = pane_id
	_stage = preview.get_stage( pane_id )
	title = pane_title
	if sized: add_size_boxes( _stage.virtual_size, "The screen size the scene is laid out at, in pixels. The game's own window is %d x %d." % [ _stage.virtual_size.x, _stage.virtual_size.y ] )
	_preview.changed.connect( refresh )
	_stage.redrawn.connect( func() -> void: _view.queue_redraw() )

func _get_texture() -> Texture2D:
	return _stage.get_texture() if _stage.mode != Stage.MODE_NONE else null

func _get_content_size() -> Vector2:
	return Vector2( _stage.virtual_size ) if _stage.mode == Stage.MODE_2D else Vector2.ZERO

func _set_available_size(pixels: Vector2i) -> void:
	_stage.set_available_size( pixels )

func _is_running() -> bool:
	return _preview.state == GodotPreview.RUNNING

func _is_up_to_date() -> bool:
	return _preview.is_up_to_date( _pane_id )

func _get_message() -> String:
	if _preview.state == GodotPreview.RUNNING: return "" if _stage.mode != Stage.MODE_NONE else "Waiting for the scene..."
	return _preview.status

func _can_restart() -> bool:
	return _preview.state == GodotPreview.FAILED or _preview.state == GodotPreview.STOPPED

func _restart() -> void:
	_preview.restart()

func _reload() -> void:
	if _preview.state == GodotPreview.RUNNING: _preview.reset_pane( _pane_id )
	else: _preview.restart()

func _get_reports() -> Array:
	return _preview.get_reports( _pane_id )

func _on_size_edited(new_size: Vector2i) -> void:
	_preview.set_virtual_size( _pane_id, new_size )
	_update_layout()

func _send_mouse(spot: Vector2, relative: Vector2, moved: bool, pressed: bool, buttons: int) -> void:
	# Only UI scenes take clicks this way. Nothing in a 3D exhibit listens for them yet.
	if _stage.mode == Stage.MODE_2D: _preview.send_mouse( _pane_id, spot, relative, moved, MOUSE_BUTTON_NONE if moved else MOUSE_BUTTON_LEFT, pressed, buttons )

