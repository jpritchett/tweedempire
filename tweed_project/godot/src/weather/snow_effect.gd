extends Node3D
class_name SnowEffect
## GPUParticles3D wrapper for snow. Slower, wider spread than rain.
## WeatherController switches between rain and snow based on temperature.

var _particles: GPUParticles3D
var _process_mat: ParticleProcessMaterial
var _intensity: float = 0.0

func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 2000
	_particles.lifetime = 4.0
	_particles.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 40, 120))
	_particles.emitting = false

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.direction = Vector3(0, -1, 0)
	_process_mat.spread = 45.0
	_process_mat.initial_velocity_min = 2.0
	_process_mat.initial_velocity_max = 4.0
	_process_mat.gravity = Vector3(0, -2.0, 0)
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(50, 2, 50)
	_process_mat.color = Color(0.9, 0.92, 0.95, 0.6)
	_process_mat.turbulence_enabled = true
	_process_mat.turbulence_noise_strength = 2.0
	_process_mat.turbulence_noise_speed_random = 0.5
	_process_mat.turbulence_noise_scale = 4.0
	_particles.process_material = _process_mat

	# Snowflake mesh (small quad)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	_particles.draw_pass_1 = mesh

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.9, 0.92, 0.95, 0.6)
	_particles.material_override = mat

	add_child(_particles)

func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	_particles.emitting = _intensity > 0.05
	var alpha := _intensity * 0.7
	_process_mat.color = Color(0.9, 0.92, 0.95, alpha)
	if _particles.material_override is StandardMaterial3D:
		(_particles.material_override as StandardMaterial3D).albedo_color = Color(0.9, 0.92, 0.95, alpha)

func set_wind(wind_vec: Vector2) -> void:
	_process_mat.gravity = Vector3(wind_vec.x * 1.5, -2.0, wind_vec.y * 1.5)

func follow_camera(cam_pos: Vector3) -> void:
	global_position = Vector3(cam_pos.x, cam_pos.y + 15.0, cam_pos.z)
