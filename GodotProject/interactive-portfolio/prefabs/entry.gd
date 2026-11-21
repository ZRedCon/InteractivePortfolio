class_name Exhibit extends EdgeProp

const SPRITE_HEIGHT_MAX = 128
const COLLIDER_WIDTH_BASE = 1.395

@onready var label := $Name
@onready var sprite := $MainImage
@onready var collider := $MouseCollider/CollisionShape3D

var entry_data : Entry

func set_entry(entry: Entry) -> void:
	var image = await FileIO.Instance.get_image( entry.main_image )
	if image == null: return
	sprite.texture = ImageTexture.create_from_image( image )
	
	var sprite_height : int = sprite.texture.get_height()
	if sprite_height > SPRITE_HEIGHT_MAX:
		var horizontal_scale = float(sprite.texture.get_width()) / sprite_height
		var factor = float(SPRITE_HEIGHT_MAX) / sprite_height
		
		sprite.scale = Vector3( factor, factor, factor )
		var collider_shape : BoxShape3D = collider.shape
		collider_shape.size.x = COLLIDER_WIDTH_BASE * horizontal_scale
	
	label.text = entry.name
