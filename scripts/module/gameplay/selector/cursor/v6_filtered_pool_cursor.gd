## 第六版过滤题池游标：每个过滤条件键单独保存索引与变换轮次。
class_name V6FilteredPoolCursor
extends BankCursor

var _key: String
var _total: int


## 保存过滤题池键，统计题数并处理跨轮。
func _init(key: String, pools: Dictionary) -> void:
	_key = key
	_total = _pool_total(pools)
	_ensure_rollover()


## 返回该过滤题池的当前位置与变换，不插入 LK 改题库。
func pos() -> Dictionary:
	_ensure_rollover()
	var progress: Dictionary = GameState.get_nl_v6_pool_progress(_key)
	return {
		"idx": int(progress.get("idx", 0)),
		"since_lk": 0,
		"transform": int(progress.get("transform", 0)),
		"lk_idx": 0,
		"is_main_path": true,
	}


## 复制进度后增加索引，暂不落盘。
func advance(_entry: Dictionary) -> void:
	var progress: Dictionary = GameState.get_nl_v6_pool_progress(_key).duplicate()
	progress["idx"] = int(progress.get("idx", 0)) + 1
	GameState.set_nl_v6_pool_progress(_key, progress, false)


## 过滤结果变化后重算长度并处理越界轮换。
func rebind_pools(pools: Dictionary) -> void:
	_total = _pool_total(pools)
	_ensure_rollover()


## 题池总数乘八种变换，作为有限扫描预算。
func budget() -> int:
	return _total * LevelData.TRANSFORM_COUNT


## 索引用尽后切换变换并归零，只修改内存进度。
func _ensure_rollover() -> void:
	if _total <= 0:
		return
	var progress: Dictionary = GameState.get_nl_v6_pool_progress(_key)
	if int(progress.get("idx", 0)) < _total:
		return
	var next_transform: int = (int(progress.get("transform", 0)) + 1) % LevelData.TRANSFORM_COUNT
	GameState.set_nl_v6_pool_progress(_key, {"idx": 0, "transform": next_transform}, false)


## 合计三个普通来源的过滤后题目数量。
static func _pool_total(pools: Dictionary) -> int:
	return (
		(pools.get("regular", []) as Array).size()
		+ (pools.get("lkstyle", []) as Array).size()
		+ (pools.get("gc", []) as Array).size()
	)
