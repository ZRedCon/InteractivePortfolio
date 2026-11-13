@tool
extends Node

# Runs the website previews. They aren't imitations of the site: a real browser (Chrome or Edge,
# started without a window) opens the real page, served by http_server.gd from the real Webfiles
# folder. The one thing that's different is the data: the entry index and the entry file are
# answered from memory, so the page finds exactly one entry, the one being edited.
#
# So main.js, entryToExhibit.js, slideShow.js and exhibit.css all run exactly as they are, and
# when one of them is edited the preview reloads. Each preview is a tab in that browser, set to
# its own window size (one wide, one thin), and what's shown in the editor is a screenshot of the
# exhibit element taken a few times a second.

signal changed # The status line, or what there is to report, is different now
signal frame_ready(page_id: String) # A page has a new picture
signal link_clicked(url: String) # A link in a preview was clicked (the preview itself stays where it is)

const Settings := preload( "../../core/settings.gd" )
const HttpServer := preload( "http_server.gd" )
const CdpClient := preload( "cdp_client.gd" )

const PAGE_WIDE := "wide"
const PAGE_THIN := "thin"
const PAGE_IDS : Array[ String ] = [ PAGE_WIDE, PAGE_THIN ]
# The browser window each preview pretends to be. exhibit.css switches layout at 960 pixels wide.
const DEFAULT_SIZES : Dictionary[ String, Vector2i ] = { PAGE_WIDE: Vector2i( 1280, 800 ), PAGE_THIN: Vector2i( 390, 844 ) }

const STOPPED := 0
const STARTING := 1
const RUNNING := 2
const FAILED := 3

# The made-up file name the entry being edited is served under.
const PREVIEW_FILE := "exhibit-editor-preview.json"
const PROFILE_PREFIX := "browser-"
const LINK_MARKER := "exhibit-editor-link:"
# The function the browser adds to each page for it to call when it has changed (see INJECTED_SCRIPT).
const CHANGE_BINDING := "exhibitEditorChanged"
# How much of the page around the exhibit is included in the picture, so its border and corners show.
const CLIP_PADDING : float = 8.0
# The shortest time between two pictures of a page that keeps changing (a slideshow sliding).
const CAPTURE_INTERVAL_MSEC : int = 100
# How often a page that hasn't said anything is checked on anyway, and the longest it goes without a
# fresh picture (for whatever the page's own count misses, like a hover effect).
const QUIET_CHECK_MSEC : int = 1500
const STALE_PICTURE_MSEC : int = 4500
const FILE_CHECK_INTERVAL_MSEC : int = 1000
const BROWSER_START_TIMEOUT_MSEC : int = 20000
const EXHIBIT_TIMEOUT_MSEC : int = 6000
const MIN_SCALE : float = 0.25
const MAX_SCALE : float = 2.0
const MAX_CAPTURE_PIXELS : int = 12000000
const MAX_REPORTS : int = 12
const SWEEP_DELAY_MSEC : int = 5000
# Sweeps go on every SWEEP_DELAY_MSEC until no old profile is left, up to this many times. A browser
# that was only just closed can hold on to its folder for a few seconds.
const SWEEPS_AFTER_START : int = 6
const CLOSE_WAIT_MSEC : int = 500

# Runs in every page before its own scripts. It does two things. It keeps count of every change to the
# page (elements added, styles set, images arriving) and tells the editor when there's been one, so a
# new picture is only taken when there's something new to see and the browser can rest in between. (Window resizes aren't counted: taking a picture of something
# below the window resizes the page for a moment, and every picture would look like a reason for another.) And since clicking a link would take the preview away from the
# page it's previewing, it reports links to the editor instead of following them.
const INJECTED_SCRIPT := """(() => {
	window.__exhibitEditorChanges = 0;
	let telling = false;
	const changed = () => {
		window.__exhibitEditorChanges++;
		if (telling || typeof window[%s] !== "function") return;
		telling = true;
		setTimeout(() => { telling = false; window[%s](""); }, 30);
	};
	new MutationObserver(changed).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
	for (const type of ["load", "error", "transitionend", "animationend"]) document.addEventListener(type, changed, true);
	const tell = url => console.info(%s + url);
	document.addEventListener("click", event => {
		const link = event.target.closest && event.target.closest("a[href]");
		if (!link) return;
		event.preventDefault();
		tell(link.href);
	}, true);
	window.open = url => { tell(String(url)); return null; };
})()"""

