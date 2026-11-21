@tool
extends RefCounted

# The Room Groups tool. Each group is a RoomGroup layer (Scenes/room_group.gd) under the map's "RoomGroups"
# node, drawn with RoomGroups.png in its own tint. A drag that starts on a group adds to it, taking over any
# other group's tiles it crosses. One that starts on an empty tile makes a new group, and a right drag erases.
# Unlike the map, a group's tiles join wherever they touch, but never across an empty tile or another group.

const MapGrid := preload( "map_grid.gd" )
const SceneEdits := preload( "scene_edits.gd" )
const TEXTURE : Texture2D = preload( "res://assets/images/RoomGroups.png" )
const CONTAINER := "RoomGroups"

var _map : TileMapLayer
var _source_id : int = -1
var _target : RoomGroup # The group a left drag adds to, or null for a right drag
var _is_new : bool # A new _target only joins the scene when the drag ends
var _cells_before : Dictionary[ RoomGroup, Dictionary ] # Each group's cells, as of the start of the drag
var _data_before : Dictionary[ RoomGroup, PackedByteArray ]
var _cells_now : Dictionary[ RoomGroup, Dictionary ] # What each group shows while dragging

# Starts a drag at a cell. A right drag erases.
func begin(map: TileMapLayer, cell: Vector2i, erase: bool) -> void:
	_map = map
	_source_id = _get_source( map )
	_cells_before.clear()
	_data_before.clear()
	_cells_now.clear()
	for group in get_groups( map ):
		_cells_before[ group ] = _get_cells( group )
		_data_before[ group ] = group.tile_map_data
	_target = null if erase else get_group_at( map, cell )
	_is_new = not erase and _target == null
	if not _is_new: return
	_target = RoomGroup.new()
	_target.name = "RoomGroup"
	_target.tile_set = map.tile_set
	_target.self_modulate = _next_tint( _cells_before.size() )
	_target.set_meta( &"_edit_lock_", true ) # Moving it would shift its tiles off the map's grid
	map.add_child( _target ) # Only so it shows while dragging, commit() adds it to the scene
	_cells_before[ _target ] = {}
	_data_before[ _target ] = _target.tile_map_data

# Shows every group the way it will be if the drag covers these cells
func paint(stroke: Array[ Vector2i ]) -> void:
	for group in _cells_before:
		var cells : Dictionary = _cells_before[ group ].duplicate()
		for cell in stroke:
			if group == _target: cells[ cell ] = true
			else: cells.erase( cell )
		if cells != _cells_now.get( group, _cells_before[ group ] ): draw_group( group, cells, _source_id )
		_cells_now[ group ] = cells

# Ends the drag as one action that can be undone. A group the drag emptied is removed.
func commit(undo_redo: EditorUndoRedoManager) -> void:
	var changed : Dictionary[ RoomGroup, PackedByteArray ] = {} # Each changed group's tiles, as the drag left them
	for group in _cells_now:
		if _cells_now[ group ] != _cells_before[ group ]: changed[ group ] = group.tile_map_data
	var cells_now := _cells_now.duplicate()
	_restore() # The action makes every change itself, so it can undo them too
	if changed.is_empty():
		cancel()
		return

	undo_redo.create_action( "Paint Room Group" if _target else "Erase Room Groups", UndoRedo.MERGE_DISABLE, _map )
	for group in changed:
		if group == _target and _is_new:
			SceneEdits.add_node( undo_redo, SceneEdits.get_container( undo_redo, _map, CONTAINER, true ), group )
			undo_redo.add_do_property( group, &"tile_map_data", changed[ group ] )
		elif cells_now[ group ].is_empty():
			SceneEdits.remove_node( undo_redo, group )
		else:
			undo_redo.add_do_property( group, &"tile_map_data", changed[ group ] )
			undo_redo.add_undo_property( group, &"tile_map_data", _data_before[ group ] )
	undo_redo.commit_action()
	_is_new = false
	_target = null

# Puts every group back how it was before the drag
func cancel() -> void:
	_restore()
	if _is_new and is_instance_valid( _target ): _target.free()
	_is_new = false
	_target = null

func _restore() -> void:
	for group in _cells_now:
		if is_instance_valid( group ): group.tile_map_data = _data_before[ group ]
	if _is_new and is_instance_valid( _target ) and _target.get_parent(): _target.get_parent().remove_child( _target )
	_cells_now.clear()

# The tint of the group a left drag is painting
func get_tint() -> Color:
	return _target.self_modulate if is_instance_valid( _target ) else Color.WHITE

# Every room group on a map
static func get_groups(map: Node) -> Array[ RoomGroup ]:
	var groups : Array[ RoomGroup ] = []
	groups.assign( map.find_children( "*", "RoomGroup", true, false ) )
	return groups

# The group a cell belongs to, or null
static func get_group_at(map: Node, cell: Vector2i) -> RoomGroup:
	for group in get_groups( map ):
		if group.get_cell_source_id( cell ) != -1: return group
	return null

# Draws a group's cells, joined wherever two of them touch
static func draw_group(group: TileMapLayer, cells: Dictionary, source_id: int) -> void:
	var grid := MapGrid.new()
	for cell : Vector2i in cells:
		grid.cells[ cell ] = true
		for side : Vector2i in [ Vector2i.RIGHT, Vector2i.DOWN ]:
			if cells.has( cell + side ): grid.set_border( cell, cell + side, MapGrid.OPEN )
	group.clear()
	for cell : Vector2i in cells:
		var tile := grid.get_wanted_tile( cell, source_id, [] )
		group.set_cell( cell, tile[ 0 ], tile[ 1 ], tile[ 2 ] )

static func _get_cells(group: RoomGroup) -> Dictionary:
	var cells := {}
	for cell in group.get_used_cells(): cells[ cell ] = true
	return cells

# Hues spread out by the golden ratio, so each new group looks different from the last few
static func _next_tint(count: int) -> Color:
	return Color.from_hsv( fmod( 0.55 + count * 0.618034, 1.0 ), 0.75, 1.0 )

# The id of RoomGroups.png in the map's tile set. A tile set that doesn't have it yet gets it added (on the
# museum's tile set that makes it atlas 1), laid out like MuseumSet.png.
static func _get_source(map: TileMapLayer) -> int:
	var id := MapGrid.find_source( map, TEXTURE )
	if id != -1: return id
	id = MapGrid.add_source( map.tile_set, TEXTURE )
	var path := map.tile_set.resource_path
	if path.begins_with( "res://" ) and not path.contains( "::" ): ResourceSaver.save( map.tile_set )
	print( "Map Painter: added %s to the map's tile set as atlas %d, for room groups" % [ TEXTURE.resource_path.get_file(), id ] )
	return id
