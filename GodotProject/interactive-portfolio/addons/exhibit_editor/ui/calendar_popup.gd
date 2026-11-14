@tool
extends PopupPanel

# A small calendar that pops up under a date field. Bullets along the top pick how exact the date
# is: a full date, just a month, or just a year, for when the exact day is long forgotten. The grid
# underneath follows the bullet: the days of a month, the months of a year, or the years of a decade.
# Clicking one picks it. The arrows step a month, a year or ten years at a time.

# `mode` says which bullet the date was picked with: MODE_DAY, MODE_MONTH or MODE_YEAR. A month
# comes with day 1, and a year with month 1 and day 1.
signal date_picked(mode: int, year: int, month: int, day: int)

const UiKit := preload( "ui_kit.gd" )
const DateText := preload( "../core/date_text.gd" )

# How exact a date is. Also the order of the bullets, and of the formats a date field hands over.
const MODE_DAY := 0
const MODE_MONTH := 1
const MODE_YEAR := 2
const MODE_NAMES : Array[ String ] = [ "Full date", "Month", "Year" ]
const MODE_DESCRIPTIONS : Array[ String ] = [ "A whole date", "Just a month", "Just a year" ]
const TODAY_TEXTS : Array[ String ] = [ "Today", "This month", "This year" ]
const PREVIOUS_TIPS : Array[ String ] = [ "Previous month", "Previous year", "Previous ten years" ]
const NEXT_TIPS : Array[ String ] = [ "Next month", "Next year", "Next ten years" ]

const WEEKDAY_LETTERS : Array[ String ] = [ "S", "M", "T", "W", "T", "F", "S" ]
const WEEKS_SHOWN : int = 6
const GRID_COLUMNS : int = 3 # For the months and the years
# A decade, plus the year before and after it (dimmed), the way most calendars show years.
const YEARS_SHOWN : int = 12
const MIN_YEAR : int = 1970
const MAX_YEAR : int = 2100

# The bullet a date was last picked with. A calendar opened on an empty box, or on text it can't
# read as a date, starts on this one.
static var last_mode : int = MODE_DAY

var _mode : int = MODE_DAY
var _year : int # The year on show (the decade it's in, for the years)
var _month : int # The month on show, for the days
# The date already in the box, so it can be marked: { "mode", "year", "month", "day" }, or empty.
var _picked : Dictionary

var _mode_buttons : Array[ CheckBox ]
var _previous_button : Button
var _next_button : Button
var _month_picker : OptionButton
var _year_picker : SpinBox
var _decade_label : Label
var _day_grid : GridContainer
var _month_grid : GridContainer
var _year_grid : GridContainer
var _day_buttons : Array[ Button ]
var _month_buttons : Array[ Button ]
var _year_buttons : Array[ Button ]
var _today_button : Button

func _init() -> void:
	var rows := VBoxContainer.new()
	add_child( rows )

	# The bullets. Being in one ButtonGroup is what makes them round, and only one can be on at a time.
	var bullets := HBoxContainer.new()
	bullets.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child( bullets )
	var group := ButtonGroup.new()
	for mode in MODE_NAMES.size():
		var bullet := CheckBox.new()
		bullet.text = MODE_NAMES[ mode ]
		bullet.button_group = group
		bullet.focus_mode = Control.FOCUS_NONE
		bullet.toggled.connect( _on_bullet_toggled.bind( mode ) )
		bullets.add_child( bullet )
		_mode_buttons.append( bullet )

	# Arrows at the ends. Between them, what's on show: a month and year, a year, or a decade.
	var top := HBoxContainer.new()
	rows.add_child( top )
	_previous_button = UiKit.make_icon_button( &"PagePrevious", "", "<" )
	_previous_button.pressed.connect( _step.bind( -1 ) )
	top.add_child( _previous_button )
	_month_picker = OptionButton.new()
	for month_name in DateText.MONTH_NAMES: _month_picker.add_item( month_name )
	_month_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_month_picker.item_selected.connect( func(index: int) -> void:
		_month = index + 1
		_refresh() )
	top.add_child( _month_picker )
	_year_picker = SpinBox.new()
	_year_picker.min_value = MIN_YEAR
	_year_picker.max_value = MAX_YEAR
	_year_picker.value_changed.connect( func(value: float) -> void:
		_year = int( value )
		_refresh() )
	top.add_child( _year_picker )
	_decade_label = Label.new()
	_decade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decade_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child( _decade_label )
	_next_button = UiKit.make_icon_button( &"PageNext", "", ">" )
	_next_button.pressed.connect( _step.bind( 1 ) )
	top.add_child( _next_button )

	# One grid for each bullet. Only the current bullet's grid shows.
	_day_grid = GridContainer.new()
	_day_grid.columns = WEEKDAY_LETTERS.size()
	rows.add_child( _day_grid )
	for letter in WEEKDAY_LETTERS:
		var heading := Label.new()
		heading.text = letter
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.modulate = Color( 1, 1, 1, 0.6 )
		_day_grid.add_child( heading )
	for i in WEEKS_SHOWN * WEEKDAY_LETTERS.size():
		var button := _make_grid_button( _day_grid, _on_day_pressed.bind( i ) )
		button.custom_minimum_size = Vector2( 32, 28 ) * UiKit.get_scale()
		_day_buttons.append( button )

	_month_grid = _make_grid( rows )
	for i in DateText.SHORT_MONTH_NAMES.size():
		var button := _make_grid_button( _month_grid, _on_month_pressed.bind( i + 1 ) )
		button.text = DateText.SHORT_MONTH_NAMES[ i ]
		_month_buttons.append( button )
	_year_grid = _make_grid( rows )
	for i in YEARS_SHOWN:
		_year_buttons.append( _make_grid_button( _year_grid, _on_year_pressed.bind( i ) ) )

	_today_button = UiKit.make_button( TODAY_TEXTS[ MODE_DAY ], &"", "" )
	_today_button.pressed.connect( _pick_today )
	rows.add_child( _today_button )

