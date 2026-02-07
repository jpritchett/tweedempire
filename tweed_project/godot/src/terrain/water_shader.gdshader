shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Wave parameters
group_uniforms waves;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float wave_scale : hint_range(0.5, 40.0) = 12.0;
uniform float wave_amplitude : hint_range(0.0, 2.0) = 0.4;
uniform float wave2_scale : hint_range(0.5, 40.0) = 18.0;
uniform float wave2_speed : hint_range(0.0, 3.0) = 0.4;
uniform float wave2_amplitude : hint_range(0.0, 2.0) = 0.25;

// Colours
group_uniforms colors;
uniform vec3 shallow_color : source_color = vec3(0.15, 0.45, 0.45);
uniform vec3 deep_color : source_color = vec3(0.05, 0.12, 0.22);
uniform vec3 foam_color : source_color = vec3(0.7, 0.8, 0.85);

// Surface
group_uniforms surface;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.92;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.15;
uniform float water_metallic : hint_range(0.0, 1.0) = 0.1;
uniform float ripple_scale : hint_range(0.1, 5.0) = 1.5;
uniform float ripple_speed : hint_range(0.0, 2.0) = 0.3;
uniform float ripple_strength : hint_range(0.0, 0.15) = 0.04;

// World-space position
varying vec3 world_pos;

// Hash for noise
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.45;
	}
	return v;
}

// Wave height at a world xz position
float wave_height(vec2 xz, float time) {
	// Wave 1 — main swell, moving along X+Z diagonal
	float w1 = sin(xz.x / wave_scale + xz.y / wave_scale * 0.7 + time * wave_speed) * wave_amplitude;

	// Wave 2 — cross-wave at different angle and frequency
	float w2 = sin(xz.x / wave2_scale * 0.6 - xz.y / wave2_scale + time * wave2_speed * 1.3) * wave2_amplitude;

	// Wave 3 — small choppy detail
	float w3 = sin(xz.x / 4.0 + time * 1.2) * cos(xz.y / 3.5 + time * 0.9) * 0.1;

	return w1 + w2 + w3;
}

void vertex() {
	// Compute world position before displacement
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Displace vertex Y by wave function
	float h = wave_height(world_pos.xz, TIME);
	VERTEX.y += h;

	// Recompute normal from wave partial derivatives (analytical)
	float eps = 0.5;
	float h_r = wave_height(world_pos.xz + vec2(eps, 0.0), TIME);
	float h_u = wave_height(world_pos.xz + vec2(0.0, eps), TIME);
	float dx = (h_r - h) / eps;
	float dz = (h_u - h) / eps;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	// Base water colour — mostly uniform
	vec3 water_color = mix(shallow_color, deep_color, 0.5);

	// Use the wave-displaced normal for specular variation — this is what
	// makes the surface look alive, not noise blobs
	// The vertex shader already set NORMAL from the wave derivatives,
	// so lighting/specular will naturally shimmer with the waves.

	ALBEDO = water_color;
	ALPHA = water_alpha;
	ROUGHNESS = water_roughness;
	METALLIC = water_metallic;
}
