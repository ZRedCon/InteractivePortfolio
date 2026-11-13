@tool
extends RefCounted

# Writes entry files, and checks hand-written ones.
#
# Godot's own JSON reader is forgiving (it accepts a comma after the last item, for one), but a web
# browser isn't: one stray comma and the website skips the whole entry while the game still shows it.
# So files are written here character by character as strict JSON, and find_strict_problem() says
# what a browser would trip over in a file somebody typed by hand.

const INDENT := "\t"

#region Writing

# An entry file's text. The keys come out in the dictionary's own order, one per line. Lists named
# in inline_keys stay on their line ("time": [ "1/2/26", "3/4/26" ]); every other list gets a line
# per item, so long text is easy to check by eye.
static func write_entry(entry: Dictionary, inline_keys: PackedStringArray = []) -> String:
	if entry.is_empty(): return "{ }\n"
	var lines : PackedStringArray = []
	for key : Variant in entry:
		var value : Variant = entry[ key ]
		var text := _write_inline( value ) if inline_keys.has( str( key ) ) else _write( value, INDENT )
		lines.append( INDENT + quote( str( key ) ) + ": " + text )
	return "{\n" + ",\n".join( lines ) + "\n}\n"

# Text as a JSON string, quotes included. Everything JSON wants escaped is escaped, and nothing else,
# so accents and other non-English letters stay readable in the file.
static func quote(text: String) -> String:
	var out : PackedStringArray = [ "\"" ]
	for i in text.length():
		var code := text.unicode_at( i )
		match code:
			0x22: out.append( "\\\"" )
			0x5C: out.append( "\\\\" )
			0x0A: out.append( "\\n" )
			0x0D: out.append( "\\r" )
			0x09: out.append( "\\t" )
			0x08: out.append( "\\b" )
			0x0C: out.append( "\\f" )
			_:
				# The other control characters have no short form.
				if code < 0x20: out.append( "\\u%04x" % code )
				else: out.append( String.chr( code ) )
	out.append( "\"" )
	return "".join( out )

static func _write(value: Variant, indent: String) -> String:
	match typeof( value ):
		TYPE_DICTIONARY:
			if value.is_empty(): return "{ }"
			var lines : PackedStringArray = []
			for key : Variant in value:
				lines.append( indent + INDENT + quote( str( key ) ) + ": " + _write( value[ key ], indent + INDENT ) )
			return "{\n" + ",\n".join( lines ) + "\n" + indent + "}"
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if value.is_empty(): return "[ ]"
			var lines : PackedStringArray = []
			for item : Variant in value:
				lines.append( indent + INDENT + _write( item, indent + INDENT ) )
			return "[\n" + ",\n".join( lines ) + "\n" + indent + "]"
	return _write_plain( value )

static func _write_inline(value: Variant) -> String:
	match typeof( value ):
		TYPE_DICTIONARY:
			if value.is_empty(): return "{ }"
			var parts : PackedStringArray = []
			for key : Variant in value: parts.append( quote( str( key ) ) + ": " + _write_inline( value[ key ] ) )
			return "{ " + ", ".join( parts ) + " }"
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if value.is_empty(): return "[ ]"
			var parts : PackedStringArray = []
			for item : Variant in value: parts.append( _write_inline( item ) )
			return "[ " + ", ".join( parts ) + " ]"
	return _write_plain( value )

static func _write_plain(value: Variant) -> String:
	match typeof( value ):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "true" if value else "false"
		TYPE_INT: return str( value )
		TYPE_FLOAT:
			if is_nan( value ) or is_inf( value ): return "null" # JSON has no way to write these
			# Godot reads every number as a float, so 7 comes back as 7.0. Whole numbers go out as they came in.
			if value == floorf( value ) and absf( value ) < 1e15: return str( int( value ) )
			return JSON.stringify( value )
		TYPE_STRING, TYPE_STRING_NAME: return quote( str( value ) )
	return quote( str( value ) )

#endregion

#region Reading

