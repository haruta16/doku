## 普通关卡策略 normal_level_12203：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12203Strategy
extends NL12100Strategy

const MIN_LEVEL: int = 51
const CYCLE_LENGTH: int = 10
const MIN_DYNAMIC_SIZE: int = 8
const MAX_DYNAMIC_SIZE: int = 10


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12203"


func select(request: LevelSelectRequest) -> Dictionary:
	var delivered: Dictionary = super.select(request)
	_log_difficulty_range(request.level_num)
	return delivered


func _log_difficulty_range(level_num: int) -> void:
	var dda_min: int = 2 if level_num >= MIN_LEVEL else 1
	var dda_max: int = max_strategy_at(level_num)
	var current: int = GameState.get_current_strategy()
	var user_cap: int = mini(
		LevelData.resolve_strategy(level_num, current, FIXED_R1_UPPER_LEVEL),
		_segment_strategy_cap(level_num)
	)
	var user_min: int = 2 if user_cap >= 3 else user_cap
	print(
		(
			"[Level.DifficultyRange] %s level=%d DDA区间=[%s,%s] 当前策略=%s 用户当前区间=[%s,%s] 本关交付=%s size=%d hard=%s super_hard=%s"
			% [
				String(get_strategy_id()),
				level_num,
				_strategy_label(dda_min),
				_strategy_label(dda_max),
				_strategy_label(current),
				_strategy_label(user_min),
				_strategy_label(user_cap),
				"R%d%s" % [_ctx.rank, "H" if _ctx.tier == "H" else ""],
				_ctx.sz,
				str(_ctx.is_hard),
				str(_ctx.is_super_hard)
			]
		)
	)


static func _strategy_label(strategy: int) -> String:
	return (
		"R%d%s"
		% [
			LevelData.strategy_to_rank(strategy),
			"H" if LevelData.strategy_to_tier(strategy) == "H" else ""
		]
	)


func _resolve_board_size(level_num: int) -> int:
	if level_num < MIN_LEVEL or _ctx.is_hard:
		return _ctx.sz
	if _ctx.is_super_hard:
		_track_stuck_streak(_ctx.sz)
		_log_size(level_num, -1, "SuperHard", _ctx.sz)
		return _ctx.sz

	var offset: int = (level_num - MIN_LEVEL) % CYCLE_LENGTH
	var size: int
	var source: String
	if offset == 0:
		GameState.set_bsz11802_dyn_size(MIN_DYNAMIC_SIZE)
		size = MIN_DYNAMIC_SIZE
		source = "锚点XX1"
	elif offset == CYCLE_LENGTH - 2 or offset == CYCLE_LENGTH - 1:
		size = MAX_DYNAMIC_SIZE
		source = "锚点XX9/XX0"
	else:
		var candidate: int = clampi(
			GameState.get_bsz11802_dyn_size(), MIN_DYNAMIC_SIZE, MAX_DYNAMIC_SIZE
		)
		if (
			candidate == GameState.get_bsz11802_last_delivered_size()
			and GameState.get_bsz11802_stuck_streak() >= 2
		):
			size = NL11802Strategy._pick_different_size(candidate)
			GameState.set_bsz11802_dyn_size(size)
			source = "连续同尺寸强制换(原x=%d)" % candidate
		else:
			size = candidate
			source = "动态x"

	_track_stuck_streak(size)
	_log_size(level_num, offset, source, size)
	return size


func _track_stuck_streak(delivered_size: int) -> void:
	if delivered_size == GameState.get_bsz11802_last_delivered_size():
		GameState.set_bsz11802_stuck_streak(GameState.get_bsz11802_stuck_streak() + 1)
	else:
		GameState.set_bsz11802_last_delivered_size(delivered_size)
		GameState.set_bsz11802_stuck_streak(1)


func _log_size(level_num: int, offset: int, source: String, size: int) -> void:
	print(
		(
			"[Level.DynamicSize] %s level=%d offset=%d 来源=%s → size=%d"
			% [String(get_strategy_id()), level_num, offset, source, size]
		)
	)


func on_level_won_settlement(ctx: LevelSettlementContext) -> void:
	super.on_level_won_settlement(ctx)
	if ctx.is_daily_first_easy_level:
		return
	var pure_tool_used: bool = ctx.tool_or_revive_used and not ctx.revive_used
	var before: int = GameState.get_bsz11802_dyn_size()
	var after: int = before
	var verdict: String
	if pure_tool_used:
		verdict = "冻结(用过道具)"
	elif ctx.strategy > ctx.strategy_before_all:
		after = maxi(before - 1, MIN_DYNAMIC_SIZE)
		verdict = "升档→x-1"
	elif ctx.strategy < ctx.strategy_before_all:
		after = mini(before + 1, MAX_DYNAMIC_SIZE)
		verdict = "降档→x+1"
	else:
		verdict = "保级→不变"
	if after != before:
		GameState.set_bsz11802_dyn_size(after)
	print(
		(
			"[Level.DynamicSize] %s settlement level=%d strategy %d→%d 判定=%s x: %d→%d"
			% [
				String(get_strategy_id()),
				ctx.level_num,
				ctx.strategy_before_all,
				ctx.strategy,
				verdict,
				before,
				after
			]
		)
	)
