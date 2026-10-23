## 题库内存索引：通过 LevelBankIO 懒加载不同来源的题库，并按尺寸、策略层级和玩法提供缓存。
## 紧凑题目通过编解码器展开；节奏数据单独加载且必须与主题库条数一致。
class_name BankData
extends RefCounted

const _LEVEL_CODEC: GDScript = preload("res://scripts/module/bank/model/bank_level_codec.gd")


## 复制题目字典并展开紧凑字段，是否深拷贝由调用方指定。
static func materialize_entry(entry: Dictionary, deep_copy: bool = false) -> Dictionary:
	return _LEVEL_CODEC.materialize_entry(entry, deep_copy)


## 通过题库编解码器读取二维区域矩阵，兼容紧凑字节表示。
static func get_region_map(entry: Dictionary) -> Array:
	return _LEVEL_CODEC.get_region_map(entry)


## 通过题库编解码器读取普通数组形式的答案向量。
static func get_solution(entry: Dictionary) -> Array:
	return _LEVEL_CODEC.get_solution(entry)


# ================= 常规题库（bankData{尺寸}x{尺寸}.json） =================
# ---- 缓存：按尺寸懒加载，顶层形如 {"1": [...], ..., "5": [...]} ----
static var _cache: Dictionary = {} # 键 "尺寸_难度"，值 = 该难度的关卡数组
static var _loaded_sizes: Array[int] = [] # 已读过的尺寸（成功失败都记，避免反复读盘）

static var _main_counts: Dictionary = {}


## 按尺寸加载常规题库，缓存非空策略层级并记录各层条数供节奏数据校验。
static func _load_size(sz: int) -> void:
	if sz in _loaded_sizes:
		return
	_loaded_sizes.append(sz)
	var data: Variant = LevelBankIO.load_json("bankData%dx%d.json" % [sz, sz])
	if not (data is Dictionary):
		return
	var counts: Dictionary = {}
	for rank_str: String in (data as Dictionary).keys():
		var rank: int = int(rank_str)
		var levels: Array = data[rank_str]
		counts[rank_str] = levels.size()
		if levels.size() > 0:
			_cache["%d_%d" % [sz, rank]] = levels
	_main_counts["%s|%d" % [_PACE_GROUP_REGULAR, sz]] = counts


## 真正有题目的尺寸（按固定候选表逐个探测，返回有内容的那些）
static func get_sizes() -> Array[int]:
	var all_sizes: Array[int] = [4, 5, 6, 7, 8, 9, 10, 12]
	for sz: int in all_sizes:
		_load_size(sz)
	var result: Array[int] = []
	for sz: int in all_sizes:
		if get_ranks(sz).size() > 0:
			result.append(sz)
	return result


## 某尺寸下存在的难度号，按 1~5 从小到大
static func get_ranks(sz: int) -> Array[int]:
	_load_size(sz)
	var result: Array[int] = []
	for rank: int in [1, 2, 3, 4, 5]:
		var key := "%d_%d" % [sz, rank]
		if _cache.has(key) and (_cache[key] as Array).size() > 0:
			result.append(rank)
	return result


## 某尺寸某难度的全部关卡；没有这份数据就返回空数组
static func get_levels(sz: int, rank: int) -> Array:
	_load_size(sz)
	return _cache.get("%d_%d" % [sz, rank], [])


## 某尺寸某难度的关卡数
static func get_level_count(sz: int, rank: int) -> int:
	return get_levels(sz, rank).size()


## 再按档位过滤（"N" 常规档 / "H" 困难档）；缺 tier 字段的关卡按空串比较，不会误命中
static func get_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
	var all: Array = get_levels(sz, rank)
	var result: Array = []
	for l in all:
		if l.get("tier", "") == tier:
			result.append(l)
	return result


## 某尺寸某难度某档位的关卡数
static func get_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
	return get_levels_by_tier(sz, rank, tier).size()


# ================= LK 题库（LinkedIn Queens 存档） =================
# ---- 整份缓存：原版与改题库各存一个数组，不再按尺寸难度切 ----
static var _lk_levels: Array = [] # LK 原版关卡（bankDataLK.json 整个文件）
static var _lk_loaded: bool = false # 是否已尝试加载过（读到空也算）

