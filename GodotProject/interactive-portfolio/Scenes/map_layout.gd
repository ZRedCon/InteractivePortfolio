extends TileMapLayer

const INDEX_TO_ROOM_TYPE : Dictionary[ Vector2i, int ] = {
	Vector2i(0, 0): 1,
	Vector2i(0, 1): 2,
	Vector2i(0, 2): 3,
	Vector2i(0, 3): 4,
	Vector2i(0, 4): 5,
	Vector2i(0, 5): 6,
	Vector2i(0, 6): 7,
	Vector2i(1, 0): 8,
	Vector2i(1, 1): 9,
	Vector2i(1, 2): 10,
	Vector2i(1, 3): 11,
	Vector2i(1, 4): 12,
	Vector2i(1, 5): 13,
	Vector2i(1, 6): 14
}

@export var start_tile := Vector2i.ZERO
