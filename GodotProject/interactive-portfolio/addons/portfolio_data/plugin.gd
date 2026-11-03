@tool
extends EditorPlugin

# While the editor is open, rewrites the data index whenever entry files are added or removed,
# so the website and the web build always know which files to download.

const FileParserScript := preload( "res://file_parser.gd" )
const CHECK_INTERVAL : float = 1.0

func _enter_tree() -> void:
	var timer := Timer.new()
	timer.wait_time = CHECK_INTERVAL
	timer.autostart = true
	timer.timeout.connect( _update_index )
	add_child( timer )
	_update_index()

func _update_index() -> void:
	var webfiles_dir := FileParserScript.get_webfiles_dir()
	if not DirAccess.dir_exists_absolute( webfiles_dir.path_join( FileParserScript.DATA_PATH ) ): return

	var entry_files := Array( FileParserScript.list_entry_files() )
	var index_path := webfiles_dir.path_join( FileParserScript.DATA_INDEX_PATH )
	# Compares the lists rather than the text, since Git may check the file out with CRLF line endings.
	if FileAccess.file_exists( index_path ) and JSON.parse_string( FileAccess.get_file_as_string( index_path ) ) == entry_files: return

	var file := FileAccess.open( index_path, FileAccess.WRITE )
	file.store_string( JSON.stringify( entry_files, "\t" ) + "\n" )
	print( "Portfolio Data: updated ", index_path )
