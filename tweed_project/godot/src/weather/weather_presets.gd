extends RefCounted
class_name WeatherPresets
## Weather pattern definitions. Each preset is a dictionary of parameters
## consumed by WeatherSimulation.spawn_pattern().

const PRESETS := {
	"cyclone": {
		"name": "Cyclone",
		"radius": 14.0,
		"wind_strength": 3.0,
		"wind_x": 0.5,
		"wind_y": 0.3,
		"rotation": -1.0,  # CCW
		"rain_amount": 0.9,
		"fog_amount": 0.3,
		"temp_offset": -0.1,
		"lifespan": 200.0,
		"drift_x": 0.08,
		"drift_y": 0.02,
		"move_speed": 0.2,
	},
	"anticyclone": {
		"name": "Anticyclone",
		"radius": 16.0,
		"wind_strength": 1.5,
		"wind_x": 0.3,
		"wind_y": -0.2,
		"rotation": 1.0,  # CW
		"rain_amount": 0.0,
		"fog_amount": 0.0,
		"temp_offset": 0.15,
		"lifespan": 250.0,
		"drift_x": 0.05,
		"drift_y": 0.01,
		"move_speed": 0.15,
	},
	"fog_bank": {
		"name": "Fog Bank",
		"radius": 12.0,
		"wind_strength": 0.3,
		"wind_x": 0.1,
		"wind_y": 0.0,
		"rotation": 0.0,
		"rain_amount": 0.05,
		"fog_amount": 1.0,
		"temp_offset": -0.05,
		"lifespan": 150.0,
		"drift_x": 0.02,
		"drift_y": 0.01,
		"move_speed": 0.1,
	},
	"cold_front": {
		"name": "Cold Front",
		"radius": 18.0,
		"wind_strength": 2.0,
		"wind_x": 0.8,
		"wind_y": 0.4,
		"rotation": -0.3,
		"rain_amount": 0.7,
		"fog_amount": 0.5,
		"temp_offset": -0.3,
		"lifespan": 120.0,
		"drift_x": 0.12,
		"drift_y": 0.04,
		"move_speed": 0.3,
	},
}

static func get_preset(id: String) -> Dictionary:
	if PRESETS.has(id):
		return PRESETS[id].duplicate(true)
	push_warning("WeatherPresets: unknown preset '%s'" % id)
	return {}

static func get_random_preset(rng: RandomNumberGenerator) -> Dictionary:
	var keys := PRESETS.keys()
	var key: String = keys[rng.randi() % keys.size()]
	return PRESETS[key].duplicate(true)

static func preset_names() -> Array:
	return PRESETS.keys()
