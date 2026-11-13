@tool
extends "field_box.gd"

# A list of longer pieces of text: used for Contributions and for Notes.
#
# Under the title is a box to type a new item into, and the + beside the title adds what's in the
# box to the list (and empties the box). Each item in the list can be edited where it is, moved up
# or down, or removed with its trash button, which asks first.

signal changed
# The field has something of its own to say (or no longer does): see own_problem.
signal own_problem_changed

const RowList := preload( "row_list.gd" )

const ADD_BOX_HEIGHT : int = 64

var items : PackedStringArray:
	get: return PackedStringArray( _rows.get_values() )
	set( value ): _rows.set_values( Array( value ) )

# Set when + is pressed with nothing typed. The form shows it like any other problem with the field.
var own_problem : String

var _noun : String
var _add_box : TextEdit
var _rows : RowList

func _init(title: String, noun: String) -> void:
	super( title )
	_noun = noun
	var add_button := UiKit.make_icon_button( &"Add", "Add what's typed in the box as a new %s (Ctrl+Enter)" % noun, "+" )
	add_button.pressed.connect( _add_typed )
	add_to_header( add_button )

	_add_box = _make_text_box()
	_add_box.placeholder_text = "Type a new %s here, then press +" % noun
	_add_box.custom_minimum_size.y = ADD_BOX_HEIGHT * UiKit.get_scale()
	_add_box.text_changed.connect( _set_own_problem.bind( "" ) )
	_add_box.gui_input.connect( _on_add_box_input )
	add_body( _add_box )

	_rows = RowList.new()
	_rows.item_noun = noun
	_rows.build_row = _build_row
	_rows.changed.connect( func() -> void: changed.emit() )
	add_body( _rows )

func set_item_problem(index: int, level: int, text: String) -> void:
	_rows.set_row_problem( index, level, text )

func _add_typed() -> void:
	var typed := _add_box.text.strip_edges()
	if typed.is_empty():
		_set_own_problem( "Type the %s into the box first, then press +." % _noun )
		_add_box.grab_focus()
		return
	_add_box.text = ""
	_set_own_problem( "" )
	_rows.add_value( typed )

func _set_own_problem(text: String) -> void:
	if own_problem == text: return
	own_problem = text
	own_problem_changed.emit()

func _on_add_box_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and key.is_command_or_control_pressed():
		_add_box.accept_event()
		_add_typed()

func _build_row(index: int, value: String) -> Control:
	var box := _make_text_box()
	box.text = value
	# Grows with its text, so the whole item is always in view.
	box.scroll_fit_content_height = true
	box.text_changed.connect( func() -> void: _rows.set_value( index, box.text ) )
	return box

func _make_text_box() -> TextEdit:
	var box := TextEdit.new()
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box