# Where the exhibit is on the page, and whether its images have finished loading.
const PROBE_SCRIPT := """(() => {
	const element = document.querySelector(%s);
	if (!element) return { found: false };
	const box = element.getBoundingClientRect();
	const images = [...element.querySelectorAll("img")];
	return {
		found: true,
		x: box.left + window.scrollX, y: box.top + window.scrollY, width: box.width, height: box.height,
		pending: images.filter(image => !image.complete).length,
		changes: window.__exhibitEditorChanges || 0,
	};
})()"""

# Brings a point of the page into view, and says how far the page is scrolled afterwards.
const SCROLL_SCRIPT := """(() => {
	window.scrollTo(%f - window.innerWidth / 2, %f - window.innerHeight / 2);
	return [window.scrollX, window.scrollY];
})()"""

class Page:
	var id : String
	var viewport_size : Vector2i # The browser window it pretends to be, in CSS pixels
	var scale : float = 1.0 # Screen pixels per CSS pixel, so the picture is drawn at the size it's shown
	var session : String
	var load_count : int # Goes up with every load. A step that waited checks it's still the same load.
	var loading : bool
	var capturing : bool
	var loaded_rev : int = -1
	var captured_rev : int = -1
	var texture : ImageTexture
	var clip : Rect2 # The part of the page in the picture, in CSS pixels
	var last_capture : String
	var last_capture_at : int
	var last_picture_at : int
	var seen_changes : int = -1
	var wants_picture : bool # Something outside the page's own count changed: its size, its scale, or it was clicked
	var reports : Array[ Dictionary ]
	var scroll : Vector2
	var input_queue : Array[ Dictionary ]
	var pumping : bool

var state : int = STOPPED
# One line saying what the browser is doing, or why it isn't.
var status : String = "Not started"

var _settings : Settings
var _cache_dir : String
var _http := HttpServer.new()
var _cdp := CdpClient.new()
var _pages : Dictionary[ String, Page ]
var _pid : int = -1
var _profile_dir : String
var _run : int # Goes up on every start and stop, so a start that's still waiting knows it's been overtaken
var _active : bool
var _entry_json : String = "{ }\n"
var _entry_rev : int
var _last_file_check : int
var _sweep_at : int
var _sweeps_left : int
var _closing : bool # Closing the browser on purpose, so the connection ending isn't a failure

func setup(settings: Settings, cache_dir: String) -> void:
	_settings = settings
	_cache_dir = cache_dir
	for id in PAGE_IDS:
		var page := Page.new()
		page.id = id
		page.viewport_size = DEFAULT_SIZES[ id ]
		_pages[ id ] = page
	_cdp.event_received.connect( _on_event )
	_cdp.closed.connect( _on_connection_closed )
	_settings.changed.connect( _on_setting_changed )

#region What the panes ask for

func get_texture(page_id: String) -> Texture2D:
	return _pages[ page_id ].texture

# The size of the picture in CSS pixels: how big the exhibit is on the page, whatever scale it's drawn at.
func get_content_size(page_id: String) -> Vector2:
	return _pages[ page_id ].clip.size

func get_viewport_size(page_id: String) -> Vector2i:
	return _pages[ page_id ].viewport_size

func is_up_to_date(page_id: String) -> bool:
	return state == RUNNING and _pages[ page_id ].captured_rev == _entry_rev

# What went wrong on this page, plus the files it asked for that aren't there.
func get_reports(page_id: String) -> Array:
	var reports : Array = _pages[ page_id ].reports.duplicate()
	for url_path : String in _http.missing:
		reports.append( { "kind": "error", "text": _http.missing[ url_path ], "where": "" } )
	return reports

# Image names (the way entries store them) that the page asked for and didn't get.
func get_missing_images() -> Dictionary[ String, String ]:
	var names : Dictionary[ String, String ] = {}
	var prefix := _settings.get_image_url_path( "" ).trim_suffix( _settings.get_value( Settings.IMAGE_EXTENSION ) )
	var ending := _settings.get_value( Settings.IMAGE_EXTENSION )
	for url_path : String in _http.missing:
		if url_path.begins_with( prefix ) and url_path.ends_with( ending ):
			names[ url_path.substr( prefix.length(), url_path.length() - prefix.length() - ending.length() ) ] = _http.missing[ url_path ]
	return names

