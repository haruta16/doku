## Test-fixture terminal cleanup only. Success requires observed release, not elapsed time.
extends RefCounted

static func drain(tree: SceneTree, timeout_msec: int = 2000) -> Dictionary:
	var players: Array[Node] = []
	_collect_players(tree.root, players)
	var watches: Dictionary = {}
	for player: Node in players:
		_watch(watches, player.get("stream"), "stream")
		if player.has_stream_playback():
			_watch(watches, player.get_stream_playback(), "playback")
		player.stop()
		player.set("stream", null)
	var started: int = Time.get_ticks_msec()
	var deadline: int = started + maxi(timeout_msec, 0)
	var polls: int = 0
	var retained: Array[Dictionary] = _retained(watches)
	while not retained.is_empty() and Time.get_ticks_msec() < deadline:
		polls += 1
		await tree.process_frame
		retained = _retained(watches)
	var reactivated: Array[String] = []
	var final_players: Array[Node] = []
	_collect_players(tree.root, final_players)
	for player: Node in final_players:
		if is_instance_valid(player) and (player.get("stream") != null or player.playing):
			reactivated.append(str(player.get_path()))
	return {"ok": retained.is_empty() and reactivated.is_empty(), "players": players.size(),
		"tracked_references": watches.size(), "remaining": retained, "reactivated": reactivated,
		"elapsed_ms": Time.get_ticks_msec() - started, "polls": polls}


static func _collect_players(node: Node, result: Array[Node]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		result.append(node)
	for child: Node in node.get_children():
		_collect_players(child, result)


static func _watch(watches: Dictionary, value: Object, role: String) -> void:
	if not is_instance_valid(value):
		return
	var identity: int = value.get_instance_id()
	if not watches.has(identity):
		watches[identity] = {"weak": weakref(value), "role": role, "class": value.get_class(),
			"resource_path": value.resource_path if value is Resource else "", "instance_id": identity}


static func _retained(watches: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in watches.values():
		if record.weak.get_ref() != null:
			result.append({"role": record.role, "class": record["class"],
				"resource_path": record.resource_path, "instance_id": record.instance_id})
	return result
