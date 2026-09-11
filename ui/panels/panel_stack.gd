class_name PanelStack
extends RefCounted
## The one modal protocol on the island. The courier Counter (JourneySystem) and the field
## Journal (ResidentCatalogue) — and any panel after them — open and close through here.
##
## Opening frees the mouse, blocks the player's controls and pauses delivery handoffs. Closing
## restores all three, but only after a one-frame latch and only once the mouse button that
## closed the panel is up, so the closing click can never fall through into the game.
##
## Both panels used to keep their own copy of that five-part protocol, and the copies had
## diverged: the Journal never paused handoffs, so reading it while parked in a pickup Ring
## collected the parcel behind the book. Game and the HUD had to enumerate both panels by name
## to ask "is anything modal?"; now they ask one question.
##
## Interface:
##   open(panel) / close(panel) / close_all()
##   any_open() -> bool      is anything modal on screen right now
##   is_open(panel) -> bool
##   just_closed() -> bool   something closed this frame or last — swallow gameplay input
##   process()               call once a frame from Game._process

var _game
var _open: Array = []
var _closed_frame := -1
var _release_controls := false
var _old_mouse := Input.MOUSE_MODE_VISIBLE


func _init(game) -> void:
	_game = game


func any_open() -> bool:
	return not _open.is_empty()


func is_open(panel) -> bool:
	return _open.has(panel)


func just_closed() -> bool:
	return _closed_frame >= 0 and Engine.get_process_frames() <= _closed_frame + 1


func open(panel) -> void:
	if _open.has(panel): return
	if _open.is_empty():
		_old_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_release_controls = false
	_open.append(panel)
	_sync()


func close(panel) -> void:
	if not _open.has(panel): return
	_open.erase(panel)
	if _open.is_empty():
		Input.mouse_mode = _old_mouse
		_closed_frame = Engine.get_process_frames()
		_release_controls = true
	_sync()


func close_all() -> void:
	for p in _open.duplicate():
		if p.has_method("close_panel"): p.close_panel()
		else: close(p)


## A frame after the last panel closed, and once the closing click is released, gameplay resumes.
func process() -> void:
	if not _release_controls or any_open(): return
	if Engine.get_process_frames() <= _closed_frame + 1: return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	_release_controls = false
	_sync()


func _sync() -> void:
	var blocked := any_open() or _release_controls
	if _game.player_controls: _game.player_controls.blocked = blocked
	if _game.gm: _game.gm.handoffs_paused = any_open()
