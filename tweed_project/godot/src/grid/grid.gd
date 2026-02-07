extends Node
class_name HiddenGrid

## Hidden logical grid over the heightmapped terrain.
## Provides:
## - world <-> grid mapping
## - occupancy tracking (for buildings)
## - A* pathfinding (slope-aware)

@export var cell_size: float = 1.0
@export var grid_w: int = 64
@export var grid_h: int = 64

@export var allow_diagonal: bool = true
@export var max_slope: float = 2.5 # max delta Y between adjacent cells (world units)
@export var slope_cost: float = 2.0 # extra cost per unit of height delta

var occupied := {} # key "x,z" -> true
var terrain: HeightmapTerrain

func init_for_terrain(t: HeightmapTerrain) -> void:
	terrain = t
	grid_w = int(round(t.size_x / cell_size))
	grid_h = int(round(t.size_z / cell_size))
	occupied.clear()

func world_to_grid(p: Vector3) -> Vector2i:
	var gx := int(floor(p.x / cell_size))
	var gz := int(floor(p.z / cell_size))
	return Vector2i(clamp(gx, 0, grid_w-1), clamp(gz, 0, grid_h-1))

func grid_to_world_center(g: Vector2i) -> Vector3:
	var wx := (float(g.x) + 0.5) * cell_size
	var wz := (float(g.y) + 0.5) * cell_size
	var wy := terrain.sample_height_world(wx, wz) if terrain != null else 0.0
	return Vector3(wx, wy, wz)

func key(g: Vector2i) -> String:
	return "%d,%d" % [g.x, g.y]

func is_occupied(g: Vector2i) -> bool:
	return occupied.has(key(g))

func set_occupied(g: Vector2i, v: bool) -> void:
	var k = key(g)
	if v:
		occupied[k] = true
	else:
		occupied.erase(k)

func footprint_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dz in range(size.y):
		for dx in range(size.x):
			cells.append(Vector2i(origin.x + dx, origin.y + dz))
	return cells

func can_place(origin: Vector2i, size: Vector2i) -> bool:
	for c in footprint_cells(origin, size):
		if c.x < 0 or c.y < 0 or c.x >= grid_w or c.y >= grid_h:
			return false
		if is_occupied(c):
			return false
	return true

func place(origin: Vector2i, size: Vector2i) -> void:
	for c in footprint_cells(origin, size):
		set_occupied(c, true)

func unplace(origin: Vector2i, size: Vector2i) -> void:
	for c in footprint_cells(origin, size):
		set_occupied(c, false)

func _neighbors(g: Vector2i) -> Array[Vector2i]:
	var n: Array[Vector2i] = []
	var dirs = [
		Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)
	]
	if allow_diagonal:
		dirs.append_array([Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)])
	for d in dirs:
		var p = g + d
		if p.x < 0 or p.y < 0 or p.x >= grid_w or p.y >= grid_h:
			continue
		n.append(p)
	return n

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Octile distance for diagonal movement
	var dx: int = absi(a.x - b.x)
	var dz: int = absi(a.y - b.y)
	if allow_diagonal:
		return (max(dx, dz) + (sqrt(2.0) - 1.0) * min(dx, dz))
	return float(dx + dz)

func _height_at(g: Vector2i) -> float:
	if terrain == null:
		return 0.0
	var wp = grid_to_world_center(g)
	return wp.y

func _move_cost(a: Vector2i, b: Vector2i) -> float:
	var base := 1.0
	# Diagonal move cost
	if a.x != b.x and a.y != b.y:
		base = sqrt(2.0)
	var dy: float = absf(_height_at(a) - _height_at(b))
	if dy > max_slope:
		return INF
	return base + dy * slope_cost

func find_path(from_g: Vector2i, to_g: Vector2i) -> Array[Vector2i]:
	# A* with slope-aware costs and occupancy avoidance
	if from_g == to_g:
		return [from_g]
	if is_occupied(to_g):
		# Can't path into occupied destination
		return []

	var open := {} # key -> fscore
	var open_list: Array[Vector2i] = []
	var came_from := {} # key -> parent key
	var g_score := {}
	var f_score := {}

	var start_k = key(from_g)
	g_score[start_k] = 0.0
	f_score[start_k] = _heuristic(from_g, to_g)
	open[start_k] = f_score[start_k]
	open_list.append(from_g)

	var guard := 0
	while open_list.size() > 0 and guard < 80000:
		guard += 1
		# Pick node in open_list with lowest f
		var best_i := 0
		var best_f := INF
		for i in range(open_list.size()):
			var k = key(open_list[i])
			var f = float(open.get(k, INF))
			if f < best_f:
				best_f = f
				best_i = i
		var current: Vector2i = open_list[best_i]
		var current_k = key(current)
		open_list.remove_at(best_i)
		open.erase(current_k)

		if current == to_g:
			return _reconstruct_path(came_from, current)

		for nb in _neighbors(current):
			if is_occupied(nb):
				continue
			var step_cost := _move_cost(current, nb)
			if step_cost == INF:
				continue
			var tentative := float(g_score.get(current_k, INF)) + step_cost
			var nb_k = key(nb)
			if tentative < float(g_score.get(nb_k, INF)):
				came_from[nb_k] = current
				g_score[nb_k] = tentative
				var fnew := tentative + _heuristic(nb, to_g)
				f_score[nb_k] = fnew
				if not open.has(nb_k):
					open[nb_k] = fnew
					open_list.append(nb)

	return []

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	var ck = key(current)
	while came_from.has(ck):
		current = came_from[ck]
		ck = key(current)
		path.append(current)
	path.reverse()
	return path
