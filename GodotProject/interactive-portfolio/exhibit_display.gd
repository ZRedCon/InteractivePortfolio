@tool
class_name ExhibitDisplay extends EdgePropDisplay

## An Exhibit on a wall of the museum map. When the museum is built it shows one entry, picked by entry_mode.

const SCENE : PackedScene = preload( "res://prefabs/Entry.tscn" )
## The Exhibit's picture is centered on its origin, so it's hung this high up its wall (meters)...
const HANG_HEIGHT := 1.6
## ...and this far out from it, so the two don't flicker through each other
const WALL_GAP := 0.05

# pseudo-enum for entry_mode
const CUSTOM := 0
const SELECT := 1
const GROUP := 2

## CUSTOM shows custom_entry, made just for this exhibit. SELECT shows entry_file, one of the entry files (any
## number of exhibits can show the same one). GROUP takes the next entry from entry_group, in queue order.
@export_enum("Custom", "Select", "Group") var entry_mode : int = SELECT:
	set( value ):
		entry_mode = value
		notify_property_list_changed()
		_changed()
@export var custom_entry : CustomEntry:
	set( value ):
		custom_entry = value
		_changed()
## A file in Webfiles/assets/data
@export var entry_file : String:
	set( value ):
		entry_file = value
		_changed()
@export var entry_group : EntryGroup:
	set( value ):
		entry_group = value
		_changed()
## Exhibits using the same group take its entries in this order, lowest first
@export var queue : int:
	set( value ):
		queue = value
		_changed()

# The grouped exhibit the mouse is over, so every exhibit in its group can light up
static var _hovered_grouped : ExhibitDisplay
var _highlighted : bool

func _init() -> void:
	draw_color = Color( 0.35, 0.75, 1.0 )

func _changed() -> void:
	queue_redraw()
	update_configuration_warnings()

func _validate_property(property: Dictionary) -> void:
	match property.name:
		"custom_entry": _show_only_for( property, CUSTOM )
		"entry_file":
			_show_only_for( property, SELECT )
			if Engine.is_editor_hint():
				property.hint = PROPERTY_HINT_ENUM
				property.hint_string = ",".join( FileIO.list_entry_files() )
		"entry_group", "queue": _show_only_for( property, GROUP )

# Hides a property from the inspector unless entry_mode is mode. It's saved either way.
func _show_only_for(property: Dictionary, mode: int) -> void:
	if entry_mode != mode: property.usage &= ~PROPERTY_USAGE_EDITOR

#region Map display

func _process(delta: float) -> void:
	super( delta )
	var grouped := entry_mode == GROUP and entry_group != null
	if grouped and hovered: _hovered_grouped = self
	elif _hovered_grouped == self: _hovered_grouped = null
	var highlighted := grouped and is_instance_valid( _hovered_grouped ) and _hovered_grouped.entry_group == entry_group
	if highlighted != _highlighted:
		_highlighted = highlighted
		queue_redraw()

func get_display_color() -> Color:
	if entry_mode == GROUP and entry_group and not marked_for_removal: return entry_group.color
	return super()

func _prop_draw() -> void:
	super()
	# A ring around every exhibit in the hovered exhibit's group
	if _highlighted: draw_arc( get_marker_position(), RADIUS * 1.7, 0.0, TAU, 24, get_display_color(), 0.6 )

func _prop_draw_advanced() -> void:
	draw_text_line( _describe_entry(), 1 )
	var problems := get_problems()
	for i in problems.size(): draw_text_line( problems[ i ], i + 2, REMOVE_COLOR )

# What this exhibit will show, for its hover text
func _describe_entry() -> String:
	match entry_mode:
		CUSTOM: return "Custom: %s" % (custom_entry.name if custom_entry else "none")
		SELECT: return "Select: %s" % entry_file
		GROUP:
			if not entry_group: return "Group: none"
			var file := get_group_entry()
			return "Group %s, queue %d: %s" % [ entry_group.get_label(), queue, file if file else "none left, so it isn't built" ]
	return ""

#endregion

#region Entries

## Whether an entry file is there: in the editor, in the entry folder; in the game, among the loaded entries
static func has_entry(file: String) -> bool:
	if Engine.is_editor_hint(): return file in FileIO.list_entry_files()
	return FileIO.Instance.get_entry( file ) != null

