@tool
@abstract
class_name CenteredPropDisplay extends PropDisplay

## A prop in the middle of a room tile: the tile draw_pos is in.

func get_marker_position() -> Vector2:
	return get_cell_center()
