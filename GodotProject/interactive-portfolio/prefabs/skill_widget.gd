class_name Skill extends PanelContainer

@onready var label := $HBoxContainer/MarginContainer/Label
@onready var color_image := $HBoxContainer/Color

func set_values(display_name: String, color: Color) -> void:
	label.text = display_name
	color_image.modulate = color
