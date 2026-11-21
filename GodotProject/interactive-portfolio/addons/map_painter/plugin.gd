@tool
extends EditorPlugin

# Tools for the museum map, which is any TileMapLayer that uses MuseumSet.png. Its bottom tab has three:
# - Map draws rooms and halls by dragging. Tiles only join where a drag crosses between them, and each
#   tile's shape and rotation is worked out from what it's joined to (see map_grid.gd).
# - Room Groups marks blocks of tiles that are built as one scene instead of as rooms (room_groups.gd).
# - Props places props like exhibits (prop_placer.gd).

const MapGrid := preload( "map_grid.gd" )
const RoomGroups := preload( "room_groups.gd" )
const PropPlacer := preload( "prop_placer.gd" )
const SETTINGS_SECTION : String = "map_painter"

enum Tool { MAP, GROUPS, PROPS }
const TOOL_NAMES : Array[ String ] = [ "Map", "Room Groups", "Props" ]
const HELP : Array[ String ] = [
	("Left-drag to draw, right-drag to erase. Hold Shift as you start a drag to use the other mode, and press Esc to cancel one.\n" +
	"Path lays a hallway through every tile you pass over, and dragging back shortens it. Rectangle makes one room from the box you drag out (one tile wide makes a hallway).\n" +
	"Tiles only join where a drag crosses the border between them, so drawing next to a tile never connects to it."),
	("Left-drag to paint a room group, right-drag to erase. Shift and Esc work the same as for the map.\n" +
	"A drag that starts on a group adds to it, taking over any other group's tiles it crosses. One that starts on an empty tile makes a new group. A group's tiles join wherever they touch.\n" +
	"The rooms under a group aren't built. Select the group (under RoomGroups in the Scene dock) to give it the scene to build instead, with its origin at the group's top-left corner. Props on a group are still built."),
	("Pick what to place. For a wall prop like an exhibit, press on a tile and drag toward one of its walls (drag back to cancel). Other props go where you let go.\n" +
	"Click a prop to select it. A new prop copies the selected prop's settings if it's the same type, and a grouped exhibit joins the end of its group's queue.\n" +
	"Right-click a prop and let go on it to remove it: it turns red first, and moving off it backs out. Hold Alt to skip the confirmation."),
]

var _dock : EditorDock
var _enabled_button : CheckButton
var _tool_buttons : Array[ Button ]
var _path_button : Button
var _rect_button : Button
var _type_button : OptionButton
var _help : Label
var _tool : Tool = Tool.MAP
var _groups := RoomGroups.new()
var _placer := PropPlacer.new()

var _layer : TileMapLayer
var _source_id : int = -1
var _selected : bool
var _hover_cell : Vector2i
var _hovering : bool

# The drag in progress, if _stroke_button isn't MOUSE_BUTTON_NONE. The Map and Room Groups tools both drag.
var _stroke_button : MouseButton = MOUSE_BUTTON_NONE
var _stroke_is_rect : bool
var _stroke_cells : Array[ Vector2i ] # The path so far, or the rectangle's two corners
var _last_position : Vector2 # In cells
var _grid_before : MapGrid
var _tiles_before : Dictionary[ Vector2i, Array ]
var _data_before : PackedByteArray
var _changed : Dictionary # Cells the drag has changed so far

func _enter_tree() -> void:
	_build_dock()

func _exit_tree() -> void:
	_cancel_stroke()
	_placer.cancel()
	remove_dock( _dock )
	_dock.queue_free()

# The map, or a prop or room group on it, so that selecting one of those keeps the tools open
func _handles(object: Object) -> bool:
	return _find_map( object ) != null

func _edit(object: Object) -> void:
	_cancel_stroke()
	_placer.cancel()
	_layer = _find_map( object )
	_source_id = MapGrid.find_source( _layer ) if _layer else -1
	_hovering = false

# The museum map an object is part of: the map itself, or the map above a prop or room group
static func _find_map(object: Object) -> TileMapLayer:
	var node := object as Node
	var root := EditorInterface.get_edited_scene_root()
	while node:
		if node is TileMapLayer and not node is RoomGroup and MapGrid.find_source( node ) != -1: return node
		if node == root: break
		node = node.get_parent()
	return null

