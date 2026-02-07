# Tweedcore RTS Prototype (Godot) — Terrain + Hidden Grid + A* + Structures

## What's new in this build
1) **A*** pathfinding on the hidden grid (slope-aware and occupancy-aware).
2) **Structures** driven from `data/unit_defs.json` with real footprints and structure views.

## Controls
- Left click: select nearest entity
- Right click: move selected unit (A* path over hidden grid)
- B: toggle build mode
- 1/2/3: choose structure to place (patchbay / loomcore / irrigation)
- Left click in build mode: place structure (occupies grid cells)

## Notes
- The A* solver uses a simple open set scan (fine for prototype). For big maps, switch to a binary heap.
- Movement is snap-per-tick to keep things deterministic-ish; later you can interpolate visuals.
