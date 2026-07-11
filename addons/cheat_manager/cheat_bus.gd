extends Node

signal command_issued(name: String, args: Array[String])

var _commands: Array[CheatCommand] = []

var _ab_params: Array[Dictionary] = []

var _tabs: Array[Dictionary] = []


func register_command(cmd: CheatCommand) -> void:
	_commands.append(cmd)


func clear_commands() -> void:
	_commands.clear()


func get_commands() -> Array[CheatCommand]:
	return _commands.duplicate()


func register_ab_param(key: String, label: String, current_value_fn: Callable) -> void:
	_ab_params.append({"key": key, "label": label, "current_value_fn": current_value_fn})


func get_ab_params() -> Array[Dictionary]:
	return _ab_params.duplicate()


func clear_ab_params() -> void:
	_ab_params.clear()


func register_tab(title: String, builder: Callable) -> void:
	_tabs.append({"title": title, "builder": builder})


func get_tabs() -> Array[Dictionary]:
	return _tabs.duplicate()


func clear_tabs() -> void:
	_tabs.clear()


func issue(raw: String) -> void:
	var parts := raw.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var cmd_name: String = parts[0]
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	command_issued.emit(cmd_name, args)
