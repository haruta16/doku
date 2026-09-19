# 题库数据访问层：把 bankData*.json 懒加载进静态缓存，对外只暴露查询函数
# 六套题库各有独立缓存：常规 / LK / LK改 / LK优化(LKStyle) / GC / SP；只有 SP 提供 reload
class_name BankData
extends RefCounted

# ================= 常规题库（bankData{尺寸}x{尺寸}.json） =================
# ---- 缓存：按尺寸懒加载，顶层形如 {"1": [...], ..., "5": [...]} ----
static var _cache: Dictionary = {}  # 键 "尺寸_难度"，值 = 该难度的关卡数组
static var _loaded_sizes: Array[int] = []  # 已读过的尺寸（成功失败都记，避免反复读盘）


# 按尺寸加载常规题库：读过就跳过；文件缺失或格式不对就静默返回（不报错）
static func _load_size(sz: int) -> void:
	if sz in _loaded_sizes:
		return
	_loaded_sizes.append(sz)  # 先记账再读盘：失败了也不会被反复重试
	var data: Variant = LevelBankIO.load_json("bankData%dx%d.json" % [sz, sz])
	if not (data is Dictionary):
		return
	for rank_str: String in (data as Dictionary).keys():
		var rank: int = int(rank_str)  # JSON 对象键只能是字符串，这里转回 1~5 的难度号
		var levels: Array = data[rank_str]
		if levels.size() > 0:
			_cache["%d_%d" % [sz, rank]] = levels  # 空数组不缓存，等价于「该难度不存在」


# 真正有题目的尺寸（按固定候选表逐个探测，返回有内容的那些）
static func get_sizes() -> Array[int]:
	var all_sizes: Array[int] = [4, 5, 6, 7, 8, 9, 10, 12]
	for sz: int in all_sizes:
		_load_size(sz)
	var result: Array[int] = []
	for sz: int in all_sizes:
		if get_ranks(sz).size() > 0:
			result.append(sz)
	return result


# 某尺寸下存在的难度号，按 1~5 从小到大
static func get_ranks(sz: int) -> Array[int]:
	_load_size(sz)
	var result: Array[int] = []
	for rank: int in [1, 2, 3, 4, 5]:
		var key := "%d_%d" % [sz, rank]
		if _cache.has(key) and (_cache[key] as Array).size() > 0:
			result.append(rank)
	return result


# 某尺寸某难度的全部关卡；没有这份数据就返回空数组
static func get_levels(sz: int, rank: int) -> Array:
	_load_size(sz)
	return _cache.get("%d_%d" % [sz, rank], [])


# 某尺寸某难度的关卡数
static func get_level_count(sz: int, rank: int) -> int:
	return get_levels(sz, rank).size()


# 再按档位过滤（"N" 常规档 / "H" 困难档）；缺 tier 字段的关卡按空串比较，不会误命中
static func get_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
	var all: Array = get_levels(sz, rank)
	var result: Array = []
	for l in all:
		if l.get("tier", "") == tier:
			result.append(l)
	return result


# 某尺寸某难度某档位的关卡数
static func get_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
	return get_levels_by_tier(sz, rank, tier).size()


# ================= LK 题库（LinkedIn Queens 存档） =================
# ---- 整份缓存：原版与改题库各存一个数组，不再按尺寸难度切 ----
static var _lk_levels: Array = []  # LK 原版关卡（bankDataLK.json 整个文件）
static var _lk_loaded: bool = false  # 是否已尝试加载过（读到空也算）

static var _lk_modified_levels: Array = []  # LK 改题库关卡（bankDataLKModified.json 的 levels）
static var _lk_modified_loaded: bool = false  # 是否已尝试加载过


# LK 改题库的全部关卡：bankDataLKModified.json 的 levels 字段（旋转/镜像变换版）
static func get_lk_modified_levels() -> Array:
	if _lk_modified_loaded:
		return _lk_modified_levels
	_lk_modified_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataLKModified.json")
	if data is Dictionary and data.has("levels"):
		_lk_modified_levels = data["levels"]
	return _lk_modified_levels


# LK 改题库关卡数
static func get_lk_modified_level_count() -> int:
	return get_lk_modified_levels().size()


# LK 原版全部关卡：bankDataLK.json 整个文件就是一个数组，按日期排序
static func get_lk_levels() -> Array:
	if _lk_loaded:
		return _lk_levels
	_lk_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataLK.json")
	if data is Array:
		_lk_levels = data
	return _lk_levels


# ================= LK 优化题库（bankDataLKStyle{尺寸}x{尺寸}.json） =================
# ---- 缓存：分「尺寸 -> 难度」两层，只有非空的难度才进缓存 ----
static var _lk_style_cache: Dictionary = {}  # 尺寸 -> { 难度: 关卡数组 }
static var _lk_style_loaded_sizes: Array[int] = []  # 已读过的尺寸
const _LK_STYLE_KNOWN_SIZES: Array[int] = [7, 8, 9, 10, 11, 12]  # LK 优化版候选尺寸（实际有没有看文件在不在）


# 按尺寸加载 LK 优化题库：整份读进来拆成 {难度: 关卡数组}
static func _load_lk_style_size(sz: int) -> void:
	if sz in _lk_style_loaded_sizes:
		return
	_lk_style_loaded_sizes.append(sz)
	var data: Variant = LevelBankIO.load_json("bankDataLKStyle%dx%d.json" % [sz, sz])
	if not (data is Dictionary):
		return
	var size_cache: Dictionary = {}
	for rank_str: String in (data as Dictionary).keys():
		var rank: int = int(rank_str)
		var levels: Array = data[rank_str]
		if levels.size() > 0:
			size_cache[rank] = levels
	if size_cache.size() > 0:
		_lk_style_cache[sz] = size_cache


