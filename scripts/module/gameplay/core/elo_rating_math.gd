## Elo 难度计算：把玩家表现与预期胜率之差转成分数变化，再反推适合的题目评分。
class_name EloRatingMath
extends RefCounted


## 前十局使用较大的评分更新系数，之后减半以降低波动。
static func k_for_games(games_before: int) -> float:
	return 32.0 if games_before < 10 else 16.0


## 指定实验组的新玩家采用更快的早期收敛系数，其余沿用默认规则。
static func k_for_group(normal_level: int, games_before: int, is_new_player: bool = false) -> float:
	if normal_level in [11920, 11970] and is_new_player:
		if games_before < 10:
			return 48.0
		return 32.0 if games_before < 20 else 16.0
	return k_for_games(games_before)


## 按消耗鱼数分档得到表现分，使用工具时再加 0.1，最终不超过 1。
static func s_from_fish(fish_consumed: int, used_tool: bool) -> float:
	var s: float
	if fish_consumed == 0:
		s = 1.0
	elif fish_consumed < 3:
		s = 0.8
	elif fish_consumed <= 8:
		s = 0.5
	else:
		s = 0.0
	if used_tool:
		s = minf(s + 0.1, 1.0)
	return s


## 由题目与玩家的评分差算出预期成功率，400 分对应公式中的十倍尺度。
static func e_from_ratings(rating_puzzle: float, rating_player: float) -> float:
	return 1.0 / (1.0 + pow(10.0, (rating_puzzle - rating_player) / 400.0))


## 用 K 乘以实际表现与预期的差值，更新玩家评分。
static func new_player_rating(rating: float, k: float, s: float, e: float) -> float:
	return rating + k * (s - e)


## 给出固定选题成功率区间 0.4～0.6。
static func fixed_target_band() -> Vector2:
	return Vector2(0.4, 0.6)


## 把难度状态映射到目标成功率区间，未知状态回退到常规区间。
static func band_for_state(band_state: int) -> Vector2:
	match band_state:
		0:
			return Vector2(0.9, 1.0)
		1:
			return Vector2(0.55, 0.8)
		2:
			return Vector2(0.4, 0.6)
		3:
			return Vector2(0.4, 0.5)
		_:
			return Vector2(0.4, 0.6)


## 按策略升降移动难度状态；初始状态先按常规档处理。
static func next_band_state(strategy_delta: int, current_band: int) -> int:
	var base: int = current_band if current_band != 0 else 2
	if strategy_delta > 0:
		return clampi(base + 1, 1, 3)
	elif strategy_delta < 0:
		return clampi(base - 1, 1, 3)
	else:
		return base


## 反解目标成功率上下界，得到题目评分区间。
static func puzzle_rating_bounds(rating_player: float, band: Vector2) -> Vector2:
	return Vector2(
		rating_player + 400.0 * _log10((1.0 - band.y) / band.y),
		rating_player + 400.0 * _log10((1.0 - band.x) / band.x),
	)


## 在成功率区间内随机取值，再反解本次目标题目评分。
static func random_target_rating(rating_player: float, band: Vector2) -> float:
	var e: float = randf_range(band.x, band.y)
	return rating_player + 400.0 * _log10((1.0 - e) / e)


## 用自然对数换算以 10 为底的对数，供 Elo 公式反解使用。
static func _log10(x: float) -> float:
	return log(x) / log(10.0)
