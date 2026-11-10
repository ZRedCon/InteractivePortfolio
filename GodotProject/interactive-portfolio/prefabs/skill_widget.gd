class_name Skill extends PanelContainer

@onready var label := $HBoxContainer/MarginContainer/Label
@onready var color_image := $HBoxContainer/Color

var lbltxt
var clrimg

func set_values(display_name: String, color: Color) -> void:
	lbltxt = display_name
	clrimg = color

func _ready() -> void:
	label.text = lbltxt
	color_image.modulate = clrimg
	