func set_viewport_size(page_id: String, size: Vector2i) -> void:
	var page := _pages[ page_id ]
	size = size.clampi( 200, 4000 )
	if page.viewport_size == size: return
	page.viewport_size = size
	if state == RUNNING: _apply_metrics( page )

# Opens the page from scratch, the way the browser's own reload button would.
func reload_page(page_id: String) -> void:
	if state == RUNNING: _load( _pages[ page_id ] )

# How big the picture is drawn compared to the page's own pixels, so it can be rendered at that size
# and stay sharp instead of being shrunk afterwards.
func set_draw_scale(page_id: String, scale: float) -> void:
	var page := _pages[ page_id ]
	scale = clampf( scale, MIN_SCALE, MAX_SCALE )
	if is_equal_approx( page.scale, scale ): return
	page.scale = scale
	if state == RUNNING: _apply_metrics( page )

# A mouse press, release or move, at a position inside the picture in CSS pixels.
func send_mouse(page_id: String, position: Vector2, moved: bool, pressed: bool, buttons: int) -> void:
	if state != RUNNING: return
	var page := _pages[ page_id ]
	var event := { "position": page.clip.position + position, "moved": moved, "pressed": pressed, "buttons": buttons }
	# Only the newest of a run of moves matters.
	if moved and not page.input_queue.is_empty() and page.input_queue.back()[ "moved" ]: page.input_queue[ -1 ] = event
	else: page.input_queue.append( event )
	if not page.pumping: _pump_input( page )

#endregion

#region Starting and stopping

func start() -> void:
	if state == STARTING or state == RUNNING: return
	_shut_down()
	_run += 1
	_set_state( STARTING, "Starting the browser..." )
	_start( _run )

func stop() -> void:
	_shut_down()
	_run += 1
	_set_state( STOPPED, "Stopped" )

func restart() -> void:
	stop()
	start()

func set_active(on: bool) -> void:
	_active = on

func set_entry_json(json: String) -> void:
	if json == _entry_json: return
	_entry_json = json
	_entry_rev += 1
	_serve_entry()
	if state == RUNNING:
		for page : Page in _pages.values(): _load( page )
	changed.emit()

