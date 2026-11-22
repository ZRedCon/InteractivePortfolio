class_name Carpet extends Node3D

const CARPET_DIST_FROM_WALL := 2.5
const CARPET_Y_OFFSET := 0.5

const NEAR_CORNER := Vector3(CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, CARPET_DIST_FROM_WALL)
const CW_POINT := Vector3(2 * CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, CARPET_DIST_FROM_WALL)
const CCW_POINT := Vector3(CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, 2 * CARPET_DIST_FROM_WALL)
const FAR_CORNER := Vector3(2 * CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, 2 * CARPET_DIST_FROM_WALL)

static func generate_verticies(borders: int) -> PackedVector3Array:
	var arr = generate_corner(
		borders & Room.BORDER_PX_ZZ, 
		borders & Room.BORDER_PX_PZ, 
		borders & Room.BORDER_ZX_PZ,
		Vector3(1,0,1))
	arr.append_array(generate_corner(
		borders & Room.BORDER_PX_ZZ, 
		borders & Room.BORDER_PX_NZ, 
		borders & Room.BORDER_ZX_NZ,
		Vector3(1,0,-1)
	))
	arr.append_array(generate_corner(
		borders & Room.BORDER_NX_ZZ, 
		borders & Room.BORDER_NX_NZ, 
		borders & Room.BORDER_ZX_NZ,
		Vector3(-1,0,-1)
	))
	arr.append_array(generate_corner(
		borders & Room.BORDER_NX_ZZ, 
		borders & Room.BORDER_NX_PZ, 
		borders & Room.BORDER_ZX_PZ,
		Vector3(-1,0,1)
	))
	
	return arr

#ccw_wall and cw_wall are counter clock wise and clock wise from the corner point
static func generate_corner(ccw_wall: bool, corner: bool, cw_wall: bool, rotation: Vector3) -> PackedVector3Array:
	var flip_x_y : bool = sign(rotation.x) != sign(rotation.z)
	# These do not exist / are inherentily illogical:
	# 1 0 0 | 0 0 1 | 1 0 1
	if not corner: # 0 0 0
		return [ FAR_CORNER * rotation ]
	if ccw_wall and cw_wall: # 1 1 1
		return [ NEAR_CORNER * rotation ]
	if ccw_wall: # 1 1 0
		return [ CCW_POINT * rotation ]
	if cw_wall: # 0 1 1
		return [ CW_POINT * rotation ]
	
	# 0 1 0
	if not flip_x_y:
		return [ CCW_POINT * rotation, NEAR_CORNER * rotation, CW_POINT * rotation ]
	else:
		return [ CW_POINT * rotation, NEAR_CORNER * rotation, CCW_POINT * rotation ] 
