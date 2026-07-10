class_name LevelData
extends RefCounted


const LEVEL_COUNT: int = 0
const SIZES: Array[int] = [
    4, 4, 5, 5, 6, 5, 5, 6, 6, 7, 
    6, 6, 6, 6, 7, 6, 7, 6, 7, 8, 
    6, 7, 6, 7, 8, 6, 7, 8, 7, 8, 
    6, 7, 6, 7, 8, 6, 7, 8, 7, 8, 
    6, 7, 6, 7, 8, 6, 7, 8, 7, 8, 
    6, 7, 8, 7, 9, 6, 7, 8, 9, 10, 
    6, 7, 8, 7, 9, 6, 7, 8, 9, 10, 
    6, 7, 8, 7, 9, 6, 7, 8, 9, 10, 
    6, 7, 8, 7, 9, 6, 7, 8, 9, 10, 
    6, 7, 8, 7, 9, 6, 7, 8, 9, 10, 
]

const _SIZES_101_PLUS: Array[int] = [7, 8, 7, 9, 10, 7, 8, 9, 8, 10]



const _SIZES_GROUP_J_21_50: Array[int] = [6, 7, 6, 7, 8, 6, 7, 8, 8, 7]

const _SIZES_GROUP_J_51_100: Array[int] = [6, 7, 8, 7, 9, 6, 7, 8, 10, 9]

const _SIZES_GROUP_J_101_PLUS: Array[int] = [7, 8, 7, 9, 10, 7, 8, 9, 10, 8]


static func get_size(level_num: int) -> int:
    if level_num < 1:
        return 0
    if level_num <= 100:
        return SIZES[level_num - 1]
    return _SIZES_101_PLUS[(level_num - 101) % 10]


static func get_size_group_j(level_num: int) -> int:
    if level_num < 1:
        return 0
    if level_num < 21:
        return SIZES[level_num - 1]
    if level_num <= 50:
        return _SIZES_GROUP_J_21_50[(level_num - 21) % 10]
    if level_num <= 100:
        return _SIZES_GROUP_J_51_100[(level_num - 51) % 10]
    return _SIZES_GROUP_J_101_PLUS[(level_num - 101) % 10]


static func is_hard_level(level_num: int) -> bool:
    return level_num >= 21 and level_num % 10 == 0


static func is_hard_level_group_j(level_num: int) -> bool:
    return level_num >= 29 and level_num % 10 == 9

static func is_special_level(level_num: int) -> bool:
    return _SPECIAL_LEVELS.has(level_num)



static func strategy_to_rank(strategy: int) -> int:
    match strategy:
        5: return 4
        6: return 5
        7: return 5
        _: return strategy


static func strategy_to_tier(strategy: int) -> String:
    match strategy:
        5: return "H"
        7: return "H"
        _: return "N"



static func get_strategy(level_num: int) -> int:
    if level_num <= 5:
        return 1
    var strategy: int = GameState.get_current_strategy()
    if level_num >= 51 and strategy < 2:
        GameState.set_current_strategy(2)
        strategy = 2
    return strategy









static func advance_for_entry(entry: Dictionary, sz: int) -> void :
    var rank: int = int(entry.get("_bank_rank", 1))
    var tier: String = entry.get("_bank_tier", "")
    var src_main: String = entry.get("_bank_source_main", "")
    if src_main == "":
        GameState.advance_bank_index(sz, rank, tier)
        return
    if src_main == "lk_mod":
        var lkprog: Dictionary = GameState.get_lkmod_progress(sz, rank)
        lkprog["idx"] = lkprog.get("idx", 0) + 1
        GameState.set_lkmod_progress(sz, rank, lkprog)
        var prog: Dictionary = GameState.get_main_progress(sz, rank, tier)
        prog["since_lk"] = 0
        GameState.set_main_progress(sz, rank, tier, prog)
    else:
        var prog: Dictionary = GameState.get_main_progress(sz, rank, tier)
        prog["idx"] = prog.get("idx", 0) + 1
        prog["since_lk"] = prog.get("since_lk", 0) + 1
        GameState.set_main_progress(sz, rank, tier, prog)






static func get_next_entry(sz: int, rank: int, tier: String = "", remaining_attempts: int = -1) -> Dictionary:
    var regular: Array = BankData.get_levels_by_tier(sz, rank, tier) if tier != ""\
