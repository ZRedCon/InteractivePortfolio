@tool
extends PopupPanel

# A small month calendar that pops up under a date field. Clicking a day picks it.
# The arrows step a month at a time, and the month and year can also be set directly.

signal date_picked(year: int, month: int, day: int)

const UiKit := preload( "ui_kit.gd" )
const DateText := preload( "../core/date_text.gd" )

const WEEKDAY_LETTERS : Array[ String ] = [ "S", "M", "T", "W", "T", "F", "S" ]
const WEEKS_SHOWN : int = 6
const MIN_YEAR : int = 1970
const MAX_YEAR : int = 2100

var _year : int
var _month : int
# The date marked as the current pick, if it's in the month on show.
var _picked : Dictionary

var _month_picker : OptionButton
var _year_picker : SpinBox
var _day_buttons : Array[ Button ]

func _init() -> void:
	var rows := VBoxContainer.new()
	add_child( rows )

	var top := HBoxContainer.new()
	rows.add_child( top )
	var previous := UiKit.make_icon_button( &"PagePrevious", "Previous month", "<" )
	previous.pressed.connect( _step_month.bind( -1 ) )
	top.add_child( previous )
	_month_picker = OptionButton.new()
	for month_name in DateText.MONTH_NAMES: _month_picker.add_item( month_name )
	_month_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_month_picker.item_selected.connect( func(index: int) -> void: _show_month( _year, index + 1 ) )
	top.add_child( _month_picker )
	_year_picker = SpinBox.new()
	_year_picker.min_value = MIN_YEAR
	_year_picker.max_value = MAX_YEAR
	_year_picker.value_changed.connect( func(value: float) -> void: _show_month( int( value ), _month ) )
	top.add_child( _year_picker )
	var next := UiKit.make_icon_button( &"PageNext", "Next month", ">" )
	next.pressed.connect( _step_month.bind( 1 ) )
	top.add_child( next )

	var grid := GridContainer.new()
	grid.columns = WEEKDAY_LETTERS.size()
	rows.add_child( grid )
	for letter in WEEKDAY_LETTERS:
		var heading := Label.new()
		heading.text = letter
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.modulate = Color( 1, 1, 1, 0.6 )
		grid.add_child( heading )
	for i in WEEKS_SHOWN * WEEKDAY_LETTERS.size():
		var button := Button.new()
		button.flat = true
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2( 32, 28 ) * UiKit.get_scale()
		button.pressed.connect( _on_day_pressed.bind( button ) )
		grid.add_child( button )
		_day_buttons.append( button )

	var today := UiKit.make_button( "Today", &"", "Pick today's date" )
	today.pressed.connect( func() -> void:
		var now := DateText.get_today()
		_pick( now[ "year" ], now[ "month" ], now[ "day" ] ) )
	rows.add_child( today )

# Opens under `anchor`, on the month of the given date with that day marked.
func open_below(anchor: Control, year: int, month: int, day: int) -> void:
	_picked = { "year": year, "month": month, "day": day }
	_show_month( year, month )
	reset_size()
	var corner := anchor.get_screen_position() + Vector2( 0, anchor.size.y )
	popup( Rect2i( Vector2i( corner ), Vector2i.ZERO ) )

func _step_month(by: int) -> void:
	var month := _month + by
	var year := _year
	if month < 1:
		month = 12
		year -= 1
	elif month > 12:
		month = 1
		year += 1
	_show_month( year, month )

func _show_month(year: int, month: int) -> void:
	_year = clampi( year, MIN_YEAR, MAX_YEAR )
	_month = clampi( month, 1, 12 )
	_month_picker.select( _month - 1 )
	_year_picker.set_value_no_signal( _year )

	# The grid starts on a Sunday, so the 1st lands in the column of its weekday.
	var first_column := DateText.get_weekday( _year, _month, 1 )
	var days := DateText.get_days_in_month( _year, _month )
	for i in _day_buttons.size():
		var button := _day_buttons[ i ]
		var day := i - first_column + 1
		var in_month := day >= 1 and day <= days
		button.text = str( day ) if in_month else ""
		button.disabled = not in_month
		button.set_meta( &"day", day )
		button.set_pressed_no_signal( in_month and _picked.get( "year" ) == _year and _picked.get( "month" ) == _month and _picked.get( "day" ) == day )

func _on_day_pressed(button: Button) -> void:
	_pick( _year, _month, button.get_meta( &"day" ) )

func _pick(year: int, month: int, day: int) -> void:
	hide()
	date_picked.emit( year, month, day )
