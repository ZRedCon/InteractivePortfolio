extends Node3D

const ROOM_SIZE := 10.0

const ROOM_SCENES : Dictionary[ int, PackedScene ] = {
	Room.TYPE_CORNER_ROOM: preload( "res://prefabs/rooms/corner_room.tscn" ),
	Room.TYPE_EDGE_ROOM: preload( "res://prefabs/rooms/edge_room.tscn" ),
	Room.TYPE_ROOM: preload( "res://prefabs/rooms/full_room.tscn" ),
	Room.TYPE_INTERSECTION_3_HALL: preload( "res://prefabs/rooms/t_intersection_hall.tscn" ),
	Room.TYPE_END_HALL: preload( "res://prefabs/rooms/end_hall.tscn" ),
	Room.TYPE_STRAIGHT_HALL: preload( "res://prefabs/rooms/straight_room.tscn" ),
	Room.TYPE_CORNER_1_EXIT_ROOM: preload( "res://prefabs/rooms/corner_room_one_exit.tscn" ),
	Room.TYPE_CORNER_2_EXIT_ROOM: preload( "res://prefabs/rooms/corner_room_two_exit.tscn" ),
	Room.TYPE_EDGE_EXIT_ROOM: preload( "res://prefabs/rooms/edge_room_exit.tscn" ),
	Room.TYPE_CORNER_OVERLAP_ROOM: preload( "res://prefabs/rooms/corner_overlap_room.tscn" ),
	Room.TYPE_INTERSECTION_4_HALL: preload( "res://prefabs/rooms/four_way_intersection_hall.tscn" ),
	Room.TYPE_CORNER_HALL: preload( "res://prefabs/rooms/corner_hall.tscn" ),
	Room.TYPE_CORNER_CONVEX_ROOM: preload( "res://prefabs/rooms/corner_convex_room.tscn" ),
	Room.TYPE_SINGLE: preload( "res://prefabs/rooms/single_room.tscn" ),
}

# Every room that's been built, by the map cell it was built from
var rooms : Dictionary[ Vector2i, Room ]

# The web build (Compatibility renderer) draws at most this many lights of each kind per frame and
# drops the rest in no useful order, which is what made whole rooms go dark. So only the rooms near
# the camera get their lights on, and never more lights than this. Raise Project Settings > Rendering >
# Limits > OpenGL > Max Renderable Lights to light more rooms at once. Lights that aren't in a room
# aren't counted here, but they use up the same limit.
var light_budget : int = ProjectSettings.get_setting( "rendering/limits/opengl/max_renderable_lights" )
# The cell the camera was in when the lit rooms were last picked
var _lit_from := Vector2i.MAX

func _ready() -> void:
	generate()
	light_rooms_near_camera()

func _process(_delta: float) -> void:
	light_rooms_near_camera()

# Picks the rooms to light again whenever the camera moves into another cell
func light_rooms_near_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera: return
	var at := to_local( camera.global_position ) / ROOM_SIZE
	# Wait until the camera is a meter past the edge, so walking along an edge doesn't keep switching rooms
	var lit_center := Vector2( _lit_from - MapLayout.start_tile )
	if absf( at.x - lit_center.x ) < 0.6 and absf( at.z - lit_center.y ) < 0.6: return
	var cell := Vector2i( roundi( at.x ), roundi( at.z ) ) + MapLayout.start_tile
	_lit_from = cell

	# Count the steps out from the camera's room through the openings, the way you'd see down a hall
	var steps : Dictionary[ Room, int ]
	var to_visit : Array[ Room ]
	if rooms.has( cell ):
		steps[ rooms[ cell ] ] = 0
		to_visit.append( rooms[ cell ] )
	while not to_visit.is_empty():
		var room : Room = to_visit.pop_front()
		for other : Room in room.neighbors.values():
			if steps.has( other ): continue
			steps[ other ] = steps[ room ] + 1
			to_visit.append( other )
	# Light passes through walls, so every room touching the camera's room helps light it
	for direction in Room.DIRECTION_TO_BORDER_TYPE:
		if rooms.has( cell + direction ): steps[ rooms[ cell + direction ] ] = 1

	# Fewest steps first, then nearest. Rooms the steps never reached come last, nearest first.
	var from := Vector3( at.x, 0, at.z ) * ROOM_SIZE
	var comes_first := func(a: Room, b: Room) -> bool:
		var steps_a : int = steps.get( a, rooms.size() )
		var steps_b : int = steps.get( b, rooms.size() )
		if steps_a != steps_b: return steps_a < steps_b
		return a.position.distance_squared_to( from ) < b.position.distance_squared_to( from )
	var order : Array = rooms.values()
	order.sort_custom( comes_first )
	var lights_on := 0
	for room : Room in order:
		var fits := lights_on + room.light_count() <= light_budget
		room.set_lit( fits )
		if fits: lights_on += room.light_count()

