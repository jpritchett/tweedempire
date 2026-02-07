extends RefCounted
class_name LogicRuntime
## Evaluates a LogicGraphResource each tick.
## Processes: sensors → logic (with verb effects) → actuators.
## Signal propagation follows graph edges.

var graph: LogicGraphResource
var values := {} # node_id -> port -> value
var events: Array = [] # queued output events from actuators
var _throttle_ticks := {} # node_id -> last_fire_tick
var _delay_buffer := {} # node_id -> previous_value

func set_graph(g: LogicGraphResource) -> void:
	graph = g
	values.clear()
	events.clear()
	_throttle_ticks.clear()
	_delay_buffer.clear()

func tick_evaluate(owner_id: int) -> void:
	if graph == null:
		return
	events.clear()

	# Evaluate in order: sensors, then logic, then actuators
	# Propagate values along edges after each node evaluates
	var sensors: Array[Dictionary] = []
	var logics: Array[Dictionary] = []
	var actuators: Array[Dictionary] = []

	for n in graph.nodes:
		match n.get("kind", ""):
			"sensor":
				sensors.append(n)
			"logic":
				logics.append(n)
			"actuator":
				actuators.append(n)

	for n in sensors:
		_eval_sensor(n, owner_id)
		_propagate_outputs(n)

	for n in logics:
		_propagate_inputs(n)
		_eval_logic(n)
		_propagate_outputs(n)

	for n in actuators:
		_propagate_inputs(n)
		_eval_actuator(n, owner_id)

func _get_val(nid: int, port: String, default_val = 0):
	return values.get(nid, {}).get(port, default_val)

func _set_val(nid: int, port: String, v) -> void:
	if not values.has(nid):
		values[nid] = {}
	values[nid][port] = v

func _propagate_outputs(n: Dictionary) -> void:
	## Copy this node's output values to connected downstream input ports
	var nid: int = n.id
	for edge in graph.edges:
		if edge.from == nid:
			var val = _get_val(nid, edge.from_port, 0)
			_set_val(edge.to, edge.to_port, val)

func _propagate_inputs(n: Dictionary) -> void:
	## Ensure input ports have values from upstream edges
	var nid: int = n.id
	for edge in graph.edges:
		if edge.to == nid:
			var val = _get_val(edge.from, edge.from_port, 0)
			_set_val(nid, edge.to_port, val)

# ─── Sensor evaluation ─────────────────────────────────────────────────────────

func _eval_sensor(n: Dictionary, owner_id: int) -> void:
	var nid: int = n.id
	var def_id: String = n.get("def_id", "")

	match def_id:
		"sensor_spores":
			# Count enemy entities within range of owner structure
			var count := _count_enemies_near_owner(owner_id, 9.0)
			_set_val(nid, "spores", count)
		"sensor_moisture":
			# Placeholder: return a moderate constant
			_set_val(nid, "moisture", 50)
		_:
			_set_val(nid, "out", 0)

func _count_enemies_near_owner(owner_id: int, radius: float) -> int:
	var owner_e = Simulation.state.entities.get(owner_id, null)
	if owner_e == null:
		return 0
	var owner_pos := Vector3(owner_e.pos[0], owner_e.pos[1], owner_e.pos[2])
	var count := 0
	for eid in Simulation.state.entities.keys():
		var e = Simulation.state.entities[eid]
		if e.get("kind", "") != "enemy":
			continue
		var ep := Vector3(e.pos[0], e.pos[1], e.pos[2])
		if owner_pos.distance_to(ep) <= radius:
			count += 1
	return count

# ─── Logic evaluation with verb effects ────────────────────────────────────────

func _eval_logic(n: Dictionary) -> void:
	var nid: int = n.id
	var input_a = _get_val(nid, "a", 0)
	var input_b = _get_val(nid, "b", 0)
	var verb_slots: Array = n.get("verb_slots", [])

	var result = input_a  # Default: pass-through

	if verb_slots.is_empty():
		# No verbs: pass-through
		_set_val(nid, "out", result)
		return

	# Apply first verb (primary effect)
	var verb_id: String = verb_slots[0] if verb_slots.size() > 0 else ""
	result = _apply_verb(nid, verb_id, input_a, input_b)

	# Apply second verb if present (modifier)
	if verb_slots.size() > 1 and verb_slots[1] != "":
		var second_verb: String = verb_slots[1]
		result = _apply_verb_modifier(nid, second_verb, result)

	_set_val(nid, "out", result)

func _apply_verb(nid: int, verb_id: String, a, b) -> int:
	match verb_id:
		"IF":
			return a if a > 0 else 0
		"FILTER":
			return a if a > 2 else 0  # threshold: more than 2 enemies triggers
		"NOT":
			return 1 if a == 0 else 0
		"AND":
			return 1 if a > 0 and b > 0 else 0
		"OR":
			return 1 if a > 0 or b > 0 else 0
		"ROUTE":
			return a
		"QUEUE":
			return a
		"RETRY":
			return a
		"BROADCAST":
			return a
		"FAILSAFE":
			return 1 if a <= 0 else a
		_:
			return a

func _apply_verb_modifier(nid: int, verb_id: String, value: int) -> int:
	match verb_id:
		"THROTTLE":
			var last_tick: int = _throttle_ticks.get(nid, -100)
			if Simulation.tick - last_tick < 40:  # 2 second minimum interval
				return 0
			if value > 0:
				_throttle_ticks[nid] = Simulation.tick
			return value
		"DELAY":
			var prev = _delay_buffer.get(nid, 0)
			_delay_buffer[nid] = value
			return prev
		"NOT":
			return 1 if value == 0 else 0
		_:
			return value

# ─── Actuator evaluation ──────────────────────────────────────────────────────

func _eval_actuator(n: Dictionary, owner_id: int) -> void:
	var nid: int = n.id
	var def_id: String = n.get("def_id", "")
	var input_port := "open"

	match def_id:
		"actuator_sprayer":
			input_port = "spray"
		"actuator_valve":
			input_port = "open"
		"actuator_shutter":
			input_port = "toggle"

	var signal_val = _get_val(nid, input_port, 0)

	if signal_val > 0:
		events.append({
			"type": def_id,
			"owner_id": owner_id,
			"value": signal_val
		})
