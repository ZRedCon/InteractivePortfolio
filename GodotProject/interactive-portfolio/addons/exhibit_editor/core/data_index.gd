@tool
extends RefCounted

# Keeps the entry index (data-index.json) listing exactly the files in the entry folder.
#
# Browsers can't look inside a folder, so the website and the web build read this list to learn
# which entry files to download. It's written the same way the Portfolio Data plugin writes it
# (every file in the folder, in alphabetical order, tab-indented), so the two never undo each other.

const JsonText := preload( "json_text.gd" )

# Rewrites the index if it doesn't match the folder.
# { "error": String ("" when it worked), "changed": bool, "files": PackedStringArray }
static func update(data_dir: String, index_path: String) -> Dictionary:
	var result := { "error": "", "changed": false, "files": PackedStringArray() }
	if not DirAccess.dir_exists_absolute( data_dir ):
		result[ "error" ] = "Entry folder not found: " + data_dir
		return result
	var files := Array( DirAccess.get_files_at( data_dir ) )
	result[ "files" ] = PackedStringArray( files )

	# Compares the lists rather than the text, since Git may check the file out with CRLF line endings.
	if FileAccess.file_exists( index_path ) and JsonText.parse_quietly( FileAccess.get_file_as_string( index_path ) ) == files: return result

	var file := FileAccess.open( index_path, FileAccess.WRITE )
	if file == null:
		result[ "error" ] = "Couldn't write %s (%s)." % [ index_path, error_string( FileAccess.get_open_error() ) ]
		return result
	file.store_string( JSON.stringify( files, "\t" ) + "\n" )
	file.close()
	result[ "changed" ] = true
	return result
