## 色彩挑战的纯投放规则；把实验分组、金鱼累计次数、间隔和跳过状态转换为关卡类型与节奏。
## 这些函数只计算决策，实际递增次数和保存待投放状态由 GameState 等调用者负责。

class_name ColorChallengeGate
extends RefCounted

const GROUP_CONTROL: int = 0

const GROUP_SINGLE: int = 1

const GROUP_SINGLE_QUIET: int = 2

const GROUP_DUAL: int = 3

const UNLOCK_GOLDEN_FISH_COUNT: int = 4

const SINCE_GF_INTERVAL: int = 2

const NOT_STARTED: int = -1

const RANK_MIN: int = 3
const RANK_MAX: int = 4

const FIRST_SIZE: int = 8

const SIZE_CYCLE: Array[int] = [8, 9, 10]

const BANK_SOURCE: String = "color_challenge"

const QUIET_SKIP_THRESHOLD: int = 2

const QUIET_INTERVAL_LEVELS: int = 8


static func current_form(group: int) -> int:
	return group


static func is_enabled(group: int) -> bool:
	return group == GROUP_SINGLE or group == GROUP_SINGLE_QUIET or group == GROUP_DUAL


static func has_quiet_rule(group: int) -> bool:
	return group == GROUP_SINGLE_QUIET


static func is_dual_color(group: int) -> bool:
	return group == GROUP_DUAL


## 综合当前形态与待投放标记判断本关是否为色彩挑战；返回关卡种类，不直接修改存档。
static func resolve_kind(level: int, pending: bool, group: int) -> int:
	if not is_enabled(group):
		return LevelKind.MAIN
	return LevelKind.COLOR_CHALLENGE if is_color_challenge_level(level, pending) else LevelKind.MAIN


static func should_show_style(level: int, pending: bool, group: int) -> bool:
	return LevelKind.is_color_challenge(resolve_kind(level, pending, group))


static func is_color_challenge_level(level: int, pending: bool) -> bool:
	return level > 0 and pending


static func is_unlocked(gf_career_count: int) -> bool:
	return gf_career_count >= UNLOCK_GOLDEN_FISH_COUNT


static func counting_enabled(gf_career_count: int, group: int) -> bool:
	if not is_enabled(group):
		return false
	return is_unlocked(gf_career_count)


static func next_since_gf_count(current: int) -> int:
	if current == NOT_STARTED:
		return NOT_STARTED
	if current >= SINCE_GF_INTERVAL:
		return SINCE_GF_INTERVAL
	return current + 1


## 判断当前次数与节奏是否满足下一次挑战的预备条件，由调用者保存待投放状态。
static func should_spawn_pending(current_since_gf: int) -> bool:
	if current_since_gf == NOT_STARTED:
		return false
	return current_since_gf + 1 >= SINCE_GF_INTERVAL


static func since_gf_after_golden_fish() -> int:
	return 0


static func cc_size(delivered: int) -> int:
	if delivered <= 0:
		return FIRST_SIZE
	return SIZE_CYCLE[(delivered - 1) % SIZE_CYCLE.size()]


static func cc_rank(main_strategy: int, delivered: int) -> int:
	if delivered <= 0:
		return RANK_MIN
	return RANK_MAX if main_strategy >= RANK_MAX else RANK_MIN


static func stale_easier_rank(snap_rank: int) -> int:
	return clampi(snap_rank - 1, RANK_MIN, RANK_MAX)


static func is_quiet_active(consecutive_skips: int, group: int) -> bool:
	return has_quiet_rule(group) and consecutive_skips >= QUIET_SKIP_THRESHOLD


static func quiet_next_level(current_level: int) -> int:
	return (current_level - 1) + QUIET_INTERVAL_LEVELS


static func should_spawn_at_quiet_target(level: int, quiet_target: int) -> bool:
	return quiet_target > 0 and level >= quiet_target


## 定义实验形态切换后哪些旧状态应失效，避免旧分组留下的待投放关卡污染新策略。
static func should_clear_on_form_switch(prev_form: int, cur_form: int) -> bool:
	if prev_form < 0:
		return false
	return prev_form != cur_form


static func should_reset_skip_count_on_switch(prev_form: int, cur_form: int) -> bool:
	return should_clear_on_form_switch(prev_form, cur_form)


static func should_clear_endgame_on_switch(
	snap_kind: int, snap_level: int, pending: bool, group: int
) -> bool:
	if snap_level <= 0:
		return false
	return resolve_kind(snap_level, pending, group) != snap_kind
