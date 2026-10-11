class_name PowerFx
## Visual effects for the volatile's powers: the tendril and the scream shockwave.
## Placeholder geometry with emissive materials until real VFX are made.

## A sinewy tendril stretched from the volatile's chest to a grabbed soldier.
## It follows both every frame and removes itself once the soldier lands.
class Tendril extends MeshInstance3D:
	var source: Node3D
	var target: Militia

	func _ready() -> void:
		top_level = true
		var tube := CylinderMesh.new()
		tube.top_radius = 0.05
		tube.bottom_radius = 0.11
		tube.height = 1.0
		tube.radial_segments = 8
		tube.rings = 1
		mesh = tube
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.01, 0.02)
		m.roughness = 0.25
		m.metallic_specular = 0.8
		m.emission_enabled = true
		m.emission = Color(0.9, 0.08, 0.05)
		m.emission_energy_multiplier = 1.4
		material_override = m
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _process(_delta: float) -> void:
		if not is_instance_valid(source) or not is_instance_valid(target) or not target.is_grabbed():
			queue_free()
			return
		var a := source.global_position + Vector3.UP * 1.35
		var b := target.grab_point()
		var length := a.distance_to(b)
		if length < 0.05:
			return
		var dir := (b - a) / length
		# Cylinders run along Y: build a basis whose Y is the tendril direction.
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		# The Y column carries the length, stretching the unit cylinder end to end.
		global_transform = Transform3D(Basis(side, dir * length, side.cross(dir)), (a + b) * 0.5)

static func tendril(parent: Node, source: Node3D, target: Militia) -> void:
	var t := Tendril.new()
	t.source = source
	t.target = target
	parent.add_child(t)

## An expanding, fading ring of distorted air in front of the volatile, plus a red flash.
static func scream_wave(parent: Node, origin: Vector3, forward: Vector3, reach: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.25, 0.15, 0.7)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.2, 0.1)
	m.emission_energy_multiplier = 3.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	# The torus lies flat in XZ; stand it up so it faces along `flat`.
	ring.global_transform = Transform3D(Basis.looking_at(flat) * Basis(Vector3.RIGHT, PI / 2), origin + flat * 1.0)
	ring.scale = Vector3.ONE * 0.4
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.2, 0.1)
	flash.light_energy = 6.0
	flash.omni_range = reach * 0.6
	parent.add_child(flash)
	flash.global_position = origin + flat * 2.0
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "global_position", origin + flat * reach * 0.8, 0.55).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3.ONE * reach * 0.35, 0.55).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.55)
	tw.tween_property(flash, "light_energy", 0.0, 0.6)
	tw.chain().tween_callback(func() -> void:
		ring.queue_free()
		flash.queue_free())
