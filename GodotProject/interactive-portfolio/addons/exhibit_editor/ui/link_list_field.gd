@tool
extends "field_box.gd"

# The Links field. Each link is a pair: the text shown on the page, then a colon, then the address
# it opens ( [Github Page] : [https://github.com/...] ). In the file those are a link's
# "display-text" and "url".
#
# Under the title is an empty pair for a new link, and the + beside the title adds it to the list.
# Each link in the list can be edited where it is, moved, or removed (which asks first).

signal changed
# The field has something of its own to say (or no longer does): see own_problem.
signal own_problem_changed

const RowList := preload( "row_list.gd" )
const EntryData := preload( "../core/entry_data.gd" )

# How much of the row the shown text gets, next to the address.
const TEXT_SHARE : float = 0.45

var links : Array[ Dictionary ]:
	get:
		var list : Array[ Dictionary ] = []
		list.assign( _rows.get_values() )
		return list
	set( value ): _rows.set_values( value )

# Set when + is pressed with half a link typed. The form shows it like any other problem with the field.
var own_problem : String

var _add_pair : Dictionary # { "row": HBoxContainer, "text": LineEdit, "url": LineEdit }
var _rows : RowList

func _init() -> void:
	super( "Links" )
	var add_button := UiKit.make_icon_button( &"Add", "Add the link typed in the boxes", "+" )
	add_button.pressed.connect( _add_typed )
	add_to_header( add_button )

	_add_pair = _make_pair( "", "" )
	for key : String in [ "text", "url" ]:
		_add_pair[ key ].text_changed.connect( func(_text: String) -> void: _set_own_problem( "" ) )
		_add_pair[ key ].text_submitted.connect( func(_text: String) -> void: _add_typed() )
	add_body( _add_pair[ "row" ] )

	_rows = RowList.new()
	_rows.item_noun = "link"
	_rows.build_row = _build_row
	_rows.describe_value = func(link: Dictionary) -> String: return "%s : %s" % [ link.get( EntryData.LINK_TEXT, "" ), link.get( EntryData.LINK_URL, "" ) ]
	_rows.changed.connect( func() -> void: changed.emit() )
	add_body( _rows )

func set_item_problem(index: int, level: int, text: String) -> void:
	_rows.set_row_problem( index, level, text )

func _add_typed() -> void:
	var shown : String = _add_pair[ "text" ].text.strip_edges()
	var address : String = _add_pair[ "url" ].text.strip_edges()
	if shown.is_empty() or address.is_empty():
		_set_own_problem( "A link needs both: the text to show on the left, and the address it opens on the right. Then press +." )
		_add_pair[ "text" if shown.is_empty() else "url" ].grab_focus()
		return
	_add_pair[ "text" ].text = ""
	_add_pair[ "url" ].text = ""
	_set_own_problem( "" )
	_rows.add_value( { EntryData.LINK_TEXT: shown, EntryData.LINK_URL: address } )

func _set_own_problem(text: String) -> void:
	if own_problem == text: return
	own_problem = text
	own_problem_changed.emit()

func _build_row(index: int, link: Dictionary) -> Control:
	var pair := _make_pair( link.get( EntryData.LINK_TEXT, "" ), link.get( EntryData.LINK_URL, "" ) )
	var update := func(_text: String) -> void:
		_rows.set_value( index, { EntryData.LINK_TEXT: pair[ "text" ].text, EntryData.LINK_URL: pair[ "url" ].text } )
	pair[ "text" ].text_changed.connect( update )
	pair[ "url" ].text_changed.connect( update )
	return pair[ "row" ]

# [ shown text ] : [ address ]
func _make_pair(shown: String, address: String) -> Dictionary:
	var row := HBoxContainer.new()
	var text_edit := LineEdit.new()
	text_edit.text = shown
	text_edit.placeholder_text = "Text shown"
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_stretch_ratio = TEXT_SHARE
	row.add_child( text_edit )
	var colon := Label.new()
	colon.text = ":"
	row.add_child( colon )
	var url_edit := LineEdit.new()
	url_edit.text = address
	url_edit.placeholder_text = "https://..."
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_edit.size_flags_stretch_ratio = 1.0 - TEXT_SHARE
	row.add_child( url_edit )
	return { "row": row, "text": text_edit, "url": url_edit }
