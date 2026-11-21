@tool
@abstract
class_name EdgePropDisplay extends PropDisplay

## A prop against one wall of a room. Its room is the cell draw_pos is in, its marker sits just inside the wall,
## and the arrow shows the way it faces: into the room, away from the wall.

# In EdgeProp's order (POS_Z, POS_X, NEG_Z, NEG_X), so a display and the prop it builds face the same way
@export_enum("Face Down", "Face Right", "Face Up", "Face Left") var start_direction : int:
	set( value ):
		start_direction = value
		queue_redraw()

## The way each start_direction faces on the map, where +y is down
const FACING : Array[ Vector2 ] = [ Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT ]
## The wall behind each start_direction, for messages
const WALL_NAMES : Array[ String ] = [ "top", "left", "bottom", "right" ]

## The direction of the wall this prop is against, which is behind it
func get_wall() -> Vector2:
	return -FACING[ start_direction ]

func get_marker_position() -> Vector2:
	# Just inside the room from the middle of its wall
	return get_cell_center() + get_wall() * (get_tile_size() / 2.0 - Vector2.ONE * (RADIUS + 0.5))

## On the wall itself, so the prop is built against it
func get_map_point() -> Vector2:
	return Vector2( get_cell() ) + Vector2( 0.5, 0.5 ) + get_wall() * 0.5

func describe() -> String:
	return "%s \"%s\" on the %s wall of cell %s" % [ get_prop_type(), name, WALL_NAMES[ start_direction ], get_cell() ]

func make_prop() -> Node3D:
	var prop := super()
	if prop is EdgeProp: prop.start_direction = start_direction
	else: prop.rotation_degrees.y = EdgeProp.ROT_DEGREE[ start_direction ]
	return prop

func _prop_draw() -> void:
	var center := get_marker_position()
	var facing := FACING[ start_direction ]
	# Dark or light, whichever shows up on the marker's color
	var color := Color.BLACK if get_display_color().get_luminance() > 0.5 else Color.WHITE
	draw_arrow( center - facing * RADIUS * 0.6, center + facing * RADIUS * 0.85, color, [ 0.0, RADIUS * 0.5, RADIUS * 0.2 ], 0.45 )
	
