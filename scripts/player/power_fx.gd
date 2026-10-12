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
	## Seconds the tip takes to shoot out from the chest to the soldier.
	const LASH_TIME := 0.1
	var _im := ImmediateMesh.new()
	var _age := 0.0
	var _seed := randf() * TAU
	var _glow: OmniLight3D

	func _ready() -> void:
		top_level = true
		# Rebuilt every rendered frame from interpolated positions, so not interpolated itself.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		global_transform = Transform3D.IDENTITY
		mesh = _im
		# A faint red glow riding the tendril, so it reads (and lights the street) at night.
		_glow = OmniLight3D.new()
		_glow.light_color = Color(1.0, 0.15, 0.08)
		_glow.light_energy = 0.0
		_glow.omni_range = 4.0
		_glow.light_specular = 0.0
		_glow.shadow_enabled = false
		add_child(_glow)
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
		# Interpolated positions, so the ends stay glued to the bodies between physics ticks.
		var a := _drawn(source) + Vector3.UP * 1.35 * source.scale.y
		var b := _drawn(target) + (target.grab_point() - target.global_position)
		# The tip lashes out to the soldier first, then the tendril hauls it in.
		var lash := ease(clampf(_age / LASH_TIME, 0.0, 1.0), 0.4)
		b = a.lerp(b, lash)
		if a.distance_to(b) < 0.05:
			return
		_build(a, b)
		_glow.global_position = a.lerp(b, 0.5)
		_glow.light_energy = 0.9 * lash

	static func _drawn(node: Node3D) -> Vector3:
		if node.is_physics_interpolated_and_enabled():
			return node.get_global_transform_interpolated().origin
		return node.global_position

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
			# Thick at the chest, thin toward the end, with a pulse of muscle running down it
			# and a swollen, gripping knot at the tip.
			var radius := lerpf(0.12, 0.04, t) * (1.0 + 0.25 * sin(t * 18.0 - _age * 20.0))
			radius += 0.07 * smoothstep(0.86, 0.97, t) * (1.0 - smoothstep(0.97, 1.0, t))
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

## The scream: three shock rings that burst forward one after another, a ring of
## blown dust racing out along the ground, and a red flash. Additive and unshaded, so
## it reads as a wave of sound rather than a solid hoop.
static func scream_wave(parent: Node, origin: Vector3, forward: Vector3, reach: float) -> void:
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	# The torus lies flat in XZ; stand it up so it faces along `flat`.
	var facing := Basis.looking_at(flat) * Basis(Vector3.RIGHT, PI / 2)
	for i in 3:
		var delay := 0.07 * i
		var ring := _wave_ring(parent, 0.9 + 0.03 * i, Color(1.0, 0.45 - 0.12 * i, 0.25 - 0.08 * i), 2.6 - 0.6 * i)
		ring.global_transform = Transform3D(facing, origin + flat * 0.8)
		ring.scale = Vector3.ONE * 0.3
		var m: StandardMaterial3D = ring.material_override
		var tw := ring.create_tween().set_parallel()
		tw.tween_property(ring, "global_position", origin + flat * reach * (0.75 - 0.1 * i), 0.6) \
			.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring, "scale", Vector3.ONE * reach * (0.32 - 0.04 * i), 0.6) \
			.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.55).set_delay(delay + 0.05).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(ring.queue_free)
	# Dust ring on the street, centred on the volatile, racing out to half the reach.
	var ground := _wave_ring(parent, 0.94, Color(0.8, 0.25, 0.12), 0.7)
	ground.global_transform = Transform3D(Basis.IDENTITY, Vector3(origin.x, origin.y - 1.3, origin.z))
	ground.scale = Vector3(0.5, 0.3, 0.5)
	var gm: StandardMaterial3D = ground.material_override
	var gt := ground.create_tween().set_parallel()
	gt.tween_property(ground, "scale", Vector3(reach * 0.5, 0.3, reach * 0.5), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	gm.albedo_color.a = 0.5
	gt.tween_property(gm, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	gt.chain().tween_callback(ground.queue_free)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.2, 0.1)
	flash.light_energy = 3.0
	flash.omni_range = reach * 0.6
	flash.light_specular = 0.0
	flash.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(flash)
	flash.global_position = origin + flat * 4.0 + Vector3.UP * 1.0
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.6).set_ease(Tween.EASE_IN)
	ft.tween_callback(flash.queue_free)

## One thin, additive, unshaded torus for the scream wave. Tweened on idle frames, so it
## is kept out of physics interpolation.
static func _wave_ring(parent: Node, inner: float, color: Color, energy: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 8
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Unshaded ignores emission; an over-bright (HDR) albedo is what makes it bloom.
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 0.85)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(ring)
	return ring
