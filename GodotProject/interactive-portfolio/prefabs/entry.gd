class_name Exhibit extends Node3D

# Enum representation
const POS_Z := 0
const POS_X := 1
const NEG_Z := 2
const NEG_X := 3

const ROT_DEGREE : Array[ int ] = [ 0, 90, 180, 270 ]

@onready var label := $Name
@onready var sprite := $MainImage

var entry_data : Entry

func face_dir(dir: int) -> void:
	rotation_degrees.y = ROT_DEGREE[ clamp(dir,0,3) ]

func face_forward(dir: Vector3) -> void:
	var z0_x1 := int( abs( dir.x ) > abs( dir.z ) )
	var mag : int = ( sign( dir.x ) if z0_x1 == 1 else sign( dir.z ) ) + 1
	face_dir( z0_x1 + mag ) 

func set_entry(entry: Entry) -> void:
	var image = await FileIO.Instance.get_image( entry.main_image )
	if image == null: return
	sprite.texture = ImageTexture.create_from_image( image )
	label.text = entry.name
