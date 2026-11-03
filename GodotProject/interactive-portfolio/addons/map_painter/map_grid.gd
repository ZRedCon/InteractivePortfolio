@tool
extends RefCounted

# The model behind the Map Painter tool. A map is a set of placed cells plus the borders between
# them, and each border is a wall, a door, or open floor. A cell's tile (and its rotation) follows
# from the borders around it, and the borders can be read back off the tiles, so the TileMapLayer
# is the only place the map is stored.

const MapGrid := preload( "map_grid.gd" )
const TEXTURE : Texture2D = preload( "res://assets/images/MuseumSet.png" )

enum { WALL, DOOR, OPEN }

const SIDES : Array[ Vector2i ] = [ Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT ]

const FLIP_H : int = TileSetAtlasSource.TRANSFORM_FLIP_H
const FLIP_V : int = TileSetAtlasSource.TRANSFORM_FLIP_V
const TRANSPOSE : int = TileSetAtlasSource.TRANSFORM_TRANSPOSE

# Each tile in MuseumSet.png as a 3x3 picture, rows top to bottom: the middle is the tile, the edges
# are its sides and the corners are its corners. "." is floor, "#" is wall.
const TILES : Dictionary[ Vector2i, String ] = {
	Vector2i( 6, 1 ): "### #.# ###", # Lone tile
	Vector2i( 4, 0 ): "### #.# #.#", # Hall end
	Vector2i( 5, 0 ): "#.# #.# #.#", # Hall
	Vector2i( 4, 1 ): "#.# ..# ###", # Hall corner
	Vector2i( 3, 0 ): "### ... #.#", # 3-way intersection
	Vector2i( 3, 1 ): "#.# ... #.#", # 4-way intersection
	Vector2i( 0, 0 ): "### #.. #..", # Room corner
	Vector2i( 1, 0 ): "### ... ...", # Room wall
	Vector2i( 2, 0 ): "... ... ...", # Room floor
	Vector2i( 5, 1 ): "#.. ... ...", # Room floor at an inside corner
	Vector2i( 2, 1 ): "#.. ... ..#", # Room floor between two inside corners
	Vector2i( 1, 1 ): "#.# ... ...", # Room wall with a door
	Vector2i( 6, 0 ): "#.# ..# ..#", # Room corner with a door
	Vector2i( 0, 1 ): "#.# ... ..#", # Room corner with two doors
}

# Tried in this order when picking how to rotate a tile. The first four keep the yellow pattern lined
# up with the tiles around it, so the rest are only used for shapes the first four can't make.
const TRANSFORMS : Array[ int ] = [ 0, FLIP_H | FLIP_V, TRANSPOSE, FLIP_H | FLIP_V | TRANSPOSE,
		FLIP_H | TRANSPOSE, FLIP_V | TRANSPOSE, FLIP_H, FLIP_V ]

static var _tile_for_shape : Dictionary[ String, Vector3i ] # Shape -> ( atlas x, atlas y, alternative tile )
static var _shape_for_tile : Dictionary[ Vector3i, String ]

var cells : Dictionary[ Vector2i, bool ] # Placed cells. False marks a tile this tool doesn't know, which it never redraws.
var borders : Dictionary[ Vector3i, int ] # ( x, y, 0 ) is the border east of cell ( x, y ), ( x, y, 1 ) the one south of it. Missing borders are walls.

static func _static_init() -> void:
	for transform in TRANSFORMS:
		for atlas in TILES:
			var tile := Vector3i( atlas.x, atlas.y, transform )
			var shape := _transform_shape( TILES[ atlas ].replace( " ", "" ), transform )
			_shape_for_tile[ tile ] = shape
			if not _tile_for_shape.has( shape ): _tile_for_shape[ shape ] = tile

#region Tiles

# The id of the MuseumSet.png atlas in the layer's tile set, or -1 if it doesn't have one.
static func find_source(layer: TileMapLayer) -> int:
	if layer.tile_set == null: return -1
	for i in layer.tile_set.get_source_count():
		var source_id := layer.tile_set.get_source_id( i )
		var source := layer.tile_set.get_source( source_id ) as TileSetAtlasSource
		if source and source.texture == TEXTURE: return source_id
	return -1