else BankData.get_levels(sz, rank)
    var lkstyle: Array = BankData.get_lk_style_levels_by_tier(sz, rank, tier) if tier != ""\
else BankData.get_lk_style_levels(sz, rank)

    if tier != "" and regular.is_empty() and lkstyle.is_empty():
        regular = BankData.get_levels(sz, rank)
        lkstyle = BankData.get_lk_style_levels(sz, rank)

    var gc: Array = []
    if (sz == 10 and rank == 1) or sz == 11:
        gc = BankData.get_gc_levels_by_tier(sz, rank, tier) if tier != ""\
else BankData.get_gc_levels(sz, rank)
        if tier != "" and gc.is_empty():
            gc = BankData.get_gc_levels(sz, rank)
    var total_regular: int = regular.size()
    var total_lkstyle: int = lkstyle.size()
    var total_gc: int = gc.size()
    var total: int = total_regular + total_lkstyle + total_gc
    if total == 0:
        return {}

    if remaining_attempts < 0:
        remaining_attempts = total
    var idx: int = GameState.get_bank_index(sz, rank, tier)
    var real_idx: int = idx % total
    var entry: Dictionary
    var source: String
    var source_idx: int
    if real_idx < total_regular:
        entry = regular[real_idx].duplicate()
        source = "regular"
        source_idx = real_idx + 1
    elif real_idx < total_regular + total_lkstyle:
        entry = lkstyle[real_idx - total_regular].duplicate()
        source = "lkstyle"
        source_idx = real_idx - total_regular + 1
    else:
        entry = gc[real_idx - total_regular - total_lkstyle].duplicate()
        source = "gc"
        source_idx = real_idx - total_regular - total_lkstyle + 1
    entry["_bank_source"] = source
    entry["_bank_idx"] = source_idx
    entry["_bank_tier"] = tier
    entry["_bank_rank"] = rank


    if ABTestManager.single_region_num.is_single_region_limited()\
or ABTestManager.single_region_num.value() == SingleRegionNumConfig.VALUE_STRICT:
        var _rm: Array = entry.get("regionMap", [])
        if _rm.size() == sz:
            var _cnt: Dictionary = {}
            for _r: int in range(sz):
                for _c: int in range(sz):
                    var _rid: int = int((_rm[_r] as Array)[_c])
                    _cnt[_rid] = _cnt.get(_rid, 0) + 1
            var _single: int = 0
            for _v: int in _cnt.values():
                if _v == 1: _single += 1
            if _single > 2:
                if remaining_attempts <= 1:
                    push_error("LevelData.get_next_entry: single_region_num 过滤后连续 %d 次无合格题,容错返回 sz=%d rank=%d tier=%s"\
%[total, sz, rank, tier])
                else:
                    GameState.advance_bank_index(sz, rank, tier)
                    return get_next_entry(sz, rank, tier, remaining_attempts - 1)

    if not QueendokuCore.validate_solution_entry(entry, sz):
        push_error("LevelData.get_next_entry: invalid solution sz=%d rank=%d tier=%s source=%s idx=%d, advancing"\
%[sz, rank, tier, source, source_idx])
        if remaining_attempts <= 1:
            push_error("LevelData.get_next_entry: 题库内连续 %d 题都不合法,容错返回最后 entry sz=%d rank=%d tier=%s"\
%[total, sz, rank, tier])
            return entry
        GameState.advance_bank_index(sz, rank, tier)
        return get_next_entry(sz, rank, tier, remaining_attempts - 1)


    advance_for_entry(entry, sz)
    return entry




static func compute_prefill(level_num: int, region_map: Array, solution: Array, sz: int) -> Array:
    if level_num < 1 or level_num > 10:
        return []
    var want_size_one: bool = level_num >= 7

    var region_area: Dictionary = {}
    for r: int in range(sz):
        for c: int in range(sz):
            var rid: int = region_map[r][c]
            region_area[rid] = region_area.get(rid, 0) + 1

    for r: int in range(sz):
        var c: int = solution[r]
        var rid: int = region_map[r][c]
        var area: int = region_area.get(rid, 0)
        if want_size_one and area == 1:
            return [r, c]
        elif not want_size_one and area > 1:
            return [r, c]

    if sz > 0 and solution.size() > 0:
        return [0, solution[0]]
    return []


