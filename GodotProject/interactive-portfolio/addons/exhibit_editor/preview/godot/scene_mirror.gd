@tool
extends RefCounted

# Editor side of the Godot previews: keeps a tree of plain, script-less nodes in step with the
# snapshots the preview helper sends (see scene_snapshot.gd for what a snapshot holds).
#
# Each new snapshot is compared with the last one, so only what changed is touched: a slideshow
# sliding sideways moves two nodes instead of rebuilding the exhibit.
#
# The copy doesn't do its own layout. Every Control is put exactly where the game's layout put the
# real one (the snapshot says where), and put back there whenever a container here tries to arrange
# its children itself. That way the picture can't drift from the game's, whatever the containers think.

const Snapshot := preload( "scene_snapshot.gd" )

const PROPS_META := &"_exhibit_mirror_props"
const RECT_META := &"_exhibit_mirror_rect"

# The copy of the scene's root node, or null before the first snapshot.
var root : Node
# What couldn't be rebuilt from the last snapshot, in words for the preview's error line.
var problems : PackedStringArray

var _parent : Node
var _textures : Dictionary # texture id -> ImageTexture, shared with the other mirrors
var _resources : Dictionary # resource id -> Resource rebuilt here
var _resource_props : Dictionary # resource id -> the properties it was last given
var _viewport_textures : Array[ Array ] # [ node or resource, property, NodePath ], filled in once the tree is whole

func _init(parent: Node, textures: Dictionary) -> void:
	_parent = parent
	_textures = textures

func clear() -> void:
	if is_instance_valid( root ):
		root.get_parent().remove_child( root )
		root.queue_free()
	root = null
	_resources.clear()
	_resource_props.clear()

func apply(snapshot: Dictionary) -> void:
	problems.clear()
	_viewport_textures.clear()
	var tree : Dictionary = snapshot.get( "tree", {} )
	if tree.is_empty():
		clear()
		return

	_sync_resources( snapshot.get( "res", {} ) )

	var old_root := root if is_instance_valid( root ) else null
	root = _sync_node( old_root, tree )
	if root != old_root:
		if old_root:
			_parent.remove_child( old_root )
			old_root.queue_free()
		if root: _parent.add_child( root )
	if root: _place_tree( root )

	for entry in _viewport_textures:
		var viewport : Viewport = root.get_node_or_null( entry[ 2 ] ) as Viewport if root else null
		if viewport and is_instance_valid( entry[ 0 ] ): entry[ 0 ].set( entry[ 1 ], viewport.get_texture() )

# "" when every Control sits exactly where the game's layout put the real one. Otherwise the node
# that's furthest off, for tests and for hunting a preview that looks wrong.
func find_layout_mismatch() -> String:
	var worst := [ 0.0, "" ]
	if is_instance_valid( root ): _find_mismatch( root, worst )
	return worst[ 1 ]

func _find_mismatch(node: Node, worst: Array) -> void:
	var control := node as Control
	if control and control.has_meta( RECT_META ):
		var wanted : Rect2 = control.get_meta( RECT_META )
		var off := maxf( (control.position - wanted.position).length(), (control.size - wanted.size).length() )
		if off > 0.01 and off > worst[ 0 ]:
			worst[ 0 ] = off
			worst[ 1 ] = "%s is at %s but should be at %s" % [ root.get_path_to( control ), Rect2( control.position, control.size ), wanted ]
	for child in node.get_children(): _find_mismatch( child, worst )

# Every texture id the last snapshot used, so the owner of the texture table can drop the rest.
func collect_texture_ids(into: Dictionary) -> void:
	if is_instance_valid( root ): _collect_texture_ids( root.get_meta( PROPS_META, {} ), root, into )
	for id : int in _resource_props: _find_texture_ids( _resource_props[ id ], into )

func _collect_texture_ids(props: Dictionary, node: Node, into: Dictionary) -> void:
	_find_texture_ids( props, into )
	for child in node.get_children():
		_collect_texture_ids( child.get_meta( PROPS_META, {} ), child, into )

func _find_texture_ids(value: Variant, into: Dictionary) -> void:
	if value is Dictionary:
		if value.size() == 1 and value.has( Snapshot.REF_TEXTURE ): into[ value[ Snapshot.REF_TEXTURE ] ] = true
		else:
			for key : Variant in value: _find_texture_ids( value[ key ], into )
	elif value is Array:
		for item : Variant in value: _find_texture_ids( item, into )

#region Nodes

# Returns the node that now matches the description: the existing one updated, or a new one.
func _sync_node(existing: Node, description: Dictionary) -> Node:
	var node_class : StringName = description.get( "class", &"" )
	var node := existing
	if node == null or node.get_class() != node_class:
		node = _make_node( node_class )
		if node == null: return null
	node.name = description.get( "name", node.name )

	var props : Dictionary = description.get( "props", {} )
	_sync_props( node, node_class, node.get_meta( PROPS_META, {} ), props )
	node.set_meta( PROPS_META, props )

	if node is Control and description.get( "rect" ) is Rect2:
		node.set_meta( RECT_META, description[ "rect" ] )
		# A container arranges its children whenever it likes, then says so with this signal.
		if node != existing and node is Container: node.sort_children.connect( _place_children.bind( node ) )

	_sync_children( node, description.get( "children", [] ) )
	return node

