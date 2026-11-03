extends Node

const DATA_PATH : String = "assets/data/"
const DATA_INDEX_PATH : String = "assets/data-index.json"

const WEBFILES_FROM_PROJECT : String = "../../Webfiles/"
const WEBFILES_FROM_PAGE : String = "../"
const JAVASCRIPT_EVAL_LABEL : String = "new URL('" + WEBFILES_FROM_PAGE + "', location.href).href"

# Editor only. The Portfolio Data plugin builds the index from this too, so both see the same files.
static func list_entry_files() -> PackedStringArray:
	var data_dir := get_webfiles_dir().path_join( DATA_PATH )
	return DirAccess.get_files_at( data_dir ) if DirAccess.dir_exists_absolute( data_dir ) else PackedStringArray()

static func get_webfiles_dir() -> String:
	return ProjectSettings.globalize_path( "res://" ).path_join( WEBFILES_FROM_PROJECT ).simplify_path()

var _is_web_mode : bool
var entries : Array[ Entry ] 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_is_web_mode = OS.has_feature( "web" )
	entries = await parse_for_web() if OS.has_feature( "web" ) else parse_for_pc()
	
	var proof : String = ""
	
	for entry in entries:
		print( entry )
		proof += str( entry ) + "\n"
		proof += "\n"
	
	await get_tree().create_timer( 0.1 ).timeout
	PauseMenu.set_debug_out( proof )

#region Web pipeline

func _download(url: String) -> String:
	var request := HTTPRequest.new()
	add_child( request )
	var response : Array = []
	if request.request( url ) == OK: response = await request.request_completed
	request.queue_free()

	if response.is_empty() or response[ 0 ] != HTTPRequest.RESULT_SUCCESS or response[ 1 ] != 200: return ""
	return response[ 3 ].get_string_from_utf8()

func _web_read_json(file_path: String) -> Variant:
	# Convert File to string
	var json_string := await _download( JavaScriptBridge.eval(JAVASCRIPT_EVAL_LABEL) + file_path )
	# Parse the Json
	var result : Variant = JSON.parse_string( json_string )
	if result == null: printerr( "Bad File at: ", file_path )
	return result

func _web_get_files() -> PackedStringArray:
	var index = await _web_read_json( DATA_INDEX_PATH )
	if index is Array: return PackedStringArray( index )
	printerr( "Bad data index at: ", DATA_INDEX_PATH )
	return PackedStringArray()

func parse_for_web() -> Array[ Entry ]:
	var caught_entries : Array[ Entry ]
	var files_to_load := await _web_get_files()
	
	for file in files_to_load:
		var data = await _web_read_json( DATA_PATH + file )
		if data is Dictionary: caught_entries.append( _make_entry_from_dict( data ) )
	
	return caught_entries

#endregion

#region PC pipeline

func _pc_get_files() -> PackedStringArray:
	var data_dir := get_webfiles_dir().path_join( DATA_PATH )
	return DirAccess.get_files_at( data_dir ) if DirAccess.dir_exists_absolute( data_dir ) else PackedStringArray()

func _pc_read_json(file_path: String) -> Variant:
	# Convert File to string
	var json_string : String
	var disk_path := get_webfiles_dir().path_join( file_path )
	if FileAccess.file_exists( disk_path ): json_string = FileAccess.get_file_as_string( disk_path )
	# Parse the Json
	var result : Variant = JSON.parse_string( json_string )
	if result == null: printerr( "Bad File at: ", file_path )
	return result

func parse_for_pc() -> Array[ Entry ]:
	var caught_entries : Array[ Entry ]
	var files_to_load := _pc_get_files()
	
	for file in files_to_load:
		var data = _pc_read_json( DATA_PATH + file )
		if data is Dictionary: caught_entries.append( _make_entry_from_dict( data ) )
	
	return caught_entries

#endregion

func _make_entry_from_dict(dict: Dictionary) -> Entry:
	return Entry.new(dict[ "name" ], dict[ "description" ],
					dict[ "time" ], dict[ "related-skills" ],
					dict[ "contribution" ],dict[ "notes" ],
					dict[ "main-image" ],dict[ "slide-show" ],
					dict[ "related-links" ] )
