@tool
extends RefCounted

# Bakes every room's lighting into lightmaps, so the web build draws no live room lights.
# Run it from Project > Tools > Bake Room Lighting after changing a room, the floor or the ceiling.
#
# RoomContainer turns each room to fit its tile, but turns the floor and ceiling back (Room.pose_floor_and_ceiling)
# so their textures line up from room to room. That makes a room's lightmaps depend on which way its walls face,
# so each room is baked once for every way its walls can face, into Room.light_bakes. For each of those it:
#   - poses the room the way RoomContainer builds it: mirrored if needed, with the floor and ceiling turned back
#   - copies the ceiling's down-light to where each open neighbor's ceiling is ("BakeLights"), so light coming
#     in through an opening gets baked too (walls still block it)
#   - bakes it into lightmaps/<room>_<way>.lmbake
# The room scene keeps only the bakes, and its own meshes get lightmap UVs (UV2). Lightmapped surfaces don't
# get the sky's ambient light; RoomContainer measures the sky in game and puts it back with a few lights, so
# changing the sky needs no re-bake.

const ROOM_SIZE := 10.0
# Meters per lightmap texel. The ceiling lights are soft, so 0.5 is enough for floors, ceilings and carpets.
const TEXEL_SIZE := 0.5
# Walls (the boxes with no thickness) get this many times finer texels. A wall's light changes fast near the
# ceiling lights, and at 0.5 m texels every wall had a faint bright line along its top and sides, which showed
# at the borders between tiles. About 2 makes walls match live lighting to within a few percent; 1.9 still lets
# a 10 m wall's lightmap fit on a 128 texel atlas page (at 2 most rooms' lightmaps came out twice the size).
const WALL_DETAIL := 1.9
# Texels left empty around each mesh's block in a lightmap. Godot pads blocks by the denoiser's range even with
# the denoiser off (10 by default), which also kept walls off 128 texel pages.
const BLOCK_PADDING := 4
# Directional lightmaps let normal maps react to the baked light, at four times the size
const DIRECTIONAL := true
# Live lights don't bounce, so neither does the bake: any bounce makes it look different from live lighting
const BOUNCES := 0
# Room meshes' UV2 padding, in their own lightmap pixels (2.5 of them make one baked texel at TEXEL_SIZE 0.5).
# Godot's default of 2 is under one baked texel, so a wall's thin edge faces bled into its edges and drew dark
# lines where rooms meet. 4 keeps every face over a texel and a half apart.
const UV2_PADDING := 4.0
# Godot's lightmapper works out each texel's light at the texel's lower left corner, not its middle (it moves
# its texel grid on purpose, see godotengine/godot#69126), while the game reads each texel as the light at its
# middle. Left alone, every room's light slid half a texel (25 cm) along the lightmap: walls came out too bright
# under the ceiling, too dark at the floor, and lighter on one side, so the borders between tiles showed.
# After each bake, every mesh reads its lightmap this many texels over, which puts the light back where it was
# worked out (measured: the walls, floors and ceilings of a test room then match live lighting all the way across).
const TEXEL_FIX := Vector2( 0.5, -0.5 )
const LIGHTMAP_DIR := "res://prefabs/rooms/lightmaps/"

var _tree : SceneTree
var _container : GDScript # RoomContainer's script, so rooms get turned and mirrored here the way it does
var _made : Dictionary[ String, bool ] # Every lightmap file this bake made, so leftovers can be cleared out

func bake_all() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_container = load( "res://Scenes/room_container.gd" )
	if not DirAccess.dir_exists_absolute( LIGHTMAP_DIR ):
		DirAccess.make_dir_recursive_absolute( LIGHTMAP_DIR )
		EditorInterface.get_resource_filesystem().scan() # So the editor knows the folder before lightmaps go in it
	var started := Time.get_ticks_msec()
	var scenes : Dictionary = _container.ROOM_SCENES
	for type : int in scenes:
		await _bake_room( ( scenes[ type ] as PackedScene ).resource_path, type )
	_remove_leftovers()
	EditorInterface.get_resource_filesystem().scan()
	print( "Bake Room Lighting: done in %.1f s" % ( ( Time.get_ticks_msec() - started ) / 1000.0 ) )

