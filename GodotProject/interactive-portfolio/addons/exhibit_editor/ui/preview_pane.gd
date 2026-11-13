@tool
extends PanelContainer

# One preview: a title bar, the picture, and under it whatever went wrong making the picture.
#
# This is the part every preview shares. Where the picture comes from is filled in by the two
# scripts that extend it: godot_pane.gd (the game's scenes) and web_pane.gd (the website). They
# override the functions in the "For the two kinds of pane" region.
#
# The picture is always drawn at the size it's shown at: when the pane is smaller than the exhibit,
# the exhibit is asked to draw itself smaller, not shrunk afterwards, so text stays sharp.

signal maximize_toggled(pane: Control, on: bool)

const UiKit := preload( "ui_kit.gd" )

const SMALLEST_SIZE := Vector2i( 200, 100 )
const LARGEST_SIZE := Vector2i( 4000, 4000 )
const REPORT_LINES_SHOWN : int = 3
# How long the pane's size has to hold still before the picture is asked for at the new size.
const RESIZE_SETTLE_MSEC : int = 150

# Draws the picture and passes on the mouse. Everything it needs to know it asks its pane.
class View extends Control:
	var pane : Control

	func _draw() -> void:
		pane._draw_view( self )

	func _gui_input(event: InputEvent) -> void:
		pane._on_view_input( event )

var title : String:
	set( value ):
		title = value
		if _title_label: _title_label.text = value

var _title_label : Label
var _busy_label : Label
var _controls : HBoxContainer
var _size_controls : HBoxContainer
var _width_box : SpinBox
var _height_box : SpinBox
var _actual_size_button : Button
var _maximize_button : Button
var _scroll : ScrollContainer
var _view : View
var _message_panel : PanelContainer
var _message_label : Label
var _restart_button : Button
var _report_label : Label
var _report_button : Button
var _report_dialog : AcceptDialog
var _report_text : TextEdit
var _resized_at : int
var _last_mouse : Vector2

func _init() -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override( &"separation", 2 )
	add_child( rows )

	# A flow container, so in a narrow pane the buttons drop to a second line instead of squeezing the title out.
	var bar := HFlowContainer.new()
	rows.add_child( bar )
	_title_label = Label.new()
	_title_label.theme_type_variation = &"HeaderSmall"
	_title_label.text = title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child( _title_label )
	_busy_label = UiKit.make_hint( "updating..." )
	_busy_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_busy_label.visible = false
	bar.add_child( _busy_label )
	_size_controls = HBoxContainer.new()
	bar.add_child( _size_controls )
	_controls = HBoxContainer.new()
	bar.add_child( _controls )

	_actual_size_button = UiKit.make_icon_button( &"ZoomReset", "Show at full size (scroll to see the rest) instead of shrinking to fit", "1:1" )
	_actual_size_button.toggle_mode = true
	_actual_size_button.toggled.connect( func(_on: bool) -> void: _update_layout() )
	_controls.add_child( _actual_size_button )
	var reload := UiKit.make_icon_button( &"Reload", "Start this preview over", "Reload" )
	reload.pressed.connect( func() -> void: _reload() )
	_controls.add_child( reload )
	_maximize_button = UiKit.make_icon_button( &"DistractionFree", "Show only this preview", "Max" )
	_maximize_button.toggle_mode = true
	_maximize_button.toggled.connect( func(on: bool) -> void: maximize_toggled.emit( self, on ) )
	_controls.add_child( _maximize_button )

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Room is kept for the scrollbar whether or not it's showing. Otherwise it appearing would make the
	# picture narrower, so shorter, so the scrollbar would go away again, round and round.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	_scroll.resized.connect( _on_resized )
	rows.add_child( _scroll )
	_view = View.new()
	_view.pane = self
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.clip_contents = true
	_scroll.add_child( _view )

	# Sits over the middle of the picture when there's something to say instead of (or about) it.
	_message_panel = PanelContainer.new()
	_message_panel.set_anchors_and_offsets_preset( Control.PRESET_CENTER )
	_message_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message_panel.visible = false
	_view.add_child( _message_panel )
	var message_rows := VBoxContainer.new()
	_message_panel.add_child( message_rows )
	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.custom_minimum_size.x = 260 * UiKit.get_scale()
	message_rows.add_child( _message_label )
	_restart_button = UiKit.make_button( "Try again", &"Reload", "" )
	_restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restart_button.pressed.connect( func() -> void: _restart() )
	message_rows.add_child( _restart_button )

	var report_row := HBoxContainer.new()
	rows.add_child( report_row )
	_report_label = Label.new()
	_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_label.max_lines_visible = REPORT_LINES_SHOWN
	_report_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_label.mouse_filter = Control.MOUSE_FILTER_PASS
	report_row.add_child( _report_label )
	_report_button = UiKit.make_icon_button( &"Script", "Show everything this preview reported, as text that can be copied", "All" )
	_report_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_report_button.pressed.connect( _show_all_reports )
	report_row.add_child( _report_button )
	report_row.visible = false

