@tool
extends RefCounted

# Turns a date picked on the calendar into text and back, following a format like "M/D/YY".
#
# An entry's dates are plain text (so "Present" or "Spring 2024" are fine too). This only decides
# what the calendar writes, and lets the calendar open on the date that's already in the field.
#
# Format letters:  D = day (2), DD = day with a zero (02),  M = month (11), MM = (07),
# MMM = short name (Nov), MMMM = full name (November),  YY = year (26), YYYY = (2026).
# Anything else in the format is copied as it is.

const MONTH_NAMES : Array[ String ] = [ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" ]
const SHORT_MONTH_NAMES : Array[ String ] = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]
# Longest first, so "MMMM" isn't read as four separate "M"s.
const TOKENS : Array[ String ] = [ "YYYY", "MMMM", "MMM", "YY", "MM", "DD", "M", "D" ]
# A two digit year this far past the current one is still taken as this century; further is last century.
const TWO_DIGIT_YEAR_REACH : int = 20

static func format_date(year: int, month: int, day: int, format: String) -> String:
	var text := ""
	for part in _split_format( format ):
		match part:
			"YYYY": text += "%04d" % year
			"YY": text += "%02d" % (year % 100)
			"MMMM": text += MONTH_NAMES[ month - 1 ]
			"MMM": text += SHORT_MONTH_NAMES[ month - 1 ]
			"MM": text += "%02d" % month
			"M": text += str( month )
			"DD": text += "%02d" % day
			"D": text += str( day )
			_: text += part
	return text

# { "year", "month", "day" } if the text is a date written in this format, otherwise an empty Dictionary.
static func parse_date(text: String, format: String) -> Dictionary:
	var pattern := "^\\s*"
	var order : Array[ String ] = []
	for part in _split_format( format ):
		match part:
			"YYYY":
				pattern += "(\\d{4})"
			"YY":
				pattern += "(\\d{2})"
			"MMMM", "MMM":
				pattern += "([A-Za-z]+)\\.?"
			"MM", "M", "DD", "D":
				pattern += "(\\d{1,2})"
			_:
				pattern += _escape_for_regex( part )
				continue
		order.append( part )
	var found := RegEx.create_from_string( pattern + "\\s*$" ).search( text )
	if found == null: return {}

	var today := get_today()
	var date := { "year": today[ "year" ], "month": 1, "day": 1 }
	for i in order.size():
		var piece := found.get_string( i + 1 )
		match order[ i ]:
			"YYYY": date[ "year" ] = piece.to_int()
			"YY":
				var year : int = (today[ "year" ] / 100) * 100 + piece.to_int()
				if year > today[ "year" ] + TWO_DIGIT_YEAR_REACH: year -= 100
				date[ "year" ] = year
			"MMMM", "MMM":
				var month := _find_month( piece )
				if month == 0: return {}
				date[ "month" ] = month
			"MM", "M": date[ "month" ] = piece.to_int()
			"DD", "D": date[ "day" ] = piece.to_int()
	if date[ "month" ] < 1 or date[ "month" ] > 12 or date[ "day" ] < 1 or date[ "day" ] > get_days_in_month( date[ "year" ], date[ "month" ] ): return {}
	return date

static func get_today() -> Dictionary:
	var now := Time.get_date_dict_from_system()
	return { "year": now[ "year" ], "month": now[ "month" ], "day": now[ "day" ] }

static func get_days_in_month(year: int, month: int) -> int:
	if month == 2: return 29 if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0 else 28
	return 30 if month in [ 4, 6, 9, 11 ] else 31

# 0 = Sunday ... 6 = Saturday
static func get_weekday(year: int, month: int, day: int) -> int:
	var unix := Time.get_unix_time_from_datetime_dict( { "year": year, "month": month, "day": day, "hour": 12, "minute": 0, "second": 0 } )
	return Time.get_datetime_dict_from_unix_time( unix )[ "weekday" ]

# "M/D/YY" -> [ "M", "/", "D", "/", "YY" ]
static func _split_format(format: String) -> PackedStringArray:
	var parts : PackedStringArray = []
	var i := 0
	while i < format.length():
		var matched := ""
		for token in TOKENS:
			if format.substr( i, token.length() ) == token:
				matched = token
				break
		if matched.is_empty(): matched = format[ i ]
		parts.append( matched )
		i += matched.length()
	return parts

static func _find_month(written: String) -> int:
	var lower := written.to_lower()
	for i in MONTH_NAMES.size():
		if lower == MONTH_NAMES[ i ].to_lower() or lower == SHORT_MONTH_NAMES[ i ].to_lower(): return i + 1
	return 0

static func _escape_for_regex(text: String) -> String:
	var escaped := ""
	for character in text:
		escaped += "\\" + character if character in "\\^$.|?*+()[]{}/" else character
	return escaped
