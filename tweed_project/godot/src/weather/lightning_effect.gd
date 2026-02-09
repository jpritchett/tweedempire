extends Node
class_name LightningEffect
## Lightning flash manager. Triggers during heavy rain (>0.75).
## Flashes sky shader uniform and briefly boosts DirectionalLight3D.
## Uses cosmetic (non-deterministic) RNG.

var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _base_sun_energy: float = 2.5

var _flash_timer: float = 0.0
var _next_flash_interval: float = 8.0
var _flash_value: float = 0.0
var _flash_duration: float = 0.15
var _flash_elapsed: float = 0.0
var _flashing: bool = false

var _local_rain: float = 0.0
var _enabled: bool = false

func setup(sky_mat: ShaderMaterial, sun: DirectionalLight3D) -> void:
	_sky_mat = sky_mat
	_sun = sun
	if _sun != null:
		_base_sun_energy = _sun.light_energy

func set_rain_intensity(rain: float) -> void:
	_local_rain = rain
	_enabled = rain > 0.75

func _process(delta: float) -> void:
	if _flashing:
		_flash_elapsed += delta
		var t := clampf(_flash_elapsed / _flash_duration, 0.0, 1.0)
		# Quadratic decay
		_flash_value = (1.0 - t) * (1.0 - t)
		if t >= 1.0:
			_flashing = false
			_flash_value = 0.0
		_apply_flash()
		return

	if not _enabled:
		if _flash_value > 0.0:
			_flash_value = 0.0
			_apply_flash()
		return

	_flash_timer += delta
	if _flash_timer >= _next_flash_interval:
		_flash_timer = 0.0
		_next_flash_interval = randf_range(3.0, 12.0)
		_trigger_flash()

func _trigger_flash() -> void:
	_flashing = true
	_flash_elapsed = 0.0
	_flash_value = 1.0
	_apply_flash()

func _apply_flash() -> void:
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("lightning_flash", _flash_value)
	if _sun != null:
		_sun.light_energy = _base_sun_energy + _flash_value * 3.0
