extends Node3D
class_name RainEffect
## GPUParticles3D wrapper for rain. Follows camera position.
## Intensity and wind are set by WeatherController.

var _particles: GPUParticles3D
var _process_mat: ParticleProcessMaterial
var _intensity: float = 0.0
var _wind: Vector2 = Vector2.ZERO

func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 4000
	_particles.lifetime = 1.5
	_particles.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 40, 120))
	_particles.emitting = false

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.direction = Vector3(0, -1, 0)
	_process_mat.spread = 5.0
	_process_mat.initial_velocity_min = 15.0
	_process_mat.initial_velocity_max = 20.0
	_process_mat.gravity = Vector3(0, -9.8, 0)
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(50, 2, 50)
	_process_mat.color = Color(0.7, 0.75, 0.8, 0.4)
	_particles.process_material = _process_mat

	# Rain streak mesh
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.02, 0.3)
	_particles.draw_pass_1 = mesh

	# Unshaded translucent material for the mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.7, 0.75, 0.8, 0.4)
	_particles.material_override = mat

	add_child(_particles)

func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	_particles.emitting = _intensity > 0.05
	# Control visibility through alpha (amount can't change at runtime)
	var alpha := _intensity * 0.5
	_process_mat.color = Color(0.7, 0.75, 0.8, alpha)
	if _particles.material_override is StandardMaterial3D:
		(_particles.material_override as StandardMaterial3D).albedo_color = Color(0.7, 0.75, 0.8, alpha)

func set_wind(wind_vec: Vector2) -> void:
	_wind = wind_vec
	# Push rain sideways with wind
	_process_mat.gravity = Vector3(_wind.x * 3.0, -9.8, _wind.y * 3.0)

func follow_camera(cam_pos: Vector3) -> void:
	global_position = Vector3(cam_pos.x, cam_pos.y + 15.0, cam_pos.z)
