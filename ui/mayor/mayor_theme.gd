class_name MayorTheme
extends RefCounted
## The Mayor view's look: the field journal's parchment and ink (ui/hud/resident_catalogue.gd) -
## a serif face, cream paper panels edged in the journal's olive-brown, a deep green title band,
## journal buttons (paper, hover cream, pressed sea-glass) - plus the small widgets every page
## builds with.

const INK := Color("303831")
const MUTED := Color("726f5a")
const PAPER := Color("efe3c6")
const PAPER_DEEP := Color("e5d6b7")
const EDGE := Color("b6a78a")
const BAND := Color("203d39")
const BAND_TEXT := Color("f1e5ca")
const GOOD := Color("5d8a4a")
const BAD := Color("a8452f")
const ACCENT := Color("496f84")
## The smallest font the Mayor view draws, at the 1600x900 base: with the UI never scaled below
## Game.UI_MIN_SCALE (0.85) that is at least 13.6 px on screen, 1280x720 included.
const MIN_FONT := 16

static var _theme: Theme
static var _font: SystemFont


static func theme() -> Theme:
	if _theme != null: return _theme
	_font = SystemFont.new(); _font.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
	_theme = Theme.new(); _theme.default_font = _font; _theme.default_font_size = MIN_FONT
	for type in ["Button", "OptionButton", "CheckButton", "Label", "SpinBox", "LineEdit", "MenuButton"]:
		_theme.set_color("font_color", type, INK)
		_theme.set_color("font_hover_color", type, INK)
		_theme.set_color("font_focus_color", type, INK)
		_theme.set_color("font_pressed_color", type, INK)
		_theme.set_color("font_disabled_color", type, MUTED.lightened(0.15))
	for type in ["Button", "OptionButton", "MenuButton"]:
		_theme.set_stylebox("normal", type, box(PAPER_DEEP, EDGE))
		_theme.set_stylebox("hover", type, box(Color("f6ebd2"), Color("73909a")))
		_theme.set_stylebox("pressed", type, box(Color("bfd1d1"), Color("73909a")))
		_theme.set_stylebox("disabled", type, box(Color("e3d8bf"), Color("cbbfa4")))
		_theme.set_stylebox("focus", type, box(Color(0, 0, 0, 0), ACCENT, 2))
	_theme.set_stylebox("normal", "LineEdit", box(Color("f7eedb"), EDGE))
	_theme.set_color("font_color", "PopupMenu", INK)
	_theme.set_color("font_hover_color", "PopupMenu", INK)
	_theme.set_color("font_disabled_color", "PopupMenu", MUTED)
	_theme.set_stylebox("panel", "PopupMenu", box(Color("f4ead4"), EDGE))
	_theme.set_stylebox("hover", "PopupMenu", box(Color("d8e2df"), Color("73909a")))
	_theme.set_stylebox("background", "ProgressBar", box(Color("d8cbac"), EDGE))
	_theme.set_stylebox("fill", "ProgressBar", box(GOOD, GOOD.darkened(0.2)))
	_theme.set_color("font_color", "ProgressBar", INK)
	_theme.set_stylebox("panel", "TooltipPanel", box(Color("f7eedb"), EDGE))
	_theme.set_color("font_color", "TooltipLabel", INK)
	return _theme


static func box(fill: Color, border: Color, width := 1, radius := 5, margin := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill; s.border_color = border; s.set_border_width_all(width)
	s.set_corner_radius_all(radius); s.set_content_margin_all(margin)
	return s


## The paper panel: cream with the journal's olive edge and a soft shadow.
static func paper() -> StyleBoxFlat:
	var s := box(Color(PAPER.r, PAPER.g, PAPER.b, 0.96), Color("8f8265"), 2, 8, 12)
	s.shadow_color = Color(0, 0, 0, 0.28); s.shadow_size = 6
	return s


static func band() -> StyleBoxFlat:
	var s := box(Color(BAND.r, BAND.g, BAND.b, 0.95), Color("61756a"), 1, 8, 10)
	s.shadow_color = Color(0, 0, 0, 0.3); s.shadow_size = 6
	return s


static func label(parent: Node, text: String, size := 15, color := INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", maxi(size, MIN_FONT))
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


static func heading(parent: Node, text: String) -> Label:
	var l := label(parent, text.to_upper(), 14, Color("5a4a33"))
	l.add_theme_constant_override("line_spacing", 0)
	return l


## A journal button. `clip`: trim long text with an ellipsis (full-width list rows); otherwise
## the button is as wide as its text (rows of buttons, the top bar).
static func button(parent: Node, text: String, action: Callable, size := 14, clip := false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 32
	node.add_theme_font_size_override("font_size", maxi(size, MIN_FONT))
	node.pressed.connect(action)
	node.focus_mode = Control.FOCUS_NONE
	if clip:
		node.clip_text = true
		node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(node)
	return node


static func bar(parent: Node, caption: String, value: float, color := GOOD) -> ProgressBar:
	var row := HBoxContainer.new(); parent.add_child(row)
	var l := label(row, caption, 13, MUTED); l.custom_minimum_size.x = 92; l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var pb := ProgressBar.new()
	pb.min_value = 0; pb.max_value = 100; pb.value = value * 100.0
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.custom_minimum_size.y = 16
	pb.show_percentage = true
	pb.custom_minimum_size.y = 20
	pb.add_theme_font_size_override("font_size", MIN_FONT - 2)
	pb.add_theme_stylebox_override("fill", box(color, color.darkened(0.2), 1, 4, 0))
	row.add_child(pb)
	return pb


static func rule(parent: Node) -> void:
	var r := ColorRect.new(); r.color = Color(EDGE.r, EDGE.g, EDGE.b, 0.7); r.custom_minimum_size.y = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


static func row(parent: Node, sep := 6) -> HBoxContainer:
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation", sep); parent.add_child(r)
	return r