func _start(run: int) -> void:
	var browser := _settings.find_browser()
	if browser.is_empty():
		_fail( "No Chrome or Edge was found, so the website can't be drawn. Pick the browser in the Settings tab." )
		return
	if not DirAccess.dir_exists_absolute( _settings.get_webfiles_dir() ):
		_fail( "The website folder wasn't found: %s. It's set in the Settings tab." % _settings.get_webfiles_dir() )
		return

	_http.root_dir = _settings.get_webfiles_dir()
	_http.blank_folders = _settings.get_blank_folders()
	if _http.start() != OK:
		_fail( "Couldn't start the preview's web server." )
		return
	_serve_entry()

	# A profile of its own keeps this browser completely apart from the one you browse with.
	_profile_dir = _cache_dir.path_join( "%s%08x" % [ PROFILE_PREFIX, randi() ] )
	DirAccess.make_dir_recursive_absolute( _profile_dir )
	_close_old_browsers()
	# A browser that was only just closed still has its files open for a moment, so sweep once more later.
	_sweep_at = Time.get_ticks_msec() + SWEEP_DELAY_MSEC
	_sweeps_left = SWEEPS_AFTER_START
	_pid = OS.create_process( browser, PackedStringArray( [
		"--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + _profile_dir,
		"--no-first-run", "--no-default-browser-check", "--disable-extensions", "--disable-sync",
		"--disable-background-networking", "--disable-component-update", "--mute-audio", "--hide-scrollbars",
		"about:blank",
	] ) )
	if _pid <= 0:
		_fail( "Couldn't start the browser at %s." % browser )
		return

	# The browser writes this file once it's listening: its port, then the address to connect to.
	var port_file := _profile_dir.path_join( "DevToolsActivePort" )
	var started_at := Time.get_ticks_msec()
	var address := PackedStringArray()
	while address.size() < 2:
		await get_tree().process_frame
		if run != _run: return
		if FileAccess.file_exists( port_file ): address = FileAccess.get_file_as_string( port_file ).strip_edges().split( "\n" )
		if address.size() < 2 and not OS.is_process_running( _pid ):
			_fail( "The browser closed as soon as it started." )
			return
		if Time.get_ticks_msec() - started_at > BROWSER_START_TIMEOUT_MSEC:
			_fail( "The browser didn't get ready within %d seconds." % (BROWSER_START_TIMEOUT_MSEC / 1000) )
			return

	_cdp.open( "ws://127.0.0.1:%s%s" % [ address[ 0 ].strip_edges(), address[ 1 ].strip_edges() ] )
	while not _cdp.is_open():
		await get_tree().process_frame
		if run != _run: return
		if _cdp.is_open(): break
		if not _cdp.is_connecting() or Time.get_ticks_msec() - started_at > BROWSER_START_TIMEOUT_MSEC:
			_fail( "Couldn't connect to the browser." )
			return

	for page : Page in _pages.values():
		# A window of its own for each page. Two tabs in one window would leave one of them in the
		# background, and the browser stops drawing (and even handling clicks for) a background tab.
		var target := await _cdp.request( "Target.createTarget", { "url": "about:blank", "newWindow": true } )
		if run != _run: return
		var attached := target
		if not CdpClient.failed( target ): attached = await _cdp.request( "Target.attachToTarget", { "targetId": target.get( "targetId", "" ), "flatten": true } )
		if run != _run: return
		if CdpClient.failed( attached ):
			_fail( "Couldn't open a preview tab in the browser." )
			return
		page.session = attached.get( "sessionId", "" )
		await _cdp.request( "Runtime.addBinding", { "name": CHANGE_BINDING }, page.session )
		if run != _run: return
		for command : String in [ "Page.enable", "Runtime.enable" ]:
			await _cdp.request( command, {}, page.session )
			if run != _run: return
		await _cdp.request( "Page.addScriptToEvaluateOnNewDocument", { "source": INJECTED_SCRIPT % [ JSON.stringify( CHANGE_BINDING ), JSON.stringify( CHANGE_BINDING ), JSON.stringify( LINK_MARKER ) ] }, page.session )
		if run != _run: return
		await _apply_metrics( page )
		if run != _run: return

	_set_state( RUNNING, "Running" )
	for page : Page in _pages.values(): _load( page )

func _shut_down() -> void:
	_closing = true
	if _cdp.is_open():
		# Asks the browser to close itself and gives it a moment to, so it lets go of its files and takes
		# its helper processes with it. Only if it's still there after that is it stopped the hard way.
		_cdp.request( "Browser.close" )
		var give_up_at := Time.get_ticks_msec() + CLOSE_WAIT_MSEC
		while _pid > 0 and OS.is_process_running( _pid ) and Time.get_ticks_msec() < give_up_at:
			_cdp.poll()
			OS.delay_msec( 10 )
	_cdp.close()
	_http.stop()
	if _pid > 0 and OS.is_process_running( _pid ): OS.kill( _pid )
	_pid = -1
	_closing = false
	for page : Page in _pages.values():
		page.session = ""
		page.load_count += 1
		page.loading = false
		page.capturing = false
		page.pumping = false
		page.input_queue.clear()
		page.loaded_rev = -1
		page.captured_rev = -1

func _fail(reason: String) -> void:
	_shut_down()
	_run += 1
	_set_state( FAILED, reason )

func _set_state(new_state: int, new_status: String) -> void:
	state = new_state
	status = new_status
	changed.emit()

func _on_connection_closed() -> void:
	if not _closing and (state == RUNNING or state == STARTING): _fail( "The browser closed." )

func _on_setting_changed(key: String) -> void:
	if state == STOPPED: return
	if key in [ Settings.WEBFILES_DIR, Settings.BLANK_FOLDERS, Settings.BROWSER_PATH, Settings.DATA_DIR, Settings.INDEX_FILE ]: restart()
	elif key in [ Settings.SITE_PAGE, Settings.EXHIBIT_SELECTOR ] and state == RUNNING:
		for page : Page in _pages.values(): _load( page )

