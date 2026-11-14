@tool
extends "field_box.gd"

# The Slide Show field: a list of images, in the order the slideshow plays them.
#
# Under the title is a box for a new image (typed, or picked with its folder button), and the +
# beside the title adds it to the list. Each image in the list shows its picture and can be changed
# where it is, moved up or down, or removed with its trash button, which asks first.

signal changed
# The field has something of its own to say (or no longer does): see own_problem.
signal own_problem_changed

const RowList := preload( "row_list.gd" )
const ImageField := preload( "image_field.gd" )
const ImageLibrary := preload( "../core/image_library.gd" )

const PICTURE_SIZE : int = 40

var images : PackedStringArray:
	get: return PackedStringArray( _rows.get_values() )
	set( value ): _rows.set_values( Array( value ) )

# Set when + is pressed with no image named. The form shows it like any other problem with the field.
var own_problem : String

var _library : ImageLibrary
var _browse : Callable
var _browse_many : Callable
var _add_field : ImageField
var _rows : RowList

# `browse` picks one image (see image_field.gd). `browse_many` is func(on_picked: Callable): it opens
# the file dialog with several files allowed, and later calls on_picked with all the picked image names.
func _init(library: ImageLibrary, browse: Callable, browse_many: Callable) -> void:
	super( "Slide Show" )
	_library = library
	_browse = browse
	_browse_many = browse_many
	var add_button := UiKit.make_icon_button( &"Add", "Add the image named in the box to the slideshow", "+" )
	add_button.pressed.connect( _add_named )
	add_to_header( add_button )

	# Its folder button picks any number of images at once, and they go straight into the list.
	# The box itself is for typing a name, which + then adds.
	_add_field = ImageField.new( _library, func(_current: String, _on_picked: Callable) -> void: _browse_many.call( _add_picked ), PICTURE_SIZE )
	_add_field.set_browse_tooltip( "Pick images to add to the slideshow. Hold Ctrl or Shift to pick several at once. They're added right away, in name order." )
	_add_field.changed.connect( func(_name: String) -> void: _set_own_problem( "" ) )
	add_body( _add_field )

	_rows = RowList.new()
	_rows.item_noun = "slide"
	_rows.build_row = _build_row
	_rows.changed.connect( func() -> void: changed.emit() )
	add_body( _rows )

func set_item_problem(index: int, level: int, text: String) -> void:
	_rows.set_row_problem( index, level, text )

func _add_named() -> void:
	var image_name := _add_field.text.strip_edges()
	if image_name.is_empty():
		_set_own_problem( "Type an image name in the box first, then press +. (Or use the folder button to pick one or more images, which adds them right away.)" )
		_add_field.grab_text_focus()
		return
	_add_field.text = ""
	_set_own_problem( "" )
	_rows.add_value( image_name )

func _add_picked(image_names: PackedStringArray) -> void:
	_set_own_problem( "" )
	_rows.add_values( Array( image_names ) )

func _set_own_problem(text: String) -> void:
	if own_problem == text: return
	own_problem = text
	own_problem_changed.emit()

func _build_row(index: int, value: String) -> Control:
	var field := ImageField.new( _library, _browse, PICTURE_SIZE )
	field.text = value
	field.changed.connect( func(image_name: String) -> void: _rows.set_value( index, image_name ) )
	return field
