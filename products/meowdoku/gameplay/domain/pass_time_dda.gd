## 通关耗时动态难度：比较最近十局与各自中位用时，给出策略段位和棋盘尺寸调整。
class_name PassTimeDda
extends RefCounted

enum Verdict { NONE, FAST, SLOW }

const WINDOW_SIZE: int = 10
const SLOW_THRESHOLD: int = 6
const SIZE_MIN: int = 8
const SIZE_MAX: int = 10
const NORMAL_SOURCES: Array[String] = ["regular", "lkstyle", "gc"]


## 限定耗时统计的普通题库来源为 regular、lkstyle 和 gc。
static func is_normal_level_source(source: String) -> bool:
	return source in NORMAL_SOURCES


## 最近十局中至少六局慢于中位用时就判慢；样本不足或数组长度不符时不判定。
static func evaluate(pass_secs: Array[int], median_secs: Array[int]) -> int:
	if pass_secs.size() < WINDOW_SIZE or median_secs.size() != pass_secs.size():
		return Verdict.NONE
	var start: int = pass_secs.size() - WINDOW_SIZE
	var slow_count: int = 0
	for i: int in range(start, pass_secs.size()):
		if pass_secs[i] > median_secs[i]:
			slow_count += 1
	return Verdict.SLOW if slow_count >= SLOW_THRESHOLD else Verdict.FAST


## 按当前关号给出允许采用的策略段位上下界。
static func segment_strategy_bounds(level_num: int) -> Vector2i:
	if level_num <= 5:
		return Vector2i(1, 1)
	if level_num <= 20:
		return Vector2i(1, 2)
	if level_num <= 50:
		return Vector2i(1, 3)
	return Vector2i(2, 4)


## 快组取当前关段的策略上界，慢组取下界，未判定时返回零。
static func forced_strategy(level_num: int, verdict: int) -> int:
	var bounds: Vector2i = segment_strategy_bounds(level_num)
	if verdict == Verdict.FAST:
		return bounds.y
	if verdict == Verdict.SLOW:
		return bounds.x
	return 0


## 根据快慢判断把棋盘尺寸增减一，调整边界分别为 10 和 8。
static func adjusted_size(base_size: int, verdict: int) -> int:
	if verdict == Verdict.FAST:
		return mini(base_size + 1, SIZE_MAX)
	if verdict == Verdict.SLOW:
		return maxi(base_size - 1, SIZE_MIN)
	return base_size


## 把快慢判定转换成记录与调试使用的字符串。
static func verdict_name(verdict: int) -> String:
	match verdict:
		Verdict.FAST:
			return "fast"
		Verdict.SLOW:
			return "slow"
		_:
			return "none"