func _exit_tree() -> void:
	_shut_down()

# A browser left running by an editor that crashed would sit there forever: it has no window to close.
# Each one's profile folder still holds the address it listens on, which is enough to tell it to quit.
func _close_old_browsers() -> void:
	if not DirAccess.dir_exists_absolute( _cache_dir ): return
	for folder in DirAccess.get_directories_at( _cache_dir ):
		var profile := _cache_dir.path_join( folder )
		if not folder.begins_with( PROFILE_PREFIX ) or profile == _profile_dir: continue
		var port_file := profile.path_join( "DevToolsActivePort" )
		var address := FileAccess.get_file_as_string( port_file ).strip_edges().split( "\n" ) if FileAccess.file_exists( port_file ) else PackedStringArray()
		if address.size() >= 2: _close_old_browser( "ws://127.0.0.1:%s%s" % [ address[ 0 ].strip_edges(), address[ 1 ].strip_edges() ], profile )
		else: _remove_folder( profile )

func _has_old_profiles() -> bool:
	for folder in DirAccess.get_directories_at( _cache_dir ):
		if folder.begins_with( PROFILE_PREFIX ) and _cache_dir.path_join( folder ) != _profile_dir: return true
	return false

func _close_old_browser(address: String, profile: String) -> void:
	var old := CdpClient.new()
	old.open( address )
	for i in 120: # A couple of seconds
		old.poll()
		if not old.is_connecting(): break
		await get_tree().process_frame
	if old.is_open():
		old.request( "Browser.close" )
		for i in 30:
			old.poll()
			await get_tree().process_frame
	old.close()
	_remove_folder( profile )

# Removes a folder and everything in it. Files a program still has open are left for next time.
static func _remove_folder(path: String) -> void:
	# DirAccess.open() just returns null for a folder it can't read, where get_files_at() would print an error.
	var dir := DirAccess.open( path )
	if dir == null: return
	dir.include_hidden = true
	for file in dir.get_files(): dir.remove( file )
	for folder in dir.get_directories(): _remove_folder( path.path_join( folder ) )
	DirAccess.remove_absolute( path )

#endregion

#region Pages

func _process(_delta: float) -> void:
	_http.poll()
	_cdp.poll()
	var now := Time.get_ticks_msec()
	if _sweep_at > 0 and now >= _sweep_at:
		_sweeps_left -= 1
		_close_old_browsers()
		_sweep_at = now + SWEEP_DELAY_MSEC if _sweeps_left > 0 and _has_old_profiles() else 0
	if state != RUNNING or not _active: return

	if now - _last_file_check > FILE_CHECK_INTERVAL_MSEC:
		_last_file_check = now
		# One of the site's own files was edited, so load it again.
		if _http.take_files_changed():
			for page : Page in _pages.values(): _load( page )
			return
	for page : Page in _pages.values():
		if page.loading or page.capturing: continue
		var since_last := now - page.last_capture_at
		if (page.wants_picture and since_last >= CAPTURE_INTERVAL_MSEC) or since_last >= QUIET_CHECK_MSEC: _capture( page )

# The entry being edited becomes the site's only entry: the index lists one file, and that file is it.
func _serve_entry() -> void:
	_http.clear_virtual_files()
	_http.set_virtual_file( _settings.get_value( Settings.INDEX_FILE ), JSON.stringify( [ PREVIEW_FILE ] ).to_utf8_buffer() )
	_http.set_virtual_file( Settings.clean_path( _settings.get_value( Settings.DATA_DIR ) ).path_join( PREVIEW_FILE ), _entry_json.to_utf8_buffer() )

func _apply_metrics(page: Page) -> void:
	await _cdp.request( "Emulation.setDeviceMetricsOverride", { "width": page.viewport_size.x, "height": page.viewport_size.y, "deviceScaleFactor": page.scale, "mobile": false }, page.session )
	page.last_capture_at = 0 # Take a new picture right away
	page.wants_picture = true

