shader_type sky;

// Sky color uniforms
group_uniforms sky_colors;
uniform vec3 day_top_color : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 day_horizon_color : source_color = vec3(0.6, 0.75, 0.9);
uniform vec3 night_top_color : source_color = vec3(0.02, 0.02, 0.06);
uniform vec3 night_horizon_color : source_color = vec3(0.05, 0.05, 0.1);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.4, 0.1);
uniform float sunset_intensity : hint_range(0.0, 2.0) = 1.2;

// Sun uniforms
group_uniforms sun;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size : hint_range(0.001, 0.1) = 0.02;
uniform float sun_bloom_size : hint_range(0.0, 0.5) = 0.15;
uniform float sun_bloom_intensity : hint_range(0.0, 2.0) = 0.5;

// Cloud uniforms
group_uniforms clouds;
uniform float cloud_speed : hint_range(0.0, 0.1) = 0.01;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.0, 1.0) = 0.4;
uniform float cloud_scale : hint_range(0.5, 10.0) = 3.0;
uniform float cloud_height : hint_range(0.1, 0.5) = 0.2;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform int cloud_octaves : hint_range(1, 8) = 5;

// Weather uniforms (set by WeatherController)
group_uniforms weather;
uniform vec2 weather_wind = vec2(0.0, 0.0);
uniform float weather_cloud_boost : hint_range(0.0, 1.0) = 0.0;
uniform float weather_fog_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float lightning_flash : hint_range(0.0, 1.0) = 0.0;

// Star uniforms
group_uniforms stars;
uniform float star_density : hint_range(100.0, 2000.0) = 800.0;
uniform float star_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float star_twinkle_speed : hint_range(0.0, 5.0) = 2.0;

// Hash functions for noise generation
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

// Value noise
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Smoothstep

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractional Brownian Motion for clouds
// Uses constant loop bound with early break for shader compatibility
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	float total_amplitude = 0.0;

	const int MAX_OCTAVES = 8;
	for (int i = 0; i < MAX_OCTAVES; i++) {
		if (i >= octaves) break;
		value += amplitude * value_noise(p * frequency);
		total_amplitude += amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return value / max(total_amplitude, 0.0001);
}

// Generate stars using hash function
float stars(vec3 dir, float time) {
	// Create a grid on the sky sphere
	vec3 p = dir * star_density;
	vec3 i = floor(p);
	vec3 f = fract(p);

	float star = 0.0;

	// Check neighboring cells
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 cell = i + vec3(float(x), float(y), float(z));
				vec3 cell_center = cell + vec3(hash3(cell), hash3(cell + 1.0), hash3(cell + 2.0));

				float dist = length(p - cell_center);
				float brightness = hash3(cell + 3.0);

				// Only show some cells as stars
				if (brightness > 0.97) {
					// Twinkle effect
					float twinkle = sin(time * star_twinkle_speed + hash3(cell) * 6.28) * 0.3 + 0.7;
					star += smoothstep(0.1, 0.0, dist) * twinkle * star_brightness;
				}
			}
		}
	}

	return star;
}

// Calculate cloud coverage at a point
float get_clouds(vec3 dir, float time) {
	// Project onto a virtual plane above the camera
	if (dir.y < 0.01) return 0.0;

	vec2 uv = dir.xz / (dir.y + cloud_height);
	uv *= cloud_scale;

	// Animate clouds — base drift + weather wind influence
	vec2 wind_drift = vec2(time * cloud_speed, time * cloud_speed * 0.3);
	wind_drift += weather_wind * time * 0.005;
	uv += wind_drift;

	// Generate cloud noise using FBM
	float noise = fbm(uv, cloud_octaves);

	// Apply density and softness, boosted by weather
	float effective_density = cloud_density + weather_cloud_boost * 0.4;
	float clouds = smoothstep(1.0 - effective_density, 1.0 - effective_density + cloud_softness, noise);

	// Fade clouds near horizon
	float horizon_fade = smoothstep(0.0, 0.15, dir.y);

	return clouds * horizon_fade;
}

