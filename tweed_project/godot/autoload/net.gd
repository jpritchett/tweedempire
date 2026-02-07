extends Node
## Networking options:
## A) Host-authoritative: server simulates, clients send commands; server replicates snapshots/deltas.
## B) Lockstep: all peers simulate; exchange only inputs; requires determinism + sync checks.
##
## For this prototype we implement host-authoritative (simpler to ship), and leave hooks for lockstep.

enum NetMode { OFFLINE, HOST, CLIENT }
var mode: int = NetMode.OFFLINE

const DEFAULT_PORT := 24567
var peer: MultiplayerPeer

# Command queue from clients -> host.
var _pending_commands: Array = []

func host_game(port: int = DEFAULT_PORT) -> void:
	var p := ENetMultiplayerPeer.new()
	p.create_server(port)
	peer = p
	multiplayer.multiplayer_peer = peer
	mode = NetMode.HOST

func join_game(address: String, port: int = DEFAULT_PORT) -> void:
	var p := ENetMultiplayerPeer.new()
	p.create_client(address, port)
	peer = p
	multiplayer.multiplayer_peer = peer
	mode = NetMode.CLIENT

func stop() -> void:
	multiplayer.multiplayer_peer = null
	peer = null
	mode = NetMode.OFFLINE

# ---- Commands ----
# A "command" is a small deterministic instruction like:
# { "t": Simulation.tick, "player": id, "type":"build", "payload":{...} }

@rpc("any_peer", "reliable")
func rpc_send_command(cmd: Dictionary) -> void:
	# Runs on host when clients call it.
	if mode != NetMode.HOST:
		return
	_pending_commands.append(cmd)

func send_command(cmd: Dictionary) -> void:
	if mode == NetMode.OFFLINE:
		# Direct apply in offline mode
		_apply_command(cmd)
		return
	if mode == NetMode.CLIENT:
		rpc_id(1, "rpc_send_command", cmd) # host is peer 1 in ENet
		return
	# Host issues its own commands locally
	_pending_commands.append(cmd)

func _process(_delta: float) -> void:
	if mode == NetMode.HOST and _pending_commands.size() > 0:
		for cmd in _pending_commands:
			_apply_command(cmd)
		_pending_commands.clear()
		# After applying, broadcast state snapshot periodically (prototype)
		# In production: send deltas, interest management, compression.
		rpc("rpc_state_snapshot", Simulation.tick, Simulation.state)

@rpc("authority", "unreliable")
func rpc_state_snapshot(tick: int, snapshot: Dictionary) -> void:
	# Runs on clients
	if mode != NetMode.CLIENT:
		return
	Simulation.tick = tick
	Simulation.state = snapshot
	Simulation.sync_entity_id_counter()

func _apply_command(cmd: Dictionary) -> void:
	# TODO: validate, then enqueue into Simulation for next tick boundary.
	match cmd.get("type",""):
		"spawn_test":
			var p = cmd.get("payload", {})
			Simulation.spawn_entity(p.get("def_id","t90_tank"), p.get("pos", Vector3.ZERO), cmd.get("player", 0))
		_:
			pass