# Opens under `anchor`, with `mode`'s bullet on. `formats` are how a date field writes each kind of
# date, shown in the bullets' tooltips. `date` is the date already in the box, as date_text.gd reads
# it ({ "year", "month", "day" }): it's shown and marked. An empty `date` opens on today.
func open_below(anchor: Control, formats: Array[ String ], mode: int, date: Dictionary) -> void:
	for i in _mode_buttons.size():
		var format := formats[ i ] if i < formats.size() else ""
		_mode_buttons[ i ].tooltip_text = "%s, written as %s" % [ MODE_DESCRIPTIONS[ i ], format ]
	_picked = date.duplicate()
	if not _picked.is_empty(): _picked[ "mode" ] = mode
	var shown := date if not date.is_empty() else DateText.get_today()
	_year = shown[ "year" ]
	_month = shown[ "month" ]

	# One size whichever bullet is on, so the calendar doesn't jump about: the size the days need,
	# which is the most of the three. The months and the years spread out to fill the same room.
	_set_mode( MODE_DAY )
	var room := _day_grid.get_combined_minimum_size()
	_month_grid.custom_minimum_size = room
	_year_grid.custom_minimum_size = room
	min_size = Vector2i( get_contents_minimum_size().ceil() )
	_set_mode( mode )

	reset_size()
	var corner := anchor.get_screen_position() + Vector2( 0, anchor.size.y )
	popup( Rect2i( Vector2i( corner ), Vector2i.ZERO ) )

func _make_grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	parent.add_child( grid )
	return grid

func _make_grid_button(grid: GridContainer, on_pressed: Callable) -> Button:
	var button := Button.new()
	# The editor's own flat style, the one its toolbars use: no box until hovered or pressed. (A plain
	# `flat` button never draws its pressed look, so the box's date wouldn't show as marked.)
	button.theme_type_variation = &"FlatButton"
	button.toggle_mode = true # Shows the date already in the box as pressed
	# ...and in the editor's accent color, since the pressed box alone is hard to tell from hovering.
	button.add_theme_color_override( &"font_pressed_color", UiKit.get_accent_color() )
	button.add_theme_color_override( &"font_hover_pressed_color", UiKit.get_accent_color() )
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.pressed.connect( on_pressed )
	grid.add_child( button )
	return button

func _on_bullet_toggled(on: bool, mode: int) -> void:
	if on and mode != _mode: _set_mode( mode )

