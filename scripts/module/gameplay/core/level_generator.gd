class_name LevelGenerator
extends RefCounted








static func compute_color_map(size: int, regions: Array) -> Array[int]:
    var num_colors: int = 12


    var adj: Array = []
    for _i in range(size):
        adj.append({})
    for r in range(size):
        for c in range(size):
            var ri: int = regions[r][c]
            if c + 1 < size:
                var rj: int = regions[r][c + 1]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true
            if r + 1 < size:
                var rj: int = regions[r + 1][c]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true


    var rgb: Array = [
        [230, 168, 193], [193, 101, 138], [145, 121, 209], [254, 160, 236], 
        [255, 169, 108], [227, 186, 70], [97, 130, 181], [166, 190, 216], 
        [105, 188, 230], [70, 179, 176], [172, 217, 148], [171, 109, 70], 
    ]


    var order: Array = []
    for i in range(size):
        order.append(i)
    order.sort_custom( func(a: int, b: int) -> bool:
        var da: int = adj[a].size()
        var db: int = adj[b].size()
        return db > da if da != db else a < b
    )

    var color_map: Array[int] = []
    color_map.resize(size)
    color_map.fill(-1)
    var used_colors: Dictionary = {}

    for ri in order:
        var adj_colors: Dictionary = {}
        for ni in adj[ri].keys():
            if color_map[ni] >= 0:
                adj_colors[color_map[ni]] = true

        var best_color: int = 0
        var best_min_dist: float = -1.0
        for ci in range(num_colors):
            if used_colors.has(ci):
                continue
            var min_dist: float = INF
            for ac in adj_colors.keys():
                var dr: float = rgb[ci][0] - rgb[ac][0]
                var dg: float = rgb[ci][1] - rgb[ac][1]
                var db: float = rgb[ci][2] - rgb[ac][2]
                var dist: float = sqrt(dr * dr + dg * dg + db * db)
                if dist < min_dist:
                    min_dist = dist
            if adj_colors.size() == 0:
                min_dist = INF
            if min_dist > best_min_dist:
                best_min_dist = min_dist
                best_color = ci
        color_map[ri] = best_color
        used_colors[best_color] = true

    return color_map



static func compute_color_map_for_rgb(size: int, regions: Array, rgb: Array) -> Array[int]:
    var num_colors: int = rgb.size()
    var adj: Array = []
    for _i in range(size):
        adj.append({})
    for r in range(size):
        for c in range(size):
            var ri: int = regions[r][c]
            if c + 1 < size:
                var rj: int = regions[r][c + 1]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true
            if r + 1 < size:
                var rj: int = regions[r + 1][c]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true
    var order: Array = []
    for i in range(size):
        order.append(i)
    order.sort_custom( func(a: int, b: int) -> bool:
        var da: int = adj[a].size()
        var db: int = adj[b].size()
        return db > da if da != db else a < b
    )
    var color_map: Array[int] = []
    color_map.resize(size)
    color_map.fill(-1)
    var used_colors: Dictionary = {}
    for ri in order:
        var adj_colors: Dictionary = {}
        for ni in adj[ri].keys():
            if color_map[ni] >= 0:
                adj_colors[color_map[ni]] = true
        var best_color: int = 0
        var best_min_dist: float = -1.0
        for ci in range(num_colors):
            if used_colors.has(ci):
                continue
            var min_dist: float = INF
            for ac in adj_colors.keys():
                var dr: float = rgb[ci][0] - rgb[ac][0]
                var dg: float = rgb[ci][1] - rgb[ac][1]
                var db: float = rgb[ci][2] - rgb[ac][2]
                var dist: float = sqrt(dr * dr + dg * dg + db * db)
                if dist < min_dist:
                    min_dist = dist
            if adj_colors.size() == 0:
                min_dist = INF
            if min_dist > best_min_dist:
                best_min_dist = min_dist
                best_color = ci
        color_map[ri] = best_color
        used_colors[best_color] = true
    return color_map



