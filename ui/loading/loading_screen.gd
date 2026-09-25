class_name LoadingScreen
extends CanvasLayer
## The loading screen: key art, the title, a progress bar driven by the real boot stages, the
## stage being built, a rotating gameplay tip. It is up from the very first frame of the boot
## (Game._boot draws a frame between stages) and for long moves (coach & ferry tickets, F6, a far
## respawn or save load: Game.relocate / Game.cover_move), and stays up until the world round the
## courier is built and the frames have stopped hitching, then fades out.
##
## Interface:
##   set_stage(id, text, progress)   a boot stage is about to run (progress 0..1 never goes back)
##   cover(text)                     show at once for a long move (progress restarts at 0)
##   wait_until_ready(built, remaining)   fade out once built() holds and the frames are smooth;
##                                   remaining() -> int (pieces still to build) moves the bar meanwhile
##   dismiss()                       hide now, no fade (tests and tools)
##   showing() -> bool, waiting() -> bool, stage_log (every stage with its progress and time)
## Signals: finished (faded out or dismissed).
## It is a modal panel of the PanelStack while it covers the game after the boot (controls
## blocked, HUD stepped back); during the boot the whole tree is paused anyway.

signal finished

const KEY_ART := "res://assets/ui/loading_key_art.jpg"
const INK := Color("2b2620")
const CREAM := Color("f6ecd4")
const PAPER := Color("efe3c6")
const EDGE := Color("8f8265")
const FILL := Color("b8412c")          # the courier bike's red
const MIN_FONT := 16
## A frame counts as smooth under 1/24 s, or on a slow machine within 1.6x the recent median.
const SMOOTH_DT := 1.0 / 24.0
const SMOOTH_FRAMES := 12
## After the world reports built, wait at most this long for smooth frames.
const SETTLE_MAX := 8.0
## Give up waiting altogether after this long (a streamer that never idles must not trap the player).
const WAIT_MAX := 25.0
const FADE := 0.55

const TIPS: Array[String] = [
	"The bike runs about 30 km on a tank and the Jeep 40 km. A load, a towed cart or a flight burns more; B at a station fills up.",
	"Every town has a station at its edge, and highway service stops are never more than about 5 km apart.",
	"A fuel can in your pack (G) pours a quarter tank into whatever you are driving.",
	"The Garand: hold the right mouse button to shoulder it, F or the left button to fire, V to reload. The empty clip pings out.",
	"Ammunition crates at camps and the Dunes Lookout cache refill your pouch.",
	"H hitches the cart: stop, back up until the drawbar eye meets the hitch. The Jeep hauls it best.",
	"The Jeep floats: drive into deep water and the pontoons swing down. A hitched cart sinks, though.",
	"T unfolds the bike's wings. Past take-off speed, S lifts you off; Shift boosts.",
	"Coach and ferry tickets take you and your bike to any town you have visited, for coins and game time.",
	"Charter a town in the Mayor view (F4) to found a colony: a hall, settlers, and taxes into your wallet.",
	"Shipping lanes carry goods between port colonies. Clear the pirate coves near a route to cut the raid risk.",
	"Carters haul goods by road between colonies, so inland Valdoro and Campo Real can trade too.",
	"M opens the map: click to set a waypoint, it shows on the minimap and the compass. Z cycles the minimap zoom.",
	"F10 picks the graphics quality: Low, Medium, High or Ultra, with the frame rate shown while you choose.",
	"R recovers the bike onto the nearest road. N opens your island journal.",
	"Bandits hold camps inland and roadblocks on the highways; a camp is cleared when nobody is left standing.",
]

