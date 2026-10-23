## 启动文案选取规则：区分当日首开、旧文案池和昼夜文案区间。
extends RefCounted

const LEGACY_COUNT: int = 67

const RICH_COUNT: int = 120

const RICH_SLEEP_LAST: int = 39

const SLEEP_HOUR_START: int = 21

const LEGACY_QUOTE_PREFIX: String = "splash_slogan_"
const LEGACY_AUTHOR_PREFIX: String = "splash_slogan_author_"
const RICH_QUOTE_PREFIX: String = "splash_slogan_v2_"
const RICH_AUTHOR_PREFIX: String = "splash_slogan_v2_author_"


## 当日首次固定取第 0 条；丰富文案池可按 21 点分为睡前与日间候选区间。
static func index_range(
	use_rich_pool: bool, time_based: bool, is_first_today: bool, hour: int
) -> Vector2i:
	if is_first_today:
		return Vector2i(0, 0)
	if not use_rich_pool:
		return Vector2i(1, LEGACY_COUNT - 1)
	if time_based:
		if hour >= SLEEP_HOUR_START:
			return Vector2i(1, RICH_SLEEP_LAST)
		return Vector2i(RICH_SLEEP_LAST + 1, RICH_COUNT - 1)
	return Vector2i(1, RICH_COUNT - 1)


## 根据文案池与下标生成正文翻译键。
static func quote_key(use_rich_pool: bool, index: int) -> String:
	var prefix: String = RICH_QUOTE_PREFIX if use_rich_pool else LEGACY_QUOTE_PREFIX
	return "%s%d" % [prefix, index]


## 与正文使用同一池和下标，生成对应作者翻译键。
static func author_key(use_rich_pool: bool, index: int) -> String:
	var prefix: String = RICH_AUTHOR_PREFIX if use_rich_pool else LEGACY_AUTHOR_PREFIX
	return "%s%d" % [prefix, index]