func _bake_room(path: String, type: int) -> void:
	var was_open := EditorInterface.get_open_scenes().has( path )
	EditorInterface.open_scene_from_path( path )
	await _frames( 3 )
	var room := EditorInterface.get_edited_scene_root() as Node3D
	if not room or room.scene_file_path != path:
		push_error( "Bake Room Lighting: couldn't open %s" % path )
		return

	# Made by an older version of this tool, which kept one bake in the scene
	for old in [ "LightmapGI", "BakeLights" ]:
		var node := room.get_node_or_null( old )
		if node: node.free()

	# Carpets are cut again, so a change to how carpets are made reaches every room and its bake
	for carpet : Carpet in room.find_children( "*", "Carpet", true, false ): carpet.cut( carpet.walls )

	# Room meshes: lightmap UVs, with texels the same size in meters however the mesh node is scaled
	var to_room := room.global_transform.affine_inverse()
	var resized : Dictionary[ Array, BoxMesh ] = {}
	for mesh : MeshInstance3D in room.find_children( "*", "MeshInstance3D", true, true ):
		if mesh.gi_mode != GeometryInstance3D.GI_MODE_STATIC or not mesh.mesh is PrimitiveMesh: continue
		_unstretch( mesh, resized )
		( mesh.mesh as PrimitiveMesh ).add_uv2 = true
		( mesh.mesh as PrimitiveMesh ).uv2_padding = UV2_PADDING
		var scale := ( to_room * mesh.global_transform ).basis.get_scale().abs()
		mesh.gi_lightmap_texel_scale = maxf( scale.x, maxf( scale.y, scale.z ) )
		var box := mesh.mesh as BoxMesh
		if box and [ box.size.x, box.size.y, box.size.z ].has( 0.0 ): mesh.gi_lightmap_texel_scale *= WALL_DETAIL

	var bakes : Dictionary[ int, LightmapGIData ] = {}
	var walls : int = Room.TYPE_TO_BORDERS[ type ]
	for layout in _wall_layouts( walls ):
		var borders : int = layout[ 0 ]
		var turns : int = layout[ 1 ]
		var mirrored : bool = layout[ 2 ]
		var way := ( "mirrored_turn%d" if mirrored else "turn%d" ) % turns
		var data_path := LIGHTMAP_DIR + "%s_%s.lmbake" % [ path.get_file().get_basename(), way ]
		var t := Time.get_ticks_msec()
		var data := await _bake_layout( room, turns, mirrored, Room.mirror_direction( walls ) if mirrored else walls, data_path )
		if data: bakes[ borders ] = data
		print( "Bake Room Lighting: %s %s %s in %d ms" % [ path.get_file(), way, "baked" if data else "FAILED to bake", Time.get_ticks_msec() - t ] )
	room.set( "light_bakes", bakes )
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()
	if not was_open: EditorInterface.close_scene()
	await _frames( 2 )

# A box stretched by its node's scale (like the old box carpets: a 1 m box scaled to 5 x 0.1 x 10) gets as many lightmap
# texels on its thin sides as on its top, which made carpets most of every lightmap. So the stretch goes into the
# box's size and the node's scale goes back to 1. It looks exactly the same: a box's texture is mapped per face.
# Boxes stretched the same way share one resized box (resized: [ old box, stretch ] -> new box).
func _unstretch(mesh: MeshInstance3D, resized: Dictionary[ Array, BoxMesh ]) -> void:
	var box := mesh.mesh as BoxMesh
	var stretch := mesh.basis.get_scale().abs()
	if not box or stretch.is_equal_approx( Vector3.ONE ): return
	var key := [ box, stretch.snappedf( 0.0001 ) ]
	if not resized.has( key ):
		resized[ key ] = box.duplicate()
		resized[ key ].size = box.size * stretch
	mesh.mesh = resized[ key ]
	mesh.basis = mesh.basis.orthonormalized()

# Every borders value a room with these walls can be built with, in the order RoomContainer tries them, as
# [ borders, quarter turns, mirrored ]. Turns that give the same walls share a bake.
func _wall_layouts(walls: int) -> Array:
	var layouts := []
	var seen : Dictionary[ int, bool ] = {}
	for mirrored in [ false, true ]:
		var start := Room.mirror_direction( walls ) if mirrored else walls
		for turns in 4:
			var borders := Room.rotate_direction( start, turns * 2 )
			if seen.has( borders ): continue
			seen[ borders ] = true
			layouts.append( [ borders, turns, mirrored ] )
	return layouts

