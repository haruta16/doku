class_name BankData
extends RefCounted







static var _cache: Dictionary = {}
static var _loaded_sizes: Array[int] = []

static func _load_size(sz: int) -> void :
    if sz in _loaded_sizes:
        return
    _loaded_sizes.append(sz)
    var data: Variant = LevelBankIO.load_json("bankData%dx%d.json" % [sz, sz])
    if not (data is Dictionary):
        return
    for rank_str: String in (data as Dictionary).keys():
        var rank: int = int(rank_str)
        var levels: Array = data[rank_str]
        if levels.size() > 0:
            _cache["%d_%d" % [sz, rank]] = levels


static func get_sizes() -> Array[int]:
    var all_sizes: Array[int] = [4, 5, 6, 7, 8, 9, 10, 12]
    for sz: int in all_sizes:
        _load_size(sz)
    var result: Array[int] = []
    for sz: int in all_sizes:
        if get_ranks(sz).size() > 0:
            result.append(sz)
    return result


static func get_ranks(sz: int) -> Array[int]:
    _load_size(sz)
    var result: Array[int] = []
    for rank: int in [1, 2, 3, 4, 5]:
        var key: = "%d_%d" % [sz, rank]
        if _cache.has(key) and (_cache[key] as Array).size() > 0:
            result.append(rank)
    return result


static func get_levels(sz: int, rank: int) -> Array:
    _load_size(sz)
    return _cache.get("%d_%d" % [sz, rank], [])


static func get_level_count(sz: int, rank: int) -> int:
    return get_levels(sz, rank).size()


static func get_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
    var all: Array = get_levels(sz, rank)
    var result: Array = []
    for l in all:
        if l.get("tier", "") == tier:
            result.append(l)
    return result


static func get_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
    return get_levels_by_tier(sz, rank, tier).size()



static var _lk_levels: Array = []
static var _lk_loaded: bool = false



static var _lk_modified_levels: Array = []
static var _lk_modified_loaded: bool = false

static func get_lk_modified_levels() -> Array:
    if _lk_modified_loaded:
        return _lk_modified_levels
    _lk_modified_loaded = true
    var data: Variant = LevelBankIO.load_json("bankDataLKModified.json")
    if data is Dictionary and data.has("levels"):
        _lk_modified_levels = data["levels"]
    return _lk_modified_levels

static func get_lk_modified_level_count() -> int:
    return get_lk_modified_levels().size()


static func get_lk_levels() -> Array:
    if _lk_loaded:
        return _lk_levels
    _lk_loaded = true
    var data: Variant = LevelBankIO.load_json("bankDataLK.json")
    if data is Array:
        _lk_levels = data
    return _lk_levels




static var _lk_style_cache: Dictionary = {}
static var _lk_style_loaded_sizes: Array[int] = []
const _LK_STYLE_KNOWN_SIZES: Array[int] = [7, 8, 9, 10, 11, 12]

static func _load_lk_style_size(sz: int) -> void :
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


static func get_lk_style_sizes() -> Array[int]:
    for sz in _LK_STYLE_KNOWN_SIZES:
        _load_lk_style_size(sz)
    var result: Array[int] = []
    for sz in _LK_STYLE_KNOWN_SIZES:
        if _lk_style_cache.has(sz) and (_lk_style_cache[sz] as Dictionary).size() > 0:
            result.append(sz)
    return result


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


static func get_lk_style_levels(sz: int, rank: int) -> Array:
    _load_lk_style_size(sz)
    if not _lk_style_cache.has(sz):
        return []
    return (_lk_style_cache[sz] as Dictionary).get(rank, [])


static func get_lk_style_level_count(sz: int, rank: int) -> int:
    return get_lk_style_levels(sz, rank).size()


static func get_lk_style_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
    var all: Array = get_lk_style_levels(sz, rank)
    var result: Array = []
    for l in all:
        var l_tier: String = l.get("tier", "")
        if l_tier == tier:
            result.append(l)
    return result


static func get_lk_style_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
    return get_lk_style_levels_by_tier(sz, rank, tier).size()




static var _gc_cache: Dictionary = {}
static var _gc_loaded_sizes: Array[int] = []
const _GC_KNOWN_SIZES: Array[int] = [6, 7, 8, 9, 10, 11, 12]

static func _load_gc_size(sz: int) -> void :
    if sz in _gc_loaded_sizes:
        return
    _gc_loaded_sizes.append(sz)
    var data: Variant = LevelBankIO.load_json("bankDataGC%dx%d.json" % [sz, sz])
    if not (data is Dictionary):
        return
    var levels: Array = (data as Dictionary).get("levels", [])
    if levels.size() > 0:
        _gc_cache[sz] = levels


static func get_gc_sizes() -> Array[int]:
    for sz: int in _GC_KNOWN_SIZES:
        _load_gc_size(sz)
    var result: Array[int] = []
    for sz: int in _GC_KNOWN_SIZES:
        if _gc_cache.has(sz) and (_gc_cache[sz] as Array).size() > 0:
            result.append(sz)
    return result


static func get_gc_ranks(sz: int) -> Array[int]:
    _load_gc_size(sz)
    if not _gc_cache.has(sz):
        return []
    var seen: Dictionary = {}
    for l: Variant in (_gc_cache[sz] as Array):
        seen[int((l as Dictionary).get("r", 0))] = true
    var result: Array[int] = []
    for rank: int in [1, 2, 3, 4, 5]:
        if seen.has(rank):
            result.append(rank)
    return result


static func get_gc_levels(sz: int, rank: int) -> Array:
    _load_gc_size(sz)
    if not _gc_cache.has(sz):
        return []
    var result: Array = []
    for l: Variant in (_gc_cache[sz] as Array):
        if int((l as Dictionary).get("r", 0)) == rank:
            result.append(l)
    return result


static func get_gc_level_count(sz: int, rank: int) -> int:
    return get_gc_levels(sz, rank).size()


static func get_gc_levels_by_tier(sz: int, rank: int, tier: String) -> Array:
    var result: Array = []
    for l: Variant in get_gc_levels(sz, rank):
        if (l as Dictionary).get("tier", "") == tier:
            result.append(l)
    return result


static func get_gc_level_count_by_tier(sz: int, rank: int, tier: String) -> int:
    return get_gc_levels_by_tier(sz, rank, tier).size()




static var _sp_levels: Array = []
static var _sp_loaded: bool = false

static func _load_sp() -> void :
    if _sp_loaded:
        return
    _sp_loaded = true
    var data: Variant = LevelBankIO.load_json("bankDataSP.json")
    if data is Dictionary and data.has("levels"):
        _sp_levels = data["levels"]


static func get_sp_levels() -> Array:
    _load_sp()
    return _sp_levels


static func get_sp_level_count() -> int:
    return get_sp_levels().size()


static func reload_sp() -> void :
    _sp_loaded = false
    _sp_levels = []
    _load_sp()
