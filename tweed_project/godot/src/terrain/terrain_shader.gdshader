shader_type spatial;

// UK biome textures (5 zones from low to high elevation)
group_uniforms textures;
uniform sampler2D peat_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D meadow_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D woodland_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moorland_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_tile_size : hint_range(1.0, 64.0) = 8.0;

// Height-based zone thresholds (normalised 0-1)
group_uniforms height_zones;
uniform float height_min : hint_range(-100.0, 100.0) = 0.0;
uniform float height_max : hint_range(-100.0, 100.0) = 25.0;
uniform float peat_upper : hint_range(0.0, 1.0) = 0.12;
uniform float meadow_upper : hint_range(0.0, 1.0) = 0.45;
uniform float woodland_upper : hint_range(0.0, 1.0) = 0.65;
uniform float moorland_upper : hint_range(0.0, 1.0) = 0.88;
uniform float zone_blend : hint_range(0.01, 0.15) = 0.06;

// Slope blending (rock on steep faces)
group_uniforms slope;
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.50;
uniform float slope_blend_range : hint_range(0.01, 0.5) = 0.15;

// Colour adjustments
group_uniforms color;
uniform float ambient_occlusion : hint_range(0.0, 1.0) = 0.25;
uniform float moisture_scale : hint_range(1.0, 100.0) = 16.0;
uniform float moisture_strength : hint_range(0.0, 0.5) = 0.15;

// Detail noise for variation
group_uniforms detail;
uniform float detail_scale : hint_range(1.0, 200.0) = 48.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.18;

// Pass world-space position from vertex to fragment
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Hash for procedural noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// World-space texture coordinates (avoids stretching on large maps)
	vec2 uv_world = world_pos.xz / texture_tile_size;

	// Sample all 5 biome textures
	vec3 peat = texture(peat_texture, uv_world).rgb;
	vec3 meadow = texture(meadow_texture, uv_world).rgb;
	vec3 woodland = texture(woodland_texture, uv_world).rgb;
	vec3 moorland = texture(moorland_texture, uv_world).rgb;
	vec3 rock = texture(rock_texture, uv_world).rgb;

	// Normalised height (0 = lowest, 1 = highest)
	float h = clamp((world_pos.y - height_min) / (height_max - height_min), 0.0, 1.0);

	// Detail noise for breaking up zone transitions
	float detail = noise(world_pos.xz / texture_tile_size * detail_scale) * detail_strength;
	float h_varied = clamp(h + detail * 0.5 - detail_strength * 0.25, 0.0, 1.0);

	// Zone weights using smoothstep crossfades
	float w_peat = 1.0 - smoothstep(peat_upper - zone_blend, peat_upper + zone_blend, h_varied);
	float w_meadow = smoothstep(peat_upper - zone_blend, peat_upper + zone_blend, h_varied)
					* (1.0 - smoothstep(meadow_upper - zone_blend, meadow_upper + zone_blend, h_varied));
	float w_woodland = smoothstep(meadow_upper - zone_blend, meadow_upper + zone_blend, h_varied)
					  * (1.0 - smoothstep(woodland_upper - zone_blend, woodland_upper + zone_blend, h_varied));
	float w_moorland = smoothstep(woodland_upper - zone_blend, woodland_upper + zone_blend, h_varied)
					  * (1.0 - smoothstep(moorland_upper - zone_blend, moorland_upper + zone_blend, h_varied));
	float w_rock_height = smoothstep(moorland_upper - zone_blend, moorland_upper + zone_blend, h_varied);

	// Slope detection: steep faces get rock regardless of elevation
	float flatness = clamp(dot(world_normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	float slope_rock = 1.0 - smoothstep(slope_threshold - slope_blend_range,
										  slope_threshold + slope_blend_range,
										  flatness);

	// Combine height-based rock and slope-based rock
	float total_rock = clamp(w_rock_height + slope_rock, 0.0, 1.0);

	// Scale down other weights when rock dominates
	float non_rock = 1.0 - total_rock;
	w_peat *= non_rock;
	w_meadow *= non_rock;
	w_woodland *= non_rock;
	w_moorland *= non_rock;

	// Blend biome colours
	vec3 final_color = peat * w_peat
					 + meadow * w_meadow
					 + woodland * w_woodland
					 + moorland * w_moorland
					 + rock * total_rock;

	// Moisture variation: shift saturation across the landscape
	float moisture = noise(world_pos.xz / moisture_scale) * moisture_strength;
	final_color = mix(final_color, final_color * vec3(0.85, 1.1, 0.85), moisture);

	// Ambient occlusion: darken valleys slightly
	float ao = mix(1.0 - ambient_occlusion, 1.0, flatness);

	ALBEDO = final_color * ao;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