# Puts each Control where the snapshot says the real one is, parents before children.
static func _place_tree(node: Node) -> void:
	var control := node as Control
	if control and control.has_meta( RECT_META ): _place( control )
	for child in node.get_children(): _place_tree( child )

static func _place_children(parent: Node) -> void:
	for child in parent.get_children():
		var control := child as Control
		if control and control.has_meta( RECT_META ): _place( control )

static func _place(control: Control) -> void:
	var rect : Rect2 = control.get_meta( RECT_META )
	# set_position() and set_size() rather than the properties: assigning `size` to a brand new node with
	# stretched anchors makes the engine print a warning, even though here it's exactly what's wanted.
	if control.position != rect.position: control.set_position( rect.position )
	if control.size != rect.size: control.set_size( rect.size )

func _make_node(node_class: StringName) -> Node:
	# Only engine node types are ever created, and never with a script, so a snapshot can't run code here.
	if not ClassDB.class_exists( node_class ) or not ClassDB.is_parent_class( node_class, &"Node" ) or not ClassDB.can_instantiate( node_class ):
		_add_problem( "Can't show a %s node" % node_class )
		return null
	return ClassDB.instantiate( node_class )

func _sync_children(node: Node, descriptions: Array) -> void:
	var by_name := {}
	for child in node.get_children():
		if child.has_meta( PROPS_META ): by_name[ child.name ] = child

	var index := 0
	for description : Dictionary in descriptions:
		var child_name : StringName = description.get( "name", &"" )
		var old_child : Node = by_name.get( child_name )
		var child := _sync_node( old_child, description )
		if child == null: continue
		if child != old_child:
			if old_child:
				node.remove_child( old_child )
				old_child.queue_free()
			node.add_child( child )
			child.name = child_name # add_child renames on a clash; the clashing node is gone now
		by_name.erase( child_name )
		if child.get_index() != index: node.move_child( child, index )
		index += 1

	for leftover : Node in by_name.values():
		node.remove_child( leftover )
		leftover.queue_free()

#endregion

#region Properties

# Sets what's new or different, and puts back to its default what the new snapshot no longer mentions.
func _sync_props(object: Object, object_class: StringName, old: Dictionary, new: Dictionary) -> void:
	for property : StringName in new:
		if property == &"script": continue
		var value : Variant = new[ property ]
		if old.has( property ) and typeof( old[ property ] ) == typeof( value ) and old[ property ] == value: continue
		if value is Dictionary and value.size() == 1 and value.has( Snapshot.REF_VIEWPORT ):
			_viewport_textures.append( [ object, property, value[ Snapshot.REF_VIEWPORT ] ] )
			continue
		object.set( property, _decode( value ) )
	for property : StringName in old:
		if not new.has( property ): object.set( property, ClassDB.class_get_property_default_value( object_class, property ) )

func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.size() == 1:
			if value.has( Snapshot.REF_PATH ): return _load_resource( value[ Snapshot.REF_PATH ] )
			if value.has( Snapshot.REF_RES ): return _resources.get( value[ Snapshot.REF_RES ] )
			if value.has( Snapshot.REF_TEXTURE ): return _textures.get( value[ Snapshot.REF_TEXTURE ] )
			if value.has( Snapshot.REF_VIEWPORT ): return null
		var decoded := {}
		for key : Variant in value: decoded[ _decode( key ) ] = _decode( value[ key ] )
		return decoded
	if value is Array:
		var decoded := []
		for item : Variant in value: decoded.append( _decode( item ) )
		return decoded
	return value

func _load_resource(path: String) -> Resource:
	if not path.begins_with( "res://" ) or not ResourceLoader.exists( path ):
		_add_problem( "Missing resource: " + path )
		return null
	var resource := ResourceLoader.load( path )
	if resource == null or resource is Script:
		_add_problem( "Can't load resource: " + path )
		return null
	return resource

#endregion

#region Resources

func _sync_resources(descriptions: Dictionary) -> void:
	# Two passes, because resources point at each other: make them all first, then fill them in.
	for id : int in descriptions:
		var resource_class : StringName = descriptions[ id ].get( "class", &"" )
		var existing : Resource = _resources.get( id )
		if existing and existing.get_class() == resource_class: continue
		_resources[ id ] = _make_resource( resource_class )
		_resource_props.erase( id )
	for id : int in _resources.keys():
		if not descriptions.has( id ):
			_resources.erase( id )
			_resource_props.erase( id )

	for id : int in descriptions:
		var resource : Resource = _resources.get( id )
		if resource == null: continue
		var props : Dictionary = descriptions[ id ].get( "props", {} )
		_sync_props( resource, resource.get_class(), _resource_props.get( id, {} ), props )
		_resource_props[ id ] = props

func _make_resource(resource_class: StringName) -> Resource:
	if (not ClassDB.class_exists( resource_class ) or not ClassDB.is_parent_class( resource_class, &"Resource" )
			or ClassDB.is_parent_class( resource_class, &"Script" ) or not ClassDB.can_instantiate( resource_class )):
		_add_problem( "Can't show a %s resource" % resource_class )
		return null
	return ClassDB.instantiate( resource_class )

#endregion

func _add_problem(text: String) -> void:
	if not problems.has( text ): problems.append( text )
