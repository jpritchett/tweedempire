extends Node
class_name CombatSystem

## Processes combat each simulation tick.
## Handles auto-targeting, damage, death, and loot drops.

signal entity_died(eid: int, pos: Vector3, def_id: String, kind: String)

func process_combat() -> void:
	var dead_eids: Array[int] = []

	for eid in Simulation.state.entities.keys():
		var e = Simulation.state.entities[eid]
		var kind: String = e.get("kind", "")
		if kind != "unit" and kind != "enemy":
			continue

		var def := Registry.get_any_def(e.def_id)
		var atk_range: float = def.get("attack_range", 0.0)
		var atk_damage: int = def.get("attack_damage", 0)
		var atk_cd: int = def.get("attack_cooldown", 20)

		if atk_damage <= 0 or atk_range <= 0.0:
			continue

		# Decrement cooldown
		var cd_current: int = e.get("attack_cooldown_current", 0)
		if cd_current > 0:
			e["attack_cooldown_current"] = cd_current - 1
			continue

		# Find target: units attack enemies, enemies attack units+structures
		var target_kind := "enemy" if kind == "unit" else ""
		var target_eid := _find_nearest_target(eid, e, atk_range, target_kind)

		if target_eid < 0:
			continue

		var target = Simulation.state.entities.get(target_eid, null)
		if target == null:
			continue

		# Deal damage
		target["hp"] = target.get("hp", 0) - atk_damage
		e["attack_cooldown_current"] = atk_cd
		e["attack_target"] = target_eid
		target["last_hit_tick"] = Simulation.tick

	# Process deaths
	for eid in Simulation.state.entities.keys():
		var e = Simulation.state.entities[eid]
		if e.get("hp", 1) <= 0:
			dead_eids.append(eid)

	for eid in dead_eids:
		var e = Simulation.state.entities[eid]
		var pos := Vector3(e.pos[0], e.pos[1], e.pos[2])
		var def_id: String = e.def_id
		var kind: String = e.get("kind", "")
		Simulation.state.entities.erase(eid)
		entity_died.emit(eid, pos, def_id, kind)

func _find_nearest_target(attacker_eid: int, attacker: Dictionary, attack_range: float, target_kind: String) -> int:
	var pos := Vector3(attacker.pos[0], attacker.pos[1], attacker.pos[2])
	var best_eid := -1
	var best_dist := attack_range
	var attacker_kind: String = attacker.get("kind", "")

	for eid in Simulation.state.entities.keys():
		if eid == attacker_eid:
			continue
		var e = Simulation.state.entities[eid]
		var ek: String = e.get("kind", "")

		# Targeting rules
		if attacker_kind == "unit":
			if ek != "enemy":
				continue
		elif attacker_kind == "enemy":
			if ek != "unit" and ek != "structure":
				continue
		else:
			continue

		var tp := Vector3(e.pos[0], e.pos[1], e.pos[2])
		var d := pos.distance_to(tp)
		if d < best_dist:
			best_dist = d
			best_eid = eid

	return best_eid