var enabled := true                 ## false: tools and tests that never want it (see Game._interactive)
var stage_log: Array = []           ## [{id, text, progress, msec}]
var progress := 0.0
var _shown := 0.0                   # the bar as drawn (eases toward progress)
var _root: Control
var _art: TextureRect
var _title: Label
var _subtitle: Label
var _stage: Label
var _percent: Label
var _bar: Control
var _tip: Label
var _tip_i := 0
var _tip_t := 0.0
var _fade := 0.0
var _waiting := false
var _built: Callable
var _remaining: Callable
var _remaining_max := 1
var _wait_t := 0.0
var _built_t := -1.0
var _smooth := 0
var _deltas: Array[float] = []
var _base := 0.0                    # the bar's value when the wait began
var _panels: PanelStack
var _font: SystemFont
var _t0 := 0


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	_font = SystemFont.new(); _font.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # nothing under it takes a click
	add_child(_root)
	var sand := ColorRect.new(); sand.color = Color("c9b48c")
	sand.set_anchors_preset(Control.PRESET_FULL_RECT); sand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(sand)
	_art = TextureRect.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(KEY_ART): _art.texture = load(KEY_ART)
	_root.add_child(_art)
	# a warm vignette and a dark foot so the card and the tip read on any picture
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.10, 0.07, 0.04, 0.0)); g.set_color(1, Color(0.10, 0.07, 0.04, 0.62))
	g.add_point(0.62, Color(0.10, 0.07, 0.04, 0.0))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.width = 4; gt.height = 256
	gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	_root.add_child(shade)
	var top := TextureRect.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE); top.offset_bottom = 330
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; top.stretch_mode = TextureRect.STRETCH_SCALE
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.10, 0.07, 0.04, 0.42)); g2.set_color(1, Color(0.10, 0.07, 0.04, 0.0))
	var gt2 := GradientTexture2D.new(); gt2.gradient = g2; gt2.width = 4; gt2.height = 128
	gt2.fill_from = Vector2(0, 0); gt2.fill_to = Vector2(0, 1)
	top.texture = gt2
	_root.add_child(top)

	_title = _label("Desert Delivery", 92, CREAM)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 62; _title.offset_bottom = 180
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", INK)
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_title.add_theme_constant_override("shadow_offset_x", 0); _title.add_theme_constant_override("shadow_offset_y", 6)
	_root.add_child(_title)
	_subtitle = _label("The long way home.", 28, Color("f1dfb6"))
	_subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_subtitle.offset_top = 176; _subtitle.offset_bottom = 220
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_outline_color", INK)
	_subtitle.add_theme_constant_override("outline_size", 7)
	_root.add_child(_subtitle)

	# the parchment card: stage, percent, the bar
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PAPER.r, PAPER.g, PAPER.b, 0.95)
	sb.border_color = EDGE; sb.set_border_width_all(2); sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 10
	card.add_theme_stylebox_override("panel", sb)
	# bottom left: the key art's courier rides in the lower right third
	card.anchor_left = 0.0; card.anchor_right = 0.0; card.anchor_top = 1.0; card.anchor_bottom = 1.0
	card.offset_left = 56; card.offset_right = 56 + 760; card.offset_top = -214; card.offset_bottom = -110
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(card)
	_stage = _label("", 21, INK)
	_stage.position = Vector2(26, 14); _stage.size = Vector2(560, 32)
	_stage.clip_text = true
	card.add_child(_stage)
	_percent = _label("", 21, Color("6b5a3e"))
	_percent.position = Vector2(620, 14); _percent.size = Vector2(114, 32)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(_percent)
	_bar = Control.new()
	_bar.position = Vector2(26, 58); _bar.size = Vector2(708, 26)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	card.add_child(_bar)

	_tip = _label("", 19, Color("f4e6c8"))
	_tip.anchor_left = 0.0; _tip.anchor_right = 0.0; _tip.anchor_top = 1.0; _tip.anchor_bottom = 1.0
	_tip.offset_left = 60; _tip.offset_right = 60 + 760; _tip.offset_top = -98; _tip.offset_bottom = -24
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_outline_color", INK)
	_tip.add_theme_constant_override("outline_size", 6)
	_root.add_child(_tip)
	_tip_i = randi() % TIPS.size()
	_show_tip()


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", maxi(size, MIN_FONT))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("d9c8a2"); track.border_color = Color("7d6d52"); track.set_border_width_all(2)
	track.set_corner_radius_all(int(r.size.y * 0.5))
	_bar.draw_style_box(track, r)
	var w := clampf(_shown, 0.0, 1.0) * (r.size.x - 6.0)
	if w > r.size.y - 6.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = FILL; fill.set_corner_radius_all(int((r.size.y - 6.0) * 0.5))
		_bar.draw_style_box(fill, Rect2(3, 3, w, r.size.y - 6.0))
		var hi := StyleBoxFlat.new()
		hi.bg_color = Color(1, 0.86, 0.7, 0.28); hi.set_corner_radius_all(4)
		_bar.draw_style_box(hi, Rect2(3 + 8, 5, maxf(w - 16, 0.0), 5))
	# the road's centre line runs through the unfilled part
	var x := 3.0 + w + 10.0
	while x < r.size.x - 14.0:
		_bar.draw_line(Vector2(x, r.size.y * 0.5), Vector2(x + 10.0, r.size.y * 0.5), Color("a8977a"), 2.0)
		x += 22.0
	# a wheel rolls at the head of the bar
	var c := Vector2(3.0 + maxf(w, r.size.y * 0.5 - 3.0), r.size.y * 0.5)
	_bar.draw_circle(c, r.size.y * 0.5 + 1.0, INK)
	_bar.draw_circle(c, r.size.y * 0.5 - 2.5, Color("e9dcc0"))
	var spin := Time.get_ticks_msec() * 0.006
	for k in range(3):
		var a := spin + k * TAU / 3.0
		_bar.draw_line(c, c + Vector2(cos(a), sin(a)) * (r.size.y * 0.5 - 3.0), INK, 2.0)


