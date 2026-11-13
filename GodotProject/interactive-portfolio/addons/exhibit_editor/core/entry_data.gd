@tool
extends RefCounted

# One portfolio entry, the way the editor holds it while it's being edited: every field always
# present and of the right type, even when the file it came from was missing some or had them wrong.
#
# to_dictionary() is the exact shape that gets saved, in the order the files are written in.

const JsonText := preload( "json_text.gd" )

const KEY_NAME := "name"
const KEY_TIME := "time"
const KEY_DESCRIPTION := "description"
const KEY_SKILLS := "related-skills"
const KEY_CONTRIBUTIONS := "contribution"
const KEY_NOTES := "notes"
const KEY_MAIN_IMAGE := "main-image"
const KEY_SLIDE_SHOW := "slide-show"
const KEY_LINKS := "related-links"
const LINK_TEXT := "display-text"
const LINK_URL := "url"

const KNOWN_KEYS : Array[ String ] = [ KEY_NAME, KEY_TIME, KEY_DESCRIPTION, KEY_SKILLS, KEY_CONTRIBUTIONS, KEY_NOTES, KEY_MAIN_IMAGE, KEY_SLIDE_SHOW, KEY_LINKS ]
# Lists written on one line. The two dates read better side by side.
const INLINE_KEYS : PackedStringArray = [ KEY_TIME ]

var name : String
var start_date : String
var end_date : String
var description : String
var skills : int # One bit per skill: bit 0 is the first skill in the game's SKILLS list
var contributions : PackedStringArray
var notes : PackedStringArray
var main_image : String
var slide_show : PackedStringArray
var links : Array[ Dictionary ] # Each { "display-text": String, "url": String }
# Fields a file had that this editor doesn't know. They're kept and saved back untouched, so a field
# added to the entry format later isn't lost by opening the file here.
var extra : Dictionary

#region Saving

func to_dictionary() -> Dictionary:
	var links_copy : Array[ Dictionary ] = []
	for link in links: links_copy.append( { LINK_TEXT: link.get( LINK_TEXT, "" ), LINK_URL: link.get( LINK_URL, "" ) } )
	var dictionary := {
		KEY_NAME: name,
		KEY_TIME: [ start_date, end_date ],
		KEY_DESCRIPTION: description,
		KEY_SKILLS: skills,
		KEY_CONTRIBUTIONS: Array( contributions ),
		KEY_NOTES: Array( notes ),
		KEY_MAIN_IMAGE: main_image,
		KEY_SLIDE_SHOW: Array( slide_show ),
		KEY_LINKS: links_copy,
	}
	for key : Variant in extra: dictionary[ key ] = extra[ key ]
	return dictionary

func to_json() -> String:
	return JsonText.write_entry( to_dictionary(), INLINE_KEYS )

# Writes the entry to a file. "" when it worked, otherwise why it didn't.
func save_file(path: String) -> String:
	var text := to_json()
	var file := FileAccess.open( path, FileAccess.WRITE )
	if file == null: return "Couldn't write %s (%s)." % [ path, error_string( FileAccess.get_open_error() ) ]
	file.store_string( text )
	file.close()
	# Reads it back, so "saved" always means the file really holds exactly this.
	if FileAccess.get_file_as_string( path ) != text: return "%s was written, but reading it back gave something different." % path
	return ""

#endregion

#region Loading

# { "entry": an entry or null, "error": String, "notes": PackedStringArray }
# `error` is set when the file can't be used at all. `notes` lists everything that had to be guessed
# or fixed to load it, so nothing changes without being mentioned.
static func load_file(path: String, skill_names: PackedStringArray) -> Dictionary:
	var result := { "entry": null, "error": "", "notes": PackedStringArray() }
	if not FileAccess.file_exists( path ):
		result[ "error" ] = "File not found: " + path
		return result
	var text := FileAccess.get_file_as_string( path )
	var json := JSON.new()
	if json.parse( text ) != OK:
		result[ "error" ] = "%s isn't readable JSON. Line %d: %s" % [ path.get_file(), json.get_error_line() + 1, json.get_error_message() ]
		return result
	if not json.data is Dictionary:
		result[ "error" ] = "%s doesn't hold an entry (it should start with { )." % path.get_file()
		return result

	var notes : PackedStringArray = []
	var strict_problem := JsonText.find_strict_problem( text )
	if not strict_problem.is_empty():
		notes.append( "Godot can read this file but a web browser can't, so the website skips it. %s Saving it from here fixes that." % strict_problem )
	result[ "entry" ] = from_dictionary( json.data, skill_names, notes )
	result[ "notes" ] = notes
	return result

# Builds an entry from a parsed file. Never fails: whatever's missing is left empty and whatever's the
# wrong type is converted as well as it can be, with a line added to `notes` for each.
static func from_dictionary(dictionary: Dictionary, skill_names: PackedStringArray, notes: PackedStringArray) -> RefCounted:
	var entry := new()
	entry.name = _read_text( dictionary, KEY_NAME, notes )
	entry.description = _read_text( dictionary, KEY_DESCRIPTION, notes )
	entry.main_image = _read_text( dictionary, KEY_MAIN_IMAGE, notes )

	var time := _read_text_list( dictionary, KEY_TIME, notes )
	if time.size() != 2 and dictionary.has( KEY_TIME ): notes.append( "\"%s\" should be a start and an end date, but has %d values." % [ KEY_TIME, time.size() ] )
	entry.start_date = time[ 0 ] if time.size() > 0 else ""
	entry.end_date = time[ 1 ] if time.size() > 1 else ""

	entry.skills = _read_skills( dictionary, skill_names, notes )
	entry.contributions = _read_text_list( dictionary, KEY_CONTRIBUTIONS, notes )
	entry.notes = _read_text_list( dictionary, KEY_NOTES, notes )
	entry.slide_show = _read_text_list( dictionary, KEY_SLIDE_SHOW, notes )
	entry.links = _read_links( dictionary, notes )

	for key : Variant in dictionary:
		if not KNOWN_KEYS.has( str( key ) ): entry.extra[ key ] = dictionary[ key ]
	if not entry.extra.is_empty():
		notes.append( "This file has fields this editor doesn't show (%s). They're kept as they are." % ", ".join( PackedStringArray( entry.extra.keys() ) ) )
	return entry