static var _lk_modified_levels: Array = [] # LK 改题库关卡（bankDataLKModified.json 的 levels）
static var _lk_modified_loaded: bool = false # 是否已尝试加载过


## LK 改题库的全部关卡：bankDataLKModified.json 的 levels 字段（旋转/镜像变换版）
static func get_lk_modified_levels() -> Array:
	if _lk_modified_loaded:
		return _lk_modified_levels
	_lk_modified_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataLKModified.json")
	if data is Dictionary and data.has("levels"):
		_lk_modified_levels = data["levels"]
	return _lk_modified_levels


## LK 改题库关卡数
static func get_lk_modified_level_count() -> int:
	return get_lk_modified_levels().size()


## LK 原版全部关卡：bankDataLK.json 整个文件就是一个数组，按日期排序
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
static var _lk_style_cache: Dictionary = {} # 尺寸 -> { 难度: 关卡数组 }
static var _lk_style_loaded_sizes: Array[int] = [] # 已读过的尺寸
const _LK_STYLE_KNOWN_SIZES: Array[int] = [7, 8, 9, 10, 11, 12] # LK 优化版候选尺寸（实际有没有看文件在不在）


## 按尺寸加载 LK 风格题库，建立尺寸和策略层级两层缓存及条数索引。
static func _load_lk_style_size(sz: int) -> void:
	if sz in _lk_style_loaded_sizes:
		return
	_lk_style_loaded_sizes.append(sz)
	var data: Variant = LevelBankIO.load_json("bankDataLKStyle%dx%d.json" % [sz, sz])
	if not (data is Dictionary):
		return
	var size_cache: Dictionary = {}
	var counts: Dictionary = {}
	for rank_str: String in (data as Dictionary).keys():
		var rank: int = int(rank_str)
		var levels: Array = data[rank_str]
		counts[rank_str] = levels.size()
		if levels.size() > 0:
			size_cache[rank] = levels
	if size_cache.size() > 0:
		_lk_style_cache[sz] = size_cache
	_main_counts["%s|%d" % [_PACE_GROUP_LKSTYLE, sz]] = counts


## LK 优化题库里有题目的尺寸
static func get_lk_style_sizes() -> Array[int]:
	for sz in _LK_STYLE_KNOWN_SIZES:
		_load_lk_style_size(sz)
	var result: Array[int] = []
	for sz in _LK_STYLE_KNOWN_SIZES:
		if _lk_style_cache.has(sz) and (_lk_style_cache[sz] as Dictionary).size() > 0:
			result.append(sz)
	return result


## LK 优化题库某尺寸下存在的难度号
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


## LK 优化题库某尺寸某难度的全部关卡
static func get_lk_style_levels(sz: int, rank: int) -> Array:
	_load_lk_style_size(sz)
	if not _lk_style_cache.has(sz):
		return []
	return (_lk_style_cache[sz] as Dictionary).get(rank, [])


## LK 优化题库某尺寸某难度的关卡数
static func get_lk_style_level_count(sz: int, rank: int) -> int:
	return get_lk_style_levels(sz, rank).size()


## LK 优化题库按档位过滤（"N" / "H"）
static func get_lk_style_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
	var all: Array = get_lk_style_levels(sz, rank)
	var result: Array = []
	for l in all:
		var l_tier: String = l.get("tier", "")
		if l_tier == tier:
			result.append(l)
	return result


## 上面的计数版本
static func get_lk_style_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
	return get_lk_style_levels_by_tier(sz, rank, tier).size()


# ================= GC 题库（bankDataGC{尺寸}x{尺寸}.json） =================
# ---- 缓存：顶层是 {"levels": [...]}，难度写在每关的 "r" 字段 ----
static var _gc_cache: Dictionary = {} # 尺寸 -> 关卡数组（难度得现扫每关的 r 字段）
static var _gc_loaded_sizes: Array[int] = [] # 已读过的尺寸
const _GC_KNOWN_SIZES: Array[int] = [6, 7, 8, 9, 10, 11, 12] # GC 题库候选尺寸


