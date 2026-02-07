extends Node
class_name LogicRuntime
## Evaluates a LogicGraphResource.
## Keep evaluation simple: process sensors -> logic -> actuators each tick,
## and support event queues for bursty networks.

var graph: LogicGraphResource
var values := {} # node_id -> port -> value
var events: Array = [] # queued events

func set_graph(g: LogicGraphResource) -> void:
	graph = g
	values.clear()
	events.clear()

func tick_evaluate(owner_id: int) -> void:
	if graph == null:
		return
	# Prototype evaluation: iterate nodes in insertion order.
	# Production: topological order + cycle handling (LOOP/DELAY blocks).
	for n in graph.nodes:
		match n.get("kind",""):
			"sensor":
				_eval_sensor(n, owner_id)
			"logic":
				_eval_logic(n)
			"actuator":
				_eval_actuator(n, owner_id)

func _get(nid: int, port: String, default_val=null):
	return values.get(nid, {}).get(port, default_val)

func _set(nid: int, port: String, v) -> void:
	if not values.has(nid):
		values[nid] = {}
	values[nid][port] = v

func _eval_sensor(n: Dictionary, owner_id: int) -> void:
	# TODO: sample from Simulation state/world spatial index.
	# Placeholder: emit random-ish spores value.
	var nid = n.id
	var spores := int((owner_id * 37 + Simulation.tick) % 100)
	_set(nid, "spores", spores)

func _eval_logic(n: Dictionary) -> void:
	var nid = n.id
	# Placeholder: pass-through "a"
	var a = _get(nid, "a", 0)
	_set(nid, "out", a)

func _eval_actuator(n: Dictionary, owner_id: int) -> void:
	# TODO: apply actions back into Simulation (e.g., open valve, spray disinfectant)
	pass