static func compute_color_map_with_seed(size: int, regions: Array, seed: int) -> Array[int]:
    if seed == 0:
        return compute_color_map(size, regions)
    var num_colors: int = 12
    var adj: Array = []
    for _i in range(size):
        adj.append({})
    for r in range(size):
        for c in range(size):
            var ri: int = regions[r][c]
            if c + 1 < size:
                var rj: int = regions[r][c + 1]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true
            if r + 1 < size:
                var rj: int = regions[r + 1][c]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true
    var rgb: Array = [
        [230, 168, 193], [193, 101, 138], [145, 121, 209], [254, 160, 236], 
        [255, 169, 108], [227, 186, 70], [97, 130, 181], [166, 190, 216], 
        [105, 188, 230], [70, 179, 176], [172, 217, 148], [171, 109, 70], 
    ]

    var order: Array = []
    for i in range(size):
        order.append(i)
    var rng_state: int = (seed * 1664525 + 1013904223) & 2147483647
    for i in range(size - 1, 0, -1):
        rng_state = (rng_state * 1664525 + 1013904223) & 2147483647
        var j: int = rng_state % (i + 1)
        var tmp: int = order[i]
        order[i] = order[j]
        order[j] = tmp
    var color_map: Array[int] = []
    color_map.resize(size)
    color_map.fill(-1)
    var used_colors: Dictionary = {}
    for ri in order:
        var adj_colors: Dictionary = {}
        for ni in adj[ri].keys():
            if color_map[ni] >= 0:
                adj_colors[color_map[ni]] = true
        var best_color: int = 0
        var best_min_dist: float = -1.0
        for ci in range(num_colors):
            if used_colors.has(ci):
                continue
            var min_dist: float = INF
            for ac in adj_colors.keys():
                var dr: float = rgb[ci][0] - rgb[ac][0]
                var dg: float = rgb[ci][1] - rgb[ac][1]
                var db: float = rgb[ci][2] - rgb[ac][2]
                var dist: float = sqrt(dr * dr + dg * dg + db * db)
                if dist < min_dist:
                    min_dist = dist
            if adj_colors.size() == 0:
                min_dist = INF
            if min_dist > best_min_dist:
                best_min_dist = min_dist
                best_color = ci
        color_map[ri] = best_color
        used_colors[best_color] = true
    return color_map



static func compute_color_map_for_rgb_with_pattern(
        size: int, regions: Array, rgb: Array, pattern_regions: Array) -> Array[int]:
    var num_colors: int = rgb.size()


    var brightness_order: Array = []
    for ci in range(num_colors):
        var lum: float = 0.299 * rgb[ci][0] + 0.587 * rgb[ci][1] + 0.114 * rgb[ci][2]
        brightness_order.append([lum, ci])
    brightness_order.sort_custom( func(a: Array, b: Array) -> bool: return a[0] < b[0])

    var n_pat: int = pattern_regions.size()
    var dark_pool: Array = []
    var light_pool: Array = []
    for i in range(num_colors):
        if i < n_pat:
            dark_pool.append(brightness_order[i][1])
        else:
            light_pool.append(brightness_order[i][1])


    var adj: Array = []
    for _i in range(size):
        adj.append({})
    for r in range(size):
        for c in range(size):
            var ri: int = regions[r][c]
            if c + 1 < size:
                var rj: int = regions[r][c + 1]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true
            if r + 1 < size:
                var rj: int = regions[r + 1][c]
                if rj != ri:
                    adj[ri][rj] = true
                    adj[rj][ri] = true

    var color_map: Array[int] = []
    color_map.resize(size)
    color_map.fill(-1)
    var used_colors: Dictionary = {}


    for pat_ri in pattern_regions:
        var adj_colors: Dictionary = {}
        for ni in adj[pat_ri].keys():
            if color_map[ni] >= 0:
                adj_colors[color_map[ni]] = true
        var best_color: int = dark_pool[0]
        var best_score: float = -1.0
        for ci in dark_pool:
            if used_colors.has(ci):
                continue
            var min_dist: float = INF
            for ac in adj_colors.keys():
                var dr: float = rgb[ci][0] - rgb[ac][0]
                var dg: float = rgb[ci][1] - rgb[ac][1]
                var db: float = rgb[ci][2] - rgb[ac][2]
                var d: float = sqrt(dr * dr + dg * dg + db * db)
                if d < min_dist:
                    min_dist = d
            if adj_colors.size() == 0:
                min_dist = INF
            if min_dist > best_score:
                best_score = min_dist
                best_color = ci
        color_map[pat_ri] = best_color
        used_colors[best_color] = true


    var remaining: Array = []
    for ri in range(size):
        if color_map[ri] < 0:
            remaining.append(ri)
    remaining.sort_custom( func(a: int, b: int) -> bool:
        var da: int = adj[a].size()
        var db: int = adj[b].size()
        return db > da if da != db else a < b)
    for ri in remaining:
        var adj_colors: Dictionary = {}
        for ni in adj[ri].keys():
            if color_map[ni] >= 0:
                adj_colors[color_map[ni]] = true
        var best_color: int = 0
        var best_min_dist: float = -1.0
        var pool: Array = light_pool if not light_pool.is_empty() else dark_pool
        for ci in pool:
            if used_colors.has(ci):
                continue
            var min_dist: float = INF
            for ac in adj_colors.keys():
                var dr: float = rgb[ci][0] - rgb[ac][0]
                var dg: float = rgb[ci][1] - rgb[ac][1]
                var db: float = rgb[ci][2] - rgb[ac][2]
                var d: float = sqrt(dr * dr + dg * dg + db * db)
                if d < min_dist:
                    min_dist = d
            if adj_colors.size() == 0:
                min_dist = INF
            if min_dist > best_min_dist:
                best_min_dist = min_dist
                best_color = ci
        color_map[ri] = best_color
        used_colors[best_color] = true
    return color_map
