## 金鱼关与预填猫机制的衔接层；根据实验配置决定是否共享主线待处理状态，以及是否隔离金鱼会话。
## 同一题的预填决定写入 GameState 锁，重试和恢复时复用，避免重复随机改变题面。

extends RefCounted
class_name GoldenFishPreCat

var _uses_control_behavior: bool = true
var _includes_golden_fish: bool = false
var _isolates_golden_fish: bool = false
var _random: RandomNumberGenerator = null


func _init(config: GoldenFishPrecatConfig = null) -> void:
	if config != null:
		_uses_control_behavior = config.uses_control_behavior()
		_includes_golden_fish = config.includes_golden_fish()
		_isolates_golden_fish = config.isolates_golden_fish()
	if _includes_golden_fish:
		_random = RandomNumberGenerator.new()
		_random.randomize()


## 进入金鱼插入关前建立专用预填会话，是否隔离主线由实验配置决定。
func prepare_entry(level_num: int, kind: int) -> void:
	if LevelKind.is_insert_golden_fish(kind):
		GameState.begin_golden_fish_pre_cat_session(level_num, _isolates_golden_fish)


## 按主线/金鱼和实验行为选择待处理状态来源；部分分支会消费状态，不能重复无条件调用。
func consume_pending(level_num: int, kind: int) -> Dictionary:
	if _uses_control_behavior and LevelKind.is_insert_golden_fish(kind):
		return GameState.consume_pre_cat_pending()
	if LevelKind.is_insert_golden_fish(kind):
		return GameState.get_golden_fish_pre_cat_source(level_num) if _includes_golden_fish else {}
	return GameState.consume_main_pre_cat_pending(
		level_num, _includes_golden_fish, _isolates_golden_fish
	)


func main_pending(level_num: int, pending: Dictionary) -> Dictionary:
	return (
		GameState.get_golden_fish_pre_cat_followup(
			level_num, _includes_golden_fish, _isolates_golden_fish
		)
		if GameState.has_golden_fish_pre_cat_followup(level_num)
		else pending
	)


func fallback_pending(level_num: int, pending: Dictionary) -> Dictionary:
	return (
		pending
		if _uses_control_behavior
		else GameState.consume_main_pre_cat_pending(
			level_num, _includes_golden_fish, _isolates_golden_fish
		)
	)


func selector_pending(kind: int, pending: Dictionary) -> Dictionary:
	return {} if not _uses_control_behavior and LevelKind.is_insert_golden_fish(kind) else pending


func settle_mouse_win(kind: int) -> void:
	if LevelKind.is_insert_golden_fish(kind):
		GameState.on_golden_fish_settled(true)


## 恢复存档时复用已保存预填；新题先检查题目指纹锁，再按当前策略生成并保存唯一决定。
func resolve_insert(config: Dictionary, puzzle: Dictionary) -> Dictionary:
	if _uses_control_behavior:
		GameState.consume_pre_cat_pending()
	var level_num: int = int(config.get("level", 0))
	var restore_state: Dictionary = config.get("restore_state", {})
	if not restore_state.is_empty():
		var pre_type: String = str(restore_state.get("pre_type", PreCatDecider.PRE_TYPE_NONE))
		var prefills: Array = config.get("prefill_positions", [])
		var position: Vector2i = Vector2i(-1, -1)
		if pre_type != PreCatDecider.PRE_TYPE_NONE and not prefills.is_empty():
			position = Vector2i(int(prefills[0][0]), int(prefills[0][1]))
		return {"pre_type": pre_type, "position": position}
	var regions: Array = puzzle.get("regions", [])
	var solution: Array = puzzle.get("solution", [])
	var puzzle_key: String = JSON.stringify([regions, solution]).sha256_text()
	var source: Dictionary = GameState.get_golden_fish_pre_cat_source(level_num)
	var lock: Dictionary = GameState.get_golden_fish_pre_cat_lock(level_num, puzzle_key)

	var locked_source: Dictionary = lock.get(
		"pending",
		{
			"hard": bool(source.get("hard", false)),
			"struggle": bool(source.get("struggle", false)),
			"demote": false
		}
	)

	if (
		bool(lock.get("locked", false))
		and bool(lock.get("allow_pre_cat", true)) == _includes_golden_fish
		and (not _includes_golden_fish or locked_source == source)
	):
		return lock
	if not _includes_golden_fish:
		GameState.set_golden_fish_pre_cat_lock(
			level_num, puzzle_key, PreCatDecider.PRE_TYPE_NONE, Vector2i(-1, -1), false
		)
		return {"pre_type": PreCatDecider.PRE_TYPE_NONE, "position": Vector2i(-1, -1)}
	var scenes: Array[int] = PreCatDecider.hit_scenarios(
		bool(source.get("hard", false)),
		int(config.get("rank", 0)),
		bool(source.get("struggle", false)),
		bool(source.get("demote", false))
	)
	if level_num <= 20:
		scenes.clear()
	var decision: Dictionary = PreCatDecider.decide(
		scenes, int(config.get("size", 0)), regions, solution, false, _pick_index
	)
	GameState.set_golden_fish_pre_cat_lock(
		level_num, puzzle_key, str(decision["pre_type"]), decision["position"], true, source
	)
	return decision


func _pick_index(candidate_count: int) -> int:
	return _random.randi_range(0, candidate_count - 1)


## 记录金鱼会话的复活；非对照行为会提前返回，避免同时污染主线预填状态。
func mark_revived(level_num: int, kind: int, isolate_main_state: bool) -> void:
	if LevelKind.is_insert_golden_fish(kind):
		GameState.mark_golden_fish_pre_cat_revived(level_num)
		if not _uses_control_behavior:
			return
	if not isolate_main_state:
		GameState.mark_pre_cat_revived()


func fx_kind(kind: int) -> int:
	return LevelKind.GOLDEN_FISH_INSERT if LevelKind.is_insert_golden_fish(kind) else LevelKind.MAIN
