## 选题随机入口：生产环境使用引擎随机数，测试可注入有限序列来复现分支。
class_name LevelSelectionRandom
extends RefCounted

static var _injected: Array[int] = []
static var _test_mode: bool = false

static var _last_drawn: int = -1


## 在闭区间取随机整数；测试模式逐个消费注入值并检查范围。
static func pick_in_range(lo: int, hi: int) -> int:
	var value: int
	if not _test_mode:
		value = randi_range(lo, hi)
	else:
		assert(not _injected.is_empty(), "LevelSelectionRandom: 测试随机序列耗尽")
		value = _injected.pop_front()
		assert(
			value >= lo and value <= hi,
			"LevelSelectionRandom: 注入值 %d 越界 [%d, %d]" % [value, lo, hi]
		)
	_last_drawn = value
	return value


## 返回最近一次随机抽取值，供选题跟踪记录。
static func get_last_drawn() -> int:
	return _last_drawn


## 把整数权重转换成累计随机区间文字，便于检查分桶边界。
static func format_weight_buckets(weights: Array) -> String:
	var s: String = ""
	var cum: int = 0
	for i in weights.size():
		var start: int = cum
		cum += int(weights[i])
		if i > 0:
			s += "|"
		s += "%d-%d" % [start, cum - 1]
	return s


## 按整数权重累计区间抽取下标，权重总和必须为正。
static func pick_weighted(weights: Array) -> int:
	var total: int = 0
	for w in weights:
		total += int(w)
	assert(total > 0, "LevelSelectionRandom.pick_weighted: 权重总和必须 > 0")
	var r: int = pick_in_range(0, total - 1)
	var cum: int = 0
	for i in weights.size():
		cum += int(weights[i])
		if r < cum:
			return i
	return weights.size() - 1


## 复制固定随机序列并开启测试模式，避免调用方随后修改原数组。
static func inject_for_test(values: Array[int]) -> void:
	_injected = values.duplicate()
	_test_mode = true


## 清除注入序列并恢复引擎随机源。
static func clear_injection() -> void:
	_injected.clear()
	_test_mode = false
