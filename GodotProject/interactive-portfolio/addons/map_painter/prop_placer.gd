@tool
extends RefCounted

# The Props tool. The left button places a prop of the chosen type (a PropDisplay, see map_prop_icon.gd):
# a wall prop by pressing on a tile and dragging toward one of its walls, any other prop where the button
# comes up. Pressing on a prop selects it instead. The right button removes the prop it went down on, but
# only once it comes back up over that prop, and after asking first unless Alt is held. Props go under the
# map's "Props" node.

const SceneEdits := preload( "scene_edits.gd" )
const CONTAINER := "Props"
# How far a wall prop's drag has to go, in tiles, to pick a wall. Coming back closer than this drops it again.
const PICK_DISTANCE := 0.25

# The kind of prop the left button places: a PropDisplay script, or null for none
var type : Script

var _map : TileMapLayer
var _placing : PropDisplay # The prop being placed, while the left button is down. It's only a preview until then.
var _press : Vector2 # Where the left button went down, in map pixels
var _marked : PropDisplay # The prop the right button went down on

# Every kind of prop there is: the PropDisplay classes that aren't @abstract
static func find_types() -> Array[ Script ]:
	var classes := ProjectSettings.get_global_class_list()
	var bases : Dictionary[ StringName, StringName ] = {}
	for info in classes: bases[ info[ "class" ] ] = info[ "base" ]
	var types : Array[ Script ] = []
	for info in classes:
		if info.get( "is_abstract", false ): continue
		var base : StringName = info[ "base" ]
		while bases.has( base ) and base != &"PropDisplay": base = bases[ base ]
		if base == &"PropDisplay": types.append( load( info[ "path" ] ) )
	return types

# The prop whose marker is under a point on the map (in map pixels), or null
static func prop_at(map: Node, point: Vector2) -> PropDisplay:
	var found : PropDisplay
	var closest := PropDisplay.RADIUS + 0.5
	for prop : PropDisplay in map.find_children( "*", "PropDisplay", true, false ):
		var distance := point.distance_to( prop.get_marker_position() )
		if distance < closest:
			found = prop
			closest = distance
	return found

# Handles an event on the 2D viewport, given the mouse position in the map's pixels. True if it was used.
func input(event: InputEvent, map: TileMapLayer, point: Vector2) -> bool:
	_map = map
	var motion := event as InputEventMouseMotion
	if motion:
		if _placing:
			# The button came up somewhere we didn't hear about, like outside the editor window
			if not motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
				cancel()
				return false
			_move( point )
			return true
		if _marked:
			if not motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				cancel()
				return false
			# Red only while the mouse is still on it, so moving off backs out
			_marked.marked_for_removal = prop_at( map, point ) == _marked
			return true
		return false

	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed and not _placing and not _marked:
			var hit := prop_at( map, point )
			if hit: _select( hit )
			elif type: _begin( point )
		elif not button.pressed and _placing:
			_finish()
		return true
	if button and button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed and not _placing and not _marked:
			_marked = prop_at( map, point )
			if _marked: _marked.marked_for_removal = true
		elif not button.pressed and _marked:
			var prop := _marked
			_marked = null
			if prop_at( map, point ) == prop: _remove( prop, button.alt_pressed )
			else: prop.marked_for_removal = false
		return true

	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE and (_placing or _marked):
		cancel()
		return true
	return false

# Drops a placement or removal in progress
func cancel() -> void:
	if is_instance_valid( _placing ):
		if _placing.get_parent(): _placing.get_parent().remove_child( _placing )
		_placing.free()
	_placing = null
	if is_instance_valid( _marked ): _marked.marked_for_removal = false
	_marked = null

# The tile a wall prop is being placed in, for the Map Painter to outline, or null
func get_wall_prop_cell() -> Variant:
	return _placing.get_cell() if _placing is EdgePropDisplay else null

func _begin(point: Vector2) -> void:
	_press = point
	_placing = type.new()
	_placing.name = _placing.get_prop_type()
	_placing.draw_name = _placing.get_prop_type()
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() == 1 and selected[ 0 ].get_script() == type: _placing.copy_settings( selected[ 0 ] )
	_placing.draw_pos = point
	_placing.set_meta( &"_edit_lock_", true ) # It only moves with this tool, so it stays lined up with its marker
	_map.add_child( _placing, true )
	_move( point )

func _move(point: Vector2) -> void:
	var wall_prop := _placing as EdgePropDisplay
	if not wall_prop:
		_placing.draw_pos = point # A CenteredPropDisplay snaps to its tile's middle by itself
		return
	# A wall prop stays in the tile it was pressed in, and faces away from the wall the drag heads toward
	var drag := (point - _press) / wall_prop.get_tile_size()
	wall_prop.visible = drag.length() >= PICK_DISTANCE
	if not wall_prop.visible: return
	var wall := Vector2( signf( drag.x ), 0.0 ) if absf( drag.x ) > absf( drag.y ) else Vector2( 0.0, signf( drag.y ) )
	wall_prop.start_direction = EdgePropDisplay.FACING.find( -wall )

func _finish() -> void:
	var prop := _placing
	_placing = null
	var placed := prop.visible # A wall prop that never picked a wall isn't placed
	prop.draw_pos = prop.get_marker_position()
	_map.remove_child( prop )
	if not placed:
		prop.free()
		return
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action( "Place %s" % prop.get_prop_type(), UndoRedo.MERGE_DISABLE, _map )
	SceneEdits.add_node( undo_redo, SceneEdits.get_container( undo_redo, _map, CONTAINER ), prop )
	undo_redo.commit_action()
	_select( prop )

func _remove(prop: PropDisplay, without_asking: bool) -> void:
	if without_asking:
		_do_remove( prop )
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove Prop"
	dialog.dialog_text = "Remove %s?" % prop.describe()
	dialog.ok_button_text = "Remove"
	dialog.confirmed.connect( _do_remove.bind( prop ) )
	# However the dialog closes, the prop goes back to its own color
	dialog.visibility_changed.connect( func() -> void:
		if dialog.visible: return
		if is_instance_valid( prop ): prop.marked_for_removal = false
		dialog.queue_free() )
	EditorInterface.popup_dialog_centered( dialog )

func _do_remove(prop: PropDisplay) -> void:
	if not is_instance_valid( prop ) or not prop.is_inside_tree(): return
	prop.marked_for_removal = false
	# A removed node can't stay selected, so the map gets selected instead, which keeps the Map Painter open
	if prop in EditorInterface.get_selection().get_selected_nodes() and is_instance_valid( _map ): _select( _map )
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action( "Remove %s" % prop.get_prop_type(), UndoRedo.MERGE_DISABLE, prop )
	SceneEdits.remove_node( undo_redo, prop )
	undo_redo.commit_action()

static func _select(node: Node) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node( node )
