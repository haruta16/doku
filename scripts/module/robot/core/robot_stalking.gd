## 追赶机制的数值规则；计算追赶容量、每次增加的分数以及允许反超的时间边界。

class_name RobotStalking
extends RefCounted


static func stalk_capacity(player_score: int, cfg: RobotConfig) -> int:
	if player_score >= cfg.ceiling:
		return 0
	return int(floor(float(cfg.ceiling - player_score) / float(cfg.stalk_slot_div)))


static func catch_up_max(dn: int, dt: float, cfg: RobotConfig, extra: float = 0.0) -> int:
	var raw_max: float = max(
		0.0, min(float(dn + cfg.stalk_dn_offset), dt * cfg.stalk_dt_factor + extra)
	)
	return int(round(raw_max)) if extra > 0.0 else int(raw_max)


## 结合目标差距和当前规则计算一次追赶的增分；容量和反超时间限制由相关辅助函数共同约束。
static func catch_up_delta(
	dn: int, dt: float, cfg: RobotConfig, rng: RandomNumberGenerator, extra: float = 0.0
) -> int:
	var max_add: int = catch_up_max(dn, dt, cfg, extra)
	match cfg.stalk_delta_strategy:
		"accumulate_values":
			return _delta_accumulate(max_add, cfg, rng)
		"uniform_range":
			return _delta_uniform(max_add, cfg, rng)
		_:
			push_error("RobotStalking: stalk_delta_strategy=%s 未实现" % cfg.stalk_delta_strategy)
			return 0


static func _delta_accumulate(max_add: int, cfg: RobotConfig, rng: RandomNumberGenerator) -> int:
	if max_add <= 0:
		return 0
	var total: int = 0
	while true:
		var v: int = cfg.stalk_values[rng.randi_range(0, cfg.stalk_values.size() - 1)]
		if total + v > max_add:
			break
		total += v
	return total


static func _delta_uniform(max_add: int, cfg: RobotConfig, rng: RandomNumberGenerator) -> int:
	if max_add < cfg.stalk_uniform_min:
		return 0
	return rng.randi_range(cfg.stalk_uniform_min, max_add)


## 计算允许反超的时间边界，供追赶逻辑避免在保护区间内过早超越玩家。
static func overtake_guard_unix(
	player_last_unix: int, cfg: RobotConfig, rng: RandomNumberGenerator
) -> int:
	return (
		player_last_unix
		+ rng.randi_range(cfg.stalk_overtake_delay_min, cfg.stalk_overtake_delay_max)
	)
