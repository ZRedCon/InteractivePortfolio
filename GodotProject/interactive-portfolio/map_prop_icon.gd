@tool
@abstract
class_name PropDisplay extends Node2D

const _HOVER_DISPLAY_TIME := 2.0
const _HOVER_DISPLAY_DISTANCE := 10.0

@export var draw_color : Color = Color()
@export var draw_pos : Vector2 = Vector2.ZERO
@export var draw_name : String = "_Null_"

var timer : float
var do_detailed_display : bool

func _is_mouse_hovering() -> bool:
	var mouse_pos := get_global_mouse_position()
	var distance = (draw_pos - mouse_pos).length()
	return distance < _HOVER_DISPLAY_DISTANCE

# detailed_display:
func _process(delta: float) -> void:
	if not _is_mouse_hovering(): 
		timer = 0
		if do_detailed_display:
			do_detailed_display = false
			queue_redraw()
		return
	
	timer = clamp(timer + delta, 0, _HOVER_DISPLAY_TIME)
	if timer >= _HOVER_DISPLAY_TIME and not do_detailed_display:
		do_detailed_display = true
		queue_redraw()

func set_display_color(new_color: Color) -> PropDisplay:
	draw_color = new_color
	queue_redraw()
	return self

func set_draw_position(new_position: Vector2) -> PropDisplay:
	draw_pos = new_position
	queue_redraw()
	return self 

func set_draw_name(new_name: String) -> PropDisplay:
	draw_name = new_name
	queue_redraw()
	return self

func _draw() -> void:
	draw_circle( draw_pos, 10.0, draw_color )
	if do_detailed_display: _advanced_draw()
	_prop_draw()

## Performs advanced_draw while also drawing the name of the prop
func _advanced_draw() -> void:
	draw_string( ThemeDB.fallback_font, draw_pos, draw_name )
	_prop_draw_advanced()

func draw_arrow(from: Vector2, to: Vector2, 
				color: Color, widths: Array[ float ] = [ 0.0, 3.0, 2.0], 
				head_distance: float = 0.1):
	# Fix input
	while widths.size() < 3:
		widths.append(2.0)
	
	head_distance = clamp(head_distance, 0.0, 1.0)
	
	# Math 
	var from_to_to := to - from
	var length := from_to_to.length()
	var seperator := length * head_distance * from_to_to.normalized()
	var up = Vector2(-from_to_to.y, from_to_to.x).normalized()
	var down = Vector2(from_to_to.y, -from_to_to.x).normalized()
	
	var points : PackedVector2Array = [
		from + up * widths[ 0 ],
		seperator + up * widths[ 1 ],
		seperator + up * widths[ 2 ],
		to + up * widths[ 2 ],
		to + down * widths[ 2 ],
		seperator + down * widths[ 2 ],
		seperator + down * widths[ 1 ],
		from + down * widths[ 0 ]
	]
	
	draw_colored_polygon( points, color )

## Draws more specific details for this prop
@abstract
func _prop_draw() -> void

## Draws more indepth details for this prop 
func _prop_draw_advanced() -> void: pass
