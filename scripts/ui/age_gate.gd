extends Control
## 18+ warning shown on first launch, before anything else.

const NEXT := "res://scenes/ui/main_menu.tscn"

func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	if Settings.age_confirmed:
		get_tree().change_scene_to_file.call_deferred(NEXT)
		return
	UiUtil.fill_background(self)
	var col := UiUtil.centered_column(self, 32)
	col.add_child(UiUtil.label(tr("AGE_TITLE"), 96, UiUtil.BLOOD, true))
	col.add_child(UiUtil.label(tr("AGE_BODY"), 40))
	col.add_child(UiUtil.label(TranslationServer.get_translation_object("en").get_message("AGE_BODY"), 24, Color(0.7, 0.7, 0.7)))
	var confirm := UiUtil.button(tr("AGE_CONFIRM"))
	confirm.pressed.connect(_on_confirm)
	col.add_child(confirm)
	var exit := UiUtil.button(tr("AGE_EXIT"))
	exit.pressed.connect(get_tree().quit)
	col.add_child(exit)
	exit.grab_focus()

func _on_confirm() -> void:
	Settings.age_confirmed = true
	Settings.save_settings()
	get_tree().change_scene_to_file(NEXT)