const LK_MOD_RESERVED: Array[int] = [20, 30, 53, 71, 72, 75, 114, 141, 164]





const TRANSFORM_COUNT: int = 8


static func apply_transform(region_map: Array, solution: Array, sz: int, t: int) -> Array:
    var rm: Array = region_map
    var sol: Array = solution
    @warning_ignore("integer_division")
    var mirror: int = t / 4
    var rot: int = t % 4
    if mirror == 1:

        var new_rm: Array = []
        for r: int in range(sz):
            var row: Array = []
            for c: int in range(sz):
                row.append(rm[r][sz - 1 - c])
            new_rm.append(row)
        var new_sol: Array = []
        for r: int in range(sz):
            new_sol.append(sz - 1 - sol[r])
        rm = new_rm;sol = new_sol
    elif mirror == 2:

        var new_rm: Array = []
        for r: int in range(sz):
            new_rm.append(rm[sz - 1 - r].duplicate())
        var new_sol: Array = sol.duplicate()
        new_sol.reverse()
        rm = new_rm;sol = new_sol
    for _i: int in range(rot):

        var new_rm: Array = []
        for r2: int in range(sz):
            var row: Array = []
            for c2: int in range(sz):
                row.append(rm[sz - 1 - c2][r2])
            new_rm.append(row)
        var new_sol: Array = []
        new_sol.resize(sz)
        for r2: int in range(sz):
            new_sol[sol[r2]] = sz - 1 - r2
        rm = new_rm;sol = new_sol
    return [rm, sol]













const _SUFFIX_NAMES: Array[String] = [
    "", "r90", "r180", "r270", 
    "h", "hr90", "hr180", "hr270", 
]

static func compute_puzzle_id(sz: int, region_map: Array) -> String:

    var input_norm_str: String = _serialize_region_map(_normalize_region_map(region_map, sz))


    var transformed_pre: Array = []
    var transformed_str: Array = []
    for t: int in range(TRANSFORM_COUNT):
        var rm_t: Array = _apply_region_transform(region_map, sz, t)
        transformed_pre.append(rm_t)
        transformed_str.append(_serialize_region_map(_normalize_region_map(rm_t, sz)))

    var canonical_str: String = transformed_str.min()
    var t_input_to_canonical: int = transformed_str.find(canonical_str)
    var canonical_pre: Array = transformed_pre[t_input_to_canonical]



    var suffix_t: int = 0
    for t: int in range(TRANSFORM_COUNT):
        var maybe_input: Array = _apply_region_transform(canonical_pre, sz, t)
        if _serialize_region_map(_normalize_region_map(maybe_input, sz)) == input_norm_str:
            suffix_t = t
            break

    var hash16: String = canonical_str.sha256_text().substr(0, 16)
    if suffix_t == 0:
        return "%d_%s" % [sz, hash16]
    return "%d_%s_%s" % [sz, hash16, _SUFFIX_NAMES[suffix_t]]


static func _apply_region_transform(region_map: Array, sz: int, t: int) -> Array:
    var rm: Array = region_map
    @warning_ignore("integer_division")
    var mirror: int = t / 4
    var rot: int = t % 4
    if mirror == 1:
        var new_rm: Array = []
        for r: int in range(sz):
            var row: Array = []
            for c: int in range(sz):
                row.append(rm[r][sz - 1 - c])
            new_rm.append(row)
        rm = new_rm
    elif mirror == 2:
        var new_rm: Array = []
        for r: int in range(sz):
            new_rm.append(rm[sz - 1 - r].duplicate())
        rm = new_rm
    for _i: int in range(rot):
        var new_rm: Array = []
        for r2: int in range(sz):
            var row: Array = []
            for c2: int in range(sz):
                row.append(rm[sz - 1 - c2][r2])
            new_rm.append(row)
        rm = new_rm
    return rm


static func _normalize_region_map(region_map: Array, sz: int) -> Array:
    var remap: Dictionary = {}
    var next_id: int = 0
    var result: Array = []
    for r: int in range(sz):
        var row: Array = []
        for c: int in range(sz):
            var v: int = int(region_map[r][c])
            if not remap.has(v):
                remap[v] = next_id
                next_id += 1
            row.append(remap[v])
        result.append(row)
    return result


