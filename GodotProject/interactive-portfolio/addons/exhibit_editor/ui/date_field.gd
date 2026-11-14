@tool
extends HBoxContainer

# A date: a box to type anything into ("11/2/26", "Present", "Spring 2024"), and a button that
# opens a calendar to pick one from instead. The calendar can pick a full date, just a month or
# just a year, and writes each kind in its own format from the settings. It opens on the date
# already in the box when the box holds one of those three kinds.

signal changed(text: String)

const UiKit := preload( "ui_kit.gd" )
const DateText := preload( "../core/date_text.gd" )
const CalendarPopup := preload( "calendar_popup.gd" )

const CAPTION_WIDTH : int = 40

# How the calendar writes each kind of date, in the order of its bullets: a full date, a month and
# a year (see date_text.gd). The form keeps these in step with the settings.
var formats : Array[ String ] = [ "M/D/YYYY", "M/YYYY", "YYYY" ]

var text : String:
	get: return _line.text
	set( value ):
		if _line.text != value: _line.text = value

var _line : LineEdit
var _calendar : CalendarPopup

func _init(label: String) -> void:
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = CAPTION_WIDTH * UiKit.get_scale()
	add_child( caption )
	_line = LineEdit.new()
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.placeholder_text = "Type a date, or pick one with the calendar"
	_line.text_changed.connect( func(new_text: String) -> void: changed.emit( new_text ) )
	add_child( _line )
	var button := UiKit.make_icon_button( &"", "Pick a date from a calendar: a full date, a month or a year", "Pick" )
	button.icon = UiKit.get_calendar_icon()
	if button.icon: button.text = ""
	button.pressed.connect( _open_calendar )
	add_child( button )

func _open_calendar() -> void:
	if _calendar == null:
		_calendar = CalendarPopup.new()
		_calendar.date_picked.connect( _on_date_picked )
		add_child( _calendar )
	# The box's date opens the calendar on the bullet for how exact it is: 3/2024 on Month, and so on.
	for mode in formats.size():
		var date := DateText.parse_date( _line.text, formats[ mode ] )
		if not date.is_empty():
			_calendar.open_below( _line, formats, mode, date )
			return
	# Nothing the calendar can read (an empty box, or text like "Present"): today, on the bullet used last.
	_calendar.open_below( _line, formats, CalendarPopup.last_mode, {} )

func _on_date_picked(mode: int, year: int, month: int, day: int) -> void:
	_line.text = DateText.format_date( year, month, day, formats[ mode ] )
	changed.emit( _line.text )
