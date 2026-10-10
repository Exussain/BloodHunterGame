extends CanvasLayer
## In-game HUD (RTL): health, mutation meter, pounce charge, prompts, pause menu.

const UNLOCK_KEYS := {&"tendril": "UNLOCK_TENDRIL", &"scream": "UNLOCK_SCREAM", &"rage": "UNLOCK_RAGE"}

var _health: ProgressBar
var _mutation: ProgressBar
var _pounce: ProgressBar
var _feed_hint: Label
var _message: Label
var _pause: Control

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
	player.power_unlocked.connect(func(power: StringName) -> void: show_message(tr(UNLOCK_KEYS[power]), 3.0))

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
