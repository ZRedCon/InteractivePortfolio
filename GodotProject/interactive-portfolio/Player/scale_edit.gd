class_name NumberEdit extends Control

signal when_number_updated

@export var display_name : String
@export var default_value : float
@export var min_value : float
@export var max_value : float

@onready var slider := $HSlider
@onready var label := $RichTextLabel
@onready var written := $SpinBox

var number : float:
	set(val):
		number = val
		when_number_updated.emit()

var _delta : float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	label.text = display_name
	number = clamp( default_value, min_value, max_value )
	_delta = (max_value - min_value) / 100
	
	slider.value = (number - min_value) / _delta
	written.max_value = max_value
	written.min_value = min_value
	written.value = default_value
	
	slider.value_changed.connect( _slider )
	written.value_changed.connect( _box )

func _slider(value: float) -> void:
	number = value * _delta + min_value
	written.set_value_no_signal( number )

func _box(value: float) -> void:
	number = value
	slider.set_value_no_signal( (number - min_value) / _delta )
