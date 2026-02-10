shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ─── Gerstner Wave Parameters ────────────────────────────────────────────────
// Each wave: vec4(direction.x, direction.y, steepness, wavelength)
group_uniforms waves;
uniform vec4 wave_a = vec4(1.0, 0.0, 0.35, 12.0);
uniform vec4 wave_b = vec4(0.6, 0.85, 0.25, 8.0);
uniform vec4 wave_c = vec4(-0.4, 0.7, 0.20, 5.0);
uniform vec4 wave_d = vec4(0.8, -0.3, 0.15, 3.0);
uniform float amplitude : hint_range(0.0, 3.0) = 0.5;
uniform float speed : hint_range(0.0, 5.0) = 0.36;

// ─── Colours ─────────────────────────────────────────────────────────────────
group_uniforms colors;
uniform vec3 shallow_color : source_color = vec3(0.10, 0.14, 0.16);
uniform vec3 deep_color : source_color = vec3(0.06, 0.09, 0.12);
uniform vec3 foam_color : source_color = vec3(0.22, 0.24, 0.26);

// ─── Weather (set by WeatherController) ──────────────────────────────────────
group_uniforms weather;
uniform float weather_wind_strength : hint_range(0.0, 5.0) = 0.0;
uniform float weather_rain_intensity : hint_range(0.0, 1.0) = 0.0;

// ─── Surface ─────────────────────────────────────────────────────────────────
group_uniforms surface;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.96;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.45;
uniform float water_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.7;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float normal_detail_scale : hint_range(0.0, 2.0) = 0.5;

// ─── Varyings ────────────────────────────────────────────────────────────────
varying vec3 world_pos;
varying vec3 world_normal;
varying float wave_crest;

// ─── Gerstner Wave Function ──────────────────────────────────────────────────
// Returns displacement vector (xyz) for a single Gerstner wave.
// Gerstner waves move vertices in circular orbits — horizontal toward
// each crest and vertical up/down — creating sharp peaks and flat troughs.
vec3 gerstner(vec4 wave_params, vec2 p, float t) {
	vec2 d = normalize(wave_params.xy);
	float steepness = wave_params.z;
	float wavelength = wave_params.w;

	float k = 6.28318 / wavelength;           // wave number (2*PI / wavelength)
	float c = sqrt(9.8 / k);                  // phase speed (deep water dispersion)
	float f = k * (dot(d, p) - c * t);        // phase
	float a = steepness / k;                   // amplitude derived from steepness

	// Horizontal displacement toward crest + vertical sine displacement
	return vec3(
		d.x * a * cos(f),
		a * sin(f),
		d.y * a * cos(f)
	);
}

// ─── Gerstner Normal via Tangent/Binormal ────────────────────────────────────
// Accumulates tangent and binormal partial derivatives for each wave.
// The cross product of the final binormal × tangent gives the surface normal.
void gerstner_normal(vec4 wave_params, vec2 p, float t,
                     inout vec3 tangent, inout vec3 binormal) {
	vec2 d = normalize(wave_params.xy);
	float steepness = wave_params.z;
	float wavelength = wave_params.w;

	float k = 6.28318 / wavelength;
	float c = sqrt(9.8 / k);
	float f = k * (dot(d, p) - c * t);

	tangent += vec3(
		-d.x * d.x * steepness * sin(f),
		d.x * steepness * cos(f),
		-d.x * d.y * steepness * sin(f)
	);
	binormal += vec3(
		-d.x * d.y * steepness * sin(f),
		d.y * steepness * cos(f),
		-d.y * d.y * steepness * sin(f)
	);
}

// ─── Simple noise for surface detail ─────────────────────────────────────────
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ─── Vertex Shader ───────────────────────────────────────────────────────────
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world_pos.xz;
	float t = TIME * speed;

	// Sum 4 Gerstner wave displacements at different directions/frequencies
	vec3 disp = vec3(0.0);
	disp += gerstner(wave_a, p, t);
	disp += gerstner(wave_b, p, t);
	disp += gerstner(wave_c, p, t);
	disp += gerstner(wave_d, p, t);

	// Apply global amplitude scaling, boosted by weather wind
	float storm_amp = amplitude * (1.0 + weather_wind_strength * 1.5);
	VERTEX += disp * storm_amp;

	// Analytical surface normal from accumulated wave tangent/binormal
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	gerstner_normal(wave_a, p, t, tangent, binormal);
	gerstner_normal(wave_b, p, t, tangent, binormal);
	gerstner_normal(wave_c, p, t, tangent, binormal);
	gerstner_normal(wave_d, p, t, tangent, binormal);
	vec3 n = normalize(cross(binormal, tangent));
	NORMAL = n;

	// Pass wave crest height to fragment shader for foam rendering
	wave_crest = disp.y * storm_amp;
	world_normal = n;
}

// ─── Fragment Shader ─────────────────────────────────────────────────────────
void fragment() {
	// Fresnel: more reflective at glancing angles (like real water)
	float ndotv = max(dot(world_normal, VIEW), 0.0);
	float fresnel = pow(1.0 - ndotv, fresnel_power);

	// Water colour: subtle blend shallow → deep based on view angle
	vec3 water_col = mix(shallow_color, deep_color, 0.4 + fresnel * 0.3);

	// Foam on wave crests — lower threshold in storms for more whitecaps
	float storm_amp = amplitude * (1.0 + weather_wind_strength * 1.5);
	float storm_foam_thresh = foam_threshold * (1.0 - weather_wind_strength * 0.15);
	float foam_edge = storm_foam_thresh * storm_amp;
	float foam_mask = smoothstep(foam_edge, storm_amp, wave_crest);
	water_col = mix(water_col, foam_color, foam_mask * 0.35);

	// Very subtle noise ripple for micro-detail
	float ripple = noise2(world_pos.xz * 2.0 + TIME * 0.3);
	ripple = (ripple - 0.5) * normal_detail_scale * 0.02;

	// Rain ripple noise on surface
	float rain_ripple = noise2(world_pos.xz * 8.0 + TIME * 2.5);
	rain_ripple = (rain_ripple - 0.5) * weather_rain_intensity * 0.03;
	water_col += ripple + rain_ripple;

	ALBEDO = water_col;
	ALPHA = mix(water_alpha, 1.0, foam_mask * 0.4);
	ROUGHNESS = mix(water_roughness, 0.55, foam_mask);
	METALLIC = water_metallic;
	SPECULAR = 0.2 + fresnel * 0.15;
}
