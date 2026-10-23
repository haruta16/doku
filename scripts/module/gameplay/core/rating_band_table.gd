## 分段题目评分表：按关号区间与策略段位查评分带，负数评分带表示该组合不适用。
class_name RatingBandTable
extends RefCounted

const MIN_LEVEL: int = 21
const RANKS: Array[int] = [3, 4, 5]
const NO_BAND: Vector2 = Vector2(-1.0, -1.0)

const SEGMENT_UPPER_LEVELS: Array[int] = [50, 100, 200, 400, 600, 800, 1000]

const BANDS_BY_RANK: Dictionary = {
	3:
	[
		Vector2(3000.0, 3013.2),
		Vector2(3000.0, 3005.06),
		Vector2(3000.0, 3005.33),
		Vector2(3000.0, 3008.0),
		Vector2(3000.48, 3008.0),
		Vector2(3001.07, 3013.33),
		Vector2(3001.14, 3018.67),
		Vector2(3001.23, 3019.0),
	],
	4:
	[
		Vector2(7037.33, 7098.0),
		Vector2(7000.0, 7225.78),
		Vector2(7002.93, 7232.0),
		Vector2(7016.0, 7254.87),
		Vector2(7003.29, 7330.3),
		Vector2(7016.0, 7466.12),
		Vector2(7025.66, 7518.73),
		Vector2(7024.16, 7503.01),
	],
	5:
	[
		Vector2(-1.0, -1.0),
		Vector2(-1.0, -1.0),
		Vector2(15032.0, 15519.0),
		Vector2(15066.67, 15733.0),
		Vector2(15087.62, 15897.0),
		Vector2(15223.68, 16032.0),
		Vector2(15267.66, 16110.0),
		Vector2(15409.14, 16164.0),
	],
}


## 按关号查第一个包含它的区间，超过最后上界时取末段。
static func segment_index(level_num: int) -> int:
	for i: int in SEGMENT_UPPER_LEVELS.size():
		if level_num <= SEGMENT_UPPER_LEVELS[i]:
			return i
	return SEGMENT_UPPER_LEVELS.size()


## 第 21 关起为支持的段位返回评分带，否则返回无效标记。
static func band(level_num: int, rank: int) -> Vector2:
	if level_num < MIN_LEVEL or not BANDS_BY_RANK.has(rank):
		return NO_BAND
	var bands: Array = BANDS_BY_RANK[rank]
	var band_value: Vector2 = bands[segment_index(level_num)]
	return band_value


## 检查评分带下界非负，且上界不小于下界。
static func is_valid_band(band_value: Vector2) -> bool:
	return band_value.x >= 0.0 and band_value.y >= band_value.x


## 判断题目评分是否位于有效评分带的闭区间内。
static func contains(band_value: Vector2, rating: float) -> bool:
	return is_valid_band(band_value) and rating >= band_value.x and rating <= band_value.y
