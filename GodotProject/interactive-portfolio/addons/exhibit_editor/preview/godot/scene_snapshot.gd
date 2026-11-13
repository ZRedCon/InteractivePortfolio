extends RefCounted

# Runs in the preview helper process (see preview_host.gd), never in the editor.
#
# Turns a live scene (ui_exhibit.tscn or Entry.tscn after the game's own scripts filled it in) into
# plain data: for every node its class, its name and each stored property that isn't at its default.
# The editor rebuilds the same nodes from that data (scene_mirror.gd) and draws them itself, so
# nothing the game's scripts do can ever run inside the editor.
#
# Resources are handled one of three ways:
#   - saved to a file of their own (res://icon.svg, a .tres)  -> just the path, the editor loads it
#   - made at run time or stored inside a scene (StyleBoxFlat)  -> class + properties, listed once in
#     "res" under their instance id however many nodes share them
#   - images loaded at run time (the slideshow's pictures)  -> an id here, and the pixels are sent
#     separately, once, by whoever calls take_new_textures()

# Markers for values that can't be sent as they are. Each is a Dictionary with exactly one of these keys.
const REF_PATH := "@path"		# { "@path": "res://icon.svg" }
const REF_RES := "@res"			# { "@res": instance id }, described in the snapshot's "res" table
const REF_TEXTURE := "@tex"		# { "@tex": instance id }, pixels sent separately
const REF_VIEWPORT := "@vp"		# { "@vp": NodePath }, a ViewportTexture showing that viewport

# Nodes that draw something. Everything else (timers, physics bodies, audio, windows...) becomes an empty
# stand-in of its nearest plain base class, so node paths still line up but nothing plays, ticks or collides
# in the editor.
const DRAWN_CLASSES : Array[ StringName ] = [
	&"Control", &"VisualInstance3D", &"CanvasLayer", &"SubViewport", &"WorldEnvironment",
	&"Sprite2D", &"AnimatedSprite2D", &"Line2D", &"Polygon2D", &"MeshInstance2D", &"MultiMeshInstance2D",
	&"TileMapLayer", &"CanvasGroup", &"BackBufferCopy", &"Light2D", &"LightOccluder2D", &"CanvasModulate",
	&"CPUParticles2D", &"GPUParticles2D", &"Parallax2D",
]
const STAND_IN_CLASSES : Array[ StringName ] = [ &"Node3D", &"Node2D", &"Node" ]

# Properties that would make the editor's copy act on its own instead of only showing what the game did.
const SKIPPED_PROPERTIES : Dictionary[ StringName, Array ] = {
	&"Node": [ &"script", &"owner", &"editor_description", &"process_mode", &"process_priority", &"process_physics_priority", &"process_thread_group", &"physics_interpolation_mode", &"auto_translate_mode", &"scene_file_path" ],
	&"VideoStreamPlayer": [ &"autoplay", &"paused" ],
	&"AnimatedSprite2D": [ &"autoplay" ],
	&"AnimatedSprite3D": [ &"autoplay" ],
}
const SKIPPED_RESOURCE_PROPERTIES : Array[ StringName ] = [ &"script", &"resource_path", &"resource_local_to_scene", &"resource_scene_unique_id" ]

var _default_values : Dictionary # "Class.property" -> Variant
var _stored_names : Dictionary # instance id -> Array[ StringName ], reused until forget_property_lists()
var _rebuilt_classes : Dictionary # class name -> the class to rebuild it as
var _class_properties : Dictionary # class name -> Dictionary of that class's property names
var _skipped : Dictionary # class name -> Dictionary of property names to leave out
var _resources : Dictionary # instance id -> description, for the snapshot being taken
var _sent_textures : Dictionary # instance id -> WeakRef, textures whose pixels were already handed over
var _new_textures : Array[ ImageTexture ]

# Makes the next snapshot look up which properties every node stores again. Reading the full property
# list is slow, so snapshots reuse the last answer and the caller refreshes it now and then (a script
# adding a theme override is the usual reason the answer changes).
func forget_property_lists() -> void:
	_stored_names.clear()

# { "tree": node description, "res": { instance id: resource description } }
func take(root: Node) -> Dictionary:
	_resources = {}
	var tree := _describe_node( root )
	return { "tree": tree, "res": _resources }

# Textures first seen in the snapshots taken since the last call. Their pixels have to reach the editor
# before the snapshot that uses them.
func take_new_textures() -> Array[ ImageTexture ]:
	var textures := _new_textures
	_new_textures = []
	return textures

