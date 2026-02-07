# Weather & Ocean Simulation Plan

Inspired by Carrier Command 2's weather and ocean system.
Phase 1 (Gerstner waves) is implemented. Phases 2-5 remain.

## Phase 1: Gerstner Wave Ocean ✅ DONE

- Replaced simple sine-wave water with 4-wave Gerstner displacement
- Proper circular vertex motion: sharp crests, flat troughs
- Analytical normals via tangent/binormal cross product
- Fresnel reflections (glancing angle = more reflective)
- Foam on wave crests (whitecaps via displacement threshold)
- Subtle noise ripple for micro-detail
- File: `src/terrain/water_shader.gdshader`

## Phase 2: Weather State System

Create a data-driven weather simulation that evolves over time.

### New file: `autoload/weather.gd`
- Singleton, ticks alongside Simulation
- State variables:
  - `wind_speed: float` (0.0 = calm, 1.0 = gale)
  - `wind_direction: Vector2` (normalised)
  - `cloud_cover: float` (0.0 = clear, 1.0 = overcast)
  - `precipitation: float` (0.0 = none, 1.0 = heavy rain)
  - `fog_density: float` (0.0 = clear, 1.0 = pea soup)
  - `temperature: float` (for future use)
- Weather presets with smooth interpolation:
  - `clear` — wind 0.1, cloud 0.1, rain 0.0, fog 0.0
  - `overcast` — wind 0.3, cloud 0.7, rain 0.0, fog 0.2
  - `light_rain` — wind 0.4, cloud 0.8, rain 0.4, fog 0.3
  - `storm` — wind 0.9, cloud 1.0, rain 0.9, fog 0.5
- Transition system: lerp between presets over 30-60 seconds
- Random weather change timer (5-10 minutes per transition)
- Signals: `weather_changed(preset_name)`, `weather_updated(state)`

### Wind drives ocean
- Weather.wind_speed → water shader `amplitude` uniform (calm sea vs. rough sea)
- Weather.wind_direction → wave_a direction uniform
- Update via `ShaderMaterial.set_shader_parameter()` each frame from `world.gd`

## Phase 3: Visual Weather Effects

### 3a: Cloud shader update
- Modify `src/sky/sky_shader.gdshader`:
  - Add `uniform float cloud_cover_override` driven by Weather.cloud_cover
  - Thicken, darken, and lower clouds as cover increases
  - Storm clouds: shift colour toward dark grey, increase turbulence

### 3b: Volumetric fog
- Use Godot 4's built-in `FogVolume` + `FogMaterial`
- Create `src/weather/weather_fog.gd`:
  - Spawns a large FogVolume covering the map
  - Density driven by Weather.fog_density
  - Colour shifts from white haze to grey in storms

### 3c: Rain particles
- Create `src/weather/rain_particles.gd`:
  - `GPUParticles3D` attached to camera, follows player view
  - Emission rate driven by Weather.precipitation
  - Particle: thin vertical white streak, falls fast
  - Optional: rain splash particles on terrain

### 3d: Wind on vegetation
- Modify `src/terrain/terrain_vegetation.gd`:
  - Add wind_direction/wind_speed uniforms to grass material
  - Vertex shader bends grass quads in wind direction
  - Strength proportional to Weather.wind_speed

## Phase 4: Foam & Water Detail

### 4a: Shore foam
- In water fragment shader: use screen-space depth buffer
- Where water depth is shallow (near terrain), add foam band
- `DEPTH_TEXTURE` + `SCREEN_TEXTURE` in Godot 4 for depth read
- Foam intensity = smoothstep(0, depth_fade_distance, water_depth)

### 4b: Dynamic whitecaps
- Already partially done in Phase 1 (foam_threshold)
- Enhance: whitecap intensity scales with Weather.wind_speed
- At high wind: lower foam_threshold, increase foam opacity

### 4c: Underwater depth fog
- In fragment: read scene depth behind water
- Mix deep_color into objects behind water based on depth
- Creates natural depth extinction effect

### 4d: Caustics (stretch goal)
- Project animated caustic pattern onto terrain below water level
- Use a light cookie or projector with animated noise texture

## Phase 5: Gameplay Integration

### 5a: Sensor range reduction in storms
- In `logic_runtime.gd` `_count_enemies_near_owner()`:
  - Read Weather.wind_speed
  - Reduce sensor radius: `radius *= (1.0 - Weather.wind_speed * 0.5)`
  - Storms halve sensor detection range

### 5b: Enemy movement affected by wind
- In `enemy_spawner.gd` `_advance_enemies()`:
  - Read Weather.wind_direction and wind_speed
  - Headwind: reduce speed by up to 30%
  - Tailwind: increase speed by up to 15%

### 5c: Lightning strikes (storm events)
- During storm weather, random chance per tick:
  - Pick random position near player structures
  - Deal AoE damage (15) to enemies in radius 4
  - Spawn visual flash (point light + particle burst)
  - Play thunder sound

### 5d: Weather HUD
- Add weather indicator to InventoryHUD or separate overlay
- Show: wind direction arrow, weather icon (sun/cloud/rain/storm)
- Optional: forecast showing next weather transition

## Reference Materials

- [Gerstner Wave Ocean Shader (Godot)](https://godotshaders.com/shader/gerstner-wave-ocean-shader/)
- [GPU Gems: Effective Water Simulation](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models)
- [Godot 4 FFT Ocean (compute shader approach)](https://github.com/tessarakkt/godot4-oceanfft)
- [Gerstner Waves with Buoyancy in Godot 4](https://www.seacreaturegame.com/blog/gerstner-waves-with-buoyancy-godot)
- [Carrier Command 2 (Geometa)](https://geometa.co.uk/)
