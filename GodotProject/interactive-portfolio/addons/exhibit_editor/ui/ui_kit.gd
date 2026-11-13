@tool
extends RefCounted

# Small things every part of the Exhibit Editor's window uses: the editor's own icons and colors,
# and buttons made the same way everywhere.

# How bad a problem with a field is. A note is something worth a second look that still works.
const LEVEL_NONE := 0
const LEVEL_NOTE := 1
const LEVEL_ERROR := 2

# One of the editor's own icons, by the name it has in the editor theme (like "Add" or "Remove").
static func get_icon(icon_name: StringName) -> Texture2D:
	if not Engine.is_editor_hint(): return null
	var theme := EditorInterface.get_editor_theme()
	return theme.get_icon( icon_name, &"EditorIcons" ) if theme.has_icon( icon_name, &"EditorIcons" ) else null

static func get_level_color(level: int) -> Color:
	var fallback := Color( 1.0, 0.47, 0.42 ) if level == LEVEL_ERROR else Color( 1.0, 0.87, 0.4 )
	if not Engine.is_editor_hint(): return fallback
	var theme := EditorInterface.get_editor_theme()
	var color_name := &"error_color" if level == LEVEL_ERROR else &"warning_color"
	return theme.get_color( color_name, &"Editor" ) if theme.has_color( color_name, &"Editor" ) else fallback

# The editor has no calendar icon, so this draws one: a page with a dark strip along the top, two
# rings above it and a few days on it. Each line of CALENDAR_ICON is a row of pixels, # for filled.
const CALENDAR_ICON : Array[ String ] = [
	"................",
	"...##......##...",
	"...##......##...",
	".##############.",
	".##############.",
	".##############.",
	".#............#.",
	".#..##.##.##..#.",
	".#..##.##.##..#.",
	".#............#.",
	".#..##.##.##..#.",
	".#..##.##.##..#.",
	".#............#.",
	".##############.",
	"................",
	"................",
]
static var _calendar_icon : Texture2D

static func get_calendar_icon() -> Texture2D:
	if not Engine.is_editor_hint(): return null
	if _calendar_icon == null:
		var rows := CALENDAR_ICON.size()
		var image := Image.create( rows, rows, false, Image.FORMAT_RGBA8 )
		# The same light gray the editor's own icons are drawn in.
		var color := Color( 0.88, 0.88, 0.88 )
		for y in rows:
			for x in rows:
				if CALENDAR_ICON[ y ][ x ] == "#": image.set_pixel( x, y, color )
		var size := roundi( rows * get_scale() )
		if size != rows: image.resize( size, size, Image.INTERPOLATE_NEAREST )
		_calendar_icon = ImageTexture.create_from_image( image )
	return _calendar_icon

# The editor's interface scale (1.0 on a normal screen, more on a high-DPI one), for sizes given in pixels.
static func get_scale() -> float:
	return EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0

# A small button that's just an icon. `fallback_text` shows if the icon can't be found.
static func make_icon_button(icon_name: StringName, tooltip: String, fallback_text: String) -> Button:
	var button := Button.new()
	button.icon = get_icon( icon_name )
	if button.icon == null: button.text = fallback_text
	button.tooltip_text = tooltip
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	return button

static func make_button(text: String, icon_name: StringName, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = get_icon( icon_name )
	button.tooltip_text = tooltip
	return button

# Small gray text that explains something.
static func make_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color( 1, 1, 1, 0.6 )
	return label

# The words that go with a list of problems: "2 problems", "1 problem and 3 notes".
static func describe_counts(errors: int, notes: int) -> String:
	var parts : PackedStringArray = []
	if errors > 0: parts.append( "%d problem%s" % [ errors, "" if errors == 1 else "s" ] )
	if notes > 0: parts.append( "%d note%s" % [ notes, "" if notes == 1 else "s" ] )
	return " and ".join( parts )