func _make_visible(visible: bool) -> void:
	_selected = visible
	if visible:
		if _tool == Tool.PROPS: _list_prop_types() # Picks up any new kinds of prop
		_dock.open()
		# Deferred so it runs after the TileMap tab opens, leaving this tab in front of it.
		_show_dock.call_deferred()
	else:
		_cancel_stroke()
		_placer.cancel()
		_dock.close()

func _show_dock() -> void:
	if _selected and _enabled_button.button_pressed: _dock.make_visible()

# Only paints while this tab is showing, the same rule the TileMap tab follows, so the two never paint at once.
func _is_active() -> bool:
	return _enabled_button.button_pressed and is_instance_valid( _layer ) and _source_id != -1 and _dock.is_visible_in_tree()

#region Input

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _is_active():
		_cancel_stroke()
		_placer.cancel()
		return false

	var mouse := event as InputEventMouse
	if mouse: _set_hover( Vector2i( _to_cells( mouse.position ).floor() ) )
	if _tool == Tool.PROPS:
		var used := _placer.input( event, _layer, _to_map( mouse.position ) if mouse else Vector2.ZERO )
		if used: update_overlays()
		return used

	var motion := event as InputEventMouseMotion
	if motion:
		if _stroke_button == MOUSE_BUTTON_NONE: return false
		# The button came up somewhere we didn't hear about, like outside the editor window.
		var mask := MOUSE_BUTTON_MASK_LEFT if _stroke_button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		if not motion.button_mask & mask:
			_end_stroke()
			return false
		_extend_stroke( _to_cells( motion.position ) )
		return true

	var button := event as InputEventMouseButton
	if button and (button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT):
		if button.pressed:
			# A second press without a release means the release got lost, so that drag is finished.
			if button.button_index == _stroke_button: _end_stroke()
			if _stroke_button == MOUSE_BUTTON_NONE: _begin_stroke( button.button_index, button.shift_pressed, _to_cells( button.position ) )
		elif button.button_index == _stroke_button:
			_end_stroke()
		return true

	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE and _stroke_button != MOUSE_BUTTON_NONE:
		_cancel_stroke()
		return true

	return false

func _layer_to_viewport() -> Transform2D:
	return _layer.get_viewport_transform() * _layer.get_global_transform()

# A position in the 2D viewport, in the layer's own pixels
func _to_map(viewport_position: Vector2) -> Vector2:
	return _layer_to_viewport().affine_inverse() * viewport_position

# A position in the 2D viewport, in the layer's cells, so ( 2.5, 0.5 ) is the middle of cell ( 2, 0 ).
func _to_cells(viewport_position: Vector2) -> Vector2:
	return _to_map( viewport_position ) / Vector2( _layer.tile_set.tile_size )

func _set_hover(cell: Vector2i) -> void:
	if _hovering and cell == _hover_cell: return
	_hover_cell = cell
	_hovering = true
	update_overlays()

func _on_viewport_mouse_exited() -> void:
	_hovering = false
	update_overlays()

#endregion

#region Strokes

func _begin_stroke(button: MouseButton, use_other_mode: bool, position: Vector2) -> void:
	_stroke_button = button
	_stroke_is_rect = _rect_button.button_pressed != use_other_mode
	var cell := Vector2i( position.floor() )
	_stroke_cells = [ cell ]
	if _stroke_is_rect: _stroke_cells.append( cell )
	_last_position = position
	if _tool == Tool.GROUPS:
		_groups.begin( _layer, cell, button == MOUSE_BUTTON_RIGHT )
	else:
		_grid_before = MapGrid.new()
		_grid_before.read_layer( _layer, _source_id )
		_tiles_before.clear()
		for used_cell in _layer.get_used_cells(): _tiles_before[ used_cell ] = MapGrid.get_tile( _layer, used_cell )
		_data_before = _layer.tile_map_data
		_changed.clear()
	_update_stroke()

func _extend_stroke(position: Vector2) -> void:
	var old_cells := _stroke_cells.duplicate()
	if _stroke_is_rect: _stroke_cells[ 1 ] = Vector2i( position.floor() )
	else: MapGrid.extend_path( _stroke_cells, _last_position, position )
	_last_position = position
	if _stroke_cells != old_cells: _update_stroke()

