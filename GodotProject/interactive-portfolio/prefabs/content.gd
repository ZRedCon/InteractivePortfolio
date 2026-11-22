@tool
class_name ContentAdjuster extends HBoxContainer

## The exhibit's middle row: the text (it scrolls) on the left and the slideshow on the right.
## SlideFrame keeps the slideshow 16:9. This makes the frame as wide as a 16:9 box as tall as the row, so
## the images get all the room the screen has, unless that would squeeze the text thinner than
## TEXT_MIN_WIDTH. Then the frame stops growing and the slideshow sits at the top of the row.

const TEXT_MIN_WIDTH : float = 320.0

@onready var slide_frame : AspectRatioContainer = $SlideFrame

func _ready() -> void:
	resized.connect( _fit_slide_frame )
	_fit_slide_frame()

func _fit_slide_frame() -> void:
	var room := size.x - TEXT_MIN_WIDTH - get_theme_constant( "separation" )
	slide_frame.custom_minimum_size.x = maxf( minf( size.y * slide_frame.ratio, room ), 0.0 )
