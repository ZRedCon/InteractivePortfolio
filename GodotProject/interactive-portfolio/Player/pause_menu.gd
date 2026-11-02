extends Control

@onready var sensitivity : NumberEdit = $"Settings Container/Sensitivity"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = PIH.is_paused
	PIH.Instance.on_pause_change.connect( func(): visible = PIH.is_paused )
	sensitivity.when_number_updated.connect( func(): PIH.Instance._sensitivity = sensitivity.number )
