extends Node

const DATA_PATH : String = "res://assets/data/"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var files_to_load := DirAccess.get_files_at( DATA_PATH ) if DirAccess.dir_exists_absolute( DATA_PATH ) else PackedStringArray()
	
	for file in files_to_load:
		print( file )
		print( _load_entry_from_file( DATA_PATH + file ) )

func _load_entry_from_file(file_path: String) -> Entry:
	if not FileAccess.file_exists( file_path ): return null
	
	var file = FileAccess.open( file_path, FileAccess.READ )
	var json_string = file.get_as_text()
	file.close()
	var data = JSON.parse_string( json_string )
	if data is Dictionary:
		return _make_entry_from_dict( data )
	else:
		printerr( "Bad File at: ", file_path )
		return null

func _make_entry_from_dict(dict: Dictionary) -> Entry:
	return Entry.new(dict[ "name" ], dict[ "description" ],
					dict[ "time" ], dict[ "related-skills" ],
					dict[ "contribution" ],dict[ "notes" ],
					dict[ "main-image" ],dict[ "slide-show" ],
					dict[ "related-links" ] )
