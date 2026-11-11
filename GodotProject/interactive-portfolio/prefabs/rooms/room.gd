class_name Room extends StaticBody3D

# This contains all the exhibits that can exist in this room
@export var exhibits : Array[ Exhibit ]

# pseudo-enum for general type
const TYPE_NONE = 0
const TYPE_CORNER_ROOM = 1
const TYPE_EDGE_ROOM = 2
const TYPE_ROOM = 3
const TYPE_INTERSECTION_3_HALL = 4
const TYPE_END_HALL = 5
const TYPE_STRAIGHT_HALL = 6
const TYPE_CORNER_1_EXIT_ROOM = 7
const TYPE_CORNER_2_EXIT_ROOM = 8
const TYPE_EDGE_EXIT_ROOM = 9
const TYPE_CORNER_OVERLAP_ROOM = 10
const TYPE_INTERSECTION_4_HALL = 11
const TYPE_CORNER_HALL = 12
const TYPE_CORNER_CONVEX_ROOM = 13
const TYPE_SINGLE = 14

#region border points enum
# pseudo-enum for border points; P = positive, Z = zero, N = Negative, X and Z represent axes.
# Directions are as seen from above, the same way MapLayout draws the map: +X is right and +Z is down.
# Counting up through the bits steps clockwise around the room, 45 degrees at a time.
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
const BORDER_UP = BORDER_PX_NZ | BORDER_ZX_NZ | BORDER_NX_NZ
const BORDER_RIGHT = BORDER_PX_NZ | BORDER_PX_ZZ | BORDER_PX_PZ
const BORDER_DOWN = BORDER_NX_PZ | BORDER_ZX_PZ | BORDER_PX_PZ

const BORDER_CORNER_ROOM = BORDER_UP | BORDER_LEFT
const BORDER_EDGE_ROOM = BORDER_UP
const BORDER_ROOM = BORDER_NONE
const BORDER_INTERSECTION_3_HALL = BORDER_UP | BORDER_NX_PZ | BORDER_PX_PZ
const BORDER_END_HALL = BORDER_UP | BORDER_STRAIGHT_HALL
const BORDER_STRAIGHT_HALL = BORDER_LEFT | BORDER_RIGHT
const BORDER_CORNER_1_EXIT_ROOM = BORDER_NX_NZ | BORDER_RIGHT
const BORDER_CORNER_2_EXIT_ROOM = BORDER_NX_NZ | BORDER_PX_NZ | BORDER_PX_PZ
const BORDER_EDGE_EXIT_ROOM = BORDER_NX_NZ | BORDER_PX_NZ
const BORDER_CORNER_OVERLAP_ROOM = BORDER_NX_NZ | BORDER_PX_PZ
const BORDER_INTERSECTION_4_HALL = BORDER_CORNERS
const BORDER_CORNER_HALL = BORDER_DOWN | BORDER_RIGHT | BORDER_NX_NZ
const BORDER_CORNER_CONVEX_ROOM = BORDER_NX_NZ
const BORDER_SINGLE = BORDER_ALL

const TYPE_TO_BORDERS : Dictionary[ int, int ] = {
	TYPE_CORNER_ROOM: BORDER_CORNER_ROOM,
	TYPE_EDGE_ROOM: BORDER_EDGE_ROOM,
	TYPE_ROOM: BORDER_ROOM,
	TYPE_INTERSECTION_3_HALL: BORDER_INTERSECTION_3_HALL,
	TYPE_END_HALL: BORDER_END_HALL,
	TYPE_STRAIGHT_HALL: BORDER_STRAIGHT_HALL,
	TYPE_CORNER_1_EXIT_ROOM: BORDER_CORNER_1_EXIT_ROOM,
	TYPE_CORNER_2_EXIT_ROOM: BORDER_CORNER_2_EXIT_ROOM,
	TYPE_EDGE_EXIT_ROOM: BORDER_EDGE_EXIT_ROOM,
	TYPE_CORNER_OVERLAP_ROOM: BORDER_CORNER_OVERLAP_ROOM,
	TYPE_INTERSECTION_4_HALL: BORDER_INTERSECTION_4_HALL,
	TYPE_CORNER_HALL: BORDER_CORNER_HALL,
	TYPE_CORNER_CONVEX_ROOM: BORDER_CORNER_CONVEX_ROOM,
	TYPE_SINGLE: BORDER_SINGLE,
}

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

# Rotates 45, +shift = clockwise, -shift = counter-clockwise
static func rotate_direction(mask: int, shift: int) -> int:
	shift = posmod( shift, 8 )
	return ((mask << shift) | (mask >> (8 - shift))) & BORDER_ALL

# Mirrors a mask left to right, so walls on the -X side end up on the +X side and the other way around
static func mirror_direction(mask: int) -> int:
	var result := BORDER_NONE
	for border in BORDER_TYPE_TO_DIRECTION:
		if mask & border:
			var direction := BORDER_TYPE_TO_DIRECTION[ border ]
			result |= DIRECTION_TO_BORDER_TYPE[ Vector2i( -direction.x, direction.y ) ]
	return result
#endregion

# What type of room is this?
var type = TYPE_NONE
# This value represents all edges and corners that have a wall (Black | Gray on the shape index used in map_layout)
var borders : int = BORDER_ALL
# This contains references to all rooms (diagonal and orthoganal) that connect to this room
var neighbors : Dictionary[ Vector2i, Room ]

# Return true if added neighbor succesfully, if space already occupide or otherwise failed: false
func add_neighbor(dir: Vector2i, room_ref: Room) -> bool:
	if neighbors.has( dir ): return false
	neighbors[ dir ] = room_ref
	return true