# LK 优化题库里有题目的尺寸
static func get_lk_style_sizes() -> Array[int]:
	for sz in _LK_STYLE_KNOWN_SIZES:
		_load_lk_style_size(sz)
	var result: Array[int] = []
	for sz in _LK_STYLE_KNOWN_SIZES:
		if _lk_style_cache.has(sz) and (_lk_style_cache[sz] as Dictionary).size() > 0:
			result.append(sz)
	return result


# LK 优化题库某尺寸下存在的难度号
static func get_lk_style_ranks(sz: int) -> Array[int]:
	_load_lk_style_size(sz)
	var result: Array[int] = []
	if not _lk_style_cache.has(sz):
		return result
	var sc: Dictionary = _lk_style_cache[sz]
	for rank: int in [1, 2, 3, 4, 5]:
		if sc.has(rank) and (sc[rank] as Array).size() > 0:
			result.append(rank)
	return result


# LK 优化题库某尺寸某难度的全部关卡
static func get_lk_style_levels(sz: int, rank: int) -> Array:
	_load_lk_style_size(sz)
	if not _lk_style_cache.has(sz):
		return []
	return (_lk_style_cache[sz] as Dictionary).get(rank, [])


# LK 优化题库某尺寸某难度的关卡数
static func get_lk_style_level_count(sz: int, rank: int) -> int:
	return get_lk_style_levels(sz, rank).size()


# LK 优化题库按档位过滤（"N" / "H"）
static func get_lk_style_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
	var all: Array = get_lk_style_levels(sz, rank)
	var result: Array = []
	for l in all:
		var l_tier: String = l.get("tier", "")
		if l_tier == tier:
			result.append(l)
	return result


# 上面的计数版本
static func get_lk_style_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
	return get_lk_style_levels_by_tier(sz, rank, tier).size()


# ================= GC 题库（bankDataGC{尺寸}x{尺寸}.json） =================
# ---- 缓存：顶层是 {"levels": [...]}，难度写在每关的 "r" 字段 ----
static var _gc_cache: Dictionary = {}  # 尺寸 -> 关卡数组（难度得现扫每关的 r 字段）
static var _gc_loaded_sizes: Array[int] = []  # 已读过的尺寸
const _GC_KNOWN_SIZES: Array[int] = [6, 7, 8, 9, 10, 11, 12]  # GC 题库候选尺寸


# 按尺寸加载 GC 题库：整个 levels 数组直接进缓存，难度过滤留到查询时做
static func _load_gc_size(sz: int) -> void:
	if sz in _gc_loaded_sizes:
		return
	_gc_loaded_sizes.append(sz)
	var data: Variant = LevelBankIO.load_json("bankDataGC%dx%d.json" % [sz, sz])
	if not (data is Dictionary):
		return
	var levels: Array = (data as Dictionary).get("levels", [])
	if levels.size() > 0:
		_gc_cache[sz] = levels


# GC 题库里有题目的尺寸
static func get_gc_sizes() -> Array[int]:
	for sz: int in _GC_KNOWN_SIZES:
		_load_gc_size(sz)
	var result: Array[int] = []
	for sz: int in _GC_KNOWN_SIZES:
		if _gc_cache.has(sz) and (_gc_cache[sz] as Array).size() > 0:
			result.append(sz)
	return result


# GC 题库某尺寸里出现过的难度号（扫每关的 r 字段现算）
static func get_gc_ranks(sz: int) -> Array[int]:
	_load_gc_size(sz)
	if not _gc_cache.has(sz):
		return []
	var seen: Dictionary = {}
	for l: Variant in _gc_cache[sz] as Array:
		seen[int((l as Dictionary).get("r", 0))] = true
	var result: Array[int] = []
	for rank: int in [1, 2, 3, 4, 5]:
		if seen.has(rank):
			result.append(rank)
	return result


# GC 题库某尺寸某难度的关卡（按 r 字段过滤）
static func get_gc_levels(sz: int, rank: int) -> Array:
	_load_gc_size(sz)
	if not _gc_cache.has(sz):
		return []
	var result: Array = []
	for l: Variant in _gc_cache[sz] as Array:
		if int((l as Dictionary).get("r", 0)) == rank:
			result.append(l)
	return result


# GC 题库某尺寸某难度的关卡数
static func get_gc_level_count(sz: int, rank: int) -> int:
	return get_gc_levels(sz, rank).size()


# GC 题库按档位过滤（"N" / "H"）
static func get_gc_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
	var result: Array = []
	for l: Variant in get_gc_levels(sz, rank):
		if (l as Dictionary).get("tier", "") == tier:
			result.append(l)
	return result


# 上面的计数版本
static func get_gc_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
	return get_gc_levels_by_tier(sz, rank, tier).size()


# ================= SP 特殊图案题库（bankDataSP.json） =================
# ---- 缓存：一次性读入整个 levels 数组 ----
static var _sp_levels: Array = []  # SP 关卡数组
static var _sp_loaded: bool = false  # 是否已尝试加载过


# 懒加载 SP 题库：只读一次 bankDataSP.json
static func _load_sp() -> void:
	if _sp_loaded:
		return
	_sp_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataSP.json")
	if data is Dictionary and data.has("levels"):
		_sp_levels = data["levels"]


# 全部 SP 关卡（每关自带 pattern 图案名与 colorMap 配色表）
static func get_sp_levels() -> Array:
	_load_sp()
	return _sp_levels


# SP 关卡数
static func get_sp_level_count() -> int:
	return get_sp_levels().size()


# 清缓存后重新读 SP 题库；仓库内暂无调用方，留给需要热重载 SP 的场景
static func reload_sp() -> void:
	_sp_loaded = false
	_sp_levels = []
	_load_sp()
