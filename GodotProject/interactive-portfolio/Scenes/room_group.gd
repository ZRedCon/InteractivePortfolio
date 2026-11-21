@tool
class_name RoomGroup extends TileMapLayer

## A block of cells on the museum map that's built as one scene instead of as rooms. Paint them with the Map
## Painter's Room Groups tool. The rooms under a group aren't built, but props on it still are.

## Built in this group's place, unturned, with its origin at the group's top-left corner (the corner of the
## smallest box around all its cells), so the group stretches away from it along +X and +Z
@export var scene : PackedScene:
	set( value ):
		scene = value
		update_configuration_warnings()

## The top-left cell of the smallest box around all the group's cells
func get_top_left() -> Vector2i:
	var cells := get_used_cells()
	var corner : Vector2i = cells[ 0 ] if not cells.is_empty() else Vector2i.ZERO
	for cell in cells: corner = corner.min( cell )
	return corner

## Where this group is, for error messages
func describe() -> String:
	return "Room group \"%s\" at %s" % [ name, get_top_left() ]

## Problems that keep this group from being built, each worded to follow describe() and a colon
func get_problems() -> PackedStringArray:
	return [] if scene else [ "it has no scene to build" ]

func _get_configuration_warnings() -> PackedStringArray:
	return get_problems()
