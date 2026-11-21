class_name Room extends StaticBody3D

# This contains all the exhibits that can exist in this room
@export var exhibits : Array[ Exhibit ]

# pseudo-enum for general type
const TYPE_NONE = 0
const TYPE_CORNER_ROOM = 1
const TYPE_EDGE_ROOM = 2
const TYPE_ROOM = 3
const TYPE_INTERSECTION_3_HALL = 4
const TYPE_END_HALL = 5
const TYPE_STRAIGHT_HALL = 6
const TYPE_CORNER_1_EXIT_ROOM = 7
const TYPE_CORNER_2_EXIT_ROOM = 8
const TYPE_EDGE_EXIT_ROOM = 9
const TYPE_CORNER_OVERLAP_ROOM = 10
const TYPE_INTERSECTION_4_HALL = 11
const TYPE_CORNER_HALL = 12
const TYPE_CORNER_CONVEX_ROOM = 13
const TYPE_SINGLE = 14

#region border points enum
# pseudo-enum for border points; P = positive, Z = zero, N = Negative, X and Z represent axes.
# Directions are as seen from above, the same way MapLayout draws the map: +X is right and +Z is down.
# Counting up through the bits steps clockwise around the room, 45 degrees at a time.
const BORDER_NONE = 0
const BORDER_PX_ZZ = 1
const BORDER_PX_PZ = 2
const BORDER_ZX_PZ = 4
const BORDER_NX_PZ = 8
const BORDER_NX_ZZ = 16
const BORDER_NX_NZ = 32
const BORDER_ZX_NZ = 64
const BORDER_PX_NZ = 128
const BORDER_ALL = 255

const BORDER_CORNERS = BORDER_PX_PZ | BORDER_NX_PZ | BORDER_NX_NZ | BORDER_PX_NZ
const BORDER_EDGES = BORDER_PX_ZZ | BORDER_ZX_PZ | BORDER_NX_ZZ | BORDER_ZX_NZ

const BORDER_LEFT = BORDER_NX_PZ | BORDER_NX_ZZ | BORDER_NX_NZ
const BORDER_UP = BORDER_PX_NZ | BORDER_ZX_NZ | BORDER_NX_NZ
const BORDER_RIGHT = BORDER_PX_NZ | BORDER_PX_ZZ | BORDER_PX_PZ
const BORDER_DOWN = BORDER_NX_PZ | BORDER_ZX_PZ | BORDER_PX_PZ

const BORDER_CORNER_ROOM = BORDER_UP | BORDER_LEFT
const BORDER_EDGE_ROOM = BORDER_UP
const BORDER_ROOM = BORDER_NONE
const BORDER_INTERSECTION_3_HALL = BORDER_UP | BORDER_NX_PZ | BORDER_PX_PZ
const BORDER_END_HALL = BORDER_UP | BORDER_STRAIGHT_HALL
const BORDER_STRAIGHT_HALL = BORDER_LEFT | BORDER_RIGHT
const BORDER_CORNER_1_EXIT_ROOM = BORDER_NX_NZ | BORDER_RIGHT
const BORDER_CORNER_2_EXIT_ROOM = BORDER_NX_NZ | BORDER_PX_NZ | BORDER_PX_PZ
const BORDER_EDGE_EXIT_ROOM = BORDER_NX_NZ | BORDER_PX_NZ
const BORDER_CORNER_OVERLAP_ROOM = BORDER_NX_NZ | BORDER_PX_PZ
const BORDER_INTERSECTION_4_HALL = BORDER_CORNERS
const BORDER_CORNER_HALL = BORDER_DOWN | BORDER_RIGHT | BORDER_NX_NZ
const BORDER_CORNER_CONVEX_ROOM = BORDER_NX_NZ
const BORDER_SINGLE = BORDER_ALL

