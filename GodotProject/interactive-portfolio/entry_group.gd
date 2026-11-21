@tool
class_name EntryGroup extends Resource

## A list of entries handed out to the exhibits on the museum map that use it (an ExhibitDisplay set to
## GROUP): the exhibit lowest in the queue gets the first entry, the next one gets the second, and so on.
## Exhibits left over once the entries run out aren't built. Save it as a .tres file to share it.

## Entry files from Webfiles/assets/data, in the order they're handed out
@export var entries : Array[ String ]
## The exhibits that use this group are drawn in this color on the map
@export var color := Color.from_hsv( randf(), 0.6, 1.0 )

func _validate_property(property: Dictionary) -> void:
	# Each entry is picked from the files in the entry folder
	if property.name == "entries" and Engine.is_editor_hint():
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:%s" % [ TYPE_STRING, PROPERTY_HINT_ENUM, ",".join( FileIO.list_entry_files() ) ]

## Its name in messages: the file it's saved in
func get_label() -> String:
	return resource_path.get_file() if resource_path else resource_name
