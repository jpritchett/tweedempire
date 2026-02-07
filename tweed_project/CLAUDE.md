# CLAUDE.md - Tweedcore RTS Prototype

## Project Overview
Tweedcore is a co-op RTS game prototype built in Godot 4.x with a "farming + automation + dark-cozy" core loop. The game features TA-style isometric gameplay with an automation system where players loot "verbs" from enemies and socket them into logic blocks.

## Quick Start
```bash
# Open in Godot 4.6+
cd godot && godot project.godot
```

## Project Structure
```
tweed_project/
├── godot/                    # Main Godot project
│   ├── autoload/             # Singleton scripts (Simulation, Net, Registry)
│   ├── data/                 # JSON definitions (units, blocks)
│   ├── scenes/               # .tscn scene files
│   ├── src/                  # GDScript source
│   │   ├── camera/           # Camera rig
│   │   ├── grid/             # Grid system & A* pathfinding
│   │   ├── logic/            # Automation graph system
│   │   ├── sky/              # Sky rendering
│   │   ├── terrain/          # Heightmap terrain
│   │   └── world/            # World, units, structures, build ghost
│   └── docs/                 # Design docs and plans
├── archives/                 # Historical prototype zips
└── docs/                     # Conversation logs
```

## Architecture Principles

### Data vs View Separation
- **Simulation state** lives in dictionaries/lightweight classes (NO Node references)
- **Nodes are views** (meshes, animations) that mirror sim state each tick
- This enables: save/load, net replication, determinism for lockstep

### Fixed Tick Simulation
- 20Hz tick rate (configurable)
- Each tick: apply commands → update movement/combat → evaluate automation → emit events

### Autoloads (Singletons)
- `Simulation.gd` - Fixed tick + pure data state
- `Net.gd` - Multiplayer transport + command routing
- `Registry.gd` - Loads data definitions (units, verbs, blocks)

## Game Controls
| Input | Action |
|-------|--------|
| Left click | Select nearest entity |
| Right click | Move selected unit (A* pathfinding) |
| B | Toggle build mode |
| 1/2/3 | Choose structure (patchbay/loomcore/irrigation) |
| Left click (build mode) | Place structure |
| WASD / Arrows | Pan camera |
| Q/E or scroll | Zoom in/out |
| Space | Rotate camera |
| V | Reset camera |

## Key Systems

### Grid & Pathfinding (`src/grid/grid.gd`)
- Hidden grid for pathfinding and structure placement
- A* pathfinding with slope awareness and occupancy checks
- Grid cells track walkability and structure footprints

### Automation System (`src/logic/`)
- `LogicGraphResource` - Node graph with sensors, logic, actuators
- `LogicRuntime` - Evaluates graphs, handles verb effects
- Verb sockets on logic blocks accept looted "verb runes"

### Terrain (`src/terrain/`)
- Heightmap-based terrain with shader
- Mandelbrot heightmap generator for testing

## Data Files
- `data/unit_defs.json` - Unit definitions (health, speed, etc.)
- `data/block_defs.json` - Structure definitions with footprints

## Networking (Planned)
- Phase 1: Host-authoritative (clients send commands, host simulates)
- Phase 2: Lockstep inputs (deterministic sim, exchange only inputs)

## Current TODO
- Deterministic entity ID allocator for net play
- Proper structure entity type separation
- Selection box and minimap
- Unit movement visual interpolation
- Binary heap for A* (large unit counts)
- Slope validation for building placement

## Code Style
- GDScript 4.x with static typing where practical
- Prefer data-driven design (JSON definitions)
- Keep simulation logic separate from view/rendering
- Use signals for loose coupling between systems

## Testing
Tests are in `godot/tests/` (not yet committed to git).
