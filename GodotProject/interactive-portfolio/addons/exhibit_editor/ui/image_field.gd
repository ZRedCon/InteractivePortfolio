@tool
extends HBoxContainer

# An image, by the name entries store it under ("Debug/Debug1/pair0": no images folder in front and
# no .png behind, because the website and the game add those). The name can be typed, or filled in
# by picking the file with the folder button. Can show a small picture of the image beside the name.

signal changed(image_name: String)

const UiKit := preload( "ui_kit.gd" )
const ImageLibrary := preload( "../core/image_library.gd" )

var text : String:
	get: return _line.text
	set( value ):
		if _line.text != value: _line.text = value
		_update_picture()

var _library : ImageLibrary
var _browse : Callable
var _line : LineEdit
var _picture : TextureRect

# `browse` is func(current_name: String, on_picked: Callable): it opens the file dialog and later
# calls on_picked with the picked image's name. `picture_size` 0 leaves the picture out.
func _init(library: ImageLibrary, browse: Callable, picture_size: int = 0) -> void:
	_library = library
	_browse = browse
	if picture_size > 0:
		_picture = make_picture( picture_size )
		add_child( _picture )
	_line = LineEdit.new()
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = "Image name, like Debug/Debug1/pair0"
	_line.text_changed.connect( _on_typed )
	add_child( _line )
	var button := UiKit.make_icon_button( &"Folder", "Pick the image file", "..." )
	button.pressed.connect( func() -> void: _browse.call( _line.text, _on_picked ) )
	add_child( button )

func grab_text_focus() -> void:
	_line.grab_focus()

# A square that shows an image whole, with hard pixel edges the way the exhibits draw them.
static func make_picture(picture_size: int) -> TextureRect:
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2.ONE * picture_size * UiKit.get_scale()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return picture

# Shows what the library found for a name: the image, or the stand-in when it can't be used.
static func show_in_picture(picture: TextureRect, found: Dictionary, image_name: String) -> void:
	picture.texture = found[ "texture" ] if not image_name.is_empty() else null
	var pixels : Vector2i = found[ "size" ]
	picture.tooltip_text = "%s  (%d x %d pixels)" % [ image_name, pixels.x, pixels.y ] if found[ "ok" ] else found[ "problem" ]

func _on_typed(new_text: String) -> void:
	_update_picture()
	changed.emit( new_text )

func _on_picked(image_name: String) -> void:
	_line.text = image_name
	_on_typed( image_name )

func _update_picture() -> void:
	if _picture: show_in_picture( _picture, _library.check( _line.text ), _line.text )
