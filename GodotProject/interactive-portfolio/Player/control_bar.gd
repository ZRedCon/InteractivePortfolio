extends HBoxContainer

@export var display_name : String
@export var keybinds : String

@onready var label := $Label
@onready var keybind := $KeyBinds

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	label.text = display_name
	keybind.text = keybinds
