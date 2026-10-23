## 金鱼插入关的纯节奏规则；综合实验形态、关卡进度、连胜与间隔判断投放，并给出尺寸和难度。

class_name GoldenFishGate
extends RefCounted

const INSERT_MODE_MIN_LEVEL: int = 51

const INSERT_INTERVAL: int = 4

const EARLY_UNLOCK_MIN_LEVEL: int = 31

const STICKY_INTERVAL: int = 3

const STREAK_TRIGGER: int = 2

const INSERT_RANK_MIN: int = 3
const INSERT_RANK_MAX: int = 4

const DIFF_EXT_RANK_MAX: int = 5


static func diff_ext_rank_candidates(main_strategy: int) -> Array[int]:
	if main_strategy <= INSERT_RANK_MIN:
		return [INSERT_RANK_MIN]
	return [INSERT_RANK_MIN, INSERT_RANK_MAX, DIFF_EXT_RANK_MAX]


const INSERT_FIRST_SIZE: int = 7

const INSERT_BANK_SOURCE: String = "onefish"

const FORM_OFF: int = 0

const FORM_INSERT_SKIP: int = 11505


static func form_from_group_value(group_value: int) -> int:
	return current_form(group_value != 0)


static func current_form(enabled: bool) -> int:
	return FORM_INSERT_SKIP if enabled else FORM_OFF


## 由金鱼实验形态和插入标记决定关卡类型，将玩法选择与 UI 金鱼样式判断分开。
static func resolve_kind(level: int, pending: bool, enabled: bool, min_level: int) -> int:
	if not enabled:
		return LevelKind.MAIN
	return (
		LevelKind.GOLDEN_FISH_INSERT
		if is_insert_golden_level(level, pending, min_level)
		else LevelKind.MAIN
	)


static func should_show_golden_style(
	level: int, pending: bool, enabled: bool, min_level: int
) -> bool:
	return LevelKind.is_golden_fish(resolve_kind(level, pending, enabled, min_level))


static func is_insert_golden_level(level: int, pending: bool, min_level: int) -> bool:
	return level >= min_level and pending


static func insert_counting_enabled(level: int, enabled: bool, min_level: int) -> bool:
	return enabled and level >= min_level


static func insert_rank(main_strategy: int) -> int:
	return clampi(main_strategy, INSERT_RANK_MIN, INSERT_RANK_MAX)


static func insert_rank_alternating(delivered: int, anchor: int) -> int:
	var phase: int = delivered - anchor
	if anchor <= 0:
		phase -= 1
	if phase < 0:
		phase = 0
	return INSERT_RANK_MIN if phase % 2 == 0 else INSERT_RANK_MAX


const INSERT_SIZE_CYCLE: Array[int] = [8, 9, 10]

const INSERT_SIZE_CYCLE_UPSIZED: Array[int] = [8, 10, 10, 9, 10, 10]


static func insert_size(insert_delivered: int, switch_anchor: int, upsized: bool) -> int:
	if insert_delivered <= 0:
		return INSERT_FIRST_SIZE
	var cycle: Array[int] = INSERT_SIZE_CYCLE_UPSIZED if upsized else INSERT_SIZE_CYCLE
	var phase: int = insert_delivered - switch_anchor
	if switch_anchor <= 0:
		phase -= 1
	if phase < 0:
		phase = 0
	return cycle[phase % cycle.size()]


static func should_clear_on_form_switch(prev_form: int, cur_form: int) -> bool:
	if prev_form < 0:
		return false
	return prev_form != cur_form


static func should_clear_endgame_on_switch(
	snap_kind: int, snap_level: int, pending: bool, enabled: bool, min_level: int
) -> bool:
	if snap_level <= 0:
		return false
	return resolve_kind(snap_level, pending, enabled, min_level) != snap_kind


static func next_streak_count(current: int, enabled: bool, interval: int) -> int:
	if not enabled:
		return 0
	var nxt: int = current + 1
	return 0 if nxt >= interval else nxt


## 根据当前节奏判断下一关是否应准备插入金鱼关；具体状态落盘由调用方执行。
static func should_spawn_pending(current_count: int, enabled: bool, interval: int) -> bool:
	return enabled and current_count + 1 >= interval


static func effective_interval(consecutive_wins: int, sticky: bool) -> int:
	if sticky and consecutive_wins >= STREAK_TRIGGER:
		return STICKY_INTERVAL
	return INSERT_INTERVAL


static func should_suppress_spawn(
	consecutive_skips: int, already_suppressed: bool, penalty: bool
) -> bool:
	if not penalty or already_suppressed:
		return false
	return consecutive_skips >= STREAK_TRIGGER
