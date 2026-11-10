@tool
class_name ContentAdjuster extends BoxContainer

const WIDE = 0
const THIN = 1

@onready var slide_show := $SlideShow
@onready var text_important := $TextImportant

var is_open : bool = false

var mode : int:
	set(val):
		if val != WIDE and val != THIN: 
			return
		mode = val
		vertical = val
		move_child(slide_show if vertical else text_important, 0)

func _calc_mode_from_parent() -> void:
	mode = THIN if size.x < 960 else WIDE

func _ready() -> void:
	await get_tree().process_frame
	_calc_mode_from_parent()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_calc_mode_from_parent()