## 读取 GC 题库的 levels 数组，保留原顺序，并记下节奏数据应有的总条数。
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

	if (data as Dictionary).has("levels"):
		_main_counts["%s|%d" % [_PACE_GROUP_GC, sz]] = {"levels": levels.size()}


## GC 题库里有题目的尺寸
static func get_gc_sizes() -> Array[int]:
	for sz: int in _GC_KNOWN_SIZES:
		_load_gc_size(sz)
	var result: Array[int] = []
	for sz: int in _GC_KNOWN_SIZES:
		if _gc_cache.has(sz) and (_gc_cache[sz] as Array).size() > 0:
			result.append(sz)
	return result


## GC 题库某尺寸里出现过的难度号（扫每关的 r 字段现算）
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


## GC 题库某尺寸某难度的关卡（按 r 字段过滤）
static func get_gc_levels(sz: int, rank: int) -> Array:
	_load_gc_size(sz)
	if not _gc_cache.has(sz):
		return []
	var result: Array = []
	for l: Variant in _gc_cache[sz] as Array:
		if int((l as Dictionary).get("r", 0)) == rank:
			result.append(l)
	return result


## GC 题库某尺寸某难度的关卡数
static func get_gc_level_count(sz: int, rank: int) -> int:
	return get_gc_levels(sz, rank).size()


## GC 题库按档位过滤（"N" / "H"）
static func get_gc_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
	var result: Array = []
	for l: Variant in get_gc_levels(sz, rank):
		if (l as Dictionary).get("tier", "") == tier:
			result.append(l)
	return result


## 上面的计数版本
static func get_gc_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
	return get_gc_levels_by_tier(sz, rank, tier).size()


static var _onefish_cache: Dictionary = {}
static var _onefish_loaded_sizes: Array[int] = []
const _ONEFISH_KNOWN_SIZES: Array[int] = [7, 8, 9, 10]


## 每个尺寸只尝试加载一次一命关题库，非空 levels 才进入缓存。
static func _load_onefish_size(sz: int) -> void:
	if sz in _onefish_loaded_sizes:
		return
	_onefish_loaded_sizes.append(sz)
	var data: Variant = LevelBankIO.load_json("bankDataOneFish%dx%d.json" % [sz, sz])
	if not (data is Dictionary):
		return
	var levels: Array = (data as Dictionary).get("levels", [])
	if levels.size() > 0:
		_onefish_cache[sz] = levels


## 探测候选尺寸，返回真正加载到一命关题目的尺寸列表。
static func get_onefish_sizes() -> Array[int]:
	for sz: int in _ONEFISH_KNOWN_SIZES:
		_load_onefish_size(sz)
	var result: Array[int] = []
	for sz: int in _ONEFISH_KNOWN_SIZES:
		if _onefish_cache.has(sz) and (_onefish_cache[sz] as Array).size() > 0:
			result.append(sz)
	return result


## 扫描一命关题目的 r 字段，按 1～5 返回实际存在的策略层级。
static func get_onefish_ranks(sz: int) -> Array[int]:
	_load_onefish_size(sz)
	if not _onefish_cache.has(sz):
		return []
	var seen: Dictionary = {}
	for l: Variant in _onefish_cache[sz] as Array:
		seen[int((l as Dictionary).get("r", 0))] = true
	var result: Array[int] = []
	for rank: int in [1, 2, 3, 4, 5]:
		if seen.has(rank):
			result.append(rank)
	return result


## 从指定尺寸的一命关缓存中筛出目标策略层级。
static func get_onefish_levels(sz: int, rank: int) -> Array:
	_load_onefish_size(sz)
	if not _onefish_cache.has(sz):
		return []
	var result: Array = []
	for l: Variant in _onefish_cache[sz] as Array:
		if int((l as Dictionary).get("r", 0)) == rank:
			result.append(l)
	return result


## 返回指定尺寸与策略层级的一命关题目数。
static func get_onefish_level_count(sz: int, rank: int) -> int:
	return get_onefish_levels(sz, rank).size()


static var _hard_r4_levels: Array = []
static var _hard_r4_loaded: bool = false