static func _serialize_region_map(region_map: Array) -> String:
    var parts: PackedStringArray = PackedStringArray()
    for row in region_map:
        for v in row:
            parts.append(str(int(v)))
    return ",".join(parts)




static func get_next_entry_main(sz: int, rank: int, tier: String, remaining_attempts: int = -1, strict_rank: bool = false) -> Dictionary:
    var lk_mod_all: Array = BankData.get_lk_modified_levels()



    var lk_mod: Array = []
    for i: int in range(lk_mod_all.size()):
        if (i + 1) in LK_MOD_RESERVED:
            continue
        var e: Dictionary = lk_mod_all[i]
        if int(e.get("size", 0)) != sz:
            continue
        var e_rank: int = int(e.get("r", 1)) if strict_rank else int(e.get("maxR", e.get("r", 1)))
        if e_rank != rank:
            continue
        lk_mod.append(e)

    var regular: Array = BankData.get_levels_by_tier(sz, rank, tier) if tier != ""\
else BankData.get_levels(sz, rank)
    var lkstyle: Array = BankData.get_lk_style_levels_by_tier(sz, rank, tier) if tier != ""\
else BankData.get_lk_style_levels(sz, rank)
    if tier != "" and regular.is_empty() and lkstyle.is_empty():
        regular = BankData.get_levels(sz, rank)
        lkstyle = BankData.get_lk_style_levels(sz, rank)

    if sz == 10 and rank in [3, 4]:
        regular = []

    var gc: Array = []
    if (sz == 10 and rank == 1) or sz == 11:
        gc = BankData.get_gc_levels_by_tier(sz, rank, tier) if tier != ""\
else BankData.get_gc_levels(sz, rank)
        if tier != "" and gc.is_empty():
            gc = BankData.get_gc_levels(sz, rank)

    var total_lk_mod: int = lk_mod.size()
    var total_regular: int = regular.size()
    var total_lkstyle: int = lkstyle.size()
    var total_gc: int = gc.size()
    var total: int = total_lk_mod + total_regular + total_lkstyle + total_gc
    if total == 0:
        return {}

    var prog: Dictionary = GameState.get_main_progress(sz, rank, tier)
    var transform: int = prog.get("transform", 0)

    var idx: int = prog.get("idx", -1)
    var since_lk: int = prog.get("since_lk", 0)


    if idx < 0:
        var legacy_idx: int = GameState.get_bank_index(sz, rank, tier)
        var denom: int = total_regular + total_lkstyle
        idx = legacy_idx % denom if (legacy_idx > 0 and denom > 0) else 0
        since_lk = 0
        prog["idx"] = idx
        prog["since_lk"] = since_lk
        GameState.set_main_progress(sz, rank, tier, prog)

    var lkprog: Dictionary = GameState.get_lkmod_progress(sz, rank)
    var lk_idx: int = lkprog.get("idx", 0)


    if idx >= total_regular + total_lkstyle + total_gc:
        transform = (transform + 1) % TRANSFORM_COUNT
        idx = 0;since_lk = 0
        prog = {"idx": 0, "since_lk": 0, "transform": transform}
        GameState.set_main_progress(sz, rank, tier, prog)



    var entry: Dictionary
    var source: String
    var source_idx: int

    if since_lk >= 4 and lk_idx < total_lk_mod:
        entry = lk_mod[lk_idx].duplicate()
        source = "lk_mod";source_idx = lk_idx + 1
    elif idx < total_regular:
        entry = regular[idx].duplicate()
        source = "regular";source_idx = idx + 1
    elif idx < total_regular + total_lkstyle:
        var li: int = idx - total_regular
        entry = lkstyle[li].duplicate()
        source = "lkstyle";source_idx = li + 1
    elif idx < total_regular + total_lkstyle + total_gc:
        var gi: int = idx - total_regular - total_lkstyle
        entry = gc[gi].duplicate()
        source = "gc";source_idx = gi + 1
    else:


        push_error("LevelData.get_next_entry_main: unexpected else branch sz=%d rank=%d tier=%s idx=%d" % [sz, rank, tier, idx])
        entry = regular[0].duplicate() if not regular.is_empty() else {}
        source = "regular";source_idx = 1


    if transform > 0 and source != "lk_mod":
        var rm: Array = []
        for row in entry.get("regionMap", []):
            var int_row: Array = []
            for v in row: int_row.append(int(v))
            rm.append(int_row)
        var sol: Array = []
        for v in entry.get("solution", []): sol.append(int(v))
        var result: Array = apply_transform(rm, sol, sz, transform)
        entry["regionMap"] = result[0]
        entry["solution"] = result[1]

    entry["_bank_source"] = source
    entry["_bank_source_main"] = source
    entry["_bank_idx"] = source_idx
    entry["_bank_tier"] = tier
    entry["_bank_rank"] = rank
    entry["_bank_transform"] = transform


    if (ABTestManager.single_region_num.is_single_region_limited()
            or ABTestManager.single_region_num.value() == SingleRegionNumConfig.VALUE_STRICT)\
