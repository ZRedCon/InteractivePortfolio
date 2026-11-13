@tool
extends RefCounted

# Looks an entry's images up for the editor: is the name one the website and the game will be able
# to load, and what does the picture look like. Every image field asks here.
#
# When an image can't be used, the answer still comes with a picture (the stand-in image from the
# settings) and says what went wrong, so the field can show both.

const Settings := preload( "settings.gd" )

# Pictures bigger than this are shrunk for the editor's small previews. The files aren't touched.
const MAX_PREVIEW_SIZE : int = 256

var _settings : Settings
var _checked : Dictionary # image name -> { "modified", "result" }
var _stand_in : Texture2D
var _stand_in_loaded : bool

func _init(settings: Settings) -> void:
	_settings = settings
	# A named function, not a lambda: a lambda made here would hold on to this object, the settings hold
	# on to the lambda, and this holds the settings, so none of them (or the pictures) would ever be freed.
	_settings.changed.connect( _on_setting_changed )

func _on_setting_changed(_key: String) -> void:
	forget()

# Looks everything up again next time, for when the image files may have changed.
func forget() -> void:
	_checked.clear()
	_stand_in_loaded = false

# { "texture": the image, or the stand-in if it can't be used (null only if that's missing too),
#   "problem": what's wrong ("" when the image is fine, or when there's no name at all),
#   "ok": true only when the image itself loaded,
#   "size": the image's size in pixels }
func check(image_name: String) -> Dictionary:
	if image_name.is_empty(): return _make_result( "" )
	var path := _settings.get_image_path( image_name )
	var modified := FileAccess.get_modified_time( path ) if FileAccess.file_exists( path ) else 0
	var known : Dictionary = _checked.get( image_name, {} )
	if known.get( "modified", -1 ) == modified: return known[ "result" ]

	var result := _check( image_name, path )
	_checked[ image_name ] = { "modified": modified, "result": result }
	return result

func _check(image_name: String, path: String) -> Dictionary:
	var ending := _settings.get_value( Settings.IMAGE_EXTENSION )
	if image_name != image_name.strip_edges(): return _make_result( "There's a space at the start or end of the name." )
	if image_name.contains( "\\" ): return _make_result( "Use / between folders, not \\." )
	if image_name.begins_with( "/" ) or image_name.contains( ".." ) or image_name.contains( ":" ):
		return _make_result( "This should be a path inside the images folder, like Debug/Debug1/pair0." )
	if not FileAccess.file_exists( path ):
		if image_name.to_lower().ends_with( ending.to_lower() ) and FileAccess.file_exists( _settings.get_image_path( image_name.left( -ending.length() ) ) ):
			return _make_result( "Leave the %s off the end. It's added automatically." % ending )
		return _make_result( "File not found: " + _settings.describe_path( path ) )

	# Windows finds a file whatever its capital letters. Web hosts don't.
	var real_name := _find_spelling_on_disk( image_name + ending )
	if real_name != image_name + ending:
		return _make_result( "On disk this is spelled \"%s\". Capital letters have to match, or it only works on this PC and not on a web host." % real_name.left( -ending.length() ) )

	var image := Image.load_from_file( path )
	if image == null or image.is_empty(): return _make_result( "This file can't be read as an image: " + _settings.describe_path( path ) )
	var size := image.get_size()
	if maxi( size.x, size.y ) > MAX_PREVIEW_SIZE:
		var shrink := float( MAX_PREVIEW_SIZE ) / maxi( size.x, size.y )
		image.resize( maxi( roundi( size.x * shrink ), 1 ), maxi( roundi( size.y * shrink ), 1 ), Image.INTERPOLATE_BILINEAR )
	return { "texture": ImageTexture.create_from_image( image ), "problem": "", "ok": true, "size": size }

func _make_result(problem: String) -> Dictionary:
	return { "texture": _get_stand_in(), "problem": problem, "ok": false, "size": Vector2i.ZERO }

func _get_stand_in() -> Texture2D:
	if not _stand_in_loaded:
		_stand_in_loaded = true
		_stand_in = null
		var path := _settings.get_image_path( _settings.get_value( Settings.FALLBACK_IMAGE ) )
		if FileAccess.file_exists( path ):
			var image := Image.load_from_file( path )
			if image and not image.is_empty(): _stand_in = ImageTexture.create_from_image( image )
	return _stand_in

# The path as it's really spelled on disk, folder by folder. `relative_path` is known to exist.
func _find_spelling_on_disk(relative_path: String) -> String:
	var dir := _settings.get_images_dir()
	var parts := relative_path.split( "/" )
	var real_parts : PackedStringArray = []
	for i in parts.size():
		var names := DirAccess.get_files_at( dir ) if i == parts.size() - 1 else DirAccess.get_directories_at( dir )
		var real_part := parts[ i ]
		if not names.has( real_part ):
			for candidate in names:
				if candidate.to_lower() == real_part.to_lower(): real_part = candidate
		real_parts.append( real_part )
		dir = dir.path_join( real_part )
	return "/".join( real_parts )
