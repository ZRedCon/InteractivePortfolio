@tool
extends RefCounted

# Bakes every room's lighting into a lightmap, so the web build draws no live room lights.
# Run it from Project > Tools > Bake Room Lighting after changing a room or the ceiling.
#
# For each scene in RoomContainer.ROOM_SCENES it:
#   - turns on lightmap UVs (UV2) for the room's own box and plane meshes
#   - copies the ceiling's down-light to where each open neighbor's ceiling is ("BakeLights"), so light
#     coming in through an opening gets baked too (walls still block it)
#   - bakes the room's LightmapGI and saves the scene
# Lightmapped surfaces don't get the sky's ambient light; RoomContainer measures the sky in game and puts it
# back with a few lights, so changing the sky needs no re-bake.

const ROOM_SIZE := 10.0
# Meters per lightmap texel. The ceiling lights are soft, so 0.5 looks the same as 0.25 at a quarter of
# the size (all rooms together: about 1.8 MB in the web build at 0.5, 6 MB at 0.25).
const TEXEL_SIZE := 0.5
# Directional lightmaps let normal maps react to the baked light, at four times the size
const DIRECTIONAL := true
# How many times baked light bounces off surfaces. 1 lets the floor softly light the ceiling; more also
# bounces the carpet's red back onto itself, which reads brighter than the live lights ever did.
const BOUNCES := 1
const CEILING_SCENE := "res://prefabs/rooms/ceiling.tscn"

var _tree : SceneTree

func bake_all() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	var started := Time.get_ticks_msec()
	var scenes : Dictionary = load( "res://Scenes/room_container.gd" ).ROOM_SCENES
	for type : int in scenes:
		await _bake_room( ( scenes[ type ] as PackedScene ).resource_path, type )
	print( "Bake Room Lighting: done in %.1f s" % ( ( Time.get_ticks_msec() - started ) / 1000.0 ) )

func _bake_room(path: String, type: int) -> void:
	var was_open := EditorInterface.get_open_scenes().has( path )
	EditorInterface.open_scene_from_path( path )
	await _frames( 3 )
	var room := EditorInterface.get_edited_scene_root() as Node3D
	if not room or room.scene_file_path != path:
		push_error( "Bake Room Lighting: couldn't open %s" % path )
		return

	# Room meshes: lightmap UVs, with texels the same size in meters however the mesh node is scaled
	var to_room := room.global_transform.affine_inverse()
	for mesh : MeshInstance3D in room.find_children( "*", "MeshInstance3D", true, true ):
		if mesh.gi_mode != GeometryInstance3D.GI_MODE_STATIC or not mesh.mesh is PrimitiveMesh: continue
		( mesh.mesh as PrimitiveMesh ).add_uv2 = true
		var scale := ( to_room * mesh.global_transform ).basis.get_scale().abs()
		mesh.gi_lightmap_texel_scale = maxf( scale.x, maxf( scale.y, scale.z ) )

	_make_bake_lights( room, type )
	var lightmap := room.get_node_or_null( "LightmapGI" ) as LightmapGI
	var has_lights := room.find_children( "*", "Light3D", true, false ).any( func(light: Light3D) -> bool: return light.light_bake_mode == Light3D.BAKE_STATIC )
	if not has_lights:
		# Nothing to bake (like the start room, which has no ceiling): it keeps the sky's live ambient light
		if lightmap: lightmap.free()
		print( "Bake Room Lighting: %s has no lights, left unbaked" % path.get_file() )
	else:
		if not lightmap:
			lightmap = LightmapGI.new()
			lightmap.name = "LightmapGI"
			room.add_child( lightmap )
			lightmap.owner = room
		lightmap.editor_description = "Made by Project > Tools > Bake Room Lighting. Re-run that after changing this room."
		lightmap.quality = LightmapGI.BAKE_QUALITY_HIGH
		lightmap.bounces = BOUNCES
		lightmap.directional = DIRECTIONAL
		lightmap.environment_mode = LightmapGI.ENVIRONMENT_MODE_DISABLED # RoomContainer adds the sky in game
		lightmap.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_DISABLED
		lightmap.texel_scale = float( ProjectSettings.get_setting( "rendering/lightmapping/primitive_meshes/texel_size" ) ) / TEXEL_SIZE
		var t := Time.get_ticks_msec()
		var baked := await _bake( lightmap, path.get_basename() + ".lmbake" )
		print( "Bake Room Lighting: %s %s in %d ms" % [ path.get_file(), "baked" if baked else "FAILED to bake", Time.get_ticks_msec() - t ] )
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()
	if not was_open: EditorInterface.close_scene()
	await _frames( 2 )

# Copies of the ceiling's down-light at each open neighbor's ceiling. They light nothing live (cull mask 0)
# and Room hides them in game; only the bake uses them.
func _make_bake_lights(room: Node3D, type: int) -> void:
	var old := room.get_node_or_null( "BakeLights" )
	if old:
		room.remove_child( old )
		old.free()
	var down_lights : Array[ Light3D ]
	for node in room.find_children( "*", "", true, false ):
		if node.scene_file_path != CEILING_SCENE: continue
		for light : Light3D in node.find_children( "*", "Light3D", true, false ):
			if light.light_bake_mode == Light3D.BAKE_STATIC and light.global_basis.z.y > 0.5: down_lights.append( light )
	if down_lights.is_empty(): return
	var bake_lights := Node3D.new()
	bake_lights.name = "BakeLights"
	bake_lights.editor_description = "Made by Bake Room Lighting: the ceiling's down-light where each open neighbor's ceiling is, so light through the openings gets baked. Never drawn in game."
	room.add_child( bake_lights )
	bake_lights.owner = room
	var walls : int = Room.TYPE_TO_BORDERS[ type ]
	for border : int in Room.BORDER_TYPE_TO_DIRECTION:
		if walls & border: continue # Wall that way
		var direction : Vector2 = Room.BORDER_TYPE_TO_DIRECTION[ border ]
		for light in down_lights:
			var copy := light.duplicate() as Light3D
			copy.name = "%s %+d,%+d" % [ light.name, direction.x, direction.y ]
			copy.editor_description = ""
			copy.light_cull_mask = 0
			bake_lights.add_child( copy )
			copy.owner = room
			copy.global_transform = Transform3D( light.global_basis.orthonormalized(), light.global_position + Vector3( direction.x, 0, direction.y ) * ROOM_SIZE )

# Presses the editor's own Bake Lightmaps button for this LightmapGI (LightmapGI.bake() isn't available to
# scripts). Its save dialog is answered with data_path, so nothing pops up.
func _bake(lightmap: LightmapGI, data_path: String) -> bool:
	EditorInterface.edit_node( lightmap )
	await _frames( 2 )
	# The button that LightmapGI's own editor plugin listens to (found that way so any editor language works)
	var button : Button
	for candidate : Button in EditorInterface.get_base_control().find_children( "*", "Button", true, false ):
		for connection in candidate.pressed.get_connections():
			var target := ( connection.callable as Callable ).get_object()
			if target and target.get_class() == "LightmapGIEditorPlugin": button = candidate
	var dialogs := button.find_children( "*", "EditorFileDialog", true, false ) if button else []
	if dialogs.is_empty():
		push_error( "Bake Room Lighting: couldn't find the editor's Bake Lightmaps button (did a Godot update change it?)" )
		return false
	( dialogs[ 0 ] as EditorFileDialog ).file_selected.emit( data_path )
	return lightmap.light_data != null and lightmap.light_data.resource_path == data_path

func _frames(count: int) -> void:
	for i in count: await _tree.process_frame