and source != "lk_mod" and source != "sp" and source != "lk":
        var _rm: Array = entry.get("regionMap", [])
        if _rm.size() == sz:
            var _cnt: Dictionary = {}
            for _r: int in range(sz):
                for _c: int in range(sz):
                    var _rid: int = int((_rm[_r] as Array)[_c])
                    _cnt[_rid] = _cnt.get(_rid, 0) + 1
            var _single: int = 0
            for _v: int in _cnt.values():
                if _v == 1: _single += 1
            if _single > 2:
                if remaining_attempts < 0:
                    remaining_attempts = total * TRANSFORM_COUNT
                if remaining_attempts <= 1:
                    push_error("LevelData.get_next_entry_main: single_region_num 过滤后连续 %d 次无合格题,容错返回 sz=%d rank=%d tier=%s"\
%[total * TRANSFORM_COUNT, sz, rank, tier])
                else:
                    if source == "lk_mod":
                        var lkprog_s: Dictionary = GameState.get_lkmod_progress(sz, rank)
                        lkprog_s["idx"] = lkprog_s.get("idx", 0) + 1
                        GameState.set_lkmod_progress(sz, rank, lkprog_s)
                    else:
                        var prog_s: Dictionary = GameState.get_main_progress(sz, rank, tier)
                        prog_s["idx"] = prog_s.get("idx", 0) + 1
                        GameState.set_main_progress(sz, rank, tier, prog_s)
                    return get_next_entry_main(sz, rank, tier, remaining_attempts - 1, strict_rank)


    if remaining_attempts < 0:
        remaining_attempts = total * TRANSFORM_COUNT
    if not QueendokuCore.validate_solution_entry(entry, sz):
        push_error("LevelData.get_next_entry_main: invalid solution sz=%d rank=%d tier=%s source=%s idx=%d transform=%d, advancing"\
%[sz, rank, tier, source, source_idx, transform])
        if remaining_attempts <= 1:
            push_error("LevelData.get_next_entry_main: 三合一题库连续 %d 次取题都不合法,容错返回最后 entry sz=%d rank=%d tier=%s"\
%[total * TRANSFORM_COUNT, sz, rank, tier])
            return entry
        if source == "lk_mod":
            var lkprog2: Dictionary = GameState.get_lkmod_progress(sz, rank)
            lkprog2["idx"] = lkprog2.get("idx", 0) + 1
            GameState.set_lkmod_progress(sz, rank, lkprog2)
        else:
            prog["idx"] = prog.get("idx", 0) + 1
            GameState.set_main_progress(sz, rank, tier, prog)
        return get_next_entry_main(sz, rank, tier, remaining_attempts - 1)


    advance_for_entry(entry, sz)
    return entry


const _SPECIAL_LEVELS: Dictionary = {
    10: {"source": "sp", "index": 44}, 
    20: {"source": "sp", "index": 45}, 
    30: {"source": "sp", "index": 36}, 
    40: {"source": "sp", "index": 9}, 
    50: {"source": "sp", "index": 37}, 
    55: {"source": "sp", "index": 7}, 
    60: {"source": "sp", "index": 34}, 
    62: {"source": "sp", "index": 8}, 
    70: {"source": "sp", "index": 32}, 
    75: {"source": "sp", "index": 6}, 
    80: {"source": "sp", "index": 43}, 
    90: {"source": "sp", "index": 33}, 
    100: {"source": "sp", "index": 5}, 
    123: {"source": "sp", "index": 1}, 
    200: {"source": "lk", "index": 30}, 
    250: {"source": "lk", "index": 75}, 
    314: {"source": "lk", "index": 141}, 
    456: {"source": "sp", "index": 2}, 
}



