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

## Moved to the middle of the start tile once the museum is built
@export var player : Node3D

# Every room that's been built, by the map cell it was built from
var rooms : Dictionary[ Vector2i, Room ]
# The room group each grouped cell belongs to. Those cells get their group's scene instead of rooms.
var group_cells : Dictionary[ Vector2i, RoomGroup ]

# The web build (Compatibility renderer) draws at most this many lights of each kind per frame and
# drops the rest in no useful order, which is what made whole rooms go dark. So only the rooms near
# the camera get their lights on, and never more lights than this. Raise Project Settings > Rendering >
# Limits > OpenGL > Max Renderable Lights to light more rooms at once. Lights that aren't in a room
# aren't counted here, but they use up the same limit.
var light_budget : int = ProjectSettings.get_setting( "rendering/limits/opengl/max_renderable_lights" )
# The cell the camera was in when the lit rooms were last picked
var _lit_from := Vector2i.MAX

## How strongly the floors and carpets shine under the baked ceiling lights (see _add_sheen). 0.5 came
## closest to the live lights when renders of the two were compared.
const SHEEN := 0.5

func _ready() -> void:
	generate()
	# The start tile's middle is this node's origin. Just above the carpet (0.05 m), so the player lands on it.
	if player: player.global_position = to_global( Vector3.UP * 0.1 )
	light_rooms_near_camera()
	_add_sky_fill()
	_add_sheen()

# A lightmap only holds the light a surface soaks up, not the shine of the ceiling lights reflecting off it
# (that changes with where you stand), so the carpet looked deeper red and the stone floor flat once baked.
# This light shines straight down on the baked meshes with almost no energy but a huge specular, so it adds
# that shine and next to nothing else.
func _add_sheen() -> void:
	var sheen := DirectionalLight3D.new()
	sheen.name = "Sheen"
	sheen.basis = Basis.looking_at( Vector3.DOWN, Vector3.FORWARD )
	sheen.light_energy = 0.001
	sheen.light_specular = SHEEN / sheen.light_energy
	sheen.light_bake_mode = Light3D.BAKE_DISABLED
	sheen.light_cull_mask = 1 << ( Room.BAKED_LIGHT_LAYER - 1 )
	sheen.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child( sheen )

# Lightmapped surfaces don't get the sky's ambient light (its warm side is what tints the walls). So the
# sky is measured once at startup, by rendering a white quad lit only by it, off screen, facing each way a
# wall or floor can face. Then one unshadowed light per direction puts that light back, on the baked-light
# layer only. Changing the sky needs no re-bake.
func _add_sky_fill() -> void:
	var environment := get_world_3d().environment
	if not environment: return
	var sky_only := environment.duplicate() as Environment
	sky_only.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	sky_only.tonemap_exposure = 1.0
	sky_only.glow_enabled = false
	sky_only.adjustment_enabled = false
	sky_only.fog_enabled = false
	var probe := SubViewport.new()
	probe.size = Vector2i( 8, 8 )
	probe.own_world_3d = true
	probe.render_target_update_mode = SubViewport.UPDATE_ALWAYS # it's never on screen, so it must be told to draw
	var world := WorldEnvironment.new()
	world.environment = sky_only
	probe.add_child( world )
	var white := StandardMaterial3D.new()
	white.metallic_specular = 0.0 # no reflections, just the ambient light
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	( quad.mesh as QuadMesh ).size = Vector2( 4, 4 )
	quad.material_override = white
	probe.add_child( quad )
	var camera := Camera3D.new()
	camera.fov = 30.0
	probe.add_child( camera )
	add_child( probe )
	# Ceilings face down, where this sky is nearly black, so they're left out
	for facing in [ Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.UP ]:
		var up := Vector3.FORWARD if facing == Vector3.UP else Vector3.UP
		quad.basis = Basis.looking_at( -facing, up ) # a QuadMesh faces +Z
		camera.position = facing * 3.0
		camera.look_at( Vector3.ZERO, up )
		for i in 2: await RenderingServer.frame_post_draw
		var ambient := probe.get_texture().get_image().get_pixel( 4, 4 ).srgb_to_linear()
		var energy := maxf( ambient.r, maxf( ambient.g, ambient.b ) )
		if energy < 0.002: continue
		var fill := DirectionalLight3D.new()
		fill.name = "SkyFill %s" % facing
		fill.basis = Basis.looking_at( -facing, up ) # shines onto surfaces that face that way
		fill.light_color = Color( ambient.r / energy, ambient.g / energy, ambient.b / energy ).linear_to_srgb()
		fill.light_energy = energy
		fill.light_specular = 0.0
		fill.light_bake_mode = Light3D.BAKE_DISABLED
		fill.light_cull_mask = 1 << ( Room.BAKED_LIGHT_LAYER - 1 )
		fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		add_child( fill )
	probe.queue_free()

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
	for group : RoomGroup in MapLayout.get_room_groups():
		for cell in group.get_used_cells(): group_cells[ cell ] = group

	# First pass: build out from the start tile through each room's openings. Tiles it can't reach
	# get built afterwards, so the whole map is there to look over.
	_build_from( MapLayout.start_tile )
	var reachable := rooms.size()
	for cell in MapLayout.get_used_cells(): _build_from( cell )
	if rooms.size() > reachable:
		push_warning( "%d of the map's %d tiles can't be reached from start_tile %s" % [ rooms.size() - reachable, rooms.size(), MapLayout.start_tile ] )
	var unbaked := rooms.values().filter( func(room: Room) -> bool: return not room.light_bakes.has( room.borders ) )
	if not unbaked.is_empty():
		push_warning( "%d rooms have no baked light for the way their walls face, so their lights are live. Run Project > Tools > Bake Room Lighting." % unbaked.size() )

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

	_build_room_groups()
	_build_props()

