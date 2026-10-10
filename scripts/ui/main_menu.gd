extends Control

const LEVEL := "res://scenes/world/haft_hoz.tscn"

func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiUtil.fill_background(self)
	var col := UiUtil.centered_column(self)
	col.add_child(UiUtil.label(tr("GAME_TITLE"), 120, UiUtil.BLOOD, true))

	var start := UiUtil.button(tr("MENU_START"))
	start.pressed.connect(func() -> void: get_tree().change_scene_to_file(LEVEL))
	col.add_child(start)

	var row := HBoxContainer.new()
	row.add_child(UiUtil.label(tr("MENU_GRAPHICS"), 32))
	var quality := OptionButton.new()
	quality.add_theme_font_size_override("font_size", 30)
	quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in Graphics.NAMES.size():
		quality.add_item(tr(Graphics.NAMES[i]), i)
	quality.select(Settings.graphics_preset)
	quality.item_selected.connect(_on_quality)
	row.add_child(quality)
	col.add_child(row)

	var subs := CheckButton.new()
	subs.text = tr("MENU_SUBS_EN")
	subs.add_theme_font_size_override("font_size", 30)
	subs.button_pressed = Settings.english_subtitles
	subs.toggled.connect(func(on: bool) -> void:
		Settings.english_subtitles = on
		Settings.save_settings())
	col.add_child(subs)

	var quit := UiUtil.button(tr("MENU_QUIT"))
	quit.pressed.connect(get_tree().quit)
	col.add_child(quit)
	start.grab_focus()

func _on_quality(index: int) -> void:
	Settings.graphics_preset = index
	Settings.save_settings()
