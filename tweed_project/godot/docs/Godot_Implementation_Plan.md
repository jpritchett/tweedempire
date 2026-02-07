# Godot Implementation Plan (Tweedcore RTS)

## Goals
- TA-style isometric battlefield readability (silhouette/team panels)
- "Farming + automation + dark-cozy + co-op" core loop
- Automation is a *progression system*: loot verbs from enemies, socket verbs into logic blocks
- Small-team shippable architecture: data-driven, deterministic-ish sim, scalable networking

---

## 1) Project architecture (Godot 4.x)

### Scene graph
- `World.tscn`
  - `Camera3D` (isometric)
  - `DirectionalLight3D`
  - `Ground` (later: GridMap or custom terrain)
  - `UnitRoot` (views only)
  - `BuildingRoot` (views only)
  - `FXRoot`
  - `UI` (CanvasLayer)

### Autoloads (singletons)
- `Simulation.gd` (fixed tick + pure data state)
- `Net.gd` (multiplayer transport + command routing)
- `Registry.gd` (loads data: unit defs, verb defs, blocks)

### Data vs View rule
- Simulation state lives in dictionaries / lightweight classes (NO Node references).
- Nodes are views (meshes, animations) that mirror sim state each tick.
This is key for:
- easier save/load
- easier net replication (snapshots/deltas)
- easier determinism if you move toward lockstep

---

## 2) Simulation model

### Fixed tick
- 20Hz (configurable)
- Each tick:
  1. Apply validated commands at tick boundary
  2. Update movement/combat/production
  3. Evaluate automation graphs (event-driven where possible)
  4. Emit results + events (for VFX/audio/UI)

### Determinism guidance
Godot floats and physics are not perfectly deterministic across machines.
To keep options open:
- avoid using physics for gameplay outcomes (only for visuals)
- prefer grid/steering math you control
- use integer or fixed-point for critical values (resource counts, timers, thresholds)

---

## 3) Networking (co-op RTS)

### Phase 1 (prototype): host-authoritative
- Clients send commands to host (build/move/attack/logic edit).
- Host applies commands on tick boundaries, simulates, and sends snapshots.
Pros: simplest, fewer desync problems
Cons: bandwidth, latency compensation needed for feel

Implementation notes:
- Use ENet `MultiplayerPeer` (already stubbed in `Net.gd`).
- Snapshot frequency: start with every tick for ease; then reduce (e.g., 5–10Hz) + client interpolation.
- Interest management (later): only replicate within camera/ally interest.

### Phase 2 (upgrade): lockstep inputs (optional)
- All peers simulate; exchange only inputs per tick
- Requires deterministic sim and strict tick discipline
- Add periodic hash checks and resync snapshots if mismatch

Recommendation:
Ship with host-authoritative first. Add lockstep only if unit counts/AI or bandwidth demand it.

---

## 4) Automation ("Redstone Gone Wild") implementation

### Data model
- `LogicGraphResource`:
  - `nodes[]`: id, kind(sensor/logic/actuator), def_id, ui_pos, verb_slots[]
  - `edges[]`: from_id:port -> to_id:port

### Runtime evaluator
- `LogicRuntime`:
  - Stores `values[node_id][port]`
  - Supports:
    - sensor sampling (world queries)
    - logic evaluation (verb effects)
    - actuator commands (enqueue sim actions)
  - Cycle handling:
    - `DELAY` introduces tick-buffer nodes
    - `LOOP` nodes are bounded by safety limits (max iterations per tick)

### Verb sockets
- A `logic_tile` block has N sockets (start with 2).
- Sockets accept "verb runes" looted from enemies.
- Each verb modifies evaluation:
  - `FILTER`: threshold gate
  - `ROUTE`: output channel select
  - `QUEUE`: buffer
  - `THROTTLE`: rate limit
  - `RETRY`: retry up to k times over k ticks
  - `QUARANTINE`: toggles zone access & routes goods to sterile line
  - `FAILSAFE`: fallback behavior when power/signal fails

### Keep it readable at TA zoom
- Every block emits visible feedback:
  - LEDs (on/off, overload, quarantined)
  - animated shutters/valves
  - small debug decals shown only when selected

---

## 5) Minimal UI flow (prototype)

### RTS controls
- Left click: select
- Drag: selection box
- Right click: issue context command (move/attack/assist)
- B: build palette
- L: open automation editor for selected building

### Automation editor (MVP)
- Node graph UI:
  - place blocks (sensor/logic/actuator)
  - connect ports
  - drag-drop verb runes into sockets
- Play mode overlay:
  - show last 10 events per selected block
  - show signal values in tiny tooltip

### Co-op UX
- Each placed building stores `builder_player_id`
- Show a subtle crest decal + minimap ping color for ownership

---

## 6) Vertical slice scope (6–8 weeks prototype target)

### Must ship
- 1 small map
- 3 units, 2 buildings (already in defs)
- 1 enemy type that drops 2–3 verbs
- 1 automation scenario: Sterile Harvest Line (spores -> quarantine -> wash -> pack)

### Nice-to-have
- co-op join/host UI
- save/load
- one boss that drops `QUARANTINE`

---

## 7) Milestones
1. **Week 1–2**: deterministic tick sim + selection/commands + spawn/build
2. **Week 3**: logic graph editor MVP + runtime eval
3. **Week 4**: enemy + loot runes + sockets
4. **Week 5**: co-op host/join + command validation
5. **Week 6**: vertical-slice scenario + trailer capture pass

---

## 8) Performance notes (Godot)
- Use MultiMeshInstance3D for lots of small props (crops, fences)
- Keep unit meshes very low poly, rely on materials/decals for personality
- Avoid per-frame heavy queries; build a spatial hash/grid for sensors
