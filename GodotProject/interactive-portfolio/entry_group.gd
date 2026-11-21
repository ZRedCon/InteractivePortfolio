@tool
class_name EntryGroup extends Resource

## A list of entries handed out to the exhibits on the museum map that use it (an ExhibitDisplay set to
## GROUP): the exhibit lowest in the queue gets the first entry, the next one gets the second, and so on.
## Exhibits left over once the entries run out aren't built. Save it as a .tres file to share it.

## Entry files from Webfiles/assets/data, in the order they're handed out
@export var entries : Array[ String ]
## The exhibits that use this group are drawn in this color on the map
@export var color := Color.from_hsv( randf(), 0.6, 1.0 )
## Numbers the queues of the exhibits using this group (in the scene being edited) in their Scene dock order,
## top to bottom. The Props tool adds new props at the bottom, so that's the order they were placed in.
@export_tool_button( "Queue Exhibits in Scene Order", "Sort" ) var queue_in_scene_order := _queue_in_scene_order

func _validate_property(property: Dictionary) -> void:
	# Each entry is picked from the files in the entry folder
	if property.name == "entries" and Engine.is_editor_hint():
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:%s" % [ TYPE_STRING, PROPERTY_HINT_ENUM, ",".join( FileIO.list_entry_files() ) ]

## Its name in messages: its Resource > Name if it has one, or else the file it's saved in
func get_label() -> String:
	return resource_name if resource_name else resource_path.get_file()

func _queue_in_scene_order() -> void:
	# Looked up by name: this script also runs in the game, which has no editor classes
	var editor := Engine.get_singleton( &"EditorInterface" )
	var scene : Node = editor.get_edited_scene_root()
	if not scene: return
	var exhibits : Array[ ExhibitDisplay ] = []
	for exhibit : ExhibitDisplay in scene.find_children( "*", "ExhibitDisplay", true, false ):
		if exhibit.entry_mode == ExhibitDisplay.GROUP and exhibit.entry_group == self: exhibits.append( exhibit )
	if exhibits.is_empty(): return
	var undo_redo : Object = editor.get_editor_undo_redo()
	undo_redo.create_action( "Queue Exhibits in Scene Order" )
	for i in exhibits.size():
		undo_redo.add_do_property( exhibits[ i ], "queue", i )
		undo_redo.add_undo_property( exhibits[ i ], "queue", exhibits[ i ].queue )
	undo_redo.commit_action()
