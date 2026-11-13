@tool
extends "field_box.gd"

# The Skills field: the skills picked so far, one per row with a trash button, and a + button that
# offers the ones not picked yet. Several can be ticked and added in one go.
#
# An entry stores its skills as a single number, one bit per skill (see skill_list.gd), so the rows
# always come out in the order of the game's SKILLS list, whatever order they were added in.

signal changed

const RowList := preload( "row_list.gd" )
const SkillList := preload( "../core/skill_list.gd" )

const DOT_SIZE : int = 12

# The number an entry stores: bit 0 set means the first skill is picked, and so on.
var skills : int:
	set( value ):
		skills = value
		_refresh()

var _names : PackedStringArray
var _hue_seed : int = -1
var _rows : RowList
var _add_button : Button
var _popup : PopupPanel
var _choices : VBoxContainer
var _confirm_button : Button

func _init() -> void:
	super( "Skills" )
	_add_button = UiKit.make_icon_button( &"Add", "Add skills", "+" )
	_add_button.pressed.connect( _open_choices )
	add_to_header( _add_button )

	_rows = RowList.new()
	_rows.item_noun = "skill"
	_rows.can_reorder = false
	_rows.confirm_remove = false
	_rows.build_row = _build_row
	_rows.changed.connect( _on_rows_changed )
	add_body( _rows )

# The skills that exist, in the game's order. `hue_seed` is the SEED both the game and the website
# color the dots with (-1 for no dots).
func set_skill_names(names: PackedStringArray, hue_seed: int) -> void:
	_names = names
	_hue_seed = hue_seed
	_refresh()

func _refresh() -> void:
	if _rows == null: return
	var picked : Array = []
	for index in _names.size():
		if skills & (1 << index): picked.append( index )
	_rows.set_values( picked )
	var all_picked := picked.size() == _names.size()
	_add_button.disabled = all_picked
	_add_button.tooltip_text = "Every skill is already added" if all_picked else "Add skills"

func _build_row(_row: int, skill_index: int) -> Control:
	var row := HBoxContainer.new()
	if _hue_seed >= 0: row.add_child( _make_dot( SkillList.get_color( skill_index, _hue_seed ) ) )
	var label := Label.new()
	label.text = _names[ skill_index ]
	row.add_child( label )
	return row

# The same colored dot the exhibits draw next to a skill.
func _make_dot(color: Color) -> Control:
	var dot := Panel.new()
	var circle := StyleBoxFlat.new()
	circle.bg_color = color
	circle.set_corner_radius_all( DOT_SIZE )
	dot.add_theme_stylebox_override( &"panel", circle )
	dot.custom_minimum_size = Vector2.ONE * DOT_SIZE * UiKit.get_scale()
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot

# A row was removed with its trash button: clears that skill's bit.
func _on_rows_changed() -> void:
	var bits := 0
	for skill_index : int in _rows.get_values(): bits |= 1 << skill_index
	skills = bits
	changed.emit()

func _open_choices() -> void:
	if _popup == null:
		_popup = PopupPanel.new()
		var rows := VBoxContainer.new()
		_popup.add_child( rows )
		_choices = VBoxContainer.new()
		rows.add_child( _choices )
		rows.add_child( HSeparator.new() )
		var buttons := HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_END
		rows.add_child( buttons )
		var cancel := UiKit.make_button( "Cancel", &"", "" )
		cancel.pressed.connect( _popup.hide )
		buttons.add_child( cancel )
		_confirm_button = UiKit.make_button( "Add", &"", "" )
		_confirm_button.pressed.connect( _add_ticked )
		buttons.add_child( _confirm_button )
		add_child( _popup )

	for child in _choices.get_children():
		_choices.remove_child( child )
		child.queue_free()
	for index in _names.size():
		if skills & (1 << index): continue
		var choice := CheckBox.new()
		choice.text = _names[ index ]
		choice.set_meta( &"skill", index )
		choice.toggled.connect( func(_on: bool) -> void: _update_confirm_button() )
		_choices.add_child( choice )
	_update_confirm_button()
	_popup.reset_size()
	_popup.popup( Rect2i( Vector2i( _add_button.get_screen_position() + Vector2( 0, _add_button.size.y ) ), Vector2i.ZERO ) )

# Add stays grayed out until at least one skill is ticked.
func _update_confirm_button() -> void:
	var ticked := 0
	for choice : CheckBox in _choices.get_children():
		if choice.button_pressed: ticked += 1
	_confirm_button.disabled = ticked == 0
	_confirm_button.text = "Add" if ticked < 2 else "Add %d" % ticked

func _add_ticked() -> void:
	var bits := skills
	for choice : CheckBox in _choices.get_children():
		if choice.button_pressed: bits |= 1 << int( choice.get_meta( &"skill" ) )
	_popup.hide()
	if bits == skills: return
	skills = bits
	changed.emit()