static func get_level_entry(level_num: int, override_sz: int = 0) -> Dictionary:
    var rnr: int = ABTestManager.rule_normal_rank.value()


    var special_levels: Dictionary = _SPECIAL_LEVELS.duplicate()
    if level_num == 10 and ABTestManager.normal_level_10.is_sp57_at_level10():
        special_levels[10] = {"source": "sp", "index": 57}

    if special_levels.has(level_num):
        var spec: Dictionary = special_levels[level_num]
        var idx: int = spec["index"] - 1
        if spec["source"] == "sp":
            var sp_levels: Array = BankData.get_sp_levels()
            if idx >= 0 and idx < sp_levels.size():
                var e: Dictionary = sp_levels[idx].duplicate()
                e["_bank_source"] = "sp"
                e["_bank_idx"] = idx + 1
                e["_bank_tier"] = ""
                e["_bank_rank"] = e.get("r", 1)
                return e
        elif spec["source"] == "lk":
            var lk_levels: Array = BankData.get_lk_levels()
            if idx >= 0 and idx < lk_levels.size():
                var e: Dictionary = lk_levels[idx].duplicate()
                e["_bank_source"] = "lk"
                e["_bank_idx"] = idx + 1
                e["_bank_tier"] = ""
                e["_bank_rank"] = e.get("maxR", 1)
                return e


    var sz: int
    if override_sz > 0:
        sz = override_sz
    elif rnr == 10:
        sz = get_size_group_j(level_num)
    else:
        sz = get_size(level_num)
    if sz == 0:
        return {}

    var strategy: int
    var rank: int
    var tier: String


    var is_hard: bool = is_hard_level_group_j(level_num) if rnr == 10 else is_hard_level(level_num)

    if is_hard:
        strategy = GameState.get_current_strategy()
        if rnr == 4 or rnr == 5:

            rank = 5;tier = "N"
        elif rnr == 8:

            rank = 5;tier = "N"
        elif rnr == 9:

            rank = 4;tier = "N"
        elif rnr == 10:


            if level_num >= 201:
                if strategy >= 6:
                    rank = 5;tier = "H"
                else:
                    rank = 5;tier = "N"
            elif level_num >= 101:
                rank = 5;tier = "N"
            elif level_num >= 51:
                if strategy >= 4:
                    rank = 5;tier = "N"
                else:
                    rank = 4;tier = "N"
            else:

                rank = 4;tier = "N"
        elif level_num >= 201:


            if strategy >= 6:
                if rnr == 11 and randi() % 2 == 0:
                    rank = 5;tier = "N"
                else:
                    rank = 5;tier = "H"
            else:
                rank = 5;tier = "N"
        else:

            rank = 5;tier = "N"
    else:
        strategy = get_strategy(level_num)


        var is_mod1_exempt: bool = (
            (rnr == 6 or rnr == 7)
            and level_num >= 51
            and level_num % 10 == 1
        )
        if is_mod1_exempt:

            if level_num >= 101:
                strategy = randi_range(2, 3)
            else:
                strategy = 2

            if GameState.is_daily_first_easy_available() and strategy > 1:
                strategy -= 1
                GameState.consume_daily_first_easy_and_mark()
            rank = strategy_to_rank(strategy)
            tier = strategy_to_tier(strategy)
            if tier == "N":
                var sample: Array = BankData.get_levels_by_tier(sz, rank, "N")
                if sample.is_empty():
                    sample = BankData.get_lk_style_levels_by_tier(sz, rank, "N")
                if sample.is_empty():
                    tier = ""

            GameState.mark_rnr_mod1_exempt()
            return get_next_entry_main(sz, rank, tier, -1, false)


        if rnr == 1:

            if level_num >= 51:
                strategy = min(strategy, 4)
            elif level_num >= 21:
                strategy = min(strategy, 3)
            else:
                strategy = min(strategy, 2)
        elif rnr == 4 or rnr == 5:

            if level_num >= 101:
                strategy = min(strategy, 5)
            elif level_num >= 51:
                strategy = min(strategy, 4)
            elif level_num >= 21:
                strategy = min(strategy, 3)
            else:
                strategy = min(strategy, 2)
        elif rnr == 8:

            if level_num >= 51:
                strategy = min(strategy, 4)
            elif level_num >= 21:
                strategy = min(strategy, 3)
            else:
                strategy = min(strategy, 2)
        elif rnr == 9:

            if level_num >= 21:
                strategy = min(strategy, 3)
            else:
                strategy = min(strategy, 2)
        elif rnr == 10:

            if level_num >= 201:
                strategy = min(strategy, 6)
            elif level_num >= 101:
                strategy = min(strategy, 5)
            elif level_num >= 51:
                strategy = min(strategy, 4)
            elif level_num >= 21:
                strategy = min(strategy, 3)
            else:
                strategy = min(strategy, 2)
        else:

            if level_num >= 201:
                strategy = min(strategy, 6)
            elif level_num >= 101:
                strategy = min(strategy, 5)
            elif level_num >= 51:
                strategy = min(strategy, 4)
            elif level_num >= 21:
                strategy = min(strategy, 3)
            else:
                strategy = min(strategy, 2)


        if rnr == 2 and strategy >= 3:

            strategy = randi_range(2, strategy)
        elif rnr == 3 and strategy >= 3:

            strategy = randi_range(max(2, strategy - 1), strategy)
        elif rnr == 4:

            var lower: int = 2 if level_num >= 51 else 1
            strategy = randi_range(lower, strategy)
        elif rnr == 5 and level_num >= 101:

            strategy = randi_range(2, strategy)
        elif rnr == 6 and strategy >= 3:

            strategy = randi_range(2, strategy)
        elif rnr == 7 and strategy >= 3:


            var seg_max: int = strategy

            if level_num > 50 and GameState.is_rnr_g_prev_was_max():
                strategy = max(2, strategy - 1)
            strategy = randi_range(2, strategy)

            GameState.set_rnr_g_prev_was_max(strategy == seg_max)
        elif rnr == 8 and strategy >= 3:

            strategy = randi_range(2, strategy)
        elif rnr == 9 and strategy >= 3:

            strategy = randi_range(2, strategy)
        elif rnr == 10 and strategy >= 3:

            strategy = randi_range(2, strategy)
        elif rnr == 11 and strategy >= 3:

            strategy = randi_range(2, strategy)


        if (GameState.is_daily_first_easy_available()
                and strategy > 1):
            strategy -= 1
            GameState.consume_daily_first_easy_and_mark()
        rank = strategy_to_rank(strategy)
        tier = strategy_to_tier(strategy)

        if tier == "N":
            var sample: Array = BankData.get_levels_by_tier(sz, rank, "N")
            if sample.is_empty():
                sample = BankData.get_lk_style_levels_by_tier(sz, rank, "N")
            if sample.is_empty():
                tier = ""

    return _get_next_entry_with_filter(sz, rank, tier, level_num, is_hard)