func _show_tip() -> void:
	_tip.text = "Tip  ·  " + TIPS[_tip_i % TIPS.size()]


## A boot stage is about to run: its text, and the share of the boot already done.
func set_stage(id: StringName, text: String, p: float) -> void:
	progress = maxf(progress, clampf(p, 0.0, 1.0))
	_stage.text = text + "…"
	_percent.text = "%d %%" % roundi(progress * 100.0)
	stage_log.append({"id": id, "text": text, "progress": progress, "msec": Time.get_ticks_msec() - _t0})


## Show at once, for a long move (the bar restarts).
func cover(text: String, panels: PanelStack = null) -> void:
	if not enabled: return
	progress = 0.0; _shown = 0.0
	_stage.text = text + "…"
	_percent.text = ""
	_title.add_theme_font_size_override("font_size", 64)
	_fade = 0.0
	_root.modulate.a = 1.0
	visible = true
	_hold(panels)


## Fade out once `built` holds and the frames have been smooth for a moment. `remaining` counts
## what is still to build and moves the bar from where it is to the end meanwhile.
func wait_until_ready(built: Callable, remaining: Callable = Callable(), panels: PanelStack = null) -> void:
	if not visible: return
	_built = built; _remaining = remaining
	_remaining_max = maxi(1, int(remaining.call()) if remaining.is_valid() else 1)
	_waiting = true; _wait_t = 0.0; _built_t = -1.0; _smooth = 0; _deltas.clear()
	_base = progress
	_hold(panels)


## Hide now, no fade.
func dismiss() -> void:
	_waiting = false
	_fade = 0.0
	visible = false
	_release()
	finished.emit()


func showing() -> bool:
	return visible


func waiting() -> bool:
	return _waiting


## The PanelStack protocol: the player cannot close the loading screen.
func close_panel() -> void:
	pass


func _hold(panels: PanelStack) -> void:
	if panels == null or _panels != null: return
	_panels = panels
	_panels.open(self)


func _release() -> void:
	if _panels == null: return
	_panels.close(self)
	_panels = null


func _smooth_frame(delta: float) -> bool:
	_deltas.append(delta)
	if _deltas.size() > 24: _deltas.pop_front()
	var sorted := _deltas.duplicate(); sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	return delta <= maxf(SMOOTH_DT, median * 1.6)


func _process(delta: float) -> void:
	if not visible: return
	_tip_t += delta
	if _tip_t > 7.0:
		_tip_t = 0.0; _tip_i += 1; _show_tip()
	if _waiting:
		_wait_t += delta
		var built: bool = _built.call() if _built.is_valid() else true
		if built:
			if _built_t < 0.0: _built_t = _wait_t
			_smooth = _smooth + 1 if _smooth_frame(delta) else 0
		else:
			_smooth = 0
			_smooth_frame(delta)
		var left := int(_remaining.call()) if _remaining.is_valid() else 0
		_remaining_max = maxi(_remaining_max, left)
		var f := 1.0 - float(left) / float(_remaining_max)
		# built: the last stretch of the bar is the frames settling (shaders, textures, townsfolk)
		var settle := clampf(float(_smooth) / SMOOTH_FRAMES, 0.0, 1.0) if built else 0.0
		progress = maxf(progress, _base + (1.0 - _base) * (0.85 * f + 0.15 * settle))
		_percent.text = "%d %%" % roundi(progress * 100.0)
		var done := built and _smooth >= SMOOTH_FRAMES and _wait_t > 0.25
		if (built and _wait_t - _built_t > SETTLE_MAX) or _wait_t > WAIT_MAX: done = true
		if done:
			_waiting = false
			progress = 1.0
			_percent.text = "100 %"
			_fade = FADE
			# the HUD comes back under the fading picture and the controls are live again
			_release()
	_shown = move_toward(_shown, progress, delta * 1.6) if _shown < progress else progress
	_bar.queue_redraw()
	if _fade > 0.0:
		_fade -= delta
		_root.modulate.a = clampf(_fade / FADE, 0.0, 1.0)
		if _fade <= 0.0:
			visible = false
			_root.modulate.a = 1.0
			finished.emit()