void sky() {
	vec3 dir = EYEDIR;

	// Get sun direction from the first directional light (fallback to noon if no light)
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float sun_height = sun_dir.y;

	// Day/night blend factor (0 = night, 1 = day)
	float day_factor = smoothstep(-0.2, 0.3, sun_height);

	// Sky gradient based on view direction
	float horizon_blend = 1.0 - abs(dir.y);
	horizon_blend = pow(horizon_blend, 1.5);

	// Day sky colors
	vec3 day_sky = mix(day_top_color, day_horizon_color, horizon_blend);

	// Night sky colors
	vec3 night_sky = mix(night_top_color, night_horizon_color, horizon_blend);

	// Blend day and night
	vec3 sky_color = mix(night_sky, day_sky, day_factor);

	// Sunset/sunrise effect (when sun is near horizon)
	float sunset_factor = 1.0 - abs(sun_height);
	sunset_factor = pow(sunset_factor, 3.0) * smoothstep(-0.3, 0.1, sun_height);

	// Apply sunset color near horizon when sun is low
	float sunset_horizon = pow(horizon_blend, 2.0);
	sky_color = mix(sky_color, sunset_color * sunset_intensity, sunset_factor * sunset_horizon * 0.7);

	// Sun disc and bloom
	float sun_dot = dot(dir, sun_dir);

	// Sun disc (hard edge)
	float sun_disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.5, sun_dot);

	// Sun bloom (soft glow)
	float sun_bloom = pow(max(0.0, sun_dot), 8.0) * sun_bloom_intensity;
	sun_bloom *= smoothstep(1.0 - sun_bloom_size, 1.0, sun_dot);

	// Add sun with day visibility
	vec3 sun = sun_color * (sun_disc + sun_bloom);
	// Fade sun when below horizon
	float sun_visibility = smoothstep(-0.1, 0.05, sun_height);
	sky_color += sun * sun_visibility;

	// Clouds
	float cloud_coverage = get_clouds(dir, TIME);

	// Cloud color varies with time of day and sunset
	vec3 cloud_col = cloud_color * mix(0.3, 1.0, day_factor);
	// Tint clouds with sunset color
	cloud_col = mix(cloud_col, sunset_color * 1.2, sunset_factor * 0.6);
	// Add slight ambient from below during day
	cloud_col += day_sky * 0.1 * day_factor;

	sky_color = mix(sky_color, cloud_col, cloud_coverage);

	// Stars (only visible at night)
	float star_visibility = 1.0 - day_factor;
	star_visibility *= (1.0 - cloud_coverage); // Stars hidden by clouds
	star_visibility *= smoothstep(-0.1, 0.3, dir.y); // Only above horizon

	if (star_visibility > 0.01) {
		float star_value = stars(dir, TIME);
		sky_color += vec3(star_value) * star_visibility;
	}

	// Weather fog: wash out horizon when foggy
	if (weather_fog_intensity > 0.01) {
		vec3 fog_col = mix(night_horizon_color, day_horizon_color, day_factor) * 0.8;
		sky_color = mix(sky_color, fog_col, weather_fog_intensity * horizon_blend * 0.6);
	}

	// Lightning flash: illuminate clouds from within
	if (lightning_flash > 0.01) {
		sky_color += vec3(0.8, 0.85, 1.0) * lightning_flash * cloud_coverage * 3.0;
	}

	// Ground (below horizon)
	if (dir.y < 0.0) {
		vec3 ground_color = mix(night_horizon_color, day_horizon_color, day_factor) * 0.3;
		float ground_blend = smoothstep(0.0, -0.1, dir.y);
		sky_color = mix(sky_color, ground_color, ground_blend);
	}

	COLOR = sky_color;
}
