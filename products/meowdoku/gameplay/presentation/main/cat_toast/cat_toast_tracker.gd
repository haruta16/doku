## 落猫鼓励的局内记录：保存落子次数、动作间隔和已触发场景，支持残局恢复。
class_name CatToastTracker
extends RefCounted

var _fired: Array[int] = []

var _level_key: String = ""

var _last_cat_sec: float = 0.0

var _last_cat_step: int = 0

var _player_cat_count: int = 0

var _last_delta_sec: float = 0.0
var _last_delta_step: int = 0


func begin_session() -> void:
	restore_state({})


func export_state() -> Dictionary:
	return {
		"last_cat_sec": _last_cat_sec,
		"last_cat_step": _last_cat_step,
		"player_cat_count": _player_cat_count,
		"fired": _fired.duplicate(),
		"level_key": _level_key,
	}


func restore_state(data: Dictionary) -> void:
	_last_cat_sec = float(data.get("last_cat_sec", 0.0))
	_last_cat_step = int(data.get("last_cat_step", 0))
	_player_cat_count = int(data.get("player_cat_count", 0))
	if data.has("fired"):
		_fired.clear()
		for scene: Variant in data["fired"]:
			_fired.append(int(scene))
	if data.has("level_key"):
		_level_key = str(data["level_key"])


func sync_level(level_key: String) -> void:
	if level_key != _level_key:
		_level_key = level_key
		_fired.clear()


func on_player_cat_placed(
	group: int,
	board_size: int,
	operable_sec: float,
	step_used: int,
	rng: RandomNumberGenerator = null
) -> int:
	_player_cat_count += 1
	var is_first: bool = _player_cat_count == 1
	var sec_delta: float = maxf(0.0, operable_sec - _last_cat_sec)
	var step_delta: int = maxi(0, step_used - _last_cat_step)
	_last_delta_sec = sec_delta
	_last_delta_step = step_delta

	var is_consecutive: bool = (not is_first) and step_delta == 1
	var scene: int = CatToastJudge.decide(
		group, board_size, sec_delta, step_delta, is_first, is_consecutive, _fired, rng
	)
	_last_cat_sec = operable_sec
	_last_cat_step = step_used
	if scene != CatToastJudge.SCENE_NONE:
		_fired.append(scene)
	return scene


func fired_scenes() -> Array[int]:
	return _fired.duplicate()


func player_cat_count() -> int:
	return _player_cat_count


func last_delta_sec() -> float:
	return _last_delta_sec


func last_delta_step() -> int:
	return _last_delta_step


func clear_fired() -> void:
	_fired.clear()
