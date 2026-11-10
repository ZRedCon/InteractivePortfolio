class_name ListItem extends HBoxContainer

@onready var text_display := $Text

var distxt

func set_values(text: String) -> void:
	distxt = text

func _ready() -> void:
	text_display.text = distxt
