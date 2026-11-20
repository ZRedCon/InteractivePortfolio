@abstract
class_name EdgeProp extends Prop

# Enum representation
const POS_Z := 0
const POS_X := 1
const NEG_Z := 2
const NEG_X := 3

const ROT_DEGREE : Array[ int ] = [ 0, 90, 180, 270 ]

@export_enum("Face Down", "Face Left", "Face Right", "Face Up") var start_direction : int

func _face_dir(dir: int) -> void:
	rotation_degrees.y = ROT_DEGREE[ clamp(dir,0,3) ]

func _face_forward(dir: Vector3) -> void:
	var z0_x1 := int( abs( dir.x ) > abs( dir.z ) )
	var mag : int = ( sign( dir.x ) if z0_x1 == 1 else sign( dir.z ) ) + 1
	_face_dir( z0_x1 + mag ) 

func _category_ready() -> void:
	_face_dir( start_direction )
	_edge_post_ready()

func _edge_post_ready() -> void: pass
