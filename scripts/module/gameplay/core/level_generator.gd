# 区域配色器：给每块区域分一个色号，保证相邻区域不同色、且尽量挑视觉差异大的颜色
# 4 个变体共用同一套贪心挑色，差别只在颜色表、区域处理顺序、是否给图案区域预留暗色
class_name LevelGenerator
extends RefCounted


# ================= 基础贪心挑色 =================
# 按内置 12 色表给区域配色；返回 color_map：下标是区域编号，值是颜色序号（0~11，用来查下面的 rgb 表）
static func compute_color_map(size: int, regions: Array) -> Array[int]:
	var num_colors: int = 12 # 候选色号个数，等于 rgb 表的长度

	var adj: Array = [] # 邻接表：adj[i] = {邻居区域号: true}，只记上下左右相邻且区域号不同的两块
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

	# 内置调色板：12 个 RGB 分量（0~255），下标就是色号
	var rgb: Array = [
		[230, 168, 193],
		[193, 101, 138],
		[145, 121, 209],
		[254, 160, 236],
		[255, 169, 108],
		[227, 186, 70],
		[97, 130, 181],
		[166, 190, 216],
		[105, 188, 230],
		[70, 179, 176],
		[172, 217, 148],
		[171, 109, 70],
	]

	var order: Array = [] # 挑色顺序：邻接越多的区域越先挑（同样多则编号小的优先），减少后面撞色
	for i in range(size):
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var da: int = adj[a].size()
			var db: int = adj[b].size()
			return db > da if da != db else a < b
	)

	var color_map: Array[int] = [] # color_map[区域号] = 色号，-1 表示尚未分配；used_colors 记录已被占用的色号
	color_map.resize(size)
	color_map.fill(-1)
	var used_colors: Dictionary = {}

	for ri in order: # 逐个区域挑色
		var adj_colors: Dictionary = {} # 先收集邻居已经用掉的色号
		for ni in adj[ri].keys():
			if color_map[ni] >= 0:
				adj_colors[color_map[ni]] = true

		var best_color: int = 0 # 在没人用过的色号里，挑「到邻居色的最小 RGB 距离」最大的那个
		var best_min_dist: float = -1.0
		for ci in range(num_colors): # 跳过用过的色号 → 一盘之内 12 个色号各用一次
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
			if adj_colors.size() == 0: # 没有已着色的邻居时距离记 INF，等价于直接取第一个未用色号
				min_dist = INF
			if min_dist > best_min_dist:
				best_min_dist = min_dist
				best_color = ci
		color_map[ri] = best_color
		used_colors[best_color] = true

	return color_map # 只返回色号，具体 RGB 由调用方查表


# 同 compute_color_map，但调色板由调用方传入，可选色号范围随 rgb.size() 变化
static func compute_color_map_for_rgb(size: int, regions: Array, rgb: Array) -> Array[int]:
	var num_colors: int = rgb.size() # 色号范围 = 传入调色板的长度
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
	var order: Array = [] # 以下挑色逻辑是 compute_color_map 的复制，只是颜色表不再写死 12 色
	for i in range(size):
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
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


# ================= 带随机种子 / 图案优先的变体 =================
# 带种子版：用 seed 洗牌决定区域挑色顺序，同一 seed 得到同一套配色；seed 为 0 时退回 compute_color_map
static func compute_color_map_with_seed(size: int, regions: Array, seed: int) -> Array[int]:
	if seed == 0: # 0 号种子表示不随机，直接走默认顺序那版
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
	# 内置调色板与 compute_color_map 完全相同，只是区域顺序会被打乱
	var rgb: Array = [
		[230, 168, 193],
		[193, 101, 138],
		[145, 121, 209],
		[254, 160, 236],
		[255, 169, 108],
		[227, 186, 70],
		[97, 130, 181],
		[166, 190, 216],
		[105, 188, 230],
		[70, 179, 176],
		[172, 217, 148],
		[171, 109, 70],
	]

	var order: Array = []
	for i in range(size):
		order.append(i)
	var rng_state: int = (seed * 1664525 + 1013904223) & 2147483647 # 线性同余伪随机：乘 1664525 加 1013904223，取低 31 位
	for i in range(size - 1, 0, -1): # 用这个伪随机源给 order 做 Fisher-Yates 洗牌
		rng_state = (rng_state * 1664525 + 1013904223) & 2147483647
		var j: int = rng_state % (i + 1)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var color_map: Array[int] = [] # 下面挑色逻辑同 compute_color_map，差别只在 ri 的遍历顺序
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


# 图案优先版：按亮度把调色板劈成暗色池/亮色池，图案区域只从暗色池取色，其余区域用亮色池
static func compute_color_map_for_rgb_with_pattern(
	size: int, regions: Array, rgb: Array, pattern_regions: Array
) -> Array[int]:
	var num_colors: int = rgb.size() # 色号范围 = 传入调色板长度

	var brightness_order: Array = [] # 按感知亮度 0.299R+0.587G+0.114B 从暗到亮排序，元素是 [亮度, 色号]
	for ci in range(num_colors):
		var lum: float = 0.299 * rgb[ci][0] + 0.587 * rgb[ci][1] + 0.114 * rgb[ci][2]
		brightness_order.append([lum, ci])
	brightness_order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	var n_pat: int = pattern_regions.size() # 图案区域个数 = 要预留的暗色号个数
	var dark_pool: Array = [] # 最暗的 n_pat 个色号留给图案，其余进亮色池
	var light_pool: Array = []
	for i in range(num_colors): # 按亮度名次分池
		if i < n_pat:
			dark_pool.append(brightness_order[i][1])
		else:
			light_pool.append(brightness_order[i][1])

	var adj: Array = [] # 邻接表，含义同 compute_color_map
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

	var color_map: Array[int] = [] # 第一步：图案区域优先占暗色号（挑法同前面的贪心）
	color_map.resize(size)
	color_map.fill(-1)
	var used_colors: Dictionary = {}

	for pat_ri in pattern_regions: # 逐个图案区域取色
		var adj_colors: Dictionary = {}
		for ni in adj[pat_ri].keys():
			if color_map[ni] >= 0:
				adj_colors[color_map[ni]] = true
		var best_color: int = dark_pool[0] # 只在暗色池里挑，保证图案区域颜色足够深
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

	var remaining: Array = [] # 第二步：剩下的区域按邻接度降序、从亮色池里挑
	for ri in range(size):
		if color_map[ri] < 0:
			remaining.append(ri)
	remaining.sort_custom(
		func(a: int, b: int) -> bool:
			var da: int = adj[a].size()
			var db: int = adj[b].size()
			return db > da if da != db else a < b
	)
	for ri in remaining:
		var adj_colors: Dictionary = {}
		for ni in adj[ri].keys():
			if color_map[ni] >= 0:
				adj_colors[color_map[ni]] = true
		var best_color: int = 0
		var best_min_dist: float = -1.0
		var pool: Array = light_pool if not light_pool.is_empty() else dark_pool # 亮色池空了就退回暗色池，保证一定有颜色可用
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
	return color_map # 返回值含义同 compute_color_map：区域号 → 色号
