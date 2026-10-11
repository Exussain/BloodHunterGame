extends Node
## Registers input actions in code so bindings stay readable in version control.

func _ready() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("feed", KEY_E)
	_key("pause", KEY_ESCAPE)
	_key("tendril", KEY_Q)
	_key("scream", KEY_F)
	_key("rage", KEY_R)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_mouse("pounce", MOUSE_BUTTON_RIGHT)
	_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_joy_button("jump", JOY_BUTTON_A)
	_joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	_joy_button("feed", JOY_BUTTON_X)
	_joy_button("pause", JOY_BUTTON_START)
	_joy_button("tendril", JOY_BUTTON_Y)
	_joy_button("scream", JOY_BUTTON_B)
	_joy_button("rage", JOY_BUTTON_RIGHT_SHOULDER)
	_joy_axis("attack", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_joy_axis("pounce", JOY_AXIS_TRIGGER_LEFT, 1.0)

func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)

func _key(action: StringName, key: Key) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

func _mouse(action: StringName, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _joy_button(action: StringName, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
