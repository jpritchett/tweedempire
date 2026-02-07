# Adding an Animated Sky to a Godot 3D Game

## Approach

The best way to create a dynamic, animated sky in Godot 4 is with a **procedural sky shader** applied to a `WorldEnvironment` node. This gives you full creative control and performs well since everything runs on the GPU.

## Key Components

**WorldEnvironment + Sky Resource** — Godot's built-in sky system renders a shader onto the background of your 3D scene. You assign a `ShaderMaterial` with a `shader_type sky` shader to the Sky resource, and everything just works with the engine's lighting pipeline.

**DirectionalLight3D as the Sun** — The sky shader can read `LIGHT0_DIRECTION` to know where the sun is. Rotating this light over time drives the entire day/night cycle automatically.

**Procedural Clouds** — Use layered noise (fractional Brownian motion) projected onto a virtual plane above the camera. Offset the UV coordinates by `TIME` to make the clouds drift. Uniforms for density, softness, and scale let you tune the look at runtime.

**Day/Night Gradient** — Blend between day and night sky colors based on the sun's height (`LIGHT0_DIRECTION.y`). Add a sunset band near the horizon when the sun is low, tinting both the sky and the clouds with warm oranges.

**Sun Disc and Bloom** — A simple `smoothstep` around the dot product between the view direction and the sun direction creates the sun disc. A high-power falloff of the same dot product adds a soft glow around it.

**Stars** — Hash-based pseudo-random points on the sky sphere, faded in as the sun drops below the horizon. A sine wave on `TIME` gives them a gentle twinkle.

## Tunable Parameters

You'll want to expose uniforms for sky colors (top, horizon, night, sunset), cloud speed/density/scale, sun size, and star density. This lets you tweak the mood in the Inspector or animate values from GDScript for weather transitions or story beats.

## Performance Notes

Procedural sky shaders are very lightweight — they only run per-pixel on the sky dome, so they're essentially free compared to mesh-based skyboxes with animated textures. Five octaves of noise for clouds is a good balance between visual quality and cost; drop to three if targeting mobile.

## Tasks

- [x] Add a `WorldEnvironment` node to your 3D scene
- [x] Create an `Environment` resource and set the background mode to Sky
- [x] Create a `Sky` resource with a `ShaderMaterial` using `shader_type sky`
- [x] Write the sky gradient logic (day top/horizon colors blending by view direction)
- [x] Add night sky colors and blend between day/night based on sun height
- [x] Add a `DirectionalLight3D` to act as the sun
- [x] Read `LIGHT0_DIRECTION` in the shader to position the sun disc and bloom
- [x] Add a sunset/sunrise horizon glow that activates when the sun is low
- [x] Implement a noise function (hash + value noise) for cloud generation
- [x] Layer noise into FBM and project onto a plane above the camera
- [x] Animate cloud UVs using `TIME` to create drifting motion
- [x] Expose cloud uniforms (speed, density, softness, scale) for tuning
- [x] Tint clouds with sunset color when the sun is near the horizon
- [x] Add hash-based stars that appear at night with a twinkle effect
- [x] Write a GDScript to rotate the `DirectionalLight3D` over time for a day/night cycle
- [x] Expose sky color uniforms so they can be adjusted in the Inspector
- [ ] Test and tune parameters for your desired mood and art style
- [ ] Optimise noise octaves if targeting mobile (reduce from 5 to 3)

## Alternatives

If you prefer an asset-based approach, you can use a **PanoramaSkyMaterial** with an HDR panorama and animate cloud layers as separate `MeshInstance3D` hemispheres with scrolling textures. This is simpler to set up but less flexible and harder to tie into a real-time day/night cycle.