const TYPE_TO_BORDERS : Dictionary[ int, int ] = {
	TYPE_CORNER_ROOM: BORDER_CORNER_ROOM,
	TYPE_EDGE_ROOM: BORDER_EDGE_ROOM,
	TYPE_ROOM: BORDER_ROOM,
	TYPE_INTERSECTION_3_HALL: BORDER_INTERSECTION_3_HALL,
	TYPE_END_HALL: BORDER_END_HALL,
	TYPE_STRAIGHT_HALL: BORDER_STRAIGHT_HALL,
	TYPE_CORNER_1_EXIT_ROOM: BORDER_CORNER_1_EXIT_ROOM,
	TYPE_CORNER_2_EXIT_ROOM: BORDER_CORNER_2_EXIT_ROOM,
	TYPE_EDGE_EXIT_ROOM: BORDER_EDGE_EXIT_ROOM,
	TYPE_CORNER_OVERLAP_ROOM: BORDER_CORNER_OVERLAP_ROOM,
	TYPE_INTERSECTION_4_HALL: BORDER_INTERSECTION_4_HALL,
	TYPE_CORNER_HALL: BORDER_CORNER_HALL,
	TYPE_CORNER_CONVEX_ROOM: BORDER_CORNER_CONVEX_ROOM,
	TYPE_SINGLE: BORDER_SINGLE,
}

const BORDER_TYPE_TO_DIRECTION : Dictionary[ int, Vector2 ] = {
	BORDER_PX_ZZ: Vector2(+1, 0),
	BORDER_PX_PZ: Vector2(+1,+1),
	BORDER_ZX_PZ: Vector2( 0,+1),
	BORDER_NX_PZ: Vector2(-1,+1),
	BORDER_NX_ZZ: Vector2(-1, 0),
	BORDER_NX_NZ: Vector2(-1,-1),
	BORDER_ZX_NZ: Vector2( 0,-1),
	BORDER_PX_NZ: Vector2(+1,-1),
}

const DIRECTION_TO_BORDER_TYPE : Dictionary[ Vector2i, int ] = {
	Vector2i(+1, 0): BORDER_PX_ZZ,
	Vector2i(+1,+1): BORDER_PX_PZ,
	Vector2i( 0,+1): BORDER_ZX_PZ,
	Vector2i(-1,+1): BORDER_NX_PZ,
	Vector2i(-1, 0): BORDER_NX_ZZ,
	Vector2i(-1,-1): BORDER_NX_NZ,
	Vector2i( 0,-1): BORDER_ZX_NZ,
	Vector2i(+1,-1): BORDER_PX_NZ,
}

# Rotates 45, +shift = clockwise, -shift = counter-clockwise
static func rotate_direction(mask: int, shift: int) -> int:
	shift = posmod( shift, 8 )
	return ((mask << shift) | (mask >> (8 - shift))) & BORDER_ALL

# Mirrors a mask left to right, so walls on the -X side end up on the +X side and the other way around
static func mirror_direction(mask: int) -> int:
	var result := BORDER_NONE
	for border in BORDER_TYPE_TO_DIRECTION:
		if mask & border:
			var direction := BORDER_TYPE_TO_DIRECTION[ border ]
			result |= DIRECTION_TO_BORDER_TYPE[ Vector2i( -direction.x, direction.y ) ]
	return result
#endregion

# What type of room is this?
var type = TYPE_NONE
# This value represents all edges and corners that have a wall (Black | Gray on the shape index used in map_layout)
var borders : int = BORDER_ALL
# This contains references to all rooms (diagonal and orthoganal) that connect to this room
var neighbors : Dictionary[ Vector2i, Room ]

# Return true if added neighbor succesfully, if space already occupide or otherwise failed: false
func add_neighbor(dir: Vector2i, room_ref: Room) -> bool:
	if neighbors.has( dir ): return false
	neighbors[ dir ] = room_ref
	return true

#region walls, floor and ceiling
## Two rooms that share a side both have a wall there, in the same spot, and each is lit from its own side.
## Drawn on top of each other they flicker (and an exhibit on one shows through the other), so every room
## draws its walls this far inside itself. Props against a wall go on it where it's drawn.
const WALL_INSET := 0.05
const FLOOR_SCENE : PackedScene = preload( "res://prefabs/rooms/floor.tscn" )
const CEILING_SCENE : PackedScene = preload( "res://prefabs/rooms/ceiling.tscn" )

## This room's baked light for each way its walls can face, by borders. Made by Project > Tools > Bake Room
## Lighting: the floor and ceiling never turn with the room, so which way its walls face changes its light.
@export var light_bakes : Dictionary[ int, LightmapGIData ]

## Moves each wall (a box with no thickness) WALL_INSET toward the middle of the room
func inset_walls() -> void:
	for wall : MeshInstance3D in find_children( "*", "MeshInstance3D", false, true ):
		var box := wall.mesh as BoxMesh
		if not box: continue
		var thin := [ box.size.x, box.size.y, box.size.z ].find( 0.0 )
		if thin == -1: continue
		var across := wall.basis[ thin ].normalized()
		wall.position -= across * signf( across.dot( wall.position ) ) * WALL_INSET

