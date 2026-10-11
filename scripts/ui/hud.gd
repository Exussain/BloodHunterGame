extends CanvasLayer
## In-game HUD (RTL): health, mutation meter, pounce charge, powers, prompts,
## the rage-form screen filter and the pause menu.

const UNLOCK_KEYS := {&"tendril": "UNLOCK_TENDRIL", &"scream": "UNLOCK_SCREAM", &"rage": "UNLOCK_RAGE"}
## Each power's HUD label and the key shown with it, in unlock order.
const POWERS := [[&"tendril", "POWER_TENDRIL", "Q"], [&"scream", "POWER_SCREAM", "F"], [&"rage", "POWER_RAGE", "R"]]
const RAGE_FILTER := preload("res://assets/shaders/canvas_fx_rage_filter.gdshader")

var _health: ProgressBar
var _mutation: ProgressBar
var _pounce: ProgressBar
var _feed_hint: Label
var _message: Label
var _pause: Control
var _power_labels := {}
var _rage_filter: ColorRect
var _player: Volatile

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL
	add_child(root)

	var stats := VBoxContainer.new()
	stats.position = Vector2(40, 40)
	stats.custom_minimum_size = Vector2(420, 0)
	stats.add_theme_constant_override("separation", 6)
	root.add_child(stats)
	# RTL mirrors anchors, so TOP_LEFT puts the bars top-right where Persian readers look first.
	stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE, 40)
	_health = _bar(stats, tr("HUD_HEALTH"), Color(0.75, 0.05, 0.05))
	_mutation = _bar(stats, tr("HUD_MUTATION"), Color(0.85, 0.55, 0.1))

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 34)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(cross)

	_pounce = ProgressBar.new()
	_pounce.show_percentage = false
	_pounce.max_value = 1.0
	_pounce.custom_minimum_size = Vector2(220, 10)
	_pounce.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pounce.position.y += 40
	_pounce.visible = false
	_tint(_pounce, Color(0.9, 0.1, 0.1))
	root.add_child(_pounce)

	_feed_hint = UiUtil.label(tr("HUD_FEED_HINT"), 34, Color(1, 0.85, 0.7))
	_feed_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_feed_hint.position.y -= 180
	_feed_hint.visible = false
	root.add_child(_feed_hint)

	var controls := UiUtil.label(tr("HUD_CONTROLS"), 18, Color(1, 1, 1, 0.55))
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.position.y -= 40
	root.add_child(controls)

	_message = UiUtil.label("", 56, UiUtil.BLOOD, true)
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.position.y += 160
	_message.visible = false
	root.add_child(_message)

	_build_powers(root)
	_build_pause(root)

func bind(player: Volatile) -> void:
	player.health_changed.connect(func(v: float, m: float) -> void:
		_health.max_value = m
		_health.value = v)
	player.mutation_changed.connect(func(v: float, m: float) -> void:
		_mutation.max_value = m
		_mutation.value = v)
	player.pounce_charge_changed.connect(func(v: float) -> void:
		_pounce.visible = v > 0.0
		_pounce.value = v)
	player.feed_target_changed.connect(func(on: bool) -> void: _feed_hint.visible = on)
	player.power_unlocked.connect(func(power: StringName) -> void:
		show_message(tr(UNLOCK_KEYS[power]), 3.0)
		_refresh_powers())
	player.power_cooldown_changed.connect(func(power: StringName, left: float, _total: float) -> void:
		_set_power_state(power, left))
	player.mutation_changed.connect(func(_v: float, _m: float) -> void: _refresh_powers())
	player.rage_changed.connect(_on_rage_changed)
	_player = player
	_refresh_powers()

func show_message(text: String, seconds := 0.0) -> void:
	_message.text = text
	_message.visible = true
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
		if _message.text == text:
			_message.visible = false

func _bar(parent: Control, title: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := UiUtil.label(title, 26)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 22)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tint(bar, color)
	row.add_child(bar)
	return bar

func _tint(bar: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bar.add_theme_stylebox_override("background", bg)

# --- Powers -----------------------------------------------------------------

func _build_powers(root: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.position.y -= 150
	root.add_child(row)
	for entry in POWERS:
		var l := UiUtil.label("[%s] %s" % [entry[2], tr(entry[1])], 30, Color(1, 0.85, 0.7))
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.visible = false
		row.add_child(l)
		_power_labels[entry[0]] = l
	# Rage form: a pulsing red, warped filter over the whole screen.
	_rage_filter = ColorRect.new()
	_rage_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rage_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = RAGE_FILTER
	_rage_filter.material = m
	_rage_filter.visible = false
	root.add_child(_rage_filter)
	root.move_child(_rage_filter, 0)

func _refresh_powers() -> void:
	if _player == null:
		return
	for entry in POWERS:
		var power: StringName = entry[0]
		var l: Label = _power_labels[power]
		l.visible = _player.unlocked.has(power)
		var ready := _player.power_ready(power) or (power == &"rage" and _player.is_raging())
		l.modulate = Color.WHITE if ready else Color(1, 1, 1, 0.35)

func _set_power_state(power: StringName, left: float) -> void:
	var l: Label = _power_labels[power]
	var entry: Array = POWERS.filter(func(e: Array) -> bool: return e[0] == power)[0]
	var text := "[%s] %s" % [entry[2], tr(entry[1])]
	if left > 0.0:
		# Persian digits for the seconds left.
		text += " " + _fa_digits(str(ceili(left)))
	l.text = text
	l.modulate = Color.WHITE if left <= 0.0 else Color(1, 1, 1, 0.35)

func _on_rage_changed(active: bool) -> void:
	_rage_filter.visible = true
	var m := _rage_filter.material as ShaderMaterial
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter(&"strength", v),
		0.0 if active else 1.0, 1.0 if active else 0.0, 0.4)
	if not active:
		tw.tween_callback(func() -> void: _rage_filter.visible = false)
	_refresh_powers()

static func _fa_digits(text: String) -> String:
	var out := ""
	for ch in text:
		out += char(0x06F0 + int(ch)) if ch >= "0" and ch <= "9" else ch
	return out

# --- Pause ------------------------------------------------------------------

func _build_pause(root: Control) -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	root.add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)
	var col := UiUtil.centered_column(_pause)
	col.custom_minimum_size = Vector2(500, 0)
	col.add_child(UiUtil.label(tr("PAUSE_TITLE"), 72, UiUtil.BLOOD, true))
	var resume := UiUtil.button(tr("PAUSE_RESUME"))
	resume.pressed.connect(_toggle_pause)
	col.add_child(resume)
	var menu := UiUtil.button(tr("PAUSE_MENU"))
	menu.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	col.add_child(menu)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
