## 实验配置 pass_anim_cat：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PassAnimCatConfig

const VALUE_CONTROL: int = 0
const VALUE_G1: int = 1
const VALUE_G2: int = 2
const VALUE_V2_PROB: int = 3
const VALUE_V2_CYCLE: int = 4
const VALUE_V2_HARD: int = 5

const ACTION_NONE: int = 0
const ACTION_TRUMPET: int = 1
const ACTION_THUMBS: int = 2
const ACTION_DRAGON: int = 3
const ACTION_CHEER: int = 4

const _ANIM_INDEX_BY_ACTION: Dictionary = {
	ACTION_THUMBS: 1,
	ACTION_DRAGON: 2,
	ACTION_CHEER: 3,
}

const _WIN_SOUND_BY_ACTION: Dictionary = {
	ACTION_THUMBS: SoundManager.Kind.PASS_ANIM_CAT_WIN_1,
	ACTION_DRAGON: SoundManager.Kind.PASS_ANIM_CAT_WIN_2,
	ACTION_CHEER: SoundManager.Kind.PASS_ANIM_CAT_WIN_3,
}

const ACTION_WEIGHTS: Array[Array] = [
	[ACTION_THUMBS, 40],
	[ACTION_DRAGON, 30],
	[ACTION_TRUMPET, 20],
	[ACTION_CHEER, 10],
]

const CYCLE_G4: Array[int] = [ACTION_THUMBS, ACTION_DRAGON, ACTION_TRUMPET, ACTION_CHEER]

const CYCLE_G5: Array[int] = [ACTION_THUMBS, ACTION_DRAGON, ACTION_TRUMPET]

const _G1_WIN_SOUND_BY_LIVES: Dictionary = {
	1: SoundManager.Kind.PASS_ANIM_CAT_WIN_1,
	2: SoundManager.Kind.PASS_ANIM_CAT_WIN_2,
	3: SoundManager.Kind.PASS_ANIM_CAT_WIN_3,
}

const _G2_WIN_SOUND_NOT_FULL: int = SoundManager.Kind.PASS_ANIM_CAT_WIN_2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "pass_anim_cat"

	default_value = VALUE_G1


func is_g1() -> bool:
	return value() == VALUE_G1


func is_g2() -> bool:
	return value() == VALUE_G2


func get_win_sound_kind(lives: int) -> int:
	var lv: int = clampi(lives, 1, 3)
	match value():
		VALUE_G1:
			return int(_G1_WIN_SOUND_BY_LIVES.get(lv, SoundManager.Kind.LEVEL_WIN))
		VALUE_G2:
			return _G2_WIN_SOUND_NOT_FULL if lv <= 2 else SoundManager.Kind.LEVEL_WIN
	return SoundManager.Kind.LEVEL_WIN


func is_v2() -> bool:
	return is_v2_group(value())


func should_advance_cycle(is_hard: bool) -> bool:
	return should_advance_cycle_for(value(), is_hard)


func pick_v2_action(is_hard: bool, cycle_count: int, roll: float) -> int:
	return pick_action_for(value(), is_hard, cycle_count, roll)


static func is_v2_group(group: int) -> bool:
	return group == VALUE_V2_PROB or group == VALUE_V2_CYCLE or group == VALUE_V2_HARD


static func uses_cycle_for(group: int) -> bool:
	return group == VALUE_V2_CYCLE or group == VALUE_V2_HARD


static func should_advance_cycle_for(group: int, is_hard: bool) -> bool:
	if not uses_cycle_for(group):
		return false
	return not (group == VALUE_V2_HARD and is_hard)


static func pick_action_for(group: int, is_hard: bool, cycle_count: int, roll: float) -> int:
	if not is_v2_group(group):
		return ACTION_NONE
	var safe_count: int = maxi(cycle_count, 0)
	match group:
		VALUE_V2_PROB:
			return _pick_weighted(roll)
		VALUE_V2_CYCLE:
			return CYCLE_G4[safe_count % CYCLE_G4.size()]
		VALUE_V2_HARD:
			if is_hard:
				return ACTION_CHEER
			return CYCLE_G5[safe_count % CYCLE_G5.size()]
	return ACTION_NONE


static func _pick_weighted(roll: float) -> int:
	var threshold: float = clampf(roll, 0.0, 0.999999) * 100.0
	var acc: float = 0.0
	for entry: Array in ACTION_WEIGHTS:
		acc += float(entry[1])
		if threshold < acc:
			return int(entry[0])
	return int(ACTION_WEIGHTS[ACTION_WEIGHTS.size() - 1][0])


static func anim_index_for_action(action: int) -> int:
	return int(_ANIM_INDEX_BY_ACTION.get(action, 0))


static func win_sound_for_action(action: int) -> int:
	return int(_WIN_SOUND_BY_ACTION.get(action, SoundManager.Kind.LEVEL_WIN))
