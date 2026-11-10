class_name SlideShow extends Control

## An exhibit's slideshow. ExhibitUI hands it image paths through add_item(); it loads each one from
## Webfiles/assets/images (the same files the website shows) and rotates through them.
## Webfiles/src/slideShow.js does the same on the website, so a change here usually belongs there too.

const SLIDE := preload("res://prefabs/slide.tscn")
const SLIDE_DOT := preload("res://prefabs/slide_dot.tscn")
const FileParserScript := preload("res://file_parser.gd")

const IMAGES_PATH : String = "assets/images/"
const IMAGE_EXTENSION : String = ".png"
const SLIDE_SECONDS : float = 0.4			# How long one slide animation takes
const DRAG_SWITCH_FRACTION : float = 0.25	# Dragging further than this much of the width switches images
const DOT_SIZE : float = 8.0
const CURRENT_DOT_SIZE : float = 12.0
const DOT_ALPHA : float = 0.5				# Brightness of the dots that aren't the current image

@onready var slides_holder : Control = $Slides
@onready var dots_holder : Container = $Dots
@onready var prev_arrow : Button = $PrevArrow
@onready var next_arrow : Button = $NextArrow
@onready var timer : Timer = $Timer			# Its wait_time is how long each image stays

var _slides : Array[ TextureRect ]
var _dots : Array[ Control ]
var _current : int = 0
# Where the current image sits, in slide widths: 0 = in the frame, 1 = one full width to the right.
# Switching images starts the new one off to the side it comes from, then eases this back to 0.
var _offset : float = 0.0:
	set(value):
		_offset = value
		_place_slides()
var _tween : Tween
var _dragging : bool = false
var _drag_start_x : float
var _drag_start_offset : float

func _ready() -> void:
	prev_arrow.pressed.connect( _go.bind( -1 ) )
	next_arrow.pressed.connect( _go.bind( 1 ) )
	timer.timeout.connect( _go.bind( 1 ) )
	resized.connect( _place_slides )
	remove_items()	# The slide and dots in the scene are only placeholders for the editor

func add_item(path: String) -> void:
	var slide := SLIDE.instantiate() as TextureRect
	slides_holder.add_child( slide )
	_slides.append( slide )
	var dot := SLIDE_DOT.instantiate() as Control
	dots_holder.add_child( dot )
	_dots.append( dot )
	_refresh()
	if _slides.size() == 2: timer.start()	# Now there's another image to rotate to
	_load_image( slide, IMAGES_PATH + path + IMAGE_EXTENSION )

func remove_items() -> void:
	for holder in [ slides_holder, dots_holder ]:
		for child in holder.get_children():
			holder.remove_child( child )
			child.queue_free()
	_slides.clear()
	_dots.clear()
	_current = 0
	_dragging = false
	if _tween: _tween.kill()
	_offset = 0.0
	timer.stop()
	timer.paused = false
	_refresh()

# Shows only the parts that make sense for how many images there are.
func _refresh() -> void:
	var can_move := _slides.size() > 1
	visible = not _slides.is_empty()	# Like the website: no images, no slideshow
	prev_arrow.visible = can_move
	next_arrow.visible = can_move
	dots_holder.visible = can_move
	mouse_default_cursor_shape = CURSOR_DRAG if can_move else CURSOR_ARROW
	_update_dots()
	_place_slides()

#region Moving between images

# Switches to the image beside the current one: 1 = the one to the right, -1 = the one to the left.
func _go(direction: int) -> void:
	if _slides.size() < 2: return
	_current = wrapi( _current + direction, 0, _slides.size() )
	_offset = clampf( _offset + direction, -1.0, 1.0 )	# The new image starts off to that side,
	_slide_home()										# then slides into the frame
	_update_dots()
	timer.paused = false
	timer.start()	# The new image gets its full time

func _slide_home() -> void:
	if _tween: _tween.kill()
	_tween = create_tween().set_trans( Tween.TRANS_CUBIC ).set_ease( Tween.EASE_OUT )
	_tween.tween_property( self, "_offset", 0.0, SLIDE_SECONDS )

# Puts the current image _offset widths from the middle and, while it's off center, the image
# beside it in the gap it leaves. All the others are hidden.
func _place_slides() -> void:
	if _slides.is_empty(): return
	var side : int = -1 if _offset > 0.0 else 1	# The neighbor that's coming into view
	var neighbor : int = wrapi( _current + side, 0, _slides.size() ) if _offset != 0.0 else _current
	for i in _slides.size():
		_slides[ i ].visible = i == _current or i == neighbor
	_slides[ _current ].position.x = _offset * size.x
	if neighbor != _current: _slides[ neighbor ].position.x = (_offset + side) * size.x

func _update_dots() -> void:
	for i in _dots.size():
		var is_current := i == _current
		_dots[ i ].custom_minimum_size = Vector2.ONE * (CURRENT_DOT_SIZE if is_current else DOT_SIZE)
		_dots[ i ].modulate.a = 1.0 if is_current else DOT_ALPHA

#endregion

#region Click and drag

# Holding the mouse down on the images lets you pull them sideways. The timer waits while you hold.
func _gui_input(event: InputEvent) -> void:
	if _slides.size() < 2: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _start_drag( event.position.x )
		elif _dragging: _end_drag()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_offset = clampf( _drag_start_offset + (event.position.x - _drag_start_x) / size.x, -1.0, 1.0 )
		accept_event()

func _start_drag(x: float) -> void:
	if _tween: _tween.kill()	# Catches the images wherever they are, even halfway through a slide
	_dragging = true
	_drag_start_x = x
	_drag_start_offset = _offset
	timer.paused = true

func _end_drag() -> void:
	_dragging = false
	var moved := _offset - _drag_start_offset
	# Pulled far enough, toward the image coming into view: switch to it (which resets the timer)
	if absf( _offset ) > DRAG_SWITCH_FRACTION and signf( moved ) == signf( _offset ):
		_go( -1 if _offset > 0.0 else 1 )
	else:	# Otherwise slide back, and the timer carries on from where it paused
		_slide_home()
		timer.paused = false

#endregion

#region Image loading

# Editor runs read the image from disk and web builds download it, the same way FileParser reads entries.
func _load_image(slide: TextureRect, file_path: String) -> void:
	var image : Image
	if OS.has_feature( "web" ):
		var bytes := await _download( JavaScriptBridge.eval( FileParserScript.JAVASCRIPT_EVAL_LABEL ) + file_path )
		if not bytes.is_empty():
			image = Image.new()
			if image.load_png_from_buffer( bytes ) != OK: image = null
	else:
		var disk_path := FileParserScript.get_webfiles_dir().path_join( file_path )
		if FileAccess.file_exists( disk_path ): image = Image.load_from_file( disk_path )

	if image == null: printerr( "Bad image at: ", file_path )
	elif is_instance_valid( slide ): slide.texture = ImageTexture.create_from_image( image )

func _download(url: String) -> PackedByteArray:
	var request := HTTPRequest.new()
	add_child( request )
	var response : Array = []
	if request.request( url ) == OK: response = await request.request_completed
	request.queue_free()

	if response.is_empty() or response[ 0 ] != HTTPRequest.RESULT_SUCCESS or response[ 1 ] != 200: return PackedByteArray()
	return response[ 3 ]

#endregion