# Builds the room at a cell, then every room it leads to that hasn't been built yet. A room group's cells
# aren't built, but the walk goes through them every way, since where its scene has doors isn't known.
func _build_from(start: Vector2i) -> void:
	var to_visit : Array[ Vector2i ] = [ start ]
	var walked : Dictionary[ Vector2i, bool ] # Grouped cells already walked through
	while not to_visit.is_empty():
		var cell : Vector2i = to_visit.pop_back()
		if rooms.has( cell ) or walked.has( cell ): continue
		var walls := Room.BORDER_NONE
		if group_cells.has( cell ): walked[ cell ] = true
		elif MapLayout.get_room_type( cell ) != Room.TYPE_NONE: walls = _spawn_room( cell ).borders
		else: continue
		for border in Room.BORDER_TYPE_TO_DIRECTION:
			if not walls & border: to_visit.append( cell + Vector2i( Room.BORDER_TYPE_TO_DIRECTION[ border ] ) )

# Builds each room group's scene, unturned, with its origin at the group's top-left corner
func _build_room_groups() -> void:
	for group : RoomGroup in MapLayout.get_room_groups():
		var problems := group.get_problems()
		if not problems.is_empty():
			push_error( "%s: %s" % [ group.describe(), ", ".join( problems ) ] )
			continue
		var built := group.scene.instantiate()
		if not built is Node3D:
			push_error( "%s: its scene, %s, needs a Node3D at its root" % [ group.describe(), group.scene.resource_path ] )
			built.free()
			continue
		built.position = _map_to_local( Vector2( group.get_top_left() ) )
		built.name = "%s %s" % [ group.name, group.get_top_left() ]
		add_child( built )

# Builds every prop placed on the map. It waits for the entries first, since exhibits show them and web
# builds download them after startup.
func _build_props() -> void:
	if not FileIO.Instance.loaded: await FileIO.Instance.entries_loaded
	for display : PropDisplay in MapLayout.get_props():
		var problems := display.get_problems()
		var cell := display.get_cell()
		if not rooms.has( cell ) and not group_cells.has( cell ):
			problems.append( "there's no room in that cell" )
		elif display is EdgePropDisplay and rooms.has( cell ) and rooms[ cell ].borders & Room.DIRECTION_TO_BORDER_TYPE[ Vector2i( (display as EdgePropDisplay).get_wall() ) ] == 0:
			problems.append( "that side of the room has no wall" )
		if not problems.is_empty():
			push_error( "%s: %s" % [ display.describe(), ", ".join( problems ) ] )
			continue
		if not display.is_built(): continue
		var prop := display.make_prop()
		prop.position = _map_to_local( display.get_map_point() )
		if display is EdgePropDisplay and rooms.has( cell ): # On the wall where it's drawn, a little inside the room
			var facing : Vector2 = EdgePropDisplay.FACING[ ( display as EdgePropDisplay ).start_direction ]
			prop.position += Vector3( facing.x, 0.0, facing.y ) * Room.WALL_INSET
		prop.name = "%s %s" % [ display.name, cell ] # Shows which prop it is in the remote scene tree
		add_child( prop )
		display.setup_prop( prop )
	ExhibitDisplay.check_groups( MapLayout )

# A point on the map, in cells (( 2.5, 0.5 ) is the middle of cell ( 2, 0 )), on the floor in this node's space
func _map_to_local(point: Vector2) -> Vector3:
	var offset := point - Vector2( 0.5, 0.5 ) - Vector2( MapLayout.start_tile )
	return Vector3( offset.x, 0.0, offset.y ) * ROOM_SIZE

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

	room.inset_walls()

	var offset : Vector2i = cell - MapLayout.start_tile
	room.position = Vector3( offset.x, 0, offset.y ) * ROOM_SIZE
	room.rotation.y = -turns * PI / 2 # Our turns are clockwise seen from above, Godot's are counter-clockwise
	room.add_floor_and_ceiling( turns ) # These don't turn, so they line up from room to room
	room.name = "%s %s" % [ room.name, cell ] # Shows which tile each room came from in the remote scene tree
	add_child( room )
	rooms[ cell ] = room
	return room

# How many quarter turns clockwise take walls to wanted, or -1 if no number of turns does
static func _quarter_turns(walls: int, wanted: int) -> int:
	for turns in 4:
		if Room.rotate_direction( walls, turns * 2 ) == wanted: return turns
	return -1

# Mirrors a room left to right by moving each piece to its mirrored spot. The pieces keep their own shape
# (their walls, carpets and pillars look the same mirrored), since physics and the light baker can't handle
# the negative scale of a true mirror image. Room Baker bakes mirrored rooms posed by this same function.
static func _mirror(room: Node3D) -> void:
	for child in room.get_children():
		var piece := child as Node3D
		if piece: piece.transform = Transform3D.FLIP_X * piece.transform * Transform3D.FLIP_X