# Opens the page from scratch and waits for the exhibit to show up on it.
func _load(page: Page) -> void:
	page.load_count += 1
	var load_id := page.load_count
	var rev := _entry_rev
	page.loading = true
	# Whatever was still waiting on the old page gives up when it sees load_count has moved on.
	page.capturing = false
	page.pumping = false
	page.input_queue.clear()
	page.reports.clear()
	_http.clear_missing()

	var navigated := await _cdp.request( "Page.navigate", { "url": _http.get_url( _settings.get_value( Settings.SITE_PAGE ) ) }, page.session )
	if load_id != page.load_count: return
	if CdpClient.failed( navigated ) or navigated.has( "errorText" ):
		page.loading = false
		_add_report( page, "error", "Couldn't open the page: %s" % navigated.get( "errorText", navigated.get( CdpClient.ERROR_KEY, "" ) ), "" )
		return

	var deadline := Time.get_ticks_msec() + EXHIBIT_TIMEOUT_MSEC
	var found := false
	while Time.get_ticks_msec() < deadline:
		var probe := await _probe( page )
		if load_id != page.load_count: return
		if probe.has( "invalid" ): break
		if probe.get( "found", false ) and probe.get( "pending", 0 ) == 0:
			found = true
			break
		await get_tree().process_frame
		if load_id != page.load_count: return

	page.loading = false
	page.loaded_rev = rev
	if not found:
		_add_report( page, "error", "Nothing on the page matches the exhibit selector \"%s\", so there's nothing to show. Either the page couldn't build the exhibit (see any errors here) or the selector in the Settings tab is out of date." % _settings.get_value( Settings.EXHIBIT_SELECTOR ), "" )
		page.captured_rev = rev
		changed.emit()
		return
	page.last_capture_at = 0

func _probe(page: Page) -> Dictionary:
	var selector := JSON.stringify( _settings.get_value( Settings.EXHIBIT_SELECTOR ) )
	var result := await _cdp.request( "Runtime.evaluate", { "expression": PROBE_SCRIPT % selector, "returnByValue": true }, page.session )
	if result.has( "exceptionDetails" ):
		_add_report( page, "error", "The exhibit selector \"%s\" isn't valid CSS." % _settings.get_value( Settings.EXHIBIT_SELECTOR ), "" )
		return { "invalid": true }
	var value : Variant = result.get( "result", {} ).get( "value" )
	return value if value is Dictionary else {}

func _capture(page: Page) -> void:
	page.capturing = true
	var load_id := page.load_count
	var rev := page.loaded_rev
	var probe := await _probe( page )
	if load_id != page.load_count: return
	if not probe.get( "found", false ):
		page.capturing = false
		page.last_capture_at = Time.get_ticks_msec()
		return

	var clip := Rect2( probe[ "x" ], probe[ "y" ], probe[ "width" ], probe[ "height" ] ).grow( CLIP_PADDING )
	clip.position = clip.position.max( Vector2.ZERO )
	# Nothing new on the page since the last picture: no need for another one yet.
	var changes := int( probe.get( "changes", 0 ) )
	var now := Time.get_ticks_msec()
	if changes == page.seen_changes and clip == page.clip and not page.wants_picture and page.captured_rev == rev and now - page.last_picture_at < STALE_PICTURE_MSEC:
		page.capturing = false
		page.last_capture_at = now
		return
	page.seen_changes = changes
	page.wants_picture = false
	page.last_picture_at = now
	# A huge exhibit drawn at a large scale could be more pixels than is sensible to send. Draws it smaller.
	var pixels := clip.size.x * clip.size.y * page.scale * page.scale
	var shrink := minf( 1.0, sqrt( MAX_CAPTURE_PIXELS / maxf( pixels, 1.0 ) ) )
	var shot := await _cdp.request( "Page.captureScreenshot", {
		"format": "png", "captureBeyondViewport": true, "optimizeForSpeed": true,
		"clip": { "x": clip.position.x, "y": clip.position.y, "width": clip.size.x, "height": clip.size.y, "scale": shrink },
	}, page.session )
	if load_id != page.load_count: return
	page.capturing = false
	page.last_capture_at = Time.get_ticks_msec()
	if CdpClient.failed( shot ): return

	var was_up_to_date := page.captured_rev == rev
	page.captured_rev = rev
	var data : String = shot.get( "data", "" )
	if data == page.last_capture and clip == page.clip:
		if not was_up_to_date: changed.emit()
		return
	var image := Image.new()
	if image.load_png_from_buffer( Marshalls.base64_to_raw( data ) ) != OK: return
	page.last_capture = data
	page.clip = clip
	if page.texture and page.texture.get_size() == Vector2( image.get_size() ): page.texture.update( image )
	else: page.texture = ImageTexture.create_from_image( image )
	frame_ready.emit( page.id )
	if not was_up_to_date: changed.emit()

