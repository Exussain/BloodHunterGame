class_name PowerFx
## Visual effects for the volatile's powers: the tendril and the scream shockwave.
## Placeholder geometry with emissive materials until real VFX are made.

## A sinewy tendril from the volatile's chest to a grabbed soldier: a tapering tube
## that arcs, coils and writhes along its length. Rebuilt every frame in world space;
## it removes itself once the soldier lands.
class Tendril extends MeshInstance3D:
	const SEGMENTS := 40
	const SIDES := 10
	var source: Node3D
	var target: Militia
	var _im := ImmediateMesh.new()
	var _age := 0.0
	var _seed := randf() * TAU

	func _ready() -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY
		mesh = _im
		var m := StandardMaterial3D.new()
		# Wet, dark flesh with a faint inner glow, so it reads at night without looking like a laser.
		m.albedo_color = Color(0.3, 0.03, 0.04)
		m.roughness = 0.18
		m.metallic_specular = 0.9
		m.rim_enabled = true
		m.rim = 0.5
		m.emission_enabled = true
		m.emission = Color(0.65, 0.04, 0.03)
		m.emission_energy_multiplier = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = m
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _process(delta: float) -> void:
		if not is_instance_valid(source) or not is_instance_valid(target) or not target.is_grabbed():
			queue_free()
			return
		_age += delta
		var a := source.global_position + Vector3.UP * 1.35
		var b := target.grab_point()
		if a.distance_to(b) < 0.05:
			return
		_build(a, b)

	## Point along the tendril at t (0 = chest, 1 = soldier).
	func _point(a: Vector3, b: Vector3, t: float) -> Vector3:
		var length := a.distance_to(b)
		var axis := (b - a) / length
		var n1 := axis.cross(Vector3.UP)
		n1 = n1.normalized() if n1.length() > 0.01 else Vector3.RIGHT
		var n2 := n1.cross(axis)
		# Arc up like a thrown whip, then coil around that arc; the coil travels
		# toward the soldier and settles as the pull tightens.
		var sag := sin(t * PI) * length * 0.08
		var coil_amp := sin(t * PI) * minf(length * 0.015, 0.16) * (1.0 + 0.6 / (1.0 + _age * 6.0))
		var phase := t * 2.0 * TAU - _age * 12.0 + _seed
		return a.lerp(b, t) + n2 * sag + (n1 * cos(phase) + n2 * sin(phase)) * coil_amp

	func _build(a: Vector3, b: Vector3) -> void:
		var rings: Array[PackedVector3Array] = []
		var normals: Array[PackedVector3Array] = []
		for i in SEGMENTS + 1:
			var t := float(i) / SEGMENTS
			var p := _point(a, b, t)
			var tangent := (_point(a, b, minf(t + 0.01, 1.0)) - _point(a, b, maxf(t - 0.01, 0.0))).normalized()
			var u := tangent.cross(Vector3.UP)
			u = u.normalized() if u.length() > 0.01 else Vector3.RIGHT
			var v := u.cross(tangent)
			# Thick at the chest, thin at the hook, with a pulse of muscle running down it.
			var radius := lerpf(0.12, 0.04, t) * (1.0 + 0.25 * sin(t * 18.0 - _age * 20.0))
			var ring := PackedVector3Array()
			var ring_n := PackedVector3Array()
			for j in SIDES:
				var ang := TAU * j / SIDES
				var n := u * cos(ang) + v * sin(ang)
				ring.append(p + n * radius)
				ring_n.append(n)
			rings.append(ring)
			normals.append(ring_n)
		_im.clear_surfaces()
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in SEGMENTS:
			for j in SIDES:
				var k := (j + 1) % SIDES
				for idx: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, k), Vector2i(i, j), Vector2i(i + 1, k), Vector2i(i, k)]:
					_im.surface_set_normal(normals[idx.x][idx.y])
					_im.surface_add_vertex(rings[idx.x][idx.y])
		_im.surface_end()

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
	flash.light_energy = 3.0
	flash.omni_range = reach * 0.6
	flash.light_specular = 0.0
	parent.add_child(flash)
	flash.global_position = origin + flat * 4.0 + Vector3.UP * 1.0
	var tw := ring.create_tween().set_parallel()
	tw.tween_property(ring, "global_position", origin + flat * reach * 0.8, 0.55).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3.ONE * reach * 0.35, 0.55).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.55)
	tw.tween_property(flash, "light_energy", 0.0, 0.6)
	tw.chain().tween_callback(func() -> void:
		ring.queue_free()
		flash.queue_free())