func set_maximized(on: bool) -> void:
	_maximize_button.set_pressed_no_signal( on )
	_maximize_button.tooltip_text = "Show all the previews again" if on else "Show only this preview"

# Re-reads everything the pane shows from where it comes from. Call when that says it changed.
func refresh() -> void:
	_busy_label.visible = _is_running() and not _is_up_to_date()
	var message := _get_message()
	_message_label.text = message
	_message_panel.visible = not message.is_empty()
	_restart_button.visible = _can_restart()

	var reports := _get_reports()
	var lines : PackedStringArray = []
	var worst := UiKit.LEVEL_NOTE
	for report : Dictionary in reports:
		if report.get( "kind", "error" ) != "warning": worst = UiKit.LEVEL_ERROR
		var where : String = report.get( "where", "" )
		lines.append( report.get( "text", "" ) + ("  (%s)" % where if not where.is_empty() else "") )
	_report_label.text = "\n".join( lines )
	_report_label.tooltip_text = _report_label.text
	_report_label.add_theme_color_override( &"font_color", UiKit.get_level_color( worst ) )
	_report_label.get_parent().visible = not lines.is_empty()
	_update_layout()

# Adds the two number boxes for the size the exhibit is laid out at ("1152 x 648").
func add_size_boxes(start_size: Vector2i, tooltip: String) -> void:
	_width_box = _make_size_box( start_size.x, SMALLEST_SIZE.x, LARGEST_SIZE.x, tooltip )
	var times := Label.new()
	times.text = "x"
	_height_box = _make_size_box( start_size.y, SMALLEST_SIZE.y, LARGEST_SIZE.y, tooltip )
	for control : Control in [ _width_box, times, _height_box ]: _size_controls.add_child( control )

func _make_size_box(value: int, smallest: int, largest: int, tooltip: String) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = smallest
	box.max_value = largest
	box.value = value
	box.tooltip_text = tooltip
	box.select_all_on_focus = true
	box.value_changed.connect( func(_value: float) -> void: _on_size_edited( Vector2i( int( _width_box.value ), int( _height_box.value ) ) ) )
	return box

#region For the two kinds of pane

func _get_texture() -> Texture2D:
	return null

# How big the exhibit is in its own pixels, before any shrinking. Zero means it has no size of its own
# and simply fills the pane (the 3D exhibit).
func _get_content_size() -> Vector2:
	return Vector2.ZERO

# How many pixels there are to draw the exhibit in.
func _set_available_size(_pixels: Vector2i) -> void:
	pass

func _is_running() -> bool:
	return false

func _is_up_to_date() -> bool:
	return true

# What to say over the picture: why there isn't one, usually. "" for nothing.
func _get_message() -> String:
	return ""

func _can_restart() -> bool:
	return false

func _restart() -> void:
	pass

func _reload() -> void:
	pass

# [ { "kind": "error" or "warning", "text": String, "where": String } ]
func _get_reports() -> Array:
	return []