func _describe_node(node: Node) -> Dictionary:
	var rebuilt_class := _class_to_rebuild( node.get_class() )
	var properties := {}
	for property : StringName in _get_stored_names( node, rebuilt_class, _get_skipped( rebuilt_class ) ):
		var value : Variant = node.get( property )
		if _is_default( rebuilt_class, property, value ): continue
		properties[ property ] = _encode( value )

	var children : Array[ Dictionary ] = []
	for child in node.get_children():
		children.append( _describe_node( child ) )
	var description := { "class": rebuilt_class, "name": node.name, "props": properties, "children": children }
	# Where the game's own layout put it. Position and size aren't stored properties (containers work
	# them out), and working them out a second time in the editor doesn't always land on the same
	# answer: a wrapping Label's height depends on the sizes it had before. So the answer is sent.
	var control := node as Control
	if control: description[ "rect" ] = Rect2( control.position, control.size )
	return description

func _class_to_rebuild(node_class: StringName) -> StringName:
	if _rebuilt_classes.has( node_class ): return _rebuilt_classes[ node_class ]
	var rebuilt := &"Node"
	for candidate in DRAWN_CLASSES:
		if ClassDB.is_parent_class( node_class, candidate ):
			rebuilt = node_class
			break
	if rebuilt == &"Node":
		for candidate in STAND_IN_CLASSES:
			if ClassDB.is_parent_class( node_class, candidate ):
				rebuilt = candidate
				break
	_rebuilt_classes[ node_class ] = rebuilt
	return rebuilt

func _get_stored_names(object: Object, rebuilt_class: StringName, skipped: Dictionary) -> Array:
	var id := object.get_instance_id()
	if _stored_names.has( id ): return _stored_names[ id ]
	# A stand-in only has its base class's properties.
	var allowed : Dictionary = _get_class_properties( rebuilt_class ) if rebuilt_class != object.get_class() else {}
	var names : Array[ StringName ] = []
	for info in object.get_property_list():
		if not info.usage & PROPERTY_USAGE_STORAGE or info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var property : StringName = info.name
		if skipped.has( property ) or String( property ).begins_with( "metadata/" ): continue
		if not allowed.is_empty() and not allowed.has( property ): continue
		names.append( property )
	_stored_names[ id ] = names
	return names

func _get_class_properties(of_class: StringName) -> Dictionary:
	if not _class_properties.has( of_class ):
		var names := {}
		for info in ClassDB.class_get_property_list( of_class ): names[ StringName( info.name ) ] = true
		_class_properties[ of_class ] = names
	return _class_properties[ of_class ]

func _get_skipped(node_class: StringName) -> Dictionary:
	if _skipped.has( node_class ): return _skipped[ node_class ]
	var skipped := {}
	for owner_class : StringName in SKIPPED_PROPERTIES:
		if ClassDB.is_parent_class( node_class, owner_class ):
			for property : StringName in SKIPPED_PROPERTIES[ owner_class ]: skipped[ property ] = true
	_skipped[ node_class ] = skipped
	return skipped

func _is_default(owner_class: StringName, property: StringName, value: Variant) -> bool:
	var key := String( owner_class ) + "." + String( property )
	if not _default_values.has( key ):
		_default_values[ key ] = ClassDB.class_get_property_default_value( owner_class, property )
	var default : Variant = _default_values[ key ]
	return typeof( default ) == typeof( value ) and default == value

#region Values

func _encode(value: Variant) -> Variant:
	match typeof( value ):
		TYPE_OBJECT:
			return _encode_object( value )
		TYPE_ARRAY:
			var encoded := []
			for item : Variant in value: encoded.append( _encode( item ) )
			return encoded
		TYPE_DICTIONARY:
			var encoded := {}
			for key : Variant in value: encoded[ _encode( key ) ] = _encode( value[ key ] )
			return encoded
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return null
	return value

func _encode_object(object: Object) -> Variant:
	var resource := object as Resource
	if resource == null or resource is Script: return null # Nodes and scripts never cross over

	var viewport_texture := resource as ViewportTexture
	if viewport_texture: return { REF_VIEWPORT: viewport_texture.viewport_path }

	# A resource stored in a file of its own. ("::" marks one stored inside a scene, which can't be loaded alone.)
	var path := resource.resource_path
	if not path.is_empty() and not path.contains( "::" ) and ResourceLoader.exists( path ):
		return { REF_PATH: path }

	var id := resource.get_instance_id()
	var image_texture := resource as ImageTexture
	if image_texture:
		var sent : WeakRef = _sent_textures.get( id )
		if sent == null or sent.get_ref() == null:
			_sent_textures[ id ] = weakref( image_texture )
			_new_textures.append( image_texture )
		return { REF_TEXTURE: id }

	if not _resources.has( id ):
		_resources[ id ] = {} # Claims the spot first, so resources that point back at each other end here
		_resources[ id ] = _describe_resource( resource )
	return { REF_RES: id }

func _describe_resource(resource: Resource) -> Dictionary:
	var resource_class : StringName = resource.get_class()
	var properties := {}
	for property : StringName in _get_stored_names( resource, resource_class, {} ):
		if SKIPPED_RESOURCE_PROPERTIES.has( property ): continue
		var value : Variant = resource.get( property )
		if _is_default( resource_class, property, value ): continue
		properties[ property ] = _encode( value )
	return { "class": resource_class, "props": properties }

#endregion