## 首次请求时加载困难 R4 题库，后续复用同一数组。
static func get_hard_r4_levels() -> Array:
	if not _hard_r4_loaded:
		_hard_r4_loaded = true
		var data: Variant = LevelBankIO.load_json("bankDataHardR4.json")
		if data is Dictionary and data.has("levels"):
			_hard_r4_levels = data["levels"]
	return _hard_r4_levels


# ================= SP 特殊图案题库（bankDataSP.json） =================
# ---- 缓存：一次性读入整个 levels 数组 ----
static var _sp_levels: Array = [] # SP 关卡数组
static var _sp_loaded: bool = false # 是否已尝试加载过


## 懒加载 SP 题库：只读一次 bankDataSP.json
static func _load_sp() -> void:
	if _sp_loaded:
		return
	_sp_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataSP.json")
	if data is Dictionary and data.has("levels"):
		_sp_levels = data["levels"]


## 全部 SP 关卡（每关自带 pattern 图案名与 colorMap 配色表）
static func get_sp_levels() -> Array:
	_load_sp()
	return _sp_levels


## SP 关卡数
static func get_sp_level_count() -> int:
	return get_sp_levels().size()


## 清缓存后重新读 SP 题库；仓库内暂无调用方，留给需要热重载 SP 的场景
static func reload_sp() -> void:
	_sp_loaded = false
	_sp_levels = []
	_load_sp()


static var _digit_sp_levels: Array = []
static var _digit_sp_loaded: bool = false


## 懒加载数字图案特殊题库的 levels 数组。
static func get_digit_sp_levels() -> Array:
	if not _digit_sp_loaded:
		_digit_sp_loaded = true
		var data: Variant = LevelBankIO.load_json("bankDataDigitsSP.json")
		if data is Dictionary and data.has("levels"):
			_digit_sp_levels = data["levels"]
	return _digit_sp_levels


static var _super_hard_levels: Array = []
static var _super_hard_loaded: bool = false


## 懒加载超难题库，加载标记避免重复读盘。
static func _load_super_hard() -> void:
	if _super_hard_loaded:
		return
	_super_hard_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataSuperHard.json")
	if data is Dictionary and data.has("levels"):
		_super_hard_levels = data["levels"]


## 按 r 字段从超难题库筛出指定策略层级。
static func get_super_hard_levels(rank: int) -> Array:
	_load_super_hard()
	var result: Array = []
	for l: Variant in _super_hard_levels:
		if int((l as Dictionary).get("r", 0)) == rank:
			result.append(l)
	return result


## 返回超难题库缓存的全部题目。
static func get_all_super_hard_levels() -> Array:
	_load_super_hard()
	return _super_hard_levels


## 清除超难题库加载标记与缓存，再立即重新读盘。
static func reload_super_hard() -> void:
	_super_hard_loaded = false
	_super_hard_levels = []
	_load_super_hard()


static var _super_hard_r4_levels: Array = []
static var _super_hard_r4_loaded: bool = false


## 懒加载独立的超难 R4 题库。
static func _load_super_hard_r4() -> void:
	if _super_hard_r4_loaded:
		return
	_super_hard_r4_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataSuperHardR4.json")
	if data is Dictionary and data.has("levels"):
		_super_hard_r4_levels = data["levels"]


## 返回超难 R4 题库的完整缓存数组。
static func get_all_super_hard_r4_levels() -> Array:
	_load_super_hard_r4()
	return _super_hard_r4_levels


static var _sp_tt_levels: Array = []
static var _sp_tt_loaded: bool = false


## 首次请求时加载 SP_TT 特殊题库。
static func _load_sp_tt() -> void:
	if _sp_tt_loaded:
		return
	_sp_tt_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataSP_TT.json")
	if data is Dictionary and data.has("levels"):
		_sp_tt_levels = data["levels"]


## 返回 SP_TT 特殊题库的全部题目。
static func get_sp_tt_levels() -> Array:
	_load_sp_tt()
	return _sp_tt_levels


## 返回 SP_TT 特殊题库条数。
static func get_sp_tt_level_count() -> int:
	return get_sp_tt_levels().size()


## 清掉 SP_TT 缓存和加载标记后重新读盘。
static func reload_sp_tt() -> void:
	_sp_tt_loaded = false
	_sp_tt_levels = []
	_load_sp_tt()


