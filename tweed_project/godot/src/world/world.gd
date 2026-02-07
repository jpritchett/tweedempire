extends Node3D

@onready var unit_root: Node3D = $UnitRoot
@onready var cam_rig = $CameraRig
@onready var cam: Camera3D = cam_rig.get_camera()
@onready var sun: DirectionalLight3D = $DirectionalLight3D

var unit_scene := preload("res://scenes/unit_view.tscn")
var structure_scene := preload("res://scenes/structure_view.tscn")
var ghost_scene := preload("res://scenes/build_ghost.tscn")
var enemy_scene := preload("res://scenes/enemy_view.tscn")
var rune_scene := preload("res://scenes/rune_view.tscn")

var terrain: HeightmapTerrain
var grid: HiddenGrid
var ghost: Node3D
var sky_controller: SkyController
var enemy_spawner: EnemySpawner
var inventory_hud: InventoryHUD

# entity_id -> view node
var views := {}
# entity_id -> queued path (grid cells)
var paths := {}

var selected_eid: int = -1

var build_mode := false
var build_def := "patchbay_relay"
var build_footprint := Vector2i(2,2)
var _last_zoom_t := -1.0

# Follow mode: camera tracks an enemy entity
var _follow_eid: int = -1
var _follow_zoom: float = 25.0  # Close zoom when following

func _ready() -> void:
	# Create terrain with UK-inspired heightmap
	terrain = HeightmapTerrain.new()
	terrain.use_uk_terrain = true
	terrain.uk_preset = "peak_district"
	terrain.uk_seed = 42
	terrain.use_terrain_shader = true
	terrain.size_x = 256.0
	terrain.size_z = 256.0
	terrain.height_scale = 25.0
	terrain.subdivisions_x = 511
	terrain.subdivisions_z = 511
	add_child(terrain)

	# Scatter vegetation across terrain biome zones
	var vegetation := TerrainVegetation.new()
	vegetation.terrain = terrain
	add_child(vegetation)

	_setup_environment()

	# Hidden grid
	grid = HiddenGrid.new()
	grid.cell_size = 1.0
	grid.init_for_terrain(terrain)
	add_child(grid)
	cam_rig.configure(terrain.world_bounds(), grid.cell_size, terrain)
	# Start with a closer view
	cam_rig._target_zoom = 60.0
	cam_rig._zoom = 60.0
	cam_rig._default_zoom = 60.0
	_setup_light()

	# Spawn test entities (units) - cycle through tank types
	if Net.mode == Net.NetMode.OFFLINE:
		var tank_types = ["t90_tank", "m1_abrams", "challenger2"]
		for i in range(6):
			var spawn_pos = grid.grid_to_world_center(Vector2i(120 + i*2, 128))
			var tank_type = tank_types[i % tank_types.size()]
			var eid = Simulation.spawn_entity(tank_type, spawn_pos, 0)
			Simulation.state.entities[eid]["kind"] = "unit"
			Simulation.state.entities[eid]["attack_cooldown_current"] = 0
			Simulation.state.entities[eid]["attack_target"] = -1
			_spawn_view(eid)

	# Setup enemy spawner
	enemy_spawner = EnemySpawner.new()
	enemy_spawner.grid = grid
	enemy_spawner.terrain = terrain
	add_child(enemy_spawner)

	# Setup inventory HUD
	inventory_hud = InventoryHUD.new()
	add_child(inventory_hud)

	# Connect simulation signals
	Simulation.tick_advanced.connect(_on_tick)
	Simulation.entity_died.connect(_on_entity_died)
	Simulation.rune_picked_up.connect(_on_rune_picked_up)

