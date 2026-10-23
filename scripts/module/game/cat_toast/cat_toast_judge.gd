## 落猫鼓励判定：汇总候选触发条件，按优先级挑选这次应展示的鼓励场景。
class_name CatToastJudge
extends RefCounted

enum Scene {
	FIRST_CAT = 0,
	SLOW_PLACE = 1,
	MANY_STEPS = 2,
	STREAK = 3,
}

const SCENE_NONE: int = -1

const PRIORITY: Array[int] = [Scene.FIRST_CAT, Scene.SLOW_PLACE, Scene.MANY_STEPS, Scene.STREAK]

const RANDOM_WITH_FIRST_CAT: Array[int] = [Scene.SLOW_PLACE, Scene.MANY_STEPS]

static var _shared_rng: RandomNumberGenerator = null


static func collect_hits(
	group: int,
	board_size: int,
	sec: float,
	steps: int,
	is_first_player_cat: bool,
	is_consecutive: bool
) -> Array[int]:
	var hits: Array[int] = []
	if is_first_player_cat and CatToastConfig.is_fast_first_cat_for(group, board_size, sec, steps):
		hits.append(Scene.FIRST_CAT)
	if CatToastConfig.is_slow_place_for(group, board_size, sec):
		hits.append(Scene.SLOW_PLACE)
	if CatToastConfig.is_many_steps_for(group, board_size, steps):
		hits.append(Scene.MANY_STEPS)
	if is_consecutive and CatToastConfig.is_streak_eligible_for(group, board_size):
		hits.append(Scene.STREAK)
	return hits


static func decide(
	group: int,
	board_size: int,
	sec: float,
	steps: int,
	is_first_player_cat: bool,
	is_consecutive: bool,
	fired: Array[int],
	rng: RandomNumberGenerator = null
) -> int:
	var hits: Array[int] = collect_hits(
		group, board_size, sec, steps, is_first_player_cat, is_consecutive
	)
	var fresh: Array[int] = []
	for scene: int in hits:
		if not fired.has(scene):
			fresh.append(scene)
	if fresh.is_empty():
		return SCENE_NONE
	return _pick(fresh, rng)


static func _pick(fresh: Array[int], rng: RandomNumberGenerator) -> int:
	if fresh.has(Scene.FIRST_CAT):
		var pool: Array[int] = [Scene.FIRST_CAT]
		for scene: int in RANDOM_WITH_FIRST_CAT:
			if fresh.has(scene):
				pool.append(scene)
		if pool.size() > 1:
			return pool[roll(rng, pool.size())]
	for scene: int in PRIORITY:
		if fresh.has(scene):
			return scene
	return SCENE_NONE


static func scene_name(scene: int) -> String:
	match scene:
		Scene.FIRST_CAT:
			return "首猫快"
		Scene.SLOW_PLACE:
			return "长耗时"
		Scene.MANY_STEPS:
			return "多step"
		Scene.STREAK:
			return "连续正确"
	return "不出"


static func roll(rng: RandomNumberGenerator, count: int) -> int:
	var source: RandomNumberGenerator = rng
	if source == null:
		if _shared_rng == null:
			_shared_rng = RandomNumberGenerator.new()
			_shared_rng.randomize()
		source = _shared_rng
	return source.randi_range(0, count - 1)