func generate() -> void:
	# First pass: build out from the start tile through each room's openings. Tiles it can't reach
	# get built afterwards, so the whole map is there to look over.
	_build_from( MapLayout.start_tile )
	var reachable := rooms.size()
	for cell in MapLayout.get_used_cells(): _build_from( cell )
	if rooms.size() > reachable:
		push_warning( "%d of the map's %d tiles can't be reached from start_tile %s" % [ rooms.size() - reachable, rooms.size(), MapLayout.start_tile ] )

	# Second pass: a room's neighbors are the rooms it opens into, diagonals included
	for cell : Vector2i in rooms:
		var room := rooms[ cell ]
		for border in Room.BORDER_TYPE_TO_DIRECTION:
			if room.borders & border: continue # Wall that way
			var direction := Vector2i( Room.BORDER_TYPE_TO_DIRECTION[ border ] )
			var other : Room = rooms.get( cell + direction )
			# The other room has to be open back toward this one
			if other and not other.borders & Room.DIRECTION_TO_BORDER_TYPE[ -direction ]:
				room.add_neighbor( direction, other )

# Builds the room at a cell, then every room it leads to that hasn't been built yet
func _build_from(start: Vector2i) -> void:
	var to_visit : Array[ Vector2i ] = [ start ]
	while not to_visit.is_empty():
		var cell : Vector2i = to_visit.pop_back()
		if rooms.has( cell ) or MapLayout.get_room_type( cell ) == Room.TYPE_NONE: continue
		var room := _spawn_room( cell )
		for border in Room.BORDER_TYPE_TO_DIRECTION:
			if not room.borders & border: to_visit.append( cell + Vector2i( Room.BORDER_TYPE_TO_DIRECTION[ border ] ) )

func _spawn_room(cell: Vector2i) -> Room:
	var type : int = MapLayout.get_room_type( cell )
	var room : Room = ROOM_SCENES[ type ].instantiate()
	room.type = type
	room.borders = MapLayout.get_borders( cell )

	# Turn the room a quarter turn at a time until its walls line up with the tile's
	var walls : int = Room.TYPE_TO_BORDERS[ type ]
	var turns := _quarter_turns( walls, room.borders )
	if turns == -1:
		# The tile is drawn as a mirror image of the room, which no amount of turning can match
		_mirror( room )
		turns = _quarter_turns( Room.mirror_direction( walls ), room.borders )

	var offset : Vector2i = cell - MapLayout.start_tile
	room.position = Vector3( offset.x, 0, offset.y ) * ROOM_SIZE
	room.rotation.y = -turns * PI / 2 # Our turns are clockwise seen from above, Godot's are counter-clockwise
	room.name = "%s %s" % [ room.name, cell ] # Shows which tile each room came from in the remote scene tree
	add_child( room )
	rooms[ cell ] = room
	return room

# How many quarter turns clockwise take walls to wanted, or -1 if no number of turns does
static func _quarter_turns(walls: int, wanted: int) -> int:
	for turns in 4:
		if Room.rotate_direction( walls, turns * 2 ) == wanted: return turns
	return -1

# Mirrors a room left to right by moving each piece to its mirrored spot. The pieces keep their own
# shapes, so nothing gets the negative scale that physics can't handle.
static func _mirror(room: Room) -> void:
	for child in room.get_children():
		var piece := child as Node3D
		if piece: piece.transform = Transform3D.FLIP_X * piece.transform * Transform3D.FLIP_X