static var _single_region_levels: Array = []
static var _single_region_loaded: bool = false


## 首次请求时加载单格区域补充题库。
static func _load_single_region() -> void:
	if _single_region_loaded:
		return
	_single_region_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataSingleRegion.json")
	if data is Dictionary and data.has("levels"):
		_single_region_levels = data["levels"]


## 返回单格区域补充题库缓存。
static func get_single_region_levels() -> Array:
	_load_single_region()
	return _single_region_levels


## 返回单格区域补充题库条数。
static func get_single_region_level_count() -> int:
	return get_single_region_levels().size()


## 清掉单格区域补充题库缓存后立即重载。
static func reload_single_region() -> void:
	_single_region_loaded = false
	_single_region_levels = []
	_load_single_region()


static var _climax_filter_levels: Array = []
static var _climax_filter_loaded: bool = false


## 首次请求时加载高潮筛选题库。
static func _load_climax_filter() -> void:
	if _climax_filter_loaded:
		return
	_climax_filter_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataClimaxFilters.json")
	if data is Dictionary and data.has("levels"):
		_climax_filter_levels = data["levels"]


## 返回高潮筛选题库缓存。
static func get_climax_filter_levels() -> Array:
	_load_climax_filter()
	return _climax_filter_levels


## 返回高潮筛选题库条数。
static func get_climax_filter_level_count() -> int:
	return get_climax_filter_levels().size()


## 清除高潮筛选题库缓存与加载标记，再重新读盘。
static func reload_climax_filter() -> void:
	_climax_filter_loaded = false
	_climax_filter_levels = []
	_load_climax_filter()


static var _color_challenge_levels: Array = []
static var _color_challenge_loaded: bool = false

const _CC_FIRST_LEVEL_INDEX: int = 0


## 首次请求时加载颜色挑战题库。
static func _load_color_challenge() -> void:
	if _color_challenge_loaded:
		return
	_color_challenge_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataColorChallenge.json")
	if data is Dictionary and data.has("levels"):
		_color_challenge_levels = data["levels"]


## 返回颜色挑战完整题库，包括索引零的固定首题。
static func get_all_color_challenge_levels() -> Array:
	_load_color_challenge()
	return _color_challenge_levels


## 返回颜色挑战固定首题，题库为空时返回空字典。
static func get_color_challenge_first_level() -> Dictionary:
	_load_color_challenge()
	if _color_challenge_levels.size() <= _CC_FIRST_LEVEL_INDEX:
		return {}
	return _color_challenge_levels[_CC_FIRST_LEVEL_INDEX] as Dictionary


## 跳过固定首题后，按尺寸与策略层级筛选颜色挑战题目。
static func get_color_challenge_levels(sz: int, rank: int) -> Array:
	_load_color_challenge()
	var result: Array = []
	for idx: int in range(_color_challenge_levels.size()):
		if idx == _CC_FIRST_LEVEL_INDEX:
			continue
		var entry: Dictionary = _color_challenge_levels[idx] as Dictionary
		if int(entry.get("size", 0)) == sz and int(entry.get("r", 0)) == rank:
			result.append(entry)
	return result


## 统计指定尺寸与策略层级的颜色挑战题数，不包含固定首题。
static func get_color_challenge_level_count(sz: int, rank: int) -> int:
	return get_color_challenge_levels(sz, rank).size()


## 清除颜色挑战缓存与加载标记，立即重新读取题库。
static func reload_color_challenge() -> void:
	_color_challenge_loaded = false
	_color_challenge_levels = []
	_load_color_challenge()


const _PACE_GROUP_REGULAR := "regular"
const _PACE_GROUP_LKSTYLE := "lkstyle"
const _PACE_GROUP_GC := "gc"

static var _pace_regular_cache: Dictionary = {}
static var _pace_regular_valid: Dictionary = {}
static var _pace_lkstyle_cache: Dictionary = {}
static var _pace_lkstyle_valid: Dictionary = {}

static var _pace_gc_cache: Dictionary = {}
static var _pace_gc_valid: Dictionary = {}

static var _pace_lkmod_cache: Array = []
static var _pace_lkmod_valid: bool = false
static var _pace_lkmod_loaded: bool = false