## The entry this exhibit shows, or null
func get_entry() -> Entry:
	match entry_mode:
		CUSTOM: return custom_entry.to_entry() if custom_entry else null
		SELECT: return FileIO.Instance.get_entry( entry_file )
		GROUP: return FileIO.Instance.get_entry( get_group_entry() )
	return null

## Every exhibit on map that takes its entries from group, in the order they take them: by queue, and by
## their order in the scene when two share a queue number
static func get_queue(map: Node, group: EntryGroup) -> Array[ ExhibitDisplay ]:
	var line : Array[ ExhibitDisplay ] = []
	for exhibit : ExhibitDisplay in map.find_children( "*", "ExhibitDisplay", true, false ):
		if exhibit.entry_mode == GROUP and exhibit.entry_group == group: line.append( exhibit )
	var scene_order := line.duplicate()
	line.sort_custom( func(a: ExhibitDisplay, b: ExhibitDisplay) -> bool:
		return a.queue < b.queue if a.queue != b.queue else scene_order.find( a ) < scene_order.find( b ) )
	return line

## The entry file this exhibit gets from its group, or "" when the group runs out before its turn
func get_group_entry() -> String:
	var map := get_map()
	if not entry_group or not map: return ""
	var place := get_queue( map, entry_group ).find( self )
	return entry_group.entries[ place ] if place >= 0 and place < entry_group.entries.size() else ""

## Prints an error for each entry group on map that has more entries than exhibits to show them, lists an
## entry file that isn't there, or has two exhibits at the same place in its queue
static func check_groups(map: Node) -> void:
	var groups : Dictionary[ EntryGroup, bool ] = {}
	for exhibit : ExhibitDisplay in map.find_children( "*", "ExhibitDisplay", true, false ):
		if exhibit.entry_mode == GROUP and exhibit.entry_group: groups[ exhibit.entry_group ] = true
	for group in groups:
		var line := get_queue( map, group )
		var label := "Entry group %s" % group.get_label()
		if line.size() < group.entries.size():
			push_error( "%s: it has %d entries but only %d exhibits take from it, so %s won't be shown" % [
					label, group.entries.size(), line.size(), ", ".join( group.entries.slice( line.size() ) ) ] )
		for file in group.entries:
			if not has_entry( file ): push_error( "%s: its entry \"%s\" isn't in the entry folder" % [ label, file ] )
		for i in range( 1, line.size() ):
			if line[ i ].queue == line[ i - 1 ].queue:
				push_error( "%s: %s and %s are both at queue %d, so their order is a guess" % [ label, line[ i - 1 ].describe(), line[ i ].describe(), line[ i ].queue ] )

#endregion

#region Building

func get_problems() -> PackedStringArray:
	match entry_mode:
		CUSTOM:
			if not custom_entry: return [ "it's set to CUSTOM but has no custom_entry" ]
		SELECT:
			if entry_file.is_empty(): return [ "it's set to SELECT but has no entry_file" ]
			if not has_entry( entry_file ): return [ "its entry_file, %s, isn't in the entry folder" % entry_file ]
		GROUP:
			if not entry_group: return [ "it's set to GROUP but has no entry_group" ]
	return []

func is_built() -> bool:
	# A group running out of entries before this exhibit's turn is fine, it just isn't built
	return entry_mode != GROUP or has_entry( get_group_entry() )

func get_prop_scene() -> PackedScene:
	return SCENE

func setup_prop(prop: Node3D) -> void:
	var facing := FACING[ start_direction ]
	prop.position += Vector3.UP * HANG_HEIGHT + Vector3( facing.x, 0.0, facing.y ) * WALL_GAP
	var entry := get_entry()
	if prop is Exhibit and entry: prop.set_entry( entry )

func copy_settings(from: PropDisplay) -> void:
	super( from )
	var exhibit := from as ExhibitDisplay
	if not exhibit: return
	entry_mode = exhibit.entry_mode
	entry_file = exhibit.entry_file
	# A custom entry belongs to one exhibit, so it isn't copied. A grouped exhibit joins the end of the queue.
	entry_group = exhibit.entry_group
	if entry_mode == GROUP and entry_group and exhibit.get_map():
		var line := get_queue( exhibit.get_map(), entry_group )
		queue = line.back().queue + 1 if not line.is_empty() else 0

#endregion
