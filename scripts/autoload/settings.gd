extends Node
## Persistent player settings (age gate, graphics preset, language).

signal changed

const PATH := "user://settings.cfg"

var age_confirmed: bool = false
var graphics_preset: int = 0
var english_subtitles: bool = false

func _ready() -> void:
	load_settings()
	TranslationServer.set_locale("fa")

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	age_confirmed = cfg.get_value("general", "age_confirmed", false)
	graphics_preset = cfg.get_value("graphics", "preset", 0)
	english_subtitles = cfg.get_value("general", "english_subtitles", false)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "age_confirmed", age_confirmed)
	cfg.set_value("graphics", "preset", graphics_preset)
	cfg.set_value("general", "english_subtitles", english_subtitles)
	cfg.save(PATH)
	changed.emit()