func _set_mode(mode: int) -> void:
	_mode = clampi( mode, MODE_DAY, MODE_YEAR )
	for i in _mode_buttons.size(): _mode_buttons[ i ].set_pressed_no_signal( i == _mode )
	_month_picker.visible = _mode == MODE_DAY
	_year_picker.visible = _mode != MODE_YEAR
	# With no month picker beside it, the year takes the middle of the row.
	_year_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _mode == MODE_MONTH else Control.SIZE_FILL
	_decade_label.visible = _mode == MODE_YEAR
	_day_grid.visible = _mode == MODE_DAY
	_month_grid.visible = _mode == MODE_MONTH
	_year_grid.visible = _mode == MODE_YEAR
	_previous_button.tooltip_text = PREVIOUS_TIPS[ _mode ]
	_next_button.tooltip_text = NEXT_TIPS[ _mode ]
	_today_button.text = TODAY_TEXTS[ _mode ]
	_refresh()

# A month, a year or ten years back (-1) or on (1), depending on the bullet.
func _step(by: int) -> void:
	match _mode:
		MODE_DAY:
			_month += by
			if _month < 1:
				_month = 12
				_year -= 1
			elif _month > 12:
				_month = 1
				_year += 1
		MODE_MONTH:
			_year += by
		MODE_YEAR:
			_year += by * 10
	_refresh()

func _refresh() -> void:
	_year = clampi( _year, MIN_YEAR, MAX_YEAR )
	_month = clampi( _month, 1, 12 )
	_month_picker.select( _month - 1 )
	_year_picker.set_value_no_signal( _year )
	match _mode:
		MODE_DAY: _show_days()
		MODE_MONTH: _show_months()
		MODE_YEAR: _show_years()

func _show_days() -> void:
	# The grid starts on a Sunday, so the 1st lands in the column of its weekday.
	var first_column := DateText.get_weekday( _year, _month, 1 )
	var days := DateText.get_days_in_month( _year, _month )
	var days_before := DateText.get_days_in_month( _year if _month > 1 else _year - 1, _month - 1 if _month > 1 else 12 )
	for i in _day_buttons.size():
		var day := i - first_column + 1
		var in_month := day >= 1 and day <= days
		# The months either side fill the cells around this one, grayed out. Besides looking like a
		# calendar, it keeps every row (and so the calendar) the same height whatever the month.
		var shown_day := day if in_month else (days_before + day if day < 1 else day - days)
		_day_buttons[ i ].text = str( shown_day )
		_day_buttons[ i ].disabled = not in_month
		_day_buttons[ i ].set_pressed_no_signal( in_month and _is_picked( MODE_DAY, _year, _month, day ) )

func _show_months() -> void:
	for i in _month_buttons.size():
		_month_buttons[ i ].set_pressed_no_signal( _is_picked( MODE_MONTH, _year, i + 1, 0 ) )

func _show_years() -> void:
	var decade := _get_decade()
	_decade_label.text = "%d - %d" % [ decade, decade + 9 ]
	for i in _year_buttons.size():
		var year := decade - 1 + i
		var button := _year_buttons[ i ]
		button.text = str( year )
		button.disabled = year < MIN_YEAR or year > MAX_YEAR
		button.modulate.a = 1.0 if year >= decade and year <= decade + 9 else 0.55
		button.set_pressed_no_signal( _is_picked( MODE_YEAR, year, 0, 0 ) )

# The first year of the decade on show: 2020 for 2026.
func _get_decade() -> int:
	return _year - posmod( _year, 10 )

# Whether the date in the box is this day, month or year. A date only counts as exact as it was
# written, so 2024 doesn't mark January 1st, but 11/2/2026 does mark November 2026.
func _is_picked(mode: int, year: int, month: int, day: int) -> bool:
	if _picked.is_empty() or _picked[ "mode" ] > mode or _picked[ "year" ] != year: return false
	if mode != MODE_YEAR and _picked[ "month" ] != month: return false
	return mode != MODE_DAY or _picked[ "day" ] == day

func _on_day_pressed(index: int) -> void:
	var day := index - DateText.get_weekday( _year, _month, 1 ) + 1
	if day >= 1 and day <= DateText.get_days_in_month( _year, _month ): _pick( MODE_DAY, _year, _month, day )

func _on_month_pressed(month: int) -> void:
	_pick( MODE_MONTH, _year, month, 1 )

func _on_year_pressed(index: int) -> void:
	_pick( MODE_YEAR, _get_decade() - 1 + index, 1, 1 )

func _pick_today() -> void:
	var today := DateText.get_today()
	_pick( _mode, today[ "year" ], today[ "month" ], today[ "day" ] )

func _pick(mode: int, year: int, month: int, day: int) -> void:
	last_mode = mode
	hide()
	date_picked.emit( mode, year, month, day )
