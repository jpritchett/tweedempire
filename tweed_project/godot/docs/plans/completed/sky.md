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

## Alternatives

If you prefer an asset-based approach, you can use a **PanoramaSkyMaterial** with an HDR panorama and animate cloud layers as separate `MeshInstance3D` hemispheres with scrolling textures. This is simpler to set up but less flexible and harder to tie into a real-time day/night cycle.
