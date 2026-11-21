class_name Exhibit extends EdgeProp

const SPRITE_HEIGHT_MAX = 

@onready var label := $Name
@onready var sprite := $MainImage

var entry_data : Entry

func set_entry(entry: Entry) -> void:
	var image = await FileIO.Instance.get_image( entry.main_image )
	if image == null: return
	sprite.texture = ImageTexture.create_from_image( image )
	label.text = entry.name
