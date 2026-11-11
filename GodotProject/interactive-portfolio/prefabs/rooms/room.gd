class_name Room extends StaticBody3D

# enum for general type
const TYPE_ROOM = 0
const TYPE_HALL = 1

#region border points enum
# psuedo-enum for border points; P = positive, Z = zero, N = Negative, X and Z represent axes
const BORDER_NONE = 0
const BORDER_PX_ZZ = 1
const BORDER_PX_PZ = 2
const BORDER_ZX_PZ = 4
const BORDER_NX_PZ = 8
const BORDER_NX_ZZ = 16
const BORDER_NX_NZ = 32
const BORDER_ZX_NZ = 64
const BORDER_PX_NZ = 128
const BORDER_ALL = 255

const BORDER_CORNERS = BORDER_PX_PZ | BORDER_NX_PZ | BORDER_NX_NZ | BORDER_PX_NZ
const BORDER_EDGES = BORDER_PX_ZZ | BORDER_ZX_PZ | BORDER_NX_ZZ | BORDER_ZX_NZ

const BORDER_LEFT = BORDER_NX_PZ | BORDER_NX_ZZ | BORDER_NX_NZ
const BORDER_UP = BORDER_PX_PZ | BORDER_ZX_PZ | BORDER_NX_PZ
const BORDER_RIGHT = BORDER_PX_NZ | BORDER_PX_ZZ | BORDER_PX_PZ
const BORDER_DOWN = BORDER_NX_NZ | BORDER_ZX_NZ | BORDER_PX_NZ

const BORDER_TYPE_TO_DIRECTION : Dictionary[ int, Vector2 ] = {
	BORDER_PX_ZZ: Vector2(+1, 0),
	BORDER_PX_PZ: Vector2(+1,+1),
	BORDER_ZX_PZ: Vector2( 0,+1),
	BORDER_NX_PZ: Vector2(-1,+1),
	BORDER_NX_ZZ: Vector2(-1, 0),
	BORDER_NX_NZ: Vector2(-1,-1),
	BORDER_ZX_NZ: Vector2( 0,-1),
	BORDER_PX_NZ: Vector2(+1,-1),
}

const DIRECTION_TO_BORDER_TYPE : Dictionary[ Vector2i, int ] = {
	Vector2i(+1, 0): BORDER_PX_ZZ,
	Vector2i(+1,+1): BORDER_PX_PZ,
	Vector2i( 0,+1): BORDER_ZX_PZ,
	Vector2i(-1,+1): BORDER_NX_PZ,
	Vector2i(-1, 0): BORDER_NX_ZZ,
	Vector2i(-1,-1): BORDER_NX_NZ,
	Vector2i( 0,-1): BORDER_ZX_NZ,
	Vector2i(+1,-1): BORDER_PX_NZ,
}

#endregion

# This value represents all edges and corners that have a wall (Black | Gray on the shape index used in map_layout)
var borders : int = BORDER_ALL
# This contains references to all rooms (diagonal and orthoganal) that connect to this room
var neighbors : Dictionary[ Vector2i, Room ]

# Return true if added neighbor succesfully, if space already occupide or otherwise failed: false
func add_neighbor(dir: Vector2i, room_ref: Room) -> bool:
	if neighbors.has( dir ): return false
	neighbors[ dir ] = room_ref
	return true
