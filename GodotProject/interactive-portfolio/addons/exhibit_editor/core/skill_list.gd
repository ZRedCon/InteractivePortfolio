@tool
extends RefCounted

# Finds the list of skills by reading it out of the source files that define it: game_entry.gd for
# the game and entryToExhibit.js for the website. An entry stores its skills as one number where
# bit 0 is the first skill in the list, bit 1 the second and so on, so both files have to list the
# same skills in the same order, and this editor has to use that same list.
#
# The files are read as text, not run. (game_entry.gd isn't a @tool script, so inside the editor its
# SKILLS variable is still empty.)

const LIST_NAME := "SKILLS"
const SEED_NAME := "SEED"

# { "skills": PackedStringArray, "seed": int (-1 when there's none), "error": String ("" when it worked) }
static func read(path: String) -> Dictionary:
	var result := { "skills": PackedStringArray(), "seed": -1, "error": "" }
	if not FileAccess.file_exists( path ):
		result[ "error" ] = "File not found: " + path
		return result
	var source := FileAccess.get_file_as_string( path )
	var is_script := path.get_extension().to_lower() == "gd"

	# "SKILLS", then anything but "=" on the same line (a type, like ": Array[ String ]"), then "= ["
	var list_start := RegEx.create_from_string( "\\b%s\\b[^=\\n]*=\\s*\\[" % LIST_NAME ).search( source )
	if list_start == null:
		result[ "error" ] = "No %s = [ ... ] list in %s" % [ LIST_NAME, path.get_file() ]
		return result
	var skills := _read_strings( source, list_start.get_end(), is_script )
	if skills.is_empty(): result[ "error" ] = "The %s list in %s is empty" % [ LIST_NAME, path.get_file() ]
	result[ "skills" ] = skills

	var seed_match := RegEx.create_from_string( "\\b%s\\b[^=\\n]*=\\s*(\\d+)" % SEED_NAME ).search( source )
	if seed_match: result[ "seed" ] = seed_match.get_string( 1 ).to_int()
	return result

# "" when both files list the same skills in the same order, otherwise the first difference.
static func describe_difference(game_skills: PackedStringArray, site_skills: PackedStringArray) -> String:
	for i in maxi( game_skills.size(), site_skills.size() ):
		var in_game := game_skills[ i ] if i < game_skills.size() else ""
		var on_site := site_skills[ i ] if i < site_skills.size() else ""
		if in_game == on_site: continue
		if in_game.is_empty(): return "The website lists skill %d (\"%s\") but the game's list ends before it." % [ i + 1, on_site ]
		if on_site.is_empty(): return "The game lists skill %d (\"%s\") but the website's list ends before it." % [ i + 1, in_game ]
		return "Skill %d is \"%s\" in the game but \"%s\" on the website." % [ i + 1, in_game, on_site ]
	return ""

# The dot color both the game and the website give a skill: the same hue steps, at full brightness.
static func get_color(index: int, hue_seed: int) -> Color:
	return Color.from_hsv( ((hue_seed * (index + 1)) % 360) / 360.0, 1.0, 1.0 )

# Every quoted string from `from` up to the "]" that closes the list. Comments are skipped, so a skill
# that's been commented out doesn't count, and a "#" inside quotes (like "C#") isn't taken for one.
static func _read_strings(source: String, from: int, is_script: bool) -> PackedStringArray:
	var strings : PackedStringArray = []
	var i := from
	while i < source.length():
		var c := source[ i ]
		if c == "]": break
		if (is_script and c == "#") or (not is_script and source.substr( i, 2 ) == "//"):
			i = _find_or_end( source, "\n", i )
		elif not is_script and source.substr( i, 2 ) == "/*":
			i = _find_or_end( source, "*/", i ) + 2
		elif c == "\"" or c == "'" or (not is_script and c == "`"):
			var text := ""
			i += 1
			while i < source.length() and source[ i ] != c:
				if source[ i ] == "\\" and i + 1 < source.length(): i += 1 # keeps the escaped character itself
				text += source[ i ]
				i += 1
			strings.append( text )
			i += 1
		else:
			i += 1
	return strings

static func _find_or_end(source: String, what: String, from: int) -> int:
	var found := source.find( what, from )
	return found if found != -1 else source.length()
