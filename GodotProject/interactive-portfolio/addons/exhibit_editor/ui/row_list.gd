@tool
extends VBoxContainer

# The list every list field is built on (skills, contributions, notes, slides, links): one row per
# item, each with a trash button on its right, and optionally arrows to move it up or down.
#
# This only looks after the rows. What a row looks like is up to whoever uses it: build_row is
# called for every item and returns the control that shows (and edits) it.

signal changed # An item was added, removed, moved or edited

const UiKit := preload( "ui_kit.gd" )

# How much of an item is quoted when asking whether to remove it.
const EXCERPT_LENGTH : int = 240

# func(index: int, value: Variant) -> Control. The control it returns fills the row. When the user
# edits it, it should call set_value() so the list knows the new value.
var build_row : Callable
# func(value: Variant) -> String. How an item is quoted when asking whether to remove it.
var describe_value : Callable
# What one item is called, for the question and the tooltips: "contribution", "note", "link"...
var item_noun : String = "item"
var can_reorder : bool = true
# Long, typed items ask first. Skills come back with two clicks, so they don't.
var confirm_remove : bool = true

var _values : Array
var _rows : Array[ Dictionary ] # { "frame": PanelContainer, "message": Label }
var _dialog : ConfirmationDialog
var _asking_about : int = -1

func _init() -> void:
	add_theme_constant_override( &"separation", 2 )

func get_values() -> Array:
	return _values.duplicate( true )

func get_count() -> int:
	return _values.size()

func set_values(values: Array) -> void:
	_values = values.duplicate( true )
	_rebuild()

func add_value(value: Variant) -> void:
	_values.append( value )
	_rebuild()
	changed.emit()

# For a row's own controls to call as they're edited. The row isn't rebuilt, so typing isn't interrupted.
func set_value(index: int, value: Variant) -> void:
	if index < 0 or index >= _values.size() or (typeof( _values[ index ] ) == typeof( value ) and _values[ index ] == value): return
	_values[ index ] = value
	changed.emit()

# Removes an item, asking first if the list is set to.
func request_remove(index: int) -> void:
	if index < 0 or index >= _values.size(): return
	if not confirm_remove:
		_remove( index )
		return
	if _dialog == null:
		_dialog = ConfirmationDialog.new()
		_dialog.ok_button_text = "Remove"
		_dialog.confirmed.connect( func() -> void: _remove( _asking_about ) )
		add_child( _dialog )
	_asking_about = index
	var quoted : String = describe_value.call( _values[ index ] ) if describe_value.is_valid() else str( _values[ index ] )
	if quoted.length() > EXCERPT_LENGTH: quoted = quoted.left( EXCERPT_LENGTH ) + "..."
	_dialog.title = "Remove %s" % item_noun
	_dialog.dialog_text = "Remove this %s?\n\n%s" % [ item_noun, quoted ]
	_dialog.dialog_autowrap = true
	_dialog.popup_centered( Vector2i( Vector2( 420, 0 ) * UiKit.get_scale() ) )

func move(index: int, by: int) -> void:
	var target := index + by
	if index < 0 or index >= _values.size() or target < 0 or target >= _values.size(): return
	var value : Variant = _values[ index ]
	_values.remove_at( index )
	_values.insert( target, value )
	_rebuild()
	changed.emit()

# Outlines one row and says what's wrong under it. LEVEL_NONE clears it.
func set_row_problem(index: int, level: int, text: String) -> void:
	if index < 0 or index >= _rows.size(): return
	var message : Label = _rows[ index ][ "message" ]
	message.text = text
	message.visible = level != UiKit.LEVEL_NONE and not text.is_empty()
	var box : StyleBox = StyleBoxEmpty.new()
	if message.visible:
		message.add_theme_color_override( &"font_color", UiKit.get_level_color( level ) )
		var flat := StyleBoxFlat.new()
		flat.draw_center = false
		flat.border_color = UiKit.get_level_color( level )
		flat.set_border_width_all( 2 )
		flat.set_corner_radius_all( 3 )
		box = flat
	box.set_content_margin_all( 2 )
	_rows[ index ][ "frame" ].add_theme_stylebox_override( &"panel", box )

func clear_row_problems() -> void:
	for index in _rows.size(): set_row_problem( index, UiKit.LEVEL_NONE, "" )

func _remove(index: int) -> void:
	if index < 0 or index >= _values.size(): return
	_values.remove_at( index )
	_rebuild()
	changed.emit()

func _rebuild() -> void:
	for child in get_children():
		if child == _dialog: continue
		remove_child( child )
		child.queue_free()
	_rows.clear()

	for index in _values.size():
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override( &"separation", 0 )
		add_child( holder )
		var frame := PanelContainer.new()
		holder.add_child( frame )
		var row := HBoxContainer.new()
		frame.add_child( row )

		var content : Control = build_row.call( index, _values[ index ] )
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child( content )

		if can_reorder:
			var up := UiKit.make_icon_button( &"MoveUp", "Move this %s up" % item_noun, "^" )
			up.disabled = index == 0
			up.pressed.connect( move.bind( index, -1 ) )
			row.add_child( up )
			var down := UiKit.make_icon_button( &"MoveDown", "Move this %s down" % item_noun, "v" )
			down.disabled = index == _values.size() - 1
			down.pressed.connect( move.bind( index, 1 ) )
			row.add_child( down )
		var trash := UiKit.make_icon_button( &"Remove", "Remove this %s" % item_noun, "x" )
		trash.pressed.connect( request_remove.bind( index ) )
		row.add_child( trash )

		var message := Label.new()
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.visible = false
		holder.add_child( message )
		_rows.append( { "frame": frame, "message": message } )
		set_row_problem( index, UiKit.LEVEL_NONE, "" )
