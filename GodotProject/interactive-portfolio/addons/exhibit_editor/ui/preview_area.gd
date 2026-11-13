@tool
extends HSplitContainer

# The four previews, all on show at once:
#
#     +-----------------------+-------------+
#     |  Website, wide        |  Website,   |
#     +-----------------------+  thin       |
#     |  ui_exhibit.tscn      +-------------+
#     |                       |  Entry.tscn |
#     +-----------------------+-------------+
#
# The wide ones share the left column and the tall ones the right. Every line between two previews
# can be dragged, and where they're left is remembered. A preview's maximize button hides the other
# three until it's pressed again.

const UiKit := preload( "ui_kit.gd" )
const GodotPreview := preload( "../preview/godot/godot_preview.gd" )
const WebPreview := preload( "../preview/web/web_preview.gd" )
const PreviewPane := preload( "preview_pane.gd" )
const GodotPane := preload( "godot_pane.gd" )
const WebPane := preload( "web_pane.gd" )

const SETTINGS_SECTION := "exhibit_editor"
# Where each dividing line starts out, as a share of the space it divides (left / top first).
const DEFAULT_SHARES : Dictionary[ String, float ] = { "columns": 0.68, "left_rows": 0.48, "right_rows": 0.62 }

var _panes : Array[ PreviewPane ]
var _splits : Dictionary[ String, SplitContainer ]
var _unplaced : Array[ String ] # Dividing lines still waiting for their split to get a size

func _init(godot_preview: GodotPreview, web_preview: WebPreview, settings_names: Dictionary) -> void:
	var left := VSplitContainer.new()
	var right := VSplitContainer.new()
	_splits[ "columns" ] = self
	_splits[ "left_rows" ] = left
	_splits[ "right_rows" ] = right
	for key : String in _splits:
		_unplaced.append( key )
		_splits[ key ].dragged.connect( func(_offset: int) -> void: _remember_share( key ) )
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child( left )
	add_child( right )

	_add_pane( left, WebPane.new( web_preview, WebPreview.PAGE_WIDE, "Website, wide" ) )
	_add_pane( left, GodotPane.new( godot_preview, GodotPreview.PANE_UI, settings_names.get( "ui", "Exhibit UI" ), true ) )
	_add_pane( right, WebPane.new( web_preview, WebPreview.PAGE_THIN, "Website, thin" ) )
	_add_pane( right, GodotPane.new( godot_preview, GodotPreview.PANE_ENTRY, settings_names.get( "entry", "3D exhibit" ), false ) )

# The scene names in the pane titles follow the settings ("ui_exhibit.tscn", "Entry.tscn").
func set_scene_titles(ui_title: String, entry_title: String) -> void:
	_panes[ 1 ].title = ui_title
	_panes[ 3 ].title = entry_title

func refresh() -> void:
	for pane in _panes: pane.refresh()

func _add_pane(column: SplitContainer, pane: PreviewPane) -> void:
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.maximize_toggled.connect( _on_maximize_toggled )
	column.add_child( pane )
	_panes.append( pane )

# Shows one pane alone, or all four again.
func _on_maximize_toggled(chosen: Control, on: bool) -> void:
	for pane in _panes:
		pane.visible = not on or pane == chosen
		pane.set_maximized( on and pane == chosen )
	# A column with nothing left in it would still take up its half.
	for column : SplitContainer in [ _splits[ "left_rows" ], _splits[ "right_rows" ] ]:
		column.visible = not on or chosen.get_parent() == column

# A dividing line can only be put in its place once its split knows how big it is, which happens a
# frame or two after the screen is first shown.
func _process(_delta: float) -> void:
	for key : String in _unplaced.duplicate():
		var split := _splits[ key ]
		var length := split.size.y if split.vertical else split.size.x
		if length <= 0 or not split.is_visible_in_tree(): continue
		# Both sides of each line stretch, and for those Godot counts the offset from the middle.
		split.split_offset = int( length * (_get_share( key ) - 0.5) )
		_unplaced.erase( key )
	if _unplaced.is_empty(): set_process( false )

func _get_share(key: String) -> float:
	var share : float = DEFAULT_SHARES[ key ]
	if Engine.is_editor_hint(): share = EditorInterface.get_editor_settings().get_project_metadata( SETTINGS_SECTION, "split_" + key, share )
	return clampf( share, 0.1, 0.9 )

func _remember_share(key: String) -> void:
	var split := _splits[ key ]
	var length := split.size.y if split.vertical else split.size.x
	if length <= 0 or not Engine.is_editor_hint(): return
	EditorInterface.get_editor_settings().set_project_metadata( SETTINGS_SECTION, "split_" + key, clampf( 0.5 + split.split_offset / length, 0.1, 0.9 ) )