# Like JSON.parse_string(), but text that isn't JSON just gives null, instead of also printing an
# error to the Output panel.
static func parse_quietly(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse( text ) == OK else null

#endregion

#region Checking

# "" when a web browser would accept the text as JSON. Otherwise what's wrong, with the line it's on.
static func find_strict_problem(text: String) -> String:
	var checker := _Checker.new()
	checker.text = text
	# A byte order mark at the very start is fine: browsers drop it before reading the file.
	if not text.is_empty() and text.unicode_at( 0 ) == 0xFEFF: checker.pos = 1
	checker.skip_space()
	if checker.pos >= text.length(): return "The file is empty."
	if not checker.read_value( 0 ): return checker.describe()
	checker.skip_space()
	if checker.pos < text.length():
		checker.fail( "there's extra text after the end" )
		return checker.describe()
	return ""

# Reads JSON the way the specification spells it out: https://www.json.org
class _Checker:
	const MAX_DEPTH : int = 200

	var text : String
	var pos : int = 0
	var problem : String
	var problem_pos : int

	func describe() -> String:
		var line := text.count( "\n", 0, problem_pos ) + 1 if problem_pos > 0 else 1
		return "Line %d: %s." % [ line, problem ]

	func fail(what: String) -> bool:
		if problem.is_empty():
			problem = what
			problem_pos = pos
		return false

	func peek() -> String:
		return text[ pos ] if pos < text.length() else ""

	func skip_space() -> void:
		while pos < text.length() and text[ pos ] in " \t\r\n": pos += 1

	func read_value(depth: int) -> bool:
		if depth > MAX_DEPTH: return fail( "the lists are nested too deep" )
		var c := peek()
		if c == "{": return read_object( depth )
		if c == "[": return read_array( depth )
		if c == "\"": return read_string()
		if c == "-" or (c >= "0" and c <= "9"): return read_number()
		for word : String in [ "true", "false", "null" ]:
			if text.substr( pos, word.length() ) == word:
				pos += word.length()
				return true
		if c == "": return fail( "the file ends too early" )
		if c == "'": return fail( "text has to be in \"double quotes\", not 'single quotes'" )
		if c == "/" or c == "#": return fail( "comments aren't allowed in JSON" )
		if c == "]" or c == "}": return fail( "there's a comma with nothing after it before the closing %s" % c )
		return fail( "unexpected %s" % c )

	func read_object(depth: int) -> bool:
		pos += 1 # {
		skip_space()
		if peek() == "}":
			pos += 1
			return true
		while true:
			skip_space()
			if peek() == "}": return fail( "there's a comma with nothing after it before the closing }" )
			if peek() != "\"": return fail( "a name in \"double quotes\" should be here" )
			if not read_string(): return false
			skip_space()
			if peek() != ":": return fail( "a : should follow the name" )
			pos += 1
			skip_space()
			if not read_value( depth + 1 ): return false
			skip_space()
			if peek() == ",":
				pos += 1
				continue
			if peek() == "}":
				pos += 1
				return true
			return fail( "the file ends too early" if peek() == "" else "a , or } should be here" )
		return false

	func read_array(depth: int) -> bool:
		pos += 1 # [
		skip_space()
		if peek() == "]":
			pos += 1
			return true
		while true:
			skip_space()
			if not read_value( depth + 1 ): return false
			skip_space()
			if peek() == ",":
				pos += 1
				continue
			if peek() == "]":
				pos += 1
				return true
			return fail( "the file ends too early" if peek() == "" else "a , or ] should be here" )
		return false

	func read_string() -> bool:
		pos += 1 # opening quote
		while pos < text.length():
			var code := text.unicode_at( pos )
			if code == 0x22:
				pos += 1
				return true
			if code < 0x20: return fail( "text can't run over the end of a line (use \\n for a line break)" if code == 0x0A or code == 0x0D else "there's an invisible control character inside some text" )
			if code == 0x5C:
				var escape := text[ pos + 1 ] if pos + 1 < text.length() else ""
				if escape == "u":
					var digits := text.substr( pos + 2, 4 )
					if digits.length() < 4 or not digits.is_valid_hex_number(): return fail( "\\u needs four hex digits after it" )
					pos += 6
					continue
				if escape.is_empty() or not escape in "\"\\/bfnrt": return fail( "\\%s isn't something JSON understands" % escape )
				pos += 2
				continue
			pos += 1
		return fail( "some text is missing its closing quote" )

	func read_number() -> bool:
		var start := pos
		if peek() == "-": pos += 1
		if peek() == "0": pos += 1
		elif peek() >= "1" and peek() <= "9": read_digits()
		else: return fail( "a number should be here" )
		if peek() >= "0" and peek() <= "9": return fail( "numbers can't start with extra zeros" )
		if peek() == ".":
			pos += 1
			if not read_digits(): return fail( "digits should follow the decimal point" )
		if peek() == "e" or peek() == "E":
			pos += 1
			if peek() == "+" or peek() == "-": pos += 1
			if not read_digits(): return fail( "digits should follow the exponent" )
		return pos > start

	func read_digits() -> bool:
		var start := pos
		while peek() >= "0" and peek() <= "9": pos += 1
		return pos > start

#endregion