# A cell's tile as [ source_id, atlas_coords, alternative_tile ], or [] for an empty cell.
static func get_tile(layer: TileMapLayer, cell: Vector2i) -> Array:
	var source_id := layer.get_cell_source_id( cell )
	if source_id == -1: return []
	return [ source_id, layer.get_cell_atlas_coords( cell ), layer.get_cell_alternative_tile( cell ) ]

# The 3x3 shape a tile draws (see TILES), or "" if it isn't a tile from MuseumSet.png.
static func get_tile_shape(tile: Array, source_id: int) -> String:
	if tile.is_empty() or tile[ 0 ] != source_id: return ""
	return _shape_for_tile.get( Vector3i( tile[ 1 ].x, tile[ 1 ].y, tile[ 2 ] ), "" )

static func _index(offset: Vector2i) -> int:
	return (offset.y + 1) * 3 + offset.x + 1

static func _shape_has_floor(shape: String, offset: Vector2i) -> bool:
	return shape[ _index( offset ) ] == "."

# Where a point of a tile ends up when the tile is drawn with the given transform flags.
static func _transform_offset(offset: Vector2i, transform: int) -> Vector2i:
	var result := Vector2i( offset.y, offset.x ) if transform & TRANSPOSE else offset
	if transform & FLIP_H: result.x = -result.x
	if transform & FLIP_V: result.y = -result.y
	return result

static func _transform_shape(shape: String, transform: int) -> String:
	var result : Array[ String ] = []
	result.resize( shape.length() )
	for y in range( -1, 2 ):
		for x in range( -1, 2 ):
			result[ _index( _transform_offset( Vector2i( x, y ), transform ) ) ] = shape[ _index( Vector2i( x, y ) ) ]
	return "".join( result )

#endregion

#region Borders

static func _border_key(a: Vector2i, b: Vector2i) -> Vector3i:
	var low := a.min( b )
	return Vector3i( low.x, low.y, 0 if a.y == b.y else 1 )

func get_border(a: Vector2i, b: Vector2i) -> int:
	return borders.get( _border_key( a, b ), WALL )

func set_border(a: Vector2i, b: Vector2i, state: int) -> void:
	if state == WALL: borders.erase( _border_key( a, b ) )
	else: borders[ _border_key( a, b ) ] = state

func copy() -> MapGrid:
	var other : MapGrid = get_script().new()
	other.cells = cells.duplicate()
	other.borders = borders.duplicate()
	return other

# Rebuilds the cells and borders from the tiles on the layer.
func read_layer(layer: TileMapLayer, source_id: int) -> void:
	var shapes : Dictionary[ Vector2i, String ]
	for cell in layer.get_used_cells():
		var shape := get_tile_shape( get_tile( layer, cell ), source_id )
		cells[ cell ] = shape != ""
		if cells[ cell ]: shapes[ cell ] = shape

	for cell in shapes:
		for side in SIDES:
			var other := cell + side
			# Borders between two known tiles get read from the upper or left one. Unknown tiles never join.
			if shapes.has( other ) and (side == Vector2i.UP or side == Vector2i.LEFT): continue
			if cells.has( other ) and not shapes.has( other ): continue
			if not _shape_has_floor( shapes[ cell ], side ): continue
			if shapes.has( other ) and not _shape_has_floor( shapes[ other ], -side ): continue
			# A door has wall at both ends, so floor at either end means the border is open.
			var across := Vector2i( side.y, side.x )
			var state := DOOR
			for end : Vector2i in [ across, -across ]:
				if _shape_has_floor( shapes[ cell ], side + end ): state = OPEN
				if shapes.has( other ) and _shape_has_floor( shapes[ other ], end - side ): state = OPEN
			set_border( cell, other, state )

#endregion

#region Strokes

# The rectangle of cells with a and b at opposite corners.
static func get_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	return Rect2i( a.min( b ), (a - b).abs() + Vector2i.ONE )

