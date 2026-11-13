@tool
extends SubViewport

# Where one Godot preview is drawn inside the editor: a viewport holding the script-less copy of an
# exhibit scene that scene_mirror.gd keeps up to date. A preview pane shows this viewport's texture.
#
# It sets itself up for whichever kind of scene arrives. A 2D or UI scene is laid out at
# virtual_size (the screen size the scene should believe it has) and drawn at whatever size fits the
# pane, re-rendered at that size rather than scaled, so text stays sharp. A 3D scene gets a camera
# that keeps the whole thing in view.

# The picture was just drawn again, so whatever is showing it should redraw too.
signal redrawn

const SceneMirror := preload( "scene_mirror.gd" )

const MODE_NONE := 0
const MODE_2D := 1
const MODE_3D := 2

const CAMERA_FOV : float = 40.0
# How much wider than the exhibit the 3D view is, so it doesn't touch the pane's edges.
const CAMERA_MARGIN : float = 1.25
const SMALLEST_VIEW : float = 0.05 # Metres. Keeps the camera sane for an exhibit with nothing in it yet.
# The picture is only drawn when something in it changed, to leave the editor idle the rest of the time.
# It's drawn for this many frames after each change, because some things settle a frame or two late
# (a container arranging its children, the size of the Label3D the camera is fitted around).
const DRAW_FRAMES : int = 3

var mode : int = MODE_NONE
var mirror : SceneMirror
# 2D: the size the scene is laid out at, in its own pixels.
var virtual_size := Vector2i( 1152, 648 ):
	set( value ):
		virtual_size = value.maxi( 1 )
		_update_size()

var _textures : Dictionary
var _display_size := Vector2i( 64, 64 )
var _holder : Node # The mirror's parent
var _camera : Camera3D
var _drawing : bool
var _frames_to_draw : int

func _init(textures: Dictionary) -> void:
	_textures = textures
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	gui_disable_input = true # It's a picture. Clicks are sent to the helper, where the real scene is.
	# The same defaults the game's own window gets from the project settings.
	canvas_item_default_texture_filter = ProjectSettings.get_setting( "rendering/textures/canvas_textures/default_texture_filter", 1 )
	canvas_item_default_texture_repeat = ProjectSettings.get_setting( "rendering/textures/canvas_textures/default_texture_repeat", 0 )
	snap_2d_transforms_to_pixel = ProjectSettings.get_setting( "rendering/2d/snap/snap_2d_transforms_to_pixel", false )
	snap_2d_vertices_to_pixel = ProjectSettings.get_setting( "rendering/2d/snap/snap_2d_vertices_to_pixel", false )
	_update_size()

# Whether to draw at all. Off while nobody can see the preview.
func set_drawing(on: bool) -> void:
	_drawing = on
	request_draw()

# Something that shows in the picture changed.
func request_draw() -> void:
	_frames_to_draw = DRAW_FRAMES
	set_process( true )

# How many pixels the pane has for this preview. A 2D scene is drawn at virtual_size scaled down to
# fit inside that (never up); a 3D scene fills it.
func set_available_size(pixels: Vector2i) -> void:
	_display_size = pixels.maxi( 8 )
	_update_size()

func apply_state(state: Dictionary) -> void:
	var tree : Dictionary = state.get( "tree", {} )
	var wanted := MODE_NONE
	if not tree.is_empty():
		wanted = MODE_3D if ClassDB.is_parent_class( tree.get( "class", &"Node" ), &"Node3D" ) else MODE_2D
	if wanted != mode: _set_mode( wanted )
	if mirror: mirror.apply( state )
	request_draw()

func clear() -> void:
	_set_mode( MODE_NONE )

func _process(_delta: float) -> void:
	if _frames_to_draw <= 0 or not _drawing:
		set_process( false )
		return
	_frames_to_draw -= 1
	if mode == MODE_3D: _frame_camera()
	# Draws this frame, then goes back to not drawing by itself.
	render_target_update_mode = SubViewport.UPDATE_ONCE
	redrawn.emit()

func _set_mode(new_mode: int) -> void:
	if mirror: mirror.clear()
	mirror = null
	for child in get_children():
		remove_child( child )
		child.queue_free()
	_camera = null
	_holder = null
	mode = new_mode

	var clear_color : Color = ProjectSettings.get_setting( "rendering/environment/defaults/default_clear_color", Color( 0.3, 0.3, 0.3 ) )
	if mode == MODE_2D:
		disable_3d = true
		var background := ColorRect.new()
		background.color = clear_color
		add_child( background )
		background.set_anchors_and_offsets_preset( Control.PRESET_FULL_RECT )
		_holder = _add_theme_root( self, ThemeDB.get_default_theme() )
		if ThemeDB.get_project_theme(): _holder = _add_theme_root( _holder, ThemeDB.get_project_theme() )
	elif mode == MODE_3D:
		disable_3d = false
		own_world_3d = true
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = clear_color
		# Enough light to see a mesh by. Label3D and Sprite3D ignore lighting unless they're set to be shaded.
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 0.6
		var world_environment := WorldEnvironment.new()
		world_environment.environment = environment
		add_child( world_environment )
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3( -45, 30, 0 )
		add_child( sun )
		_camera = Camera3D.new()
		_camera.fov = CAMERA_FOV
		add_child( _camera )
		_camera.current = true
		_holder = Node3D.new()
		add_child( _holder )
	if _holder: mirror = SceneMirror.new( _holder, _textures )
	_update_size()

# Controls in here would otherwise pick up the editor's fonts and colors, because they're inside the
# editor's window. A theme on a parent wins over that, so the copy is wrapped in the same themes the
# running game uses: Godot's default one, then the project's own on top if it has one.
func _add_theme_root(parent: Node, theme: Theme) -> Control:
	var root := Control.new()
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child( root )
	root.set_anchors_and_offsets_preset( Control.PRESET_FULL_RECT )
	return root

func _update_size() -> void:
	if mode == MODE_2D:
		var scale := minf( 1.0, minf( float( _display_size.x ) / virtual_size.x, float( _display_size.y ) / virtual_size.y ) )
		size = Vector2i( (Vector2( virtual_size ) * scale).round() ).maxi( 8 )
		size_2d_override = virtual_size
		size_2d_override_stretch = true
	else:
		size = _display_size
		size_2d_override = Vector2i.ZERO
		size_2d_override_stretch = false
	request_draw()

# Backs the camera off along +Z (the side a Sprite3D and a Label3D face) until everything visible fits.
func _frame_camera() -> void:
	var bounds := AABB()
	var found := false
	for node in _holder.find_children( "*", "VisualInstance3D", true, false ):
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree() or visual is Light3D: continue
		var box := visual.global_transform * visual.get_aabb()
		if box.size == Vector3.ZERO: continue
		bounds = bounds.merge( box ) if found else box
		found = true
	if not found: return

	var half_height := maxf( bounds.size.y / 2.0, SMALLEST_VIEW ) * CAMERA_MARGIN
	var half_width := maxf( bounds.size.x / 2.0, SMALLEST_VIEW ) * CAMERA_MARGIN
	var slope := tan( deg_to_rad( CAMERA_FOV ) / 2.0 )
	var aspect := float( size.x ) / maxf( size.y, 1.0 )
	var distance := maxf( half_height / slope, half_width / (slope * aspect) ) + bounds.size.z / 2.0
	_camera.position = bounds.get_center() + Vector3( 0, 0, distance )
	_camera.near = maxf( distance / 100.0, 0.001 )
	_camera.far = distance * 10.0 + bounds.size.z