func _pump_input(page: Page) -> void:
	page.pumping = true
	var load_id := page.load_count
	while not page.input_queue.is_empty():
		var event : Dictionary = page.input_queue.pop_front()
		var position : Vector2 = event[ "position" ]
		var kind := "mouseMoved"
		if not event[ "moved" ]:
			kind = "mousePressed" if event[ "pressed" ] else "mouseReleased"
			if event[ "pressed" ]:
				# The browser only clicks what's inside its window, and the exhibit is usually further down the
				# page. Scrolls there first. (The picture doesn't change: it's taken by page position.)
				var scrolled := await _cdp.request( "Runtime.evaluate", { "expression": SCROLL_SCRIPT % [ position.x, position.y ], "returnByValue": true }, page.session )
				if load_id != page.load_count: return
				var offset : Variant = scrolled.get( "result", {} ).get( "value" )
				if offset is Array and offset.size() == 2: page.scroll = Vector2( offset[ 0 ], offset[ 1 ] )
		await _cdp.request( "Input.dispatchMouseEvent", {
			"type": kind, "x": position.x - page.scroll.x, "y": position.y - page.scroll.y,
			"button": "none" if event[ "moved" ] else "left", "buttons": event[ "buttons" ], "clickCount": 0 if event[ "moved" ] else 1,
		}, page.session )
		if load_id != page.load_count: return
		page.last_capture_at = 0
		page.wants_picture = true
	page.pumping = false

#endregion

#region What the pages say

func _on_event(session: String, method: String, params: Dictionary) -> void:
	var page : Page = null
	for candidate : Page in _pages.values():
		if candidate.session == session: page = candidate
	if page == null: return

	match method:
		"Runtime.exceptionThrown":
			var details : Dictionary = params.get( "exceptionDetails", {} )
			var text : String = details.get( "exception", {} ).get( "description", details.get( "text", "A script on the page failed." ) )
			var where := ""
			if details.has( "url" ): where = "%s:%d" % [ str( details[ "url" ] ).get_file(), int( details.get( "lineNumber", 0 ) ) + 1 ]
			_add_report( page, "error", text.get_slice( "\n", 0 ), where )
		"Runtime.bindingCalled":
			# The page says it has changed (see INJECTED_SCRIPT).
			if params.get( "name", "" ) == CHANGE_BINDING: page.wants_picture = true
		"Runtime.consoleAPICalled":
			var parts : PackedStringArray = []
			for argument : Dictionary in params.get( "args", [] ):
				var value : Variant = argument.get( "value", argument.get( "description", "" ) )
				# Every number arrives as a decimal. 42 should read as 42, not 42.0.
				if value is float and value == floorf( value ): value = int( value )
				parts.append( str( value ).get_slice( "\n", 0 ) )
			var text := " ".join( parts )
			var type : String = params.get( "type", "" )
			if text.begins_with( LINK_MARKER ): link_clicked.emit( text.trim_prefix( LINK_MARKER ) )
			elif type == "error" or type == "assert": _add_report( page, "error", text, "" )
			elif type == "warning": _add_report( page, "warning", text, "" )
		"Page.javascriptDialogOpening":
			# An alert() would hold the page still until someone pressed OK, and there's nobody to press it.
			_cdp.request( "Page.handleJavaScriptDialog", { "accept": true }, session )
		"Inspector.targetCrashed":
			_add_report( page, "error", "The page crashed in the browser.", "" )

func _add_report(page: Page, kind: String, text: String, where: String) -> void:
	for existing in page.reports:
		if existing[ "text" ] == text and existing[ "where" ] == where: return
	page.reports.append( { "kind": kind, "text": text, "where": where } )
	if page.reports.size() > MAX_REPORTS: page.reports.pop_front()
	changed.emit()

#endregion
