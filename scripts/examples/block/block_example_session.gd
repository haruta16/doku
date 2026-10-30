## 独立产品装配示例：玩法只认识方块，宿主只认识快照与库存，界面只调用本类。
## 路径由启动器注入，与 Meowdoku 存档完全分离。
class_name BlockExampleSession
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const Files = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const Module = preload("res://scripts/examples/block/domain/block_probe_module.gd")
const MODULE_ID: String = "block_probe"
const MODE_ID: String = "example"

var _files: RefCounted
var _core: RefCounted
var _host: RefCounted
var _module := Module.new()
var _latest: Dictionary = {}


func open(directory: String) -> Dictionary:
	# 重新打开失败时不能把新存储与旧宿主/画面拼在一起。
	_host = null
	_latest = {}
	_files = Files.new("block-example-local", directory, true, directory.path_join("a.cfg"), directory.path_join("b.cfg"), directory.path_join("flag"))
	_core = Core.new(_files, 1, _validate_state)
	var opened: Dictionary = _core.open({"inventory": {"star": 0}, "round_services": {}})
	if not opened.get("ok", false):
		return opened
	_host = Host.new(_core)
	_host.register_module(MODULE_ID, _module)
	var resumed: Dictionary = _host.resume(MODULE_ID, MODE_ID)
	if resumed.get("error") == "missing":
		return new_round()
	return _accept(resumed, _host)


func new_round(context: Dictionary = {}) -> Dictionary:
	if _host == null:
		return Result.failure("not_open")
	var host: RefCounted = _host
	var current: Dictionary = host.resume(MODULE_ID, MODE_ID)
	if not current.get("ok", false) and current.get("error") != "missing":
		return current
	var sequence: int = int(current.get("start_sequence", 0)) + 1
	return _accept(host.start(MODULE_ID, MODE_ID, sequence, definition() if context.is_empty() else context), host)


func place(row: int, col: int) -> Dictionary:
	if _latest.is_empty():
		return Result.failure("not_open")
	var host: RefCounted = _host
	return _accept(host.action(MODULE_ID, MODE_ID, _latest.round_id, _latest.next_sequence, "place", {"row": row, "col": col}), host)


func collect() -> Dictionary:
	if _latest.is_empty():
		return Result.failure("not_open")
	var host: RefCounted = _host
	return _accept(host.settle(MODULE_ID, MODE_ID, _latest.round_id, _latest.next_sequence), host)


func preview(row: int, col: int) -> Dictionary:
	if _latest.is_empty() or _latest.get("status") != "active":
		return {"valid": false, "cells": []}
	return _module.preview_placement(_latest.snapshot, row, col)


func current() -> Dictionary:
	return _latest.duplicate(true)


func stars() -> int:
	return int(_core.snapshot().get("inventory", {}).get("star", 0)) if _core != null and _core.is_open() else 0


func _accept(result: Dictionary, source: RefCounted) -> Dictionary:
	if result.get("ok", false) and source == _host:
		# committed 的同步监听可能已切局或接受更新回执；外层只返回自己的结果。
		if not _latest.is_empty():
			if result.start_sequence < _latest.start_sequence:
				return result
			if result.start_sequence == _latest.start_sequence and result.sequence < _latest.sequence:
				return result
		_latest = result.duplicate(true)
	return result


static func _validate_state(state: Dictionary) -> String:
	if not state.get("inventory") is Dictionary or typeof(state.inventory.get("star")) != TYPE_INT or state.inventory.star < 0:
		return "invalid star balance"
	if not state.get("round_services") is Dictionary:
		return "invalid round records"
	return ""


static func definition() -> Dictionary:
	return {
		"size": 5,
		"board": [[1, 1, 1, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0]],
		"pieces": [
			[[0, 0], [0, 1]], [[0, 0], [1, 0], [2, 0]],
			[[0, 0], [0, 1], [1, 0], [1, 1]], [[0, 0], [0, 1], [0, 2]],
			[[0, 0]], [[0, 0], [1, 0]], [[0, 0], [0, 1]],
			[[0, 0], [1, 0], [1, 1]], [[0, 0]], [[0, 0], [0, 1], [0, 2]],
		],
		"reward": {"star": 1},
	}
