@tool
extends VBoxContainer

# One field of the entry form: a title, the controls for editing it, and a line underneath that says
# what's wrong when something is. While there's a problem the controls get a colored outline:
# red for an error, yellow for a note.

const UiKit := preload( "ui_kit.gd" )

const OUTLINE_WIDTH : int = 2
const PADDING : int = 4

var level : int = UiKit.LEVEL_NONE
var message : String

var _header : HBoxContainer
var _title : Label
var _frame : PanelContainer
var _body : VBoxContainer
var _message_label : Label

func _init(title: String = "") -> void:
	add_theme_constant_override( &"separation", 2 )
	_header = HBoxContainer.new()
	add_child( _header )
	_title = Label.new()
	_title.text = title
	_title.theme_type_variation = &"HeaderSmall"
	_header.add_child( _title )
	_header.visible = not title.is_empty()

	_frame = PanelContainer.new()
	add_child( _frame )
	_body = VBoxContainer.new()
	_frame.add_child( _body )

	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.visible = false
	add_child( _message_label )
	_update_outline()

# Puts a control on the title's line, after the title (the + button of a list goes here).
func add_to_header(control: Control) -> void:
	_header.add_child( control )

# Adds one of the field's own controls. They stack top to bottom inside the outline.
func add_body(control: Control) -> void:
	_body.add_child( control )

func set_problem(new_level: int, text: String) -> void:
	if new_level == level and text == message: return
	level = new_level if not text.is_empty() else UiKit.LEVEL_NONE
	message = text
	_message_label.text = text
	_message_label.visible = level != UiKit.LEVEL_NONE
	if level != UiKit.LEVEL_NONE: _message_label.add_theme_color_override( &"font_color", UiKit.get_level_color( level ) )
	_update_outline()

func clear_problem() -> void:
	set_problem( UiKit.LEVEL_NONE, "" )

# The same space is kept around the controls with or without an outline, so nothing shifts when one appears.
func _update_outline() -> void:
	var box : StyleBox
	if level == UiKit.LEVEL_NONE:
		box = StyleBoxEmpty.new()
	else:
		var flat := StyleBoxFlat.new()
		flat.draw_center = false
		flat.border_color = UiKit.get_level_color( level )
		flat.set_border_width_all( OUTLINE_WIDTH )
		flat.set_corner_radius_all( 3 )
		box = flat
	box.set_content_margin_all( PADDING )
	_frame.add_theme_stylebox_override( &"panel", box )