# Draws the map as it will look if the drag ends here. Each update starts over from the map as it
# was before the drag, so shrinking a rectangle or backing up a path puts the old tiles back.
func _update_stroke() -> void:
	var stroke := _get_stroke_cells()
	if _tool == Tool.GROUPS:
		_groups.paint( stroke )
		update_overlays()
		return

	var grid := _grid_before.copy()
	if _stroke_button == MOUSE_BUTTON_RIGHT: grid.erase( stroke )
	elif _stroke_is_rect: grid.add_rect( MapGrid.get_rect( _stroke_cells[ 0 ], _stroke_cells[ 1 ] ) )
	else: grid.add_path( _stroke_cells )

	# Cells changed last time get redrawn in case they're back to normal. A tile also depends on the
	# borders at its corners, so the cells around the stroke get redrawn too.
	var to_draw := _changed
	for cell in stroke:
		for y in range( -1, 2 ):
			for x in range( -1, 2 ):
				to_draw[ cell + Vector2i( x, y ) ] = true
	_changed = grid.draw( _layer, _source_id, _tiles_before, to_draw )
	update_overlays()

func _get_stroke_cells() -> Array[ Vector2i ]:
	if not _stroke_is_rect: return _stroke_cells
	var rect := MapGrid.get_rect( _stroke_cells[ 0 ], _stroke_cells[ 1 ] )
	var rect_cells : Array[ Vector2i ] = []
	for y in range( rect.position.y, rect.end.y ):
		for x in range( rect.position.x, rect.end.x ):
			rect_cells.append( Vector2i( x, y ) )
	return rect_cells

func _end_stroke() -> void:
	if _tool == Tool.GROUPS:
		_groups.commit( get_undo_redo() )
	elif not _changed.is_empty():
		var undo_redo := get_undo_redo()
		undo_redo.create_action( "Erase Map Tiles" if _stroke_button == MOUSE_BUTTON_RIGHT else "Draw Map Tiles", UndoRedo.MERGE_DISABLE, _layer )
		undo_redo.add_do_property( _layer, &"tile_map_data", _layer.tile_map_data )
		undo_redo.add_undo_property( _layer, &"tile_map_data", _data_before )
		# The drag already drew the tiles, so the action only needs recording.
		undo_redo.commit_action( false )
	_stroke_button = MOUSE_BUTTON_NONE
	update_overlays()

func _cancel_stroke() -> void:
	if _stroke_button == MOUSE_BUTTON_NONE: return
	_stroke_button = MOUSE_BUTTON_NONE
	if _tool == Tool.GROUPS: _groups.cancel()
	elif is_instance_valid( _layer ): _layer.tile_map_data = _data_before
	update_overlays()

#endregion

#region Dock and overlay

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	if not viewport_control.mouse_exited.is_connected( _on_viewport_mouse_exited ):
		viewport_control.mouse_exited.connect( _on_viewport_mouse_exited )
	if not _is_active(): return

	var area : Rect2i
	var wall_prop_cell : Variant = _placer.get_wall_prop_cell() if _tool == Tool.PROPS else null
	if wall_prop_cell != null: area = Rect2i( wall_prop_cell, Vector2i.ONE )
	elif _stroke_button != MOUSE_BUTTON_NONE and _stroke_is_rect: area = MapGrid.get_rect( _stroke_cells[ 0 ], _stroke_cells[ 1 ] )
	elif _hovering: area = Rect2i( _hover_cell, Vector2i.ONE )
	else: return

	var tile_size := Vector2( _layer.tile_set.tile_size )
	var to_viewport := _layer_to_viewport()
	var outline := PackedVector2Array()
	for corner : Vector2i in [ area.position, Vector2i( area.end.x, area.position.y ), area.end, Vector2i( area.position.x, area.end.y ), area.position ]:
		outline.append( to_viewport * (Vector2( corner ) * tile_size) )
	var color := EditorInterface.get_editor_theme().get_color( &"accent_color", &"Editor" )
	if _stroke_button == MOUSE_BUTTON_RIGHT: color = Color( 1.0, 0.4, 0.4 )
	elif _stroke_button == MOUSE_BUTTON_LEFT and _tool == Tool.GROUPS: color = _groups.get_tint()
	viewport_control.draw_polyline( outline, color, 2.0 )