## 按题库来源和尺寸生成对应 .pace.json 文件名，未知来源返回空串。
static func _pace_filename(group: String, sz: int) -> String:
	match group:
		_PACE_GROUP_REGULAR:
			return "bankData%dx%d.pace.json" % [sz, sz]
		_PACE_GROUP_LKSTYLE:
			return "bankDataLKStyle%dx%d.pace.json" % [sz, sz]
		_PACE_GROUP_GC:
			return "bankDataGC%dx%d.pace.json" % [sz, sz]
	return ""


## 为当前尺寸的非空主题库预热节奏记录，并确保 LK 改题库节奏已加载。
static func prewarm_pace(sz: int) -> void:
	if sz <= 0:
		return

	if not _pace_regular_cache.has(sz) and get_ranks(sz).size() > 0:
		_load_pace_regular_or_lkstyle(sz, _PACE_GROUP_REGULAR)
	if not _pace_lkstyle_cache.has(sz) and get_lk_style_ranks(sz).size() > 0:
		_load_pace_regular_or_lkstyle(sz, _PACE_GROUP_LKSTYLE)
	if not _pace_gc_cache.has(sz) and get_gc_ranks(sz).size() > 0:
		_load_pace_gc(sz)
	_ensure_lkmod_pace_loaded()


## 按来源把节奏查询分派到相应缓存，未知来源返回空字典。
static func get_pace_entry(group: String, sz: int, rank: int, idx: int) -> Dictionary:
	if group == _PACE_GROUP_REGULAR:
		return _get_pace_regular(sz, rank, idx)
	if group == _PACE_GROUP_LKSTYLE:
		return _get_pace_lkstyle(sz, rank, idx)
	if group == _PACE_GROUP_GC:
		return _get_pace_gc(sz, idx)
	return {}


## 用 LK 改题库原始索引读取节奏，数据无效或越界时返回空字典。
static func get_lkmod_pace_by_original_idx(original_idx: int) -> Dictionary:
	_ensure_lkmod_pace_loaded()
	if not _pace_lkmod_valid:
		return {}
	if original_idx < 0 or original_idx >= _pace_lkmod_cache.size():
		return {}
	return _pace_lkmod_cache[original_idx]


## 按尺寸、层级和索引取常规题库节奏，缺失时先加载。
static func _get_pace_regular(sz: int, rank: int, idx: int) -> Dictionary:
	if not _pace_regular_cache.has(sz):
		_load_pace_regular_or_lkstyle(sz, _PACE_GROUP_REGULAR)
	if not _pace_regular_valid.get(sz, false):
		return {}
	var by_rank: Dictionary = _pace_regular_cache[sz]
	var arr: Array = by_rank.get(str(rank), [])
	if idx < 0 or idx >= arr.size():
		return {}
	return arr[idx]


## 按尺寸、层级和索引取 LK 风格节奏，缓存无效或索引越界时返回空字典。
static func _get_pace_lkstyle(sz: int, rank: int, idx: int) -> Dictionary:
	if not _pace_lkstyle_cache.has(sz):
		_load_pace_regular_or_lkstyle(sz, _PACE_GROUP_LKSTYLE)
	if not _pace_lkstyle_valid.get(sz, false):
		return {}
	var by_rank: Dictionary = _pace_lkstyle_cache[sz]
	var arr: Array = by_rank.get(str(rank), [])
	if idx < 0 or idx >= arr.size():
		return {}
	return arr[idx]


## 按 GC 原始 levels 索引读取节奏，不按策略层级重新编号。
static func _get_pace_gc(sz: int, idx: int) -> Dictionary:
	if not _pace_gc_cache.has(sz):
		_load_pace_gc(sz)
	if not _pace_gc_valid.get(sz, false):
		return {}
	var arr: Array = _pace_gc_cache[sz]
	if idx < 0 or idx >= arr.size():
		return {}
	return arr[idx]