## The floor and ceiling every room gets. They aren't part of the room scenes, so their textures never turn
## with a room and line up from room to room (see pose_floor_and_ceiling).
static func make_floor_and_ceiling() -> Node3D:
	var floor_and_ceiling := Node3D.new()
	floor_and_ceiling.name = "FloorAndCeiling"
	floor_and_ceiling.add_child( FLOOR_SCENE.instantiate() )
	floor_and_ceiling.add_child( CEILING_SCENE.instantiate() )
	return floor_and_ceiling

## Turns the floor and ceiling back by the room's quarter turns, so their textures face the same way as every
## other room's. The ceiling's light fixture and lights still turn with the room.
static func pose_floor_and_ceiling(floor_and_ceiling: Node3D, turns: int) -> void:
	floor_and_ceiling.rotation.y = turns * PI / 2
	var with_room := Transform3D( Basis( Vector3.UP, -turns * PI / 2 ), Vector3.ZERO )
	for part : Node3D in floor_and_ceiling.get_node( "Ceiling" ).get_children(): part.transform = with_room * part.transform

## Adds the floor and ceiling (see pose_floor_and_ceiling) and the light baked for the way this room's walls
## face. Without that bake the room's lights stay live.
func add_floor_and_ceiling(turns: int) -> void:
	var floor_and_ceiling := make_floor_and_ceiling()
	pose_floor_and_ceiling( floor_and_ceiling, turns )
	add_child( floor_and_ceiling )
	if not light_bakes.has( borders ): return
	var lightmap := LightmapGI.new()
	lightmap.light_data = light_bakes[ borders ]
	add_child( lightmap )
#endregion

#region lights
# How long this room's lights take to fade in when RoomContainer turns them on
const LIGHT_FADE_TIME := 0.5
# Render layer for lightmapped meshes. Lightmaps replace the sky's ambient light, so RoomContainer's sky
# fill lights light only this layer to put it back.
const BAKED_LIGHT_LAYER := 20

# Whether this room's lights are on. RoomContainer switches rooms on and off as the camera moves.
var lit := true
# Every live light in this room (the ceiling's, and any added later) that starts out visible, with its color
var _lights : Array[ Light3D ]
var _light_colors : Array[ Color ]
var _light_fade : Tween

func _ready() -> void:
	# A LightmapGI bakes the Static lights under its parent (like the ceiling's up-light). Once baked, they
	# only need to exist in the editor: hiding them keeps them out of the web build's live light limit.
	var baked_under : Array[ Node ]
	for lightmap : LightmapGI in find_children( "*", "LightmapGI", true, false ):
		if not lightmap.light_data: continue
		baked_under.append( lightmap.get_parent() )
		# user_data lists each baked mesh as [path, uv rect, slice, sub-instance]
		var users : Array = lightmap.light_data.get( "user_data" )
		for i in range( 0, users.size(), 4 ):
			var mesh := lightmap.get_node_or_null( users[ i ] ) as VisualInstance3D
			if mesh: mesh.set_layer_mask_value( BAKED_LIGHT_LAYER, true )
	for light : Light3D in find_children( "*", "Light3D", true, false ):
		if not light.visible: continue # Hidden on purpose, leave it alone
		if light.light_bake_mode == Light3D.BAKE_STATIC and baked_under.any( func(node: Node) -> bool: return node.is_ancestor_of( light ) ):
			light.visible = false
			continue
		_lights.append( light )
		_light_colors.append( light.light_color )

func light_count() -> int:
	return _lights.size()

# Turns this room's lights off at once, or back on with a fade.
# The fade goes through the color, not the energy: Godot picks the lights for each mesh partly by
# energy when a light switches on, so a light switched on at zero energy could lose its spot.
func set_lit(on: bool) -> void:
	if on == lit: return
	lit = on
	if _light_fade: _light_fade.kill()
	for light in _lights: light.visible = on
	if not on or _lights.is_empty(): return
	_light_fade = create_tween().set_parallel()
	for i in _lights.size():
		_lights[ i ].light_color = Color.BLACK
		_light_fade.tween_property( _lights[ i ], "light_color", _light_colors[ i ], LIGHT_FADE_TIME )
#endregion