func _build_dock() -> void:
	_dock = EditorDock.new()
	_dock.title = "Map Painter"
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL
	# Like the TileMap tab, it only shows up while a map is selected.
	_dock.transient = true
	_dock.global = false

	var rows := VBoxContainer.new()
	_dock.add_child( rows )
	var toolbar := HBoxContainer.new()
	rows.add_child( toolbar )

	_enabled_button = CheckButton.new()
	_enabled_button.text = "Enabled"
	_enabled_button.button_pressed = _get_setting( "enabled", true )
	_enabled_button.toggled.connect( _on_enabled_toggled )
	toolbar.add_child( _enabled_button )
	toolbar.add_child( VSeparator.new() )

	var tools := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var button := _add_mode_button( toolbar, TOOL_NAMES[ i ], tools )
		button.pressed.connect( _set_tool.bind( i ) )
		_tool_buttons.append( button )
	toolbar.add_child( VSeparator.new() )

	var modes := ButtonGroup.new()
	_path_button = _add_mode_button( toolbar, "Path", modes )
	_rect_button = _add_mode_button( toolbar, "Rectangle", modes )
	# Map and Room Groups each remember their own mode
	_rect_button.toggled.connect( func(on: bool) -> void: _set_setting( _get_rect_key(), on ) )

	_type_button = OptionButton.new()
	_type_button.tooltip_text = "What the left button places"
	_type_button.item_selected.connect( _on_type_selected )
	toolbar.add_child( _type_button )

	_help = Label.new()
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child( _help )

	_set_tool( _get_setting( "tool", Tool.MAP ) )
	add_dock( _dock )
	_dock.close()

func _add_mode_button(parent: Control, text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.theme_type_variation = &"FlatButton"
	parent.add_child( button )
	return button

func _set_tool(tool: int) -> void:
	_cancel_stroke()
	_placer.cancel()
	tool = clampi( tool, 0, TOOL_NAMES.size() - 1 )
	_tool = tool as Tool
	_set_setting( "tool", tool )
	_tool_buttons[ tool ].button_pressed = true
	var is_rect : bool = _get_setting( _get_rect_key(), _tool == Tool.GROUPS )
	(_rect_button if is_rect else _path_button).button_pressed = true
	_path_button.visible = _tool != Tool.PROPS
	_rect_button.visible = _tool != Tool.PROPS
	_type_button.visible = _tool == Tool.PROPS
	if _tool == Tool.PROPS: _list_prop_types()
	_help.text = HELP[ _tool ]
	update_overlays()

func _get_rect_key() -> String:
	return "group_rectangle" if _tool == Tool.GROUPS else "rectangle"

# Lists every kind of prop. A new kind shows up once its script has a class_name and isn't @abstract.
func _list_prop_types() -> void:
	var chosen : String = _get_setting( "prop_type", "" )
	_type_button.clear()
	for script in PropPlacer.find_types():
		_type_button.add_item( String( script.get_global_name() ).trim_suffix( "Display" ) )
		_type_button.set_item_metadata( -1, script.resource_path )
		if script.resource_path == chosen: _type_button.select( _type_button.item_count - 1 )
	_on_type_selected( _type_button.selected )

func _on_type_selected(index: int) -> void:
	var path : String = _type_button.get_item_metadata( index ) if index >= 0 else ""
	_placer.type = load( path ) if path else null
	if path: _set_setting( "prop_type", path )

func _on_enabled_toggled(on: bool) -> void:
	_set_setting( "enabled", on )
	_cancel_stroke()
	_placer.cancel()
	update_overlays()

func _get_setting(key: String, default: Variant) -> Variant:
	return EditorInterface.get_editor_settings().get_project_metadata( SETTINGS_SECTION, key, default )

func _set_setting(key: String, value: Variant) -> void:
	EditorInterface.get_editor_settings().set_project_metadata( SETTINGS_SECTION, key, value )

#endregion