## 确保对应主题库加载完成，并返回其各层或总条数供节奏数据校验。
static func _ensure_main_counts(group: String, sz: int) -> Variant:
	match group:
		_PACE_GROUP_REGULAR:
			_load_size(sz)
		_PACE_GROUP_LKSTYLE:
			_load_lk_style_size(sz)
		_PACE_GROUP_GC:
			_load_gc_size(sz)
		_:
			return null
	var key: String = "%s|%d" % [group, sz]
	return _main_counts[key] if _main_counts.has(key) else null


## 逐层核对节奏数组与主题库长度，完全一致才把该尺寸缓存标为有效。
static func _load_pace_regular_or_lkstyle(sz: int, group: String) -> void:
	var fname: String = _pace_filename(group, sz)
	if fname == "":
		_mark_pace_invalid(sz, group)
		return
	var data: Variant = LevelBankIO.load_json(fname)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		_mark_pace_invalid(sz, group)
		return

	var counts: Variant = _ensure_main_counts(group, sz)
	if counts == null:
		_mark_pace_invalid(sz, group)
		return
	for rk: String in (counts as Dictionary).keys():
		var main_size: int = counts[rk]
		var side_arr: Array = data.get(rk, [])
		if side_arr.size() != main_size:
			push_error(
				(
					"[pace] %s sz=%d rank=%s size mismatch: main=%d side=%d"
					% [group, sz, rk, main_size, side_arr.size()]
				)
			)
			_mark_pace_invalid(sz, group)
			return
	if group == _PACE_GROUP_REGULAR:
		_pace_regular_cache[sz] = data
		_pace_regular_valid[sz] = true
	else:
		_pace_lkstyle_cache[sz] = data
		_pace_lkstyle_valid[sz] = true


## 核对 GC 节奏 levels 与主题库总条数，避免索引对应到错误题目。
static func _load_pace_gc(sz: int) -> void:
	var fname: String = _pace_filename(_PACE_GROUP_GC, sz)
	var data: Variant = LevelBankIO.load_json(fname)
	if data == null or typeof(data) != TYPE_DICTIONARY or not data.has("levels"):
		_mark_pace_invalid(sz, _PACE_GROUP_GC)
		return

	var counts: Variant = _ensure_main_counts(_PACE_GROUP_GC, sz)
	if counts == null:
		_mark_pace_invalid(sz, _PACE_GROUP_GC)
		return
	var main_total: int = (counts as Dictionary).get("levels", 0)
	if data["levels"].size() != main_total:
		push_error(
			(
				"[pace] gc sz=%d size mismatch: main=%d side=%d"
				% [sz, main_total, data["levels"].size()]
			)
		)
		_mark_pace_invalid(sz, _PACE_GROUP_GC)
		return
	_pace_gc_cache[sz] = data["levels"]
	_pace_gc_valid[sz] = true


## 只尝试加载一次 LK 改题库节奏，并核对其条数与主题库一致。
static func _ensure_lkmod_pace_loaded() -> void:
	if _pace_lkmod_loaded:
		return
	_pace_lkmod_loaded = true
	var data: Variant = LevelBankIO.load_json("bankDataLKModified.pace.json")
	if data == null or typeof(data) != TYPE_DICTIONARY or not data.has("levels"):
		_pace_lkmod_valid = false
		push_error("[pace] lkmod sidecar 无效或缺 'levels' key")
		return

	var side_arr: Array = data["levels"]
	var main_size: int = get_lk_modified_levels().size()
	if side_arr.size() != main_size:
		_pace_lkmod_valid = false
		push_error("[pace] lkmod size mismatch: main=%d side=%d" % [main_size, side_arr.size()])
		return
	_pace_lkmod_cache = side_arr
	_pace_lkmod_valid = true


## 记录节奏数据错误并写入无效缓存，防止后续反复读盘。
static func _mark_pace_invalid(sz: int, group: String) -> void:
	push_error("[pace] mark invalid: group=%s sz=%d" % [group, sz])
	match group:
		_PACE_GROUP_REGULAR:
			_pace_regular_cache[sz] = {}
			_pace_regular_valid[sz] = false
		_PACE_GROUP_LKSTYLE:
			_pace_lkstyle_cache[sz] = {}
			_pace_lkstyle_valid[sz] = false
		_PACE_GROUP_GC:
			_pace_gc_cache[sz] = []
			_pace_gc_valid[sz] = false
