@tool
extends "preview_pane.gd"

# A preview of the website at one browser window size: the picture is a screenshot of the exhibit
# on the real page, which web_preview.gd takes a few times a second.

const WebPreview := preload( "../preview/web/web_preview.gd" )

var _preview : WebPreview
var _page_id : String

func _init(preview: WebPreview, page_id: String, pane_title: String) -> void:
	super()
	_preview = preview
	_page_id = page_id
	title = pane_title
	add_size_boxes( _preview.get_viewport_size( page_id ), "The browser window size the page is shown at, in pixels. exhibit.css switches between its thin and wide layouts at 960 wide." )
	_preview.changed.connect( refresh )
	_preview.frame_ready.connect( func(id: String) -> void:
		if id == _page_id: _update_layout() )

func _get_texture() -> Texture2D:
	return _preview.get_texture( _page_id )

func _get_content_size() -> Vector2:
	var content := _preview.get_content_size( _page_id )
	# Until the first picture arrives, plans for an exhibit as wide as the window.
	return content if content != Vector2.ZERO else Vector2( _preview.get_viewport_size( _page_id ) )

func _set_available_size(pixels: Vector2i) -> void:
	var content := _get_content_size()
	# Never bigger than the page's own pixels, the same rule the pane draws by.
	_preview.set_draw_scale( _page_id, minf( 1.0, minf( float( pixels.x ) / content.x, float( pixels.y ) / content.y ) ) )

func _is_running() -> bool:
	return _preview.state == WebPreview.RUNNING

func _is_up_to_date() -> bool:
	return _preview.is_up_to_date( _page_id )

func _get_message() -> String:
	if _preview.state == WebPreview.RUNNING: return "" if _preview.get_texture( _page_id ) or not _preview.is_up_to_date( _page_id ) else "Nothing to show."
	return _preview.status

func _can_restart() -> bool:
	return _preview.state == WebPreview.FAILED or _preview.state == WebPreview.STOPPED

func _restart() -> void:
	_preview.restart()

func _reload() -> void:
	if _preview.state == WebPreview.RUNNING: _preview.reload_page( _page_id )
	else: _preview.restart()

func _get_reports() -> Array:
	return _preview.get_reports( _page_id )

func _on_size_edited(new_size: Vector2i) -> void:
	_preview.set_viewport_size( _page_id, new_size )

func _send_mouse(spot: Vector2, _relative: Vector2, moved: bool, pressed: bool, buttons: int) -> void:
	_preview.send_mouse( _page_id, spot, moved, pressed, buttons )
