@tool
extends HBoxContainer

# A date: a box to type anything into ("11/2/26", "Present", "Spring 2024"), and a button that
# opens a calendar to pick a day from instead. The calendar writes the day in the format from the
# settings, and opens on the date already in the box when it can read it.

signal changed(text: String)

const UiKit := preload( "ui_kit.gd" )
const DateText := preload( "../core/date_text.gd" )
const CalendarPopup := preload( "calendar_popup.gd" )

const CAPTION_WIDTH : int = 40

# The format the calendar writes (see date_text.gd). The form keeps this in step with the settings.
var date_format : String = "M/D/YY"

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
	var button := UiKit.make_icon_button( &"", "Pick a date from a calendar", "Pick" )
	button.icon = UiKit.get_calendar_icon()
	if button.icon: button.text = ""
	button.pressed.connect( _open_calendar )
	add_child( button )

func _open_calendar() -> void:
	if _calendar == null:
		_calendar = CalendarPopup.new()
		_calendar.date_picked.connect( _on_date_picked )
		add_child( _calendar )
	var date := DateText.parse_date( _line.text, date_format )
	if date.is_empty(): date = DateText.get_today()
	_calendar.open_below( _line, date[ "year" ], date[ "month" ], date[ "day" ] )

func _on_date_picked(year: int, month: int, day: int) -> void:
	_line.text = DateText.format_date( year, month, day, date_format )
	changed.emit( _line.text )
