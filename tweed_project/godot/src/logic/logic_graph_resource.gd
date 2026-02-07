extends Resource
class_name LogicGraphResource
## Data model for a "redstone gone wild" network.
## Graph is stored as nodes + edges, fully serializable.

@export var nodes: Array[Dictionary] = [] # {id:int, kind:String, def_id:String, pos:Vector2, verb_slots:Array}
@export var edges: Array[Dictionary] = [] # {from:int, from_port:String, to:int, to_port:String}

func add_node(kind: String, def_id: String, pos: Vector2) -> int:
	var nid: int = (int(nodes[-1].id) + 1) if nodes.size() > 0 else 1
	nodes.append({"id": nid, "kind": kind, "def_id": def_id, "pos": pos, "verb_slots": []})
	return nid

func connect_nodes(from_id: int, from_port: String, to_id: int, to_port: String) -> void:
	edges.append({"from": from_id, "from_port": from_port, "to": to_id, "to_port": to_port})
