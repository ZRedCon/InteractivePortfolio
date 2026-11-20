@tool
class_name EdgePropDisplay extends PropDisplay

@export_enum("Face Down", "Face Left", "Face Right", "Face Up") var start_direction : int

func _prop_draw() -> void:
	var draw_dir := (Vector2.RIGHT if start_direction == 2 else
					 Vector2.LEFT  if start_direction == 1 else
					 Vector2.UP    if start_direction == 3 else
					 Vector2.DOWN)
	
	draw_arrow(draw_pos + draw_dir * 4.0, draw_pos + draw_dir * 9.0, draw_color, [0.0, 2.0, 3.0], 0.5)
