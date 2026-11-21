@tool
@abstract
class_name PropDisplay extends Node2D

## A prop's marker on the museum map (MapLayout). The Map Painter's Props tool places them, and when the
## museum is built, RoomContainer turns each one into its 3D prop (see get_prop_scene).
##
## The node itself stays at (0, 0) (the Props tool locks it there) and draws its marker at draw_pos, in the
## map's pixels. This base kind sits wherever it's placed; EdgePropDisplay and CenteredPropDisplay snap.
## A subclass that overrides _ready or _process has to call super().

const _HOVER_DISPLAY_TIME := 2.0
## The marker's size, in map pixels (one tile is 16)
const RADIUS := 3.0
const _HOVER_DISPLAY_DISTANCE := RADIUS + 0.5
## Replaces the marker's color while the Props tool is about to remove it
const REMOVE_COLOR := Color( 1.0, 0.25, 0.2 )
# Text is drawn this big and then shrunk by TEXT_SCALE (to 4 map pixels tall), so it stays sharp when the
# editor is zoomed in
const TEXT_SIZE := 32
const TEXT_SCALE := 0.125

@export var draw_color : Color = Color():
	set( value ):
		draw_color = value
		queue_redraw()
@export var draw_pos : Vector2 = Vector2.ZERO:
	set( value ):
		draw_pos = value
		queue_redraw()
@export var draw_name : String = "_Null_":
	set( value ):
		draw_name = value
		queue_redraw()

var timer : float
var do_detailed_display : bool
## Whether the mouse is over the marker
var hovered : bool
## The Props tool sets this while the prop is about to be removed, which draws it in REMOVE_COLOR
var marked_for_removal : bool:
	set( value ):
		marked_for_removal = value
		queue_redraw()

func _ready() -> void:
	# The map only shows in the editor, so in the game there's nothing to hover over
	set_process( Engine.is_editor_hint() )

func _is_mouse_hovering() -> bool:
	return get_local_mouse_position().distance_to( get_marker_position() ) < _HOVER_DISPLAY_DISTANCE

# detailed_display:
func _process(delta: float) -> void:
	hovered = _is_mouse_hovering()
	if not hovered:
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

## The color the marker is drawn in right now
func get_display_color() -> Color:
	return REMOVE_COLOR if marked_for_removal else draw_color

func _draw() -> void:
	var center := get_marker_position()
	draw_circle( center, RADIUS, get_display_color() )
	# A thin dark edge, so the marker shows up on any tile
	draw_arc( center, RADIUS, 0.0, TAU, 24, Color( 0.0, 0.0, 0.0, 0.6 ), 0.4 )
	_prop_draw()
	if do_detailed_display: _advanced_draw()

## Performs advanced_draw while also drawing the name of the prop
func _advanced_draw() -> void:
	draw_text_line( draw_name, 0 )
	_prop_draw_advanced()

## Draws a line of small text under the marker, on a dark backing. Line 0 is the one right under it.
func draw_text_line(text: String, line: int, color: Color = Color.WHITE) -> void:
	var font := ThemeDB.fallback_font
	var size := font.get_string_size( text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE ) * TEXT_SCALE
	var top_left := get_marker_position() + Vector2( -size.x / 2.0, RADIUS + 1.0 + line * size.y )
	draw_rect( Rect2( top_left, size ), Color( 0.0, 0.0, 0.0, 0.75 ) )
	draw_set_transform( top_left + Vector2( 0.0, font.get_ascent( TEXT_SIZE ) * TEXT_SCALE ), 0.0, Vector2.ONE * TEXT_SCALE )
	draw_string( font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, color )
	draw_set_transform( Vector2.ZERO )

