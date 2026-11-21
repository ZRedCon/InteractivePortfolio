@tool
extends RefCounted

# Undoable scene edits shared by the Room Groups and Props tools. Each one adds steps to the action being
# built, so it goes between create_action() and commit_action().

# The map's child called name, which holds one kind of node ("RoomGroups" or "Props"). When there isn't one,
# the action makes it. first puts it before the map's other children, so what comes after draws over it.
static func get_container(undo_redo: EditorUndoRedoManager, map: Node, name: String, first: bool = false) -> Node:
	var container := map.get_node_or_null( NodePath( name ) )
	if container: return container
	container = Node2D.new()
	container.name = name
	container.set_meta( &"_edit_lock_", true ) # Moving it would shift everything in it off the map's grid
	add_node( undo_redo, map, container )
	if first: undo_redo.add_do_method( map, &"move_child", container, 0 )
	return container

# Adds a node to the edited scene under parent
static func add_node(undo_redo: EditorUndoRedoManager, parent: Node, node: Node) -> void:
	undo_redo.add_do_method( parent, &"add_child", node, true )
	undo_redo.add_do_property( node, &"owner", EditorInterface.get_edited_scene_root() )
	undo_redo.add_do_reference( node )
	undo_redo.add_undo_method( parent, &"remove_child", node )

# Takes a node out of the edited scene
static func remove_node(undo_redo: EditorUndoRedoManager, node: Node) -> void:
	var parent := node.get_parent()
	undo_redo.add_do_method( parent, &"remove_child", node )
	undo_redo.add_undo_method( parent, &"add_child", node, true )
	undo_redo.add_undo_method( parent, &"move_child", node, node.get_index() )
	undo_redo.add_undo_property( node, &"owner", node.owner )
	undo_redo.add_undo_reference( node )