# Bakes the room posed with this many quarter turns, mirrored or not, the way RoomContainer builds it. The room
# itself stays unturned and the floor and ceiling turn the other way, which lights it the same. walls is the
# room's borders as posed, in its own space.
func _bake_layout(room: Node3D, turns: int, mirrored: bool, walls: int, data_path: String) -> LightmapGIData:
	if mirrored: _container._mirror( room )
	var floor_and_ceiling : Node3D = Room.make_floor_and_ceiling()
	Room.pose_floor_and_ceiling( floor_and_ceiling, turns )
	_add_to_bake( room, floor_and_ceiling )
	var bake_lights := _add_bake_lights( room, floor_and_ceiling, walls )

	var data : LightmapGIData = null
	var lightmap := LightmapGI.new()
	lightmap.name = "LightmapGI"
	_add_to_bake( room, lightmap )
	# Live area lights cast no shadows in the Compatibility renderer, so nothing casts one in the bake either:
	# every mesh is see-through to the bake's shadow rays while it bakes (each still gets its own light). And the
	# shadow rays go straight from each texel to each light's middle, not spread over the light's size or the
	# texel. Spread out, rays aimed above the ceiling light hit the ceiling and darkened the walls. Everything
	# gets its own settings back after the bake.
	var see_through := StandardMaterial3D.new()
	see_through.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	see_through.albedo_color = Color( 1.0, 1.0, 1.0, 0.0 )
	var materials : Dictionary[ GeometryInstance3D, Material ] = {}
	for mesh : GeometryInstance3D in room.find_children( "*", "GeometryInstance3D", true, false ):
		if mesh.gi_mode != GeometryInstance3D.GI_MODE_STATIC: continue
		materials[ mesh ] = mesh.material_override
		mesh.material_override = see_through
	var lights : Array[ Light3D ] = []
	lights.assign( room.find_children( "*", "Light3D", true, false ).filter( func(light: Light3D) -> bool: return light.light_bake_mode == Light3D.BAKE_STATIC ) )
	var shadow_settings : Array[ Vector2 ] = []
	for light in lights:
		shadow_settings.append( Vector2( light.light_size, light.shadow_blur ) )
		light.light_size = 0.0
		light.shadow_blur = 0.0
	if not lights.is_empty():
		lightmap.quality = LightmapGI.BAKE_QUALITY_HIGH
		lightmap.bounces = BOUNCES
		lightmap.directional = DIRECTIONAL
		# The denoiser blurs over 10 texels, which is most of a wall. It flattened the light down each wall and
		# darkened every edge, so it's off: with no bounces there's next to no noise to remove.
		lightmap.use_denoiser = false
		lightmap.denoiser_range = BLOCK_PADDING
		lightmap.environment_mode = LightmapGI.ENVIRONMENT_MODE_DISABLED # RoomContainer adds the sky in game
		lightmap.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_DISABLED
		lightmap.texel_scale = float( ProjectSettings.get_setting( "rendering/lightmapping/primitive_meshes/texel_size" ) ) / TEXEL_SIZE
		data = await _bake( lightmap, data_path )
	else:
		push_error( "Bake Room Lighting: %s has no Static lights to bake" % room.scene_file_path.get_file() )

	# Back the way the scene was
	for mesh in materials: mesh.material_override = materials[ mesh ]
	for i in lights.size():
		lights[ i ].light_size = shadow_settings[ i ].x
		lights[ i ].shadow_blur = shadow_settings[ i ].y
	for node : Node in [ lightmap, bake_lights, floor_and_ceiling ]:
		room.remove_child( node )
		node.free()
	if mirrored: _container._mirror( room ) # Mirroring twice puts every piece back
	return data

# Adds a node to the scene being baked. It gets an owner, because the bake skips nodes that have none.
func _add_to_bake(room: Node, node: Node) -> void:
	room.add_child( node )
	node.owner = room
	for child in node.get_children(): child.owner = room

# Copies of the ceiling's down-light where each open neighbor's ceiling is, so light coming in through an
# opening gets baked too. They're only ever in the bake.
func _add_bake_lights(room: Node3D, floor_and_ceiling: Node3D, walls: int) -> Node3D:
	var bake_lights := Node3D.new()
	bake_lights.name = "BakeLights"
	_add_to_bake( room, bake_lights )
	for light : Light3D in floor_and_ceiling.find_children( "*", "Light3D", true, false ):
		if light.light_bake_mode != Light3D.BAKE_STATIC or light.global_basis.z.y < 0.5: continue # Only lights shining down
		for border : int in Room.BORDER_TYPE_TO_DIRECTION:
			if walls & border: continue # Wall that way
			var direction : Vector2 = Room.BORDER_TYPE_TO_DIRECTION[ border ]
			var copy := light.duplicate() as Light3D
			copy.name = "%s %+d,%+d" % [ light.name, direction.x, direction.y ]
			bake_lights.add_child( copy )
			copy.owner = room
			copy.global_transform = Transform3D( light.global_basis.orthonormalized(), light.global_position + Vector3( direction.x, 0, direction.y ) * ROOM_SIZE )
	return bake_lights

