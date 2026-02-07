# Heightmapped Terrain + Hidden Grid (Godot 4)

This prototype uses:
- A **visual heightmapped terrain** (MeshInstance3D generated from an Image heightmap)
- A **hidden logical grid** for RTS movement/building/automation placement.

## Why hidden grid?
- Pathfinding and placement are much easier on a grid than directly on a mesh.
- You still get the nice sculpted terrain look and TA-style readability.

## Coordinate mapping
- Grid coordinates are integer (gx, gz)
- Each cell maps to a world-space center:
  - world_x = (gx + 0.5) * cell_size
  - world_z = (gz + 0.5) * cell_size
- Height is sampled from the heightmap at the corresponding pixel.

## Height sampling
Terrain height is sampled from the stored heightmap `Image`:
- Convert world position to normalized UV over the terrain bounds
- Read height value (0..1)
- Convert to world Y using `height_scale`

## Placement
Buildings validate:
- footprint is within bounds
- slope in footprint < max_slope (optional)
- occupancy grid cells are free

## Files
- `src/terrain/heightmap_terrain.gd` : generates a mesh from heightmap and exposes sampling
- `src/grid/grid.gd` : hidden grid utilities (mapping, occupancy, path stubs)
- `src/world/world.gd` : uses Grid for click-to-move and build placement
