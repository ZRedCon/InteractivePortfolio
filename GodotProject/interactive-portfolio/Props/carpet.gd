@tool
class_name Carpet extends StaticBody3D

const CARPET_DIST_FROM_WALL := 2.5
const CARPET_Y_OFFSET := 0.05

const NEAR_CORNER := Vector3(CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, CARPET_DIST_FROM_WALL)
const CW_POINT := Vector3(2 * CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, CARPET_DIST_FROM_WALL)
const CCW_POINT := Vector3(CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, 2 * CARPET_DIST_FROM_WALL)
const FAR_CORNER := Vector3(2 * CARPET_DIST_FROM_WALL, CARPET_Y_OFFSET, 2 * CARPET_DIST_FROM_WALL)

static func generate_verticies(borders: int) -> PackedVector3Array:
	var arr = generate_corner(
		borders & Room.BORDER_PX_ZZ, 
		borders & Room.BORDER_PX_PZ, 
		borders & Room.BORDER_ZX_PZ,
		Vector3(1,1,1))
	arr.append_array(generate_corner(
		borders & Room.BORDER_PX_ZZ, 
		borders & Room.BORDER_PX_NZ, 
		borders & Room.BORDER_ZX_NZ,
		Vector3(1,1,-1)
	))
	arr.append_array(generate_corner(
		borders & Room.BORDER_NX_ZZ, 
		borders & Room.BORDER_NX_NZ, 
		borders & Room.BORDER_ZX_NZ,
		Vector3(-1,1,-1)
	))
	arr.append_array(generate_corner(
		borders & Room.BORDER_NX_ZZ, 
		borders & Room.BORDER_NX_PZ, 
		borders & Room.BORDER_ZX_PZ,
		Vector3(-1,1,1)
	))
	
	return arr

#ccw_wall and cw_wall are counter clock wise and clock wise from the corner point
#rotation's x and z pick the corner; its y stays 1 so the points keep CARPET_Y_OFFSET
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

#region the carpet in a room
## The walls this carpet is cut to fit (Room.BORDER_* flags, in its room's own unturned space). They're set for you:
## from the room scene it's in whenever that scene is opened in the editor, and mirrored by RoomContainer._mirror.
@export_custom(PROPERTY_HINT_FLAGS, "PX_ZZ,PX_PZ,ZX_PZ,NX_PZ,NX_ZZ,NX_NZ,ZX_NZ,PX_NZ", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY)
var walls := Room.BORDER_NONE

# The mesh and collision shape cut for walls. They're cut in the editor and saved with the room scene, so the game
# only has to show them (a mirrored room's carpet gets cut again).
@export_storage var _mesh : ArrayMesh
@export_storage var _shape : ConcavePolygonShape3D

func _ready() -> void:
	if Engine.is_editor_hint():
		var room_walls := _edited_room_walls()
		if room_walls == -1: return # Not in a room scene, so there's nothing to fit (see _get_configuration_warnings)
		if room_walls != walls or not _mesh: cut(room_walls)
	_show()

## Cuts the carpet's mesh and collision shape to fit these walls, and shows them
func cut(new_walls: int) -> void:
	walls = new_walls
	_mesh = ProceduralCarpet.make_mesh(generate_verticies(walls))
	_shape = _mesh.create_trimesh_shape()
	_show()

func _show() -> void:
	$CarpetMesh.mesh = _mesh
	$CollisionShape3D.shape = _shape

# The walls of the room scene open in the editor, if RoomContainer builds rooms from it, or else -1
func _edited_room_walls() -> int:
	var room := get_tree().edited_scene_root if is_inside_tree() else null
	if not room: return -1
	var room_scenes : Dictionary = load("res://Scenes/room_container.gd").ROOM_SCENES
	for type : int in room_scenes:
		if room_scenes[type].resource_path == room.scene_file_path: return Room.TYPE_TO_BORDERS[type]
	return -1

func _get_configuration_warnings() -> PackedStringArray:
	if _edited_room_walls() != -1: return []
	return ["A carpet is cut to fit the room scene it's in (one of RoomContainer.ROOM_SCENES), so it stays empty anywhere else."]
#endregion
