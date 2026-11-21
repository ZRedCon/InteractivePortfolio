@abstract
class_name EdgeProp extends Prop

# Enum representation
const POS_Z := 0
const POS_X := 1
const NEG_Z := 2
const NEG_X := 3

const ROT_DEGREE : Array[ int ] = [ 0, 90, 180, 270 ]

# The prop's front is its +Z side. On the map +Z is down and +X is right, so the names follow the constants above.
@export_enum("Face Down", "Face Right", "Face Up", "Face Left") var start_direction : int

func _face_dir(dir: int) -> void:
	rotation_degrees.y = ROT_DEGREE[ clamp(dir,0,3) ]

# Turns the prop's front toward whichever of the four directions is closest to dir
func _face_forward(dir: Vector3) -> void:
	if abs( dir.x ) > abs( dir.z ): _face_dir( POS_X if dir.x > 0 else NEG_X )
	else: _face_dir( POS_Z if dir.z > 0 else NEG_Z )

func _category_ready() -> void:
	_face_dir( start_direction )
	_edge_post_ready()

func _edge_post_ready() -> void: pass