static func _read_text(dictionary: Dictionary, key: String, notes: PackedStringArray) -> String:
	if not dictionary.has( key ):
		notes.append( "\"%s\" was missing, so it's empty." % key )
		return ""
	var value : Variant = dictionary[ key ]
	if value is String: return value
	notes.append( "\"%s\" should be text, but was %s." % [ key, _describe( value ) ] )
	return "" if value == null or value is Array or value is Dictionary else _number_text( value )

static func _read_text_list(dictionary: Dictionary, key: String, notes: PackedStringArray) -> PackedStringArray:
	var list : PackedStringArray = []
	if not dictionary.has( key ):
		notes.append( "\"%s\" was missing, so it's empty." % key )
		return list
	var value : Variant = dictionary[ key ]
	if value is String:
		notes.append( "\"%s\" should be a list, but was a single piece of text. It's now a list of one." % key )
		list.append( value )
	elif value is Array:
		for item : Variant in value:
			if item is String: list.append( item )
			elif item == null or item is Array or item is Dictionary: notes.append( "\"%s\" had %s in it, which was left out." % [ key, _describe( item ) ] )
			else:
				notes.append( "\"%s\" had %s in it where text should be." % [ key, _describe( item ) ] )
				list.append( _number_text( item ) )
	else:
		notes.append( "\"%s\" should be a list, but was %s." % [ key, _describe( value ) ] )
	return list

static func _read_skills(dictionary: Dictionary, skill_names: PackedStringArray, notes: PackedStringArray) -> int:
	if not dictionary.has( KEY_SKILLS ):
		notes.append( "\"%s\" was missing, so no skills are picked." % KEY_SKILLS )
		return 0
	var value : Variant = dictionary[ KEY_SKILLS ]
	var bits := 0
	if value is float or value is int:
		if value < 0 or value != floorf( value ):
			notes.append( "\"%s\" should be a whole number that's 0 or more, but was %s." % [ KEY_SKILLS, _number_text( value ) ] )
		bits = maxi( int( value ), 0 )
	elif value is Array:
		# The game also accepts a list of skill names. It's saved back as the number.
		for item : Variant in value:
			var index := skill_names.find( str( item ) )
			if index == -1: notes.append( "\"%s\" isn't one of the skills, so it was left out." % str( item ) )
			else: bits |= 1 << index
		notes.append( "\"%s\" was a list of names. It will be saved as a number, which is what the website reads." % KEY_SKILLS )
	else:
		notes.append( "\"%s\" should be a number, but was %s." % [ KEY_SKILLS, _describe( value ) ] )

	# Bits past the end of the skill list don't stand for anything (and the game would stumble over them).
	if not skill_names.is_empty():
		var known := (1 << skill_names.size()) - 1
		if bits & ~known:
			notes.append( "\"%s\" was %d, which includes skills that don't exist (there are %d). Those were dropped." % [ KEY_SKILLS, bits, skill_names.size() ] )
			bits &= known
	return bits

static func _read_links(dictionary: Dictionary, notes: PackedStringArray) -> Array[ Dictionary ]:
	var links : Array[ Dictionary ] = []
	if not dictionary.has( KEY_LINKS ):
		notes.append( "\"%s\" was missing, so there are no links." % KEY_LINKS )
		return links
	var value : Variant = dictionary[ KEY_LINKS ]
	if not value is Array:
		notes.append( "\"%s\" should be a list, but was %s." % [ KEY_LINKS, _describe( value ) ] )
		return links
	for item : Variant in value:
		if not item is Dictionary:
			notes.append( "\"%s\" had %s in it instead of a link, which was left out." % [ KEY_LINKS, _describe( item ) ] )
			continue
		var link := {}
		for key : String in [ LINK_TEXT, LINK_URL ]:
			if item.has( key ) and item[ key ] is String: link[ key ] = item[ key ]
			else:
				notes.append( "A link had no \"%s\" text." % key )
				link[ key ] = ""
		links.append( link )
	return links

static func _describe(value: Variant) -> String:
	if value == null: return "empty (null)"
	if value is Array: return "a list"
	if value is Dictionary: return "a { } group"
	if value is bool: return "true" if value else "false"
	if value is float or value is int: return "the number " + _number_text( value )
	return "\"%s\"" % str( value )

# 7.0 -> "7". JSON only has one kind of number, and Godot reads them all as decimals.
static func _number_text(value: Variant) -> String:
	if value is float and value == floorf( value ): return str( int( value ) )
	return str( value )

#endregion

#region Comparing and copying

func is_same_as(other: RefCounted) -> bool:
	return other != null and to_dictionary() == other.to_dictionary()

func make_copy() -> RefCounted:
	var copy := new()
	copy.name = name
	copy.start_date = start_date
	copy.end_date = end_date
	copy.description = description
	copy.skills = skills
	copy.contributions = contributions.duplicate()
	copy.notes = notes.duplicate()
	copy.main_image = main_image
	copy.slide_show = slide_show.duplicate()
	copy.links = links.duplicate( true )
	copy.extra = extra.duplicate( true )
	return copy

#endregion
