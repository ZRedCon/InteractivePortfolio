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

func _ready() -> void:
	generate()

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
