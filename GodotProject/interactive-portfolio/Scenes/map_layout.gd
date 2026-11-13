extends TileMapLayer

const INDEX_TO_ROOM_TYPE : Dictionary[ Vector2i, int ] = {
	Vector2i(0, 0): Room.TYPE_CORNER_ROOM,
	Vector2i(1, 0): Room.TYPE_EDGE_ROOM,
	Vector2i(2, 0): Room.TYPE_ROOM,
	Vector2i(3, 0): Room.TYPE_INTERSECTION_3_HALL,
	Vector2i(4, 0): Room.TYPE_END_HALL,
	Vector2i(5, 0): Room.TYPE_STRAIGHT_HALL,
	Vector2i(6, 0): Room.TYPE_CORNER_1_EXIT_ROOM,
	Vector2i(0, 1): Room.TYPE_CORNER_2_EXIT_ROOM,
	Vector2i(1, 1): Room.TYPE_EDGE_EXIT_ROOM,
	Vector2i(2, 1): Room.TYPE_CORNER_OVERLAP_ROOM,
	Vector2i(3, 1): Room.TYPE_INTERSECTION_4_HALL,
	Vector2i(4, 1): Room.TYPE_CORNER_HALL,
	Vector2i(5, 1): Room.TYPE_CORNER_CONVEX_ROOM,
	Vector2i(6, 1): Room.TYPE_SINGLE
}

@export var start_tile := Vector2i.ZERO


func _ready() -> void:
	visible = false

func get_room_type(cell: Vector2i) -> int:
	return INDEX_TO_ROOM_TYPE.get( get_cell_atlas_coords( cell ), Room.TYPE_NONE )

func get_borders(cell: Vector2i) -> int:
	var flips := get_cell_alternative_tile( cell )
	var walls : int = Room.TYPE_TO_BORDERS[ get_room_type( cell ) ]
	var borders := Room.BORDER_NONE
	for border in Room.BORDER_TYPE_TO_DIRECTION:
		if not walls & border: continue
		# A tile swaps x and y first, then mirrors
		var direction := Vector2i( Room.BORDER_TYPE_TO_DIRECTION[ border ] )
		if flips & TileSetAtlasSource.TRANSFORM_TRANSPOSE: direction = Vector2i( direction.y, direction.x )
		if flips & TileSetAtlasSource.TRANSFORM_FLIP_H: direction.x = -direction.x
		if flips & TileSetAtlasSource.TRANSFORM_FLIP_V: direction.y = -direction.y
		borders |= Room.DIRECTION_TO_BORDER_TYPE[ direction ]
	return borders
