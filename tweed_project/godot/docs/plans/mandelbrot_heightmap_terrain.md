# Mandelbrot Heightmap Terrain

## Concept

Use a section of the Mandelbrot set as the basis for terrain heightmap generation. The fractal's natural mix of smooth basins, sharp ridges, and spiralling detail creates far more interesting landscapes than typical Perlin noise — deep valleys where points converge quickly, towering peaks along the set boundary, and rolling plains in the escape regions.

## How It Works

**Mandelbrot as Height** — For each pixel in the heightmap, run the Mandelbrot iteration `z = z² + c` where `c` is mapped from the pixel's UV coordinates to a region of the complex plane. The iteration count at escape becomes the raw height value. Points that never escape (inside the set) become the lowest terrain.

**Choosing the Right Region** — The full Mandelbrot set is iconic but not great terrain. Zoom into a boundary region where there's a rich mix of escape speeds. Good candidates include the Seahorse Valley (around `-0.75 + 0.1i`), the antenna tip area, or any mini-brot boundary. The region you pick dramatically changes the terrain character.

**Emphasising Contrast** — Raw iteration counts produce fairly flat heightmaps. To get dramatic peaks and deep valleys, apply post-processing to the height values: power curves to push extremes apart, logarithmic smoothing to reduce banding, and normalisation to fill the full `0–1` range. Optionally blend in a secondary noise layer to break up any remaining uniformity.

**Smooth Iteration Count** — Standard integer iteration counts create visible terracing in the terrain. Use the smooth iteration formula (`n - log2(log2(|z|))`) to get continuous height values, which produce much cleaner slopes and ridges.

## Key Parameters

**Complex plane window** — The `min` and `max` real/imaginary coordinates defining which section of the Mandelbrot set to render. This is the single most impactful parameter — small shifts produce completely different landscapes.

**Max iterations** — Higher values reveal more detail along the set boundary but cost more to compute. 256–1024 is a good range for heightmaps.

**Height exponent** — A power curve applied to normalised heights. Values above 1.0 sharpen peaks and deepen valleys; values below 1.0 flatten everything out. Something around 1.5–3.0 gives dramatic terrain.

**Heightmap resolution** — The pixel dimensions of the generated image. 512×512 is fine for prototyping; 2048×2048 or 4096×4096 for final quality.

**Terrain mesh scale** — How the heightmap maps to world units in Godot (horizontal extent and vertical amplitude).

## Integration with Godot

The heightmap can be used with Godot's `Terrain3D` plugin, applied to a subdivided `MeshInstance3D` via vertex displacement in a shader, or used to generate mesh geometry from GDScript/C#. For quick results, a plane mesh with a vertex shader that samples the heightmap texture and displaces `VERTEX.y` is the simplest path.

## Tasks

- [x] Write a heightmap generator script (GDScript, Python, or C#) that iterates the Mandelbrot formula per pixel
- [x] Implement smooth iteration count to avoid terracing artifacts
- [x] Choose a compelling region of the complex plane to zoom into (e.g. Seahorse Valley around `-0.75 + 0.1i`)
- [x] Add parameters for complex plane window, max iterations, and resolution
- [x] Normalise the raw iteration values to the `0.0–1.0` range
- [x] Apply a power curve to emphasise height extremes (experiment with exponents 1.5–3.0)
- [ ] Optionally apply logarithmic smoothing or histogram equalisation for better height distribution
- [ ] Export the heightmap as a 16-bit PNG or EXR for maximum precision
- [x] Import the heightmap into Godot as an `Image` or `ImageTexture`
- [x] Create a subdivided plane mesh (or use Terrain3D) to display the terrain
- [ ] Write a vertex shader that samples the heightmap and displaces `VERTEX.y`
- [x] Add a uniform for vertical scale so peak height can be tuned in the Inspector
- [x] Apply a terrain material with slope-based texturing (grass on flat, rock on steep)
- [ ] Optionally blend in a noise layer to add micro-detail the fractal doesn't provide
- [ ] Add LOD or distance-based tessellation if using high-resolution meshes
- [x] Connect the terrain to the animated sky system for a unified scene
- [ ] Test different Mandelbrot regions and exponents until the landscape feels right

## Notes

The Mandelbrot computation is CPU-heavy for large resolutions but only needs to run once — bake the heightmap to disk and load it as a texture at runtime. If you want real-time zooming or exploration, move the computation to a compute shader.

## Implementation Files

- `src/terrain/mandelbrot_heightmap.gd` - Mandelbrot heightmap generator class
- `src/terrain/heightmap_terrain.gd` - Updated terrain with Mandelbrot support
- `src/terrain/terrain_shader.gdshader` - Slope-based terrain material shader

## Available Presets

The `MandelbrotHeightmap` class includes these preset regions:

| Preset | Description |
|--------|-------------|
| `seahorse_valley` | Classic area with spirals and varied detail |
| `elephant_valley` | Elephant trunk shapes with rolling terrain |
| `antenna_tip` | Sharp peaks and deep valleys at the antenna |
| `mini_brot` | Miniature Mandelbrot with surrounding detail |
| `spiral_arms` | Tight spirals creating ridge-like terrain |
| `full_set` | The complete Mandelbrot set (less interesting as terrain) |
