# A* Pathfinding + Structures (Prototype)

## A*
Implemented in `src/grid/grid.gd`:
- slope-aware adjacency cost (height delta adds cost, hard cap `max_slope`)
- avoids occupied cells
- octile heuristic for diagonal movement

Tuning knobs:
- `HiddenGrid.max_slope` (world units)
- `HiddenGrid.slope_cost`
- `HiddenGrid.allow_diagonal`

## Structures
Driven by `data/unit_defs.json` under `structures[]`:
- `id`: structure def id
- `footprint`: [w,h] in grid cells

Placement:
- Build mode shows a footprint-aligned ghost
- Placement occupies grid cells via `HiddenGrid.place()`

Views:
- `scenes/structure_view.tscn` scales its mesh based on the footprint
