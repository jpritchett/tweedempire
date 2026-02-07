extends Node
class_name EnemySpawner

## Spawns waves of enemies near player structures on a timer.
## Enemies pathfind toward the nearest player structure.

var grid: HiddenGrid
var terrain: HeightmapTerrain

## Ticks between waves
var wave_interval: int = 600  # 30 seconds at 20Hz
## Enemies per wave (grows over time)
var base_wave_size: int = 3
## Max simultaneous enemies
var max_enemies: int = 20
## Spawn distance from target (in grid cells)
var spawn_radius_min: int = 15
var spawn_radius_max: int = 30

var _tick_counter: int = 0
var _wave_number: int = 0
var _enemy_types := ["spore_crawler", "blight_drone"]

## enemy eid -> path (grid cells)
var enemy_paths := {}
## enemy eid -> accumulated move budget (cells)
var _move_budget := {}
## Queue of enemies waiting to pathfind (staggered to avoid stalls)
var _repath_queue: Array[int] = []

func _ready() -> void:
	Simulation.tick_advanced.connect(_on_tick)

func _on_tick(_t: int) -> void:
	_tick_counter += 1
	if _tick_counter >= wave_interval:
		_tick_counter = 0
		_spawn_wave()
	# Process at most 1 pathfind per tick to avoid stalls
	_process_repath_queue()
	_advance_enemies()

func _spawn_wave() -> void:
	if grid == null or terrain == null:
		return
	_wave_number += 1
	var count := mini(base_wave_size + _wave_number, max_enemies - _count_enemies())
	if count <= 0:
		return

	# Find a target to spawn near
	var target_pos := _find_any_player_position()
	if target_pos == Vector3.ZERO:
		return

	for i in count:
		var spawn_pos := _random_position_near(target_pos, spawn_radius_min, spawn_radius_max)
		if spawn_pos == Vector3.ZERO:
			continue
		var enemy_type: String = _enemy_types[i % _enemy_types.size()]
		var eid: int = Simulation.spawn_entity(enemy_type, spawn_pos, -1)
		var e = Simulation.state.entities[eid]
		e["kind"] = "enemy"
		e["attack_cooldown_current"] = 0
		e["attack_target"] = -1
		# Queue pathfinding (staggered across ticks)
		_repath_queue.append(eid)

func _process_repath_queue() -> void:
	if _repath_queue.is_empty():
		return
	# Process 1 pathfind per tick
	var eid: int = _repath_queue[0]
	_repath_queue.remove_at(0)
	var e = Simulation.state.entities.get(eid, null)
	if e == null or e.get("hp", 0) <= 0:
		return
	_repath_enemy(eid)

func _advance_enemies() -> void:
	var tick_dt := 1.0 / 20.0  # seconds per tick
	for eid in enemy_paths.keys():
		var e = Simulation.state.entities.get(eid, null)
		if e == null or e.get("hp", 0) <= 0:
			enemy_paths.erase(eid)
			_move_budget.erase(eid)
			continue
		var path: Array = enemy_paths[eid]
		if path.is_empty():
			# Queue a repath instead of doing it immediately
			if eid not in _repath_queue:
				_repath_queue.append(eid)
			continue
		# Accumulate move budget based on speed (cells per second)
		var def = Registry.get_enemy_def(e.get("def_id", ""))
		var speed: float = def.get("speed", 3.0)
		var budget: float = _move_budget.get(eid, 0.0) + speed * tick_dt
		# Only move when we've accumulated enough for one cell
		if budget >= 1.0:
			budget -= 1.0
			var next_g: Vector2i = path[0]
			path.remove_at(0)
			enemy_paths[eid] = path
			var wp := grid.grid_to_world_center(next_g)
			e.pos = [wp.x, wp.y, wp.z]
		_move_budget[eid] = budget

func _repath_enemy(eid: int) -> void:
	var e = Simulation.state.entities.get(eid, null)
	if e == null:
		return
	var target_pos := _find_nearest_player_pos(e.pos)
	if target_pos == Vector3.ZERO:
		return
	var from_g := grid.world_to_grid(Vector3(e.pos[0], e.pos[1], e.pos[2]))
	var to_g := grid.world_to_grid(target_pos)
	var path := grid.find_path(from_g, to_g)
	if path.size() > 1:
		enemy_paths[eid] = path.slice(1, path.size())
	else:
		enemy_paths[eid] = []

func _find_nearest_player_pos(from_pos) -> Vector3:
	var from: Vector3
	if from_pos is Array:
		from = Vector3(from_pos[0], from_pos[1], from_pos[2])
	else:
		from = from_pos as Vector3
	var best_dist := INF
	var best_pos := Vector3.ZERO
	# Prefer structures as targets
	for eid in Simulation.state.entities.keys():
		var e = Simulation.state.entities[eid]
		var kind: String = e.get("kind", "")
		if kind == "structure" or kind == "unit":
			var p := Vector3(e.pos[0], e.pos[1], e.pos[2])
			var d := from.distance_to(p)
			if d < best_dist:
				best_dist = d
				best_pos = p
	return best_pos

func _find_any_player_position() -> Vector3:
	# Find any structure or unit to spawn near
	for eid in Simulation.state.entities.keys():
		var e = Simulation.state.entities[eid]
		var kind: String = e.get("kind", "")
		if kind == "structure":
			return Vector3(e.pos[0], e.pos[1], e.pos[2])
	# Fallback to any unit
	for eid in Simulation.state.entities.keys():
		var e = Simulation.state.entities[eid]
		if e.get("kind", "") == "unit":
			return Vector3(e.pos[0], e.pos[1], e.pos[2])
	return Vector3.ZERO

func _random_position_near(center: Vector3, min_dist: int, max_dist: int) -> Vector3:
	## Pick a random walkable position within min_dist..max_dist grid cells of center
	var center_g := grid.world_to_grid(center)
	for _attempt in range(10):
		var angle := randf() * TAU
		var dist := randi_range(min_dist, max_dist)
		var offset_x := int(cos(angle) * dist)
		var offset_z := int(sin(angle) * dist)
		var g := Vector2i(center_g.x + offset_x, center_g.y + offset_z)
		# Clamp to grid bounds
		g.x = clampi(g.x, 1, grid.grid_w - 2)
		g.y = clampi(g.y, 1, grid.grid_h - 2)
		if grid.is_occupied(g):
			continue
		var wp := grid.grid_to_world_center(g)
		# Don't spawn underwater
		if wp.y < terrain.water_level * terrain.height_scale + 1.0:
			continue
		return wp
	return Vector3.ZERO

func _count_enemies() -> int:
	var count := 0
	for eid in Simulation.state.entities.keys():
		if Simulation.state.entities[eid].get("kind", "") == "enemy":
			count += 1
	return count