# Follows the mouse from one position to the next, adding each cell it enters to the path. Positions
# are in cells, so ( 2.5, 0.5 ) is the middle of cell ( 2, 0 ). Steps only go between side neighbours,
# and moving back into the previous cell takes the last step back off.
static func extend_path(path: Array[ Vector2i ], from: Vector2, to: Vector2) -> void:
	var cell := Vector2i( from.floor() )
	var remaining := (Vector2i( to.floor() ) - cell).abs()
	var delta := to - from
	var step := Vector2i( delta.sign() )
	# How far along the line the next column and row boundaries are.
	var next := Vector2( INF, INF )
	var spacing := Vector2( INF, INF )
	if delta.x != 0.0:
		spacing.x = 1.0 / absf( delta.x )
		next.x = (cell.x + 1 - from.x if delta.x > 0.0 else from.x - cell.x) * spacing.x
	if delta.y != 0.0:
		spacing.y = 1.0 / absf( delta.y )
		next.y = (cell.y + 1 - from.y if delta.y > 0.0 else from.y - cell.y) * spacing.y

	while remaining != Vector2i.ZERO:
		if remaining.y == 0 or (remaining.x > 0 and next.x < next.y):
			cell.x += step.x
			next.x += spacing.x
			remaining.x -= 1
		else:
			cell.y += step.y
			next.y += spacing.y
			remaining.y -= 1
		if path.size() > 1 and path[ -2 ] == cell: path.pop_back()
		else: path.append( cell )

# Places every cell along the path and joins each pair of cells it steps between.
func add_path(path: Array[ Vector2i ]) -> void:
	for i in path.size():
		cells[ path[ i ] ] = true
		if i > 0 and get_border( path[ i - 1 ], path[ i ] ) == WALL: set_border( path[ i - 1 ], path[ i ], DOOR )

# Places every cell in the rectangle as one room. Nothing outside it gets joined.
func add_rect(rect: Rect2i) -> void:
	for y in range( rect.position.y, rect.end.y ):
		for x in range( rect.position.x, rect.end.x ):
			var cell := Vector2i( x, y )
			cells[ cell ] = true
			if x > rect.position.x: set_border( cell + Vector2i.LEFT, cell, OPEN )
			if y > rect.position.y: set_border( cell + Vector2i.UP, cell, OPEN )

# Removes the cells, walling off whatever they were joined to.
func erase(to_erase: Array[ Vector2i ]) -> void:
	for cell in to_erase:
		cells.erase( cell )
		for side in SIDES: set_border( cell, cell + side, WALL )

#endregion

#region Drawing

# The 3x3 shape a cell's tile needs, in the same format as TILES.
func get_shape(cell: Vector2i) -> String:
	var shape := ""
	for y in range( -1, 2 ):
		for x in range( -1, 2 ):
			shape += "." if _has_floor( cell, Vector2i( x, y ) ) else "#"
	return shape

func _has_floor(cell: Vector2i, offset: Vector2i) -> bool:
	if offset == Vector2i.ZERO: return true
	if offset.x == 0 or offset.y == 0: return get_border( cell, cell + offset ) != WALL
	# A corner only has floor when all four borders meeting there are open. Otherwise a wall ends there.
	var side_x := cell + Vector2i( offset.x, 0 )
	var side_y := cell + Vector2i( 0, offset.y )
	return (get_border( cell, side_x ) == OPEN and get_border( cell, side_y ) == OPEN and
			get_border( side_x, cell + offset ) == OPEN and get_border( side_y, cell + offset ) == OPEN)

# The tile a cell should show (see get_tile), given the tile it had before. A cell whose shape didn't
# change keeps its old tile, so tiles placed by hand keep their rotation.
func get_wanted_tile(cell: Vector2i, source_id: int, old_tile: Array) -> Array:
	if not cells.has( cell ): return []
	if not cells[ cell ]: return old_tile
	var shape := get_shape( cell )
	if shape == get_tile_shape( old_tile, source_id ): return old_tile
	var tile := _tile_for_shape[ shape ]
	return [ source_id, Vector2i( tile.x, tile.y ), tile.z ]

# Redraws the given cells of the layer to match this grid. old_tiles holds each cell's tile from
# before, and the result lists the cells that no longer match it.
func draw(layer: TileMapLayer, source_id: int, old_tiles: Dictionary[ Vector2i, Array ], cells_to_draw: Dictionary) -> Dictionary:
	var changed := {}
	for cell : Vector2i in cells_to_draw:
		var old_tile : Array = old_tiles.get( cell, [] )
		var tile := get_wanted_tile( cell, source_id, old_tile )
		if tile.is_empty(): layer.erase_cell( cell )
		else: layer.set_cell( cell, tile[ 0 ], tile[ 1 ], tile[ 2 ] )
		if tile != old_tile: changed[ cell ] = true
	return changed

#endregion
