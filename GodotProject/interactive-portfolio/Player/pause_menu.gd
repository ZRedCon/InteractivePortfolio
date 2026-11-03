class_name PauseMenu extends Control

static var Instance : PauseMenu 

static func set_debug_out(input: String) -> void:
	Instance.debug_print_text.text = input

@onready var sensitivity : NumberEdit = $"HBoxContainer/Settings Container/Sensitivity"
@onready var debug_print_text : RichTextLabel = $HBoxContainer/RichTextLabel3


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Instance == null: Instance = self
	visible = PIH.is_paused
	PIH.Instance.on_pause_change.connect( func(): visible = PIH.is_paused )
	sensitivity.when_number_updated.connect( func(): PIH.Instance._sensitivity = sensitivity.number )