static func _get_next_entry_with_filter(sz: int, rank: int, tier: String, level_num: int, is_hard: bool, remaining: int = -1) -> Dictionary:
    var entry: Dictionary
    if level_num >= 51:
        entry = get_next_entry_main(sz, rank, tier, -1, is_hard)
    else:
        entry = get_next_entry(sz, rank, tier)

    if ABTestManager.single_region_num.is_strict_limited_at(level_num) and not entry.is_empty():
        var _src: String = entry.get("_bank_source_main", entry.get("_bank_source", ""))
        if _src != "lk_mod" and _src != "sp" and _src != "lk":
            var _rm: Array = entry.get("regionMap", [])
            if _rm.size() == sz:
                var _cnt: Dictionary = {}
                for _r: int in range(sz):
                    for _c: int in range(sz):
                        var _rid: int = int((_rm[_r] as Array)[_c])
                        _cnt[_rid] = _cnt.get(_rid, 0) + 1
                var _single: int = 0
                for _v: int in _cnt.values():
                    if _v == 1: _single += 1
                if _single > 1:
                    if remaining < 0:
                        remaining = (sz * sz) * 12
                    if remaining <= 1:
                        push_error("LevelData: single_region_num=2 过滤后无合格题,容错返回 sz=%d rank=%d lv=%d" % [sz, rank, level_num])
                    else:
                        return _get_next_entry_with_filter(sz, rank, tier, level_num, is_hard, remaining - 1)
    return entry
