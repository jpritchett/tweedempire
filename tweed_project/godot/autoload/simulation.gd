extends Node
## Fixed-tick deterministic-ish simulation driver.
## Recommendation: keep the simulation pure-data, and treat Nodes as views.
## This makes lockstep or host-authoritative replication much easier.

signal tick_advanced(tick: int)

const TICK_RATE := 20.0 # 20Hz is a good RTS baseline
var tick: int = 0
var _accum := 0.0
var paused := false

# The simulation state is stored in a Dictionary for the prototype.
# In production, you'll likely use custom classes/resources for speed.
var state := {
	"entities": {}, # entity_id -> entity_state dictionary
	"logic_networks": {} # owner_id -> LogicGraphResource (serialized)
}

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
	# 1) Apply queued commands (from player inputs)
	# 2) Advance entity movement/production/combat
	# 3) Evaluate automation networks (event-driven when possible)
	# This prototype keeps things minimal and easy to inspect.
	for eid in state.entities.keys():
		var e = state.entities[eid]
		# Example: decay temporary statuses
		if e.has("status"):
			for k in e.status.keys():
				e.status[k] = max(0, e.status[k] - 1)

func spawn_entity(def_id: String, pos: Vector3, owner: int) -> int:
	var eid := _new_entity_id()
	var def = Registry.get_unit_def(def_id)
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
	# Simple monotonic id. In lockstep, all peers must generate IDs the same way.
	# For lockstep, have host allocate IDs or use deterministic allocation rules.
	var eid = _next_entity_id
	_next_entity_id += 1
	return eid

func sync_entity_id_counter() -> void:
	# Call this after loading or replacing state.entities to prevent ID collisions.
	# Sets _next_entity_id to max existing ID + 1.
	# Convert keys to int to handle JSON deserialization which stringifies numeric keys.
	var max_id := 0
	for eid in state.entities.keys():
		var eid_int := int(eid)
		if eid_int > max_id:
			max_id = eid_int
	_next_entity_id = max_id + 1
