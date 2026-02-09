extends Node
## Fixed-tick deterministic-ish simulation driver.
## Recommendation: keep the simulation pure-data, and treat Nodes as views.
## This makes lockstep or host-authoritative replication much easier.

signal tick_advanced(tick: int)
signal entity_died(eid: int, pos: Vector3, def_id: String, kind: String)
signal rune_picked_up(verb_id: String)
signal weather_stepped

const TICK_RATE := 20.0 # 20Hz is a good RTS baseline
var tick: int = 0
var _accum := 0.0
var paused := false

var state := {
	"entities": {},          # entity_id -> entity_state dictionary
	"logic_networks": {},    # structure_eid -> LogicRuntime instance
	"inventory": [],         # Array of verb ID strings the player has collected
	"weather_tick": 0,       # Sub-tick counter for weather (steps every 5 sim ticks)
}

var weather_sim: WeatherSimulation
var weather_rng: RandomNumberGenerator

var _combat_system: CombatSystem

func _ready() -> void:
	_combat_system = CombatSystem.new()
	add_child(_combat_system)
	_combat_system.entity_died.connect(_on_combat_death)

	# Weather simulation
	weather_sim = WeatherSimulation.new()
	weather_sim.setup(Vector2(256.0, 256.0))
	weather_rng = RandomNumberGenerator.new()
	weather_rng.seed = 12345

func _process(delta: float) -> void:
	if paused:
		return
	_accum += delta
	var step := 1.0 / TICK_RATE
	while _accum >= step:
		_accum -= step
		_step_sim()
		tick += 1
		emit_signal("tick_advanced", tick)

func _step_sim() -> void:
	# 1) Decay temporary statuses
	for eid in state.entities.keys():
		var e = state.entities[eid]
		if e.has("status"):
			for k in e.status.keys():
				e.status[k] = max(0, e.status[k] - 1)
		# Clear actuator_firing flag each tick (views read this)
		e["actuator_firing"] = false

	# 2) Combat: auto-targeting + damage + death
	_combat_system.process_combat()

	# 3) Rune pickup: player units near dropped runes auto-collect
	_process_rune_pickups()

	# 4) Evaluate automation logic networks
	_eval_logic_networks()

	# 5) Weather: step every 5 sim ticks (= 4 Hz at 20 Hz base)
	state.weather_tick += 1
	if state.weather_tick >= 5:
		state.weather_tick = 0
		weather_sim.step(weather_rng)
		weather_stepped.emit()

func _process_rune_pickups() -> void:
	var pickup_range := 2.5
	var rune_eids: Array[int] = []
	var unit_positions: Array[Vector3] = []

	for eid in state.entities.keys():
		var e = state.entities[eid]
		if e.get("kind", "") == "rune":
			rune_eids.append(eid)
		elif e.get("kind", "") == "unit":
			unit_positions.append(Vector3(e.pos[0], e.pos[1], e.pos[2]))

	var picked_up: Array[int] = []
	for rune_eid in rune_eids:
		var re = state.entities.get(rune_eid, null)
		if re == null:
			continue
		var rp := Vector3(re.pos[0], re.pos[1], re.pos[2])
		for up in unit_positions:
			if rp.distance_to(up) < pickup_range:
				var verb_id: String = re.get("verb_id", "")
				if not verb_id.is_empty():
					state.inventory.append(verb_id)
					rune_picked_up.emit(verb_id)
				picked_up.append(rune_eid)
				break

	for eid in picked_up:
		state.entities.erase(eid)
		entity_died.emit(eid, Vector3.ZERO, "rune", "rune")

func _eval_logic_networks() -> void:
	for structure_eid in state.logic_networks.keys():
		var runtime: LogicRuntime = state.logic_networks[structure_eid]
		if runtime == null:
			continue
		# Check structure still exists
		if not state.entities.has(structure_eid):
			continue
		runtime.tick_evaluate(structure_eid)
		# Apply actuator events
		for event in runtime.events:
			_apply_actuator_event(event)

func _apply_actuator_event(event: Dictionary) -> void:
	var owner_id: int = event.get("owner_id", -1)
	var event_type: String = event.get("type", "")
	var owner_e = state.entities.get(owner_id, null)
	if owner_e == null:
		return
	var owner_pos := Vector3(owner_e.pos[0], owner_e.pos[1], owner_e.pos[2])

	match event_type:
		"actuator_sprayer":
			# Deal damage to all enemies within range 6
			for eid in state.entities.keys():
				var e = state.entities[eid]
				if e.get("kind", "") != "enemy":
					continue
				var ep := Vector3(e.pos[0], e.pos[1], e.pos[2])
				if owner_pos.distance_to(ep) <= 6.0:
					e["hp"] = e.get("hp", 0) - 10
			owner_e["actuator_firing"] = true
		"actuator_valve":
			# Heal owner structure by 2 HP per tick
			var def := Registry.get_any_def(owner_e.def_id)
			var max_hp: int = def.get("hp", 100)
			owner_e["hp"] = mini(owner_e.get("hp", 0) + 2, max_hp)
			owner_e["actuator_firing"] = true
		"actuator_shutter":
			owner_e["actuator_firing"] = true

func _on_combat_death(eid: int, pos: Vector3, def_id: String, kind: String) -> void:
	# When an enemy dies, spawn a verb rune drop
	if kind == "enemy":
		var def := Registry.get_enemy_def(def_id)
		var drops: Array = def.get("drops", [])
		if drops.size() > 0:
			var verb_id: String = drops[randi() % drops.size()]
			var rune_eid := spawn_entity("rune_drop", pos, -1)
			var rune_e = state.entities[rune_eid]
			rune_e["kind"] = "rune"
			rune_e["verb_id"] = verb_id
			rune_e["def_id"] = "rune_drop"
	entity_died.emit(eid, pos, def_id, kind)

func spawn_entity(def_id: String, pos: Vector3, owner: int) -> int:
	var eid := _new_entity_id()
	var def = Registry.get_unit_def(def_id)
	if def.is_empty():
		def = Registry.get_enemy_def(def_id)
	if def.is_empty():
		def = Registry.get_structure_def(def_id)
	state.entities[eid] = {
		"def_id": def_id,
		"owner": owner,
		"pos": [pos.x, pos.y, pos.z],
		"hp": def.get("hp", 100),
		"status": {}
	}
	return eid

var _next_entity_id: int = 1

func _new_entity_id() -> int:
	var eid = _next_entity_id
	_next_entity_id += 1
	return eid

func sync_entity_id_counter() -> void:
	var max_id := 0
	for eid in state.entities.keys():
		var eid_int := int(eid)
		if eid_int > max_id:
			max_id = eid_int
	_next_entity_id = max_id + 1