# Presses the editor's own Bake Lightmaps button for this LightmapGI (LightmapGI.bake() isn't available to
# scripts). Its save dialog is answered with data_path, so nothing pops up. Returns the bake, or null.
func _bake(lightmap: LightmapGI, data_path: String) -> LightmapGIData:
	EditorInterface.edit_node( lightmap )
	await _frames( 2 )
	# The bake imports its lightmap right away, which fails while the editor is scanning the project's files
	while EditorInterface.get_resource_filesystem().is_scanning(): await _frames( 1 )
	# The button that LightmapGI's own editor plugin listens to (found that way so any editor language works)
	var button : Button
	for candidate : Button in EditorInterface.get_base_control().find_children( "*", "Button", true, false ):
		for connection in candidate.pressed.get_connections():
			var target := ( connection.callable as Callable ).get_object()
			if target and target.get_class() == "LightmapGIEditorPlugin": button = candidate
	var dialogs := button.find_children( "*", "EditorFileDialog", true, false ) if button else []
	if dialogs.is_empty():
		push_error( "Bake Room Lighting: couldn't find the editor's Bake Lightmaps button (did a Godot update change it?)" )
		return null
	( dialogs[ 0 ] as EditorFileDialog ).file_selected.emit( data_path )
	if not lightmap.light_data or lightmap.light_data.resource_path != data_path: return null
	_made[ data_path ] = true
	_made[ data_path.get_basename() + ".exr" ] = true
	_made[ data_path.get_basename() + ".exr.import" ] = true
	_fix_texel_offset( lightmap.light_data )
	return lightmap.light_data

# Moves where every mesh reads its lightmap by TEXEL_FIX (see there) and saves the bake again.
# Moved over, a face whose top edge is the top of its mesh's block in the lightmap (a wall's room side, a floor)
# reads the texel row above that block too, which the lightmapper leaves black. So that row first gets the light
# the face would have there, carried on from the two rows under it.
func _fix_texel_offset(data: LightmapGIData) -> void:
	var atlas : TextureLayered = data.lightmap_textures[ 0 ]
	var texel := Vector2( 1.0 / atlas.get_width(), 1.0 / atlas.get_height() )
	var users : Array = data.get( "user_data" ) # [ mesh path, uv rect, slice, sub-instance ] per mesh
	if data.lightmap_textures.size() == 1:
		var file := ProjectSettings.globalize_path( atlas.resource_path )
		var image := Image.load_from_file( file )
		# The .exr stacks the atlas's layers top to bottom; directional lightmaps have four layers per slice
		var layers_per_slice := 4 if data.is_using_spherical_harmonics() else 1
		for i in range( 0, users.size(), 4 ):
			var uv : Rect2 = users[ i + 1 ]
			var block := Rect2i( Vector2i( ( uv.position / texel ).round() ), Vector2i( ( uv.size / texel ).round() ) )
			var first_layer : int = users[ i + 2 ] * layers_per_slice
			var top := block.position.y - 1
			if top < 0: continue
			for x in range( maxi( block.position.x - 1, 0 ), mini( block.end.x + 1, atlas.get_width() ) ):
				var at := func(layer: int, y: int) -> Color: return image.get_pixel( x, ( first_layer + layer ) * atlas.get_height() + y )
				var is_empty := func(y: int) -> bool: return at.call( 0, y ) == Color.BLACK
				if not is_empty.call( top ) or is_empty.call( top + 1 ): continue
				var below_too : bool = not is_empty.call( top + 2 )
				for layer in layers_per_slice:
					var edge : Color = at.call( layer, top + 1 )
					var past : Color = edge * 2.0 - at.call( layer, top + 2 ) if below_too else edge
					# Light can't go under zero, and the direction layers hold 0..1
					past = Color( maxf( past.r, 0.0 ), maxf( past.g, 0.0 ), maxf( past.b, 0.0 ) ) if layer == 0 else past.clamp()
					image.set_pixel( x, ( first_layer + layer ) * atlas.get_height() + top, Color( past, 1.0 ) )
		image.save_exr( file )
		# A brand new lightmap isn't in the editor's file list yet; the scan at the end of bake_all imports it then
		var files := EditorInterface.get_resource_filesystem()
		if files.get_file_type( atlas.resource_path ) != "": files.reimport_files( PackedStringArray( [ atlas.resource_path ] ) )
	else:
		push_warning( "Bake Room Lighting: %s came out in more than one texture, so its block edges weren't filled" % data.resource_path )
	data.clear_users()
	for i in range( 0, users.size(), 4 ):
		var uv : Rect2 = users[ i + 1 ]
		data.add_user( users[ i ], Rect2( uv.position + TEXEL_FIX * texel, uv.size ), users[ i + 2 ], users[ i + 3 ] )
	ResourceSaver.save( data )

# Deletes lightmaps from earlier bakes that nothing uses any more (a room that was removed or changed shape)
func _remove_leftovers() -> void:
	for file in DirAccess.get_files_at( LIGHTMAP_DIR ):
		var file_path := LIGHTMAP_DIR + file
		if _made.has( file_path ) or not file.get_extension() in [ "lmbake", "exr", "import" ]: continue
		DirAccess.remove_absolute( file_path )
		print( "Bake Room Lighting: removed %s, which no room uses any more" % file )

func _frames(count: int) -> void:
	for i in count: await _tree.process_frame