func _on_size_edited(_new_size: Vector2i) -> void:
	pass

# The mouse did something over the picture. The position is in the exhibit's own pixels.
func _send_mouse(_spot: Vector2, _relative: Vector2, _moved: bool, _pressed: bool, _buttons: int) -> void:
	pass

#endregion

#region Size and drawing

func _process(_delta: float) -> void:
	if _resized_at > 0 and Time.get_ticks_msec() - _resized_at >= RESIZE_SETTLE_MSEC:
		_resized_at = 0
		_update_layout()

func _on_resized() -> void:
	_resized_at = Time.get_ticks_msec()
	_view.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _view: _resized_at = Time.get_ticks_msec()

func _update_layout() -> void:
	var content := _get_content_size()
	if content == Vector2.ZERO:
		# Nothing with a size of its own (the 3D exhibit): the picture is simply as big as the pane.
		_view.custom_minimum_size = Vector2.ZERO
		if _scroll.size.x > 0 and _scroll.size.y > 0: _set_available_size( Vector2i( _scroll.size ) )
	else:
		var drawn_size := _get_drawn_size( content )
		# The view is as tall as the picture (as wide too, at full size), and the pane scrolls over the rest.
		_view.custom_minimum_size = drawn_size if _actual_size_button.button_pressed else Vector2( 0, drawn_size.y )
		if drawn_size.x >= 1 and drawn_size.y >= 1: _set_available_size( Vector2i( drawn_size ) )
	_view.queue_redraw()

# How big the exhibit is drawn: shrunk to the pane's width if it's wider than that, never enlarged.
# With the 1:1 button down it isn't shrunk at all. A tall exhibit keeps its height and is scrolled.
func _get_drawn_size(content: Vector2) -> Vector2:
	var width := _view.size.x if _view.size.x > 0 else _scroll.size.x
	var shrink := 1.0 if _actual_size_button.button_pressed else minf( 1.0, width / content.x )
	return (content * shrink).round()

# Where in the view the picture goes: in the middle, or at the top left when it's bigger than the view.
func _get_picture_rect() -> Rect2:
	var content := _get_content_size()
	if content == Vector2.ZERO: return Rect2( Vector2.ZERO, _view.size )
	var drawn_size := _get_drawn_size( content )
	return Rect2( ((_view.size - drawn_size) / 2.0).floor().max( Vector2.ZERO ), drawn_size )

func _draw_view(view: Control) -> void:
	var texture := _get_texture()
	if texture: view.draw_texture_rect( texture, _get_picture_rect(), false )

func _on_view_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null: return
	var button := event as InputEventMouseButton
	if button and button.button_index != MOUSE_BUTTON_LEFT: return # The wheel still scrolls the pane

	var rect := _get_picture_rect()
	var content := _get_content_size()
	if rect.size.x <= 0 or rect.size.y <= 0: return
	# From a spot in the pane to the same spot in the exhibit's own pixels.
	var per_pixel := content / rect.size if content != Vector2.ZERO else Vector2.ONE
	var spot := (mouse.position - rect.position) * per_pixel
	var relative := spot - _last_mouse
	_last_mouse = spot
	var buttons := mouse.button_mask & MOUSE_BUTTON_MASK_LEFT
	if button: _send_mouse( spot, Vector2.ZERO, false, button.pressed, buttons )
	else: _send_mouse( spot, relative, true, false, buttons )

#endregion

func _show_all_reports() -> void:
	if _report_dialog == null:
		_report_dialog = AcceptDialog.new()
		_report_text = TextEdit.new()
		_report_text.editable = false
		_report_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		_report_text.custom_minimum_size = Vector2( 640, 320 ) * UiKit.get_scale()
		_report_dialog.add_child( _report_text )
		add_child( _report_dialog )
	_report_dialog.title = "%s: what went wrong" % title
	_report_text.text = _report_label.text.replace( "\n", "\n\n" )
	_report_dialog.popup_centered()