## Draws an arrow from `from` to `to`, with its point at `to`. widths are the half-widths of its point, the
## back of its head and its shaft, and head_distance is how much of its length the head takes up.
func draw_arrow(from: Vector2, to: Vector2, 
				color: Color, widths: Array[ float ] = [ 0.0, 3.0, 2.0], 
				head_distance: float = 0.1):
	# Fix input
	while widths.size() < 3:
		widths.append(2.0)
	
	head_distance = clamp(head_distance, 0.0, 1.0)
	
	# Math 
	var from_to_to := to - from
	var seperator := to - from_to_to * head_distance # Where the head meets the shaft
	var up = Vector2(-from_to_to.y, from_to_to.x).normalized()
	var down = Vector2(from_to_to.y, -from_to_to.x).normalized()
	
	var points : PackedVector2Array = [
		to + up * widths[ 0 ],
		seperator + up * widths[ 1 ],
		seperator + up * widths[ 2 ],
		from + up * widths[ 2 ],
		from + down * widths[ 2 ],
		seperator + down * widths[ 2 ],
		seperator + down * widths[ 1 ],
		to + down * widths[ 0 ]
	]
	# A sharp point would be the same corner twice, which a polygon can't have
	if is_zero_approx( widths[ 0 ] ): points.remove_at( points.size() - 1 )
	
	draw_colored_polygon( points, color )

## Draws more specific details for this prop
@abstract
func _prop_draw() -> void

## Draws more indepth details for this prop 
func _prop_draw_advanced() -> void: pass

#region Placement

## The map this prop is on: the closest TileMapLayer above it
func get_map() -> TileMapLayer:
	var node := get_parent()
	while node and not node is TileMapLayer: node = node.get_parent()
	return node as TileMapLayer

## One map tile's size, in pixels
func get_tile_size() -> Vector2:
	var map := get_map()
	return Vector2( map.tile_set.tile_size ) if map and map.tile_set else Vector2( 16.0, 16.0 )

## The map cell (room) this prop is in
func get_cell() -> Vector2i:
	return Vector2i( (draw_pos / get_tile_size()).floor() )

## The middle of this prop's cell, in map pixels
func get_cell_center() -> Vector2:
	return (Vector2( get_cell() ) + Vector2( 0.5, 0.5 )) * get_tile_size()

## Where the marker is drawn, in map pixels. Kinds that snap override this.
func get_marker_position() -> Vector2:
	return draw_pos

## Where the prop stands on the map, in cells: ( 2.5, 0.5 ) is the middle of cell ( 2, 0 ). RoomContainer
## builds the prop there, on the floor.
func get_map_point() -> Vector2:
	return get_marker_position() / get_tile_size()

#endregion

#region Building

## The kind of prop, from the display's class name: an ExhibitDisplay is an "Exhibit"
func get_prop_type() -> String:
	var type := String( (get_script() as Script).get_global_name() ).trim_suffix( "Display" )
	return type if type else "Prop"

## Where this prop is, for error messages
func describe() -> String:
	return "%s \"%s\" in cell %s" % [ get_prop_type(), name, get_cell() ]

## Problems that keep this prop from being built, each worded to follow describe() and a colon. The museum
## prints them as errors when it's built, and the Scene dock shows them as warnings.
func get_problems() -> PackedStringArray:
	return []

func _get_configuration_warnings() -> PackedStringArray:
	return get_problems()

## False leaves the prop out of the museum without an error, like a grouped exhibit whose group ran out of entries
func is_built() -> bool:
	return true

## The 3D scene this prop builds
@abstract
func get_prop_scene() -> PackedScene

## The 3D prop, made but not in the tree yet. Kinds that face a way turn it here.
func make_prop() -> Node3D:
	return get_prop_scene().instantiate() as Node3D

## Called once the built prop is in the tree, to hand it this display's settings
func setup_prop(_prop: Node3D) -> void: pass

## Called on a new prop the Props tool is placing while another prop of the same type is selected, so a row
## of props can be placed without setting up each one
func copy_settings(from: PropDisplay) -> void:
	draw_color = from.draw_color
	draw_name = from.draw_name

#endregion