func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()

	# Load the procedural sky shader
	var sky_shader := load("res://src/sky/sky_shader.gdshader")
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader

	# Set sky shader uniforms (can be tuned in code or exposed via SkyController)
	sky_mat.set_shader_parameter("day_top_color", Color(0.2, 0.4, 0.8))
	sky_mat.set_shader_parameter("day_horizon_color", Color(0.6, 0.75, 0.9))
	sky_mat.set_shader_parameter("night_top_color", Color(0.02, 0.02, 0.06))
	sky_mat.set_shader_parameter("night_horizon_color", Color(0.05, 0.05, 0.1))
	sky_mat.set_shader_parameter("sunset_color", Color(1.0, 0.4, 0.1))
	sky_mat.set_shader_parameter("cloud_speed", 0.01)
	sky_mat.set_shader_parameter("cloud_density", 0.5)
	sky_mat.set_shader_parameter("cloud_scale", 3.0)
	sky_mat.set_shader_parameter("cloud_octaves", 5)
	sky_mat.set_shader_parameter("star_density", 800.0)

	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME  # Enable TIME updates for animation

	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 2.0
	env.tonemap_exposure = 1.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_node.environment = env
	add_child(env_node)

func _setup_light() -> void:
	# Position sun at terrain center (the sky controller will handle rotation)
	var center = Vector3(terrain.size_x * 0.5, 0.0, terrain.size_z * 0.5)
	sun.global_position = center + Vector3(0.0, 100.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 2.5
	sun.shadow_bias = 0.05

	# Setup sky controller for day/night cycle
	sky_controller = SkyController.new()
	sky_controller.sun = sun
	sky_controller.noon_energy = 2.5
	sky_controller.cycle_duration = 10.0
	sky_controller.time_of_day = 0.5  # Midday
	sky_controller.cycle_enabled = false
	add_child(sky_controller)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			_toggle_build_mode()
		elif event.keycode == KEY_ESCAPE:
			_exit_follow_mode()
		elif event.keycode == KEY_R:
			_socket_verb_into_structure()
		elif event.keycode == KEY_L:
			_inspect_logic_graph()
		# Shift+1/2/3: structure selection in build mode
		elif event.shift_pressed and event.keycode == KEY_1:
			_set_build_def("patchbay_relay")
		elif event.shift_pressed and event.keycode == KEY_2:
			_set_build_def("loomcore_hub")
		elif event.shift_pressed and event.keycode == KEY_3:
			_set_build_def("irrigation_manifold")
		# 1-9: follow nth enemy
		elif not event.shift_pressed and not event.ctrl_pressed:
			var num := _number_key(event.keycode)
			if num >= 1 and num <= 9:
				_follow_enemy(num)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click()

func _set_build_def(def_id: String) -> void:
	build_def = def_id
	var sdef = Registry.get_structure_def(def_id)
	if sdef.size() > 0:
		build_footprint = Vector2i(int(sdef.get("footprint",[2,2])[0]), int(sdef.get("footprint",[2,2])[1]))
	if build_mode and ghost != null:
		ghost.footprint = build_footprint
		ghost.cell_size = grid.cell_size
		ghost.set_size_from_footprint()

func _toggle_build_mode() -> void:
	build_mode = not build_mode
	if build_mode:
		ghost = ghost_scene.instantiate()
		add_child(ghost)
		ghost.footprint = build_footprint
		ghost.cell_size = grid.cell_size
		ghost.set_size_from_footprint()
	else:
		if ghost != null:
			ghost.queue_free()
			ghost = null

func _process(_delta: float) -> void:
	# Follow mode: keep camera locked on the followed entity
	if _follow_eid != -1:
		var fe = Simulation.state.entities.get(_follow_eid, null)
		if fe == null:
			_exit_follow_mode()
		else:
			var fp := Vector3(fe.pos[0], fe.pos[1], fe.pos[2])
			cam_rig.set_focus(fp)

	if build_mode and ghost != null:
		var hit = _ray_pick_terrain()
		if hit.has("position"):
			var p: Vector3 = hit.position
			var g = grid.world_to_grid(p)
			var origin = Vector2i(g.x, g.y)
			var center = grid.grid_to_world_center(Vector2i(origin.x + build_footprint.x/2.0, origin.y + build_footprint.y/2))
			ghost.global_position = Vector3(center.x, center.y + 0.15, center.z)
			ghost.set_valid(grid.can_place(origin, build_footprint))
	var zoom_t = cam_rig.get_zoom_t()
	if abs(zoom_t - _last_zoom_t) > 0.01:
		for eid in views.keys():
			var v = views[eid]
			if v != null and v.is_node_ready():
				v.set_zoom_lod(zoom_t)
		_last_zoom_t = zoom_t

func _on_left_click() -> void:
	if build_mode:
		_try_place_building()
		return
	var hit = _ray_pick_terrain()
	if not hit.has("position"):
		return
	var p: Vector3 = hit.position
	var zoom_t = cam_rig.get_zoom_t()
	var select_radius = lerp(1.8, 6.0, zoom_t)
	selected_eid = _find_nearest_entity(p, select_radius)
	_update_selection_ui()

func _on_right_click() -> void:
	if selected_eid == -1:
		return
	var e = Simulation.state.entities.get(selected_eid, null)
	if e == null:
		selected_eid = -1
		_update_selection_ui()
		return
	if e.get("kind","unit") != "unit":
		return

	var hit = _ray_pick_terrain()
	if not hit.has("position"):
		return
	var p: Vector3 = hit.position
	var to_g = grid.world_to_grid(p)
	var from_p = e.pos
	var from_g = grid.world_to_grid(Vector3(from_p[0], from_p[1], from_p[2]))
	var path = grid.find_path(from_g, to_g)
	if path.size() == 0:
		return
	# Store path excluding current cell
	paths[selected_eid] = path.slice(1, path.size())

func _try_place_building() -> void:
	var sdef = Registry.get_structure_def(build_def)
	if sdef.size() == 0:
		return
	var hit = _ray_pick_terrain()
	if not hit.has("position"):
		return
	var p: Vector3 = hit.position
	var g = grid.world_to_grid(p)
	var origin = Vector2i(g.x, g.y)
	if not grid.can_place(origin, build_footprint):
		return
	grid.place(origin, build_footprint)

	var center = grid.grid_to_world_center(Vector2i(origin.x + build_footprint.x/2, origin.y + build_footprint.y/2))
	var eid = Simulation.spawn_entity(build_def, center, 0)
	Simulation.state.entities[eid]["kind"] = "structure"
	Simulation.state.entities[eid]["footprint"] = [build_footprint.x, build_footprint.y]
	Simulation.state.entities[eid]["grid_origin"] = [origin.x, origin.y]

	# Auto-create default logic graph for this structure
	_create_default_logic_graph(eid)

	_spawn_view(eid)

func _create_default_logic_graph(eid: int) -> void:
	## Creates a default sensor -> logic -> actuator graph for a new structure
	var graph := LogicGraphResource.new()

	# Add sensor (spore detector)
	var sensor_id := graph.add_node("sensor", "sensor_spores", Vector2(0, 0))
	# Add logic tile (empty verb slots — player sockets verbs later)
	var logic_id := graph.add_node("logic", "logic_tile", Vector2(1, 0))
	# Add actuator (sprayer)
	var actuator_id := graph.add_node("actuator", "actuator_sprayer", Vector2(2, 0))

	# Connect sensor -> logic -> actuator
	graph.connect_nodes(sensor_id, "spores", logic_id, "a")
	graph.connect_nodes(logic_id, "out", actuator_id, "spray")

	# Create runtime and register
	var runtime := LogicRuntime.new()
	runtime.set_graph(graph)
	Simulation.state.logic_networks[eid] = runtime

	# Store graph reference on entity
	Simulation.state.entities[eid]["logic_graph"] = graph
	Simulation.state.entities[eid]["verb_slots"] = ["", ""]

func _socket_verb_into_structure() -> void:
	## R key: socket next inventory verb into selected structure's first empty slot
	if selected_eid == -1:
		return
	var e = Simulation.state.entities.get(selected_eid, null)
	if e == null or e.get("kind", "") != "structure":
		print("[World] Select a structure first (R to socket verb)")
		return

	var inv: Array = Simulation.state.inventory
	if inv.is_empty():
		print("[World] No verbs in inventory to socket")
		return

	var slots: Array = e.get("verb_slots", [])
	var empty_idx := -1
	for i in range(slots.size()):
		if slots[i] == "":
			empty_idx = i
			break

	if empty_idx == -1:
		print("[World] All verb slots are full on this structure")
		return

	# Take the first verb from inventory
	var verb_id: String = inv[0]
	inv.remove_at(0)

	# Socket it
	slots[empty_idx] = verb_id
	e["verb_slots"] = slots

	# Update the logic graph node's verb_slots
	var graph: LogicGraphResource = e.get("logic_graph", null)
	if graph != null:
		for n in graph.nodes:
			if n.get("kind", "") == "logic":
				n["verb_slots"] = slots.duplicate()
				break
		# Re-set graph on runtime to apply changes
		var runtime = Simulation.state.logic_networks.get(selected_eid, null)
		if runtime != null:
			runtime.set_graph(graph)

	print("[World] Socketed '%s' into slot %d of %s" % [verb_id, empty_idx, e.def_id])
	# Refresh HUD
	if inventory_hud != null:
		inventory_hud._rebuild()

func _inspect_logic_graph() -> void:
	## L key: print logic graph info for selected structure
	if selected_eid == -1:
		return
	var e = Simulation.state.entities.get(selected_eid, null)
	if e == null or e.get("kind", "") != "structure":
		print("[World] Select a structure to inspect (L key)")
		return

	var graph: LogicGraphResource = e.get("logic_graph", null)
	if graph == null:
		print("[World] No logic graph on this structure")
		return

	print("=== Logic Graph for %s (eid %d) ===" % [e.def_id, selected_eid])
	print("Verb slots: %s" % str(e.get("verb_slots", [])))
	for n in graph.nodes:
		print("  Node %d: %s (%s) verbs=%s" % [n.id, n.kind, n.def_id, str(n.get("verb_slots", []))])
	for edge in graph.edges:
		print("  Edge: %d.%s -> %d.%s" % [edge.from, edge.from_port, edge.to, edge.to_port])

	var runtime = Simulation.state.logic_networks.get(selected_eid, null)
	if runtime != null:
		print("  Runtime values: %s" % str(runtime.values))
		print("  Last events: %s" % str(runtime.events))

func _number_key(keycode: int) -> int:
	## Returns 1-9 for KEY_1..KEY_9, or 0 if not a number key
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1 + 1
	return 0

func _follow_enemy(index: int) -> void:
	## Follow the nth enemy entity (1-indexed)
	var enemies: Array[int] = []
	for eid in Simulation.state.entities.keys():
		if Simulation.state.entities[eid].get("kind", "") == "enemy":
			enemies.append(eid)
	enemies.sort()
	if index > enemies.size():
		print("[World] No enemy #%d (only %d enemies)" % [index, enemies.size()])
		return
	_follow_eid = enemies[index - 1]
	cam_rig._target_zoom = _follow_zoom
	print("[World] Following enemy #%d (eid %d)" % [index, _follow_eid])

func _exit_follow_mode() -> void:
	if _follow_eid != -1:
		_follow_eid = -1
		cam_rig._target_zoom = cam_rig._default_zoom
		print("[World] Exited follow mode")

func _ray_pick_terrain() -> Dictionary:
	return cam_rig.screen_to_ground(get_viewport().get_mouse_position())

func _find_nearest_entity(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d := radius
	for eid in Simulation.state.entities.keys():
		var e = Simulation.state.entities[eid]
		var p = e.pos
		var v = Vector3(p[0], p[1], p[2])
		var d = v.distance_to(pos)
		if d < best_d:
			best_d = d
			best = eid
	return best

func _update_selection_ui() -> void:
	for eid in views.keys():
		if views[eid] != null and is_instance_valid(views[eid]):
			views[eid].set_selected(eid == selected_eid)

func _on_entity_died(eid: int, pos: Vector3, _def_id: String, _kind: String) -> void:
	# Play death animation on view if it exists
	var v = views.get(eid, null)
	if v != null and is_instance_valid(v):
		if v.has_method("play_death"):
			v.play_death()
			# Remove from views dict — the view will queue_free itself after animation
			views.erase(eid)
		else:
			v.queue_free()
			views.erase(eid)
	paths.erase(eid)

func _on_rune_picked_up(verb_id: String) -> void:
	print("[World] Picked up verb rune: %s" % verb_id)

func _on_tick(_t: int) -> void:
	# Move units along stored paths (simple snap step per tick)
	for eid in paths.keys():
		var q: Array = paths[eid]
		if q.size() == 0:
			continue
		var next_g: Vector2i = q[0]
		q.remove_at(0)
		paths[eid] = q
		var wp = grid.grid_to_world_center(next_g)
		var e = Simulation.state.entities.get(eid, null)
		if e == null:
			paths.erase(eid)
			continue
		e.pos = [wp.x, wp.y, wp.z]

	# Remove views for deleted entities (that weren't caught by entity_died signal)
	for eid in views.keys():
		if not Simulation.state.entities.has(eid):
			if views[eid] != null and is_instance_valid(views[eid]):
				views[eid].queue_free()
			views.erase(eid)
			paths.erase(eid)

	# Sync views — spawn for new entities, update positions
	for eid in Simulation.state.entities.keys():
		if not views.has(eid):
			_spawn_view(eid)
		var e = Simulation.state.entities.get(eid, null)
		if e == null:
			continue
		var v = views.get(eid, null)
		if v == null or not is_instance_valid(v):
			continue
		var p = e.pos
		v.global_position = Vector3(p[0], p[1], p[2])
		v.set_label(e.def_id)

		# Update enemy-specific visuals
		var kind: String = e.get("kind", "")
		if kind == "enemy" and v.has_method("update_hp"):
			v.update_hp(e.get("hp", 0))
			# Flash on damage
			if e.get("last_hit_tick", -1) == Simulation.tick and v.has_method("flash_damage"):
				v.flash_damage()

		# Update structure actuator visual feedback
		if kind == "structure" and v.has_method("set_actuator_state"):
			var firing: bool = e.get("actuator_firing", false)
			var has_graph: bool = Simulation.state.logic_networks.has(eid)
			v.set_actuator_state(has_graph, firing)

func _spawn_view(eid: int) -> void:
	var e = Simulation.state.entities[eid]
	var kind = e.get("kind", "unit")
	var v
	match kind:
		"structure":
			v = structure_scene.instantiate()
			var fp = e.get("footprint", [2,2])
			v.call_deferred("set_size", float(fp[0]) * grid.cell_size, float(fp[1]) * grid.cell_size)
		"enemy":
			v = enemy_scene.instantiate()
		"rune":
			v = rune_scene.instantiate()
		_:
			v = unit_scene.instantiate()
	unit_root.add_child(v)
	views[eid] = v

	# Kind-specific setup after adding to tree
	match kind:
		"enemy":
			var def := Registry.get_enemy_def(e.def_id)
			var max_hp: int = def.get("hp", 100)
			if v.has_method("set_max_hp"):
				v.set_max_hp(max_hp)
				v.update_hp(e.get("hp", max_hp))
		"rune":
			if v.has_method("set_verb"):
				v.set_verb(e.get("verb_id", ""))
		"unit":
			var unit_def = Registry.get_unit_def(e.def_id)
			var model_path = unit_def.get("model", "")
			if not model_path.is_empty():
				v.set_model(model_path)

	# Apply zoom LOD after setup
	v.call_deferred("set_zoom_lod", cam_rig.get_zoom_t())
