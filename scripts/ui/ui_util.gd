class_name UiUtil
## Shared helpers for building the Persian (RTL) menus in code.

const BG := Color(0.04, 0.01, 0.01)
const BLOOD := Color(0.62, 0.03, 0.03)

static func fill_background(root: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

static func centered_column(root: Control, separation: int = 24) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", separation)
	col.custom_minimum_size = Vector2(900, 0)
	center.add_child(col)
	return col

static func label(text: String, size: int, color: Color = Color.WHITE, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", load("res://assets/fonts/Vazirmatn-Black.ttf"))
	return l

static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.add_theme_font_size_override("font_size", 32)
	return b
