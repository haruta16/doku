## 排行活动的规则目录；集中定义解锁、周期、奖励、收集映射以及机器人配置和昵称来源。

class_name RankActivityConfig
extends RefCounted

const GROUP_1: int = 1
const GROUP_3: int = 3
const GROUP_2: int = 2

const APPLIED_GROUP: int = GROUP_2

const UNLOCK_LEVEL: int = 11
const PERIOD_DURATION_SEC: int = 86400
const REOPEN_WINS: int = 10

const GLOBAL_T0_LOCAL_DAY: int = 20650

const ROBOT_COUNT: int = 49

const MIN_SCORING_ROBOTS: int = 5


static func build_nickname_source() -> Dictionary:
	return build_nickname_source_for(
		int(ABTestManager.rank_bot_name.value()), TranslationServer.get_locale()
	)


static func build_nickname_source_for(group: int, locale: String) -> Dictionary:
	var buckets: Array = []
	match group:
		RankBotNameConfig.VALUE_CONTROL:
			pass

		RankBotNameConfig.VALUE_ORIGINAL_WEIGHTED:
			buckets = [
				{"weight": 30, "names": RobotNicknamePool.original_random_names()},
				{"weight": 70, "names": RobotNicknamePool.original_human_names()},
			]

		RankBotNameConfig.VALUE_LOCALIZED_WEIGHTED:
			var primary_locale: String = locale.to_lower().replace("-", "_").split("_")[0]
			var localized_names: Array = (
				RobotLocalizedNicknamePool.JAPANESE_NAMES
				if primary_locale == "ja"
				else RobotLocalizedNicknamePool.ENGLISH_NAMES
			)
			buckets = [
				{"weight": 30, "names": RobotNicknamePool.original_random_names()},
				{"weight": 70, "names": localized_names},
			]
		_:
			pass
	return {"pool": RobotNicknamePool.NAMES, "buckets": buckets}


static func build_robot_config(x_base_rule: Dictionary = {}) -> RobotConfig:
	var ab: LeaderboardRobotLogicConfig = ABTestManager.leaderboard_robot_logic
	return build_robot_config_for(
		ab.is_dt_from_last_timeline_point(),
		ab.is_ranked_preset_score(),
		ab.is_stalk_overtake(),
		x_base_rule
	)


static func build_robot_config_for(
	dt_legacy: bool, ranked: bool, overtake: bool, x_base_rule: Dictionary = {}
) -> RobotConfig:
	var c := RobotConfig.new()
	c.robot_count = ROBOT_COUNT
	c.min_scoring_robots = MIN_SCORING_ROBOTS

	c.base_floor = 32
	c.ceiling = 230
	c.bot_offset = 1

	c.arr_values = [1, 2, 3]
	c.arr_weights = [0.2, 0.3, 0.5]
	c.array_strategy = "fill_to_zero"
	c.stalk_values = [1, 2, 3]
	c.stalk_dt_factor = 1.5

	if dt_legacy:
		c.stalk_dt_from_freeze = false
	if ranked:
		c.ceiling = 450
		c.target_score_strategy = "ranked_interpolate"

	if overtake:
		c.stalk_dn_offset = 4
		c.stalk_delta_strategy = "uniform_range"
		c.stalk_uniform_min = 2
		c.stalk_freeze_scope = "members_only"
		c.stalk_tick_on_query = true

	if not x_base_rule.is_empty():
		var alpha: Array = x_base_rule.get("alpha", [])
		if alpha.size() == 4:
			c.alpha_first = float(alpha[0])
			c.alpha_top10 = float(alpha[1])
			c.alpha_top30 = float(alpha[2])
			c.alpha_rest = float(alpha[3])
		c.ceiling_mult = maxi(1, int(x_base_rule.get("k", 1)))
		c.ceiling *= c.ceiling_mult
	return c


const GOLDEN_FISH_COLLECT_RATIO: int = 5

const INF_LEVEL_COLLECT: int = 3

@warning_ignore("unused_parameter")
static func map_collect(
	level_cats: int, remaining_fish: int, is_golden_fish: bool = false, is_inf: bool = false
) -> int:
	if is_golden_fish:
		return remaining_fish * GOLDEN_FISH_COLLECT_RATIO
	if is_inf:
		return INF_LEVEL_COLLECT
	return remaining_fish


static func has_reward(rank: int) -> bool:
	return rank > 0 and rank <= 3


static func is_first_place(rank: int) -> bool:
	return rank == 1


static func build_first_frame_badge_table(period_count: int, tiered: bool) -> Array:
	if not tiered:
		return [{"weight": 100, "badge_min": 1, "badge_max": maxi(1, period_count)}]
	var weights: Array[int] = [5000, 3000, 1500, 400, 45, 20, 15, 10, 5, 3, 1]
	for i in range(ProfileCatalog.FIRST_FRAME_FORM_COUNT - 1, 2, -1):
		if period_count < ProfileCatalog.threshold_for_form(i):
			weights[i - 1] += weights[i]
			weights[i] = 0
	var badge_table: Array = []
	for i in range(ProfileCatalog.FIRST_FRAME_FORM_COUNT):
		if weights[i] <= 0:
			continue
		var badge_min: int = ProfileCatalog.threshold_for_form(i)
		var badge_max: int = maxi(badge_min, period_count)
		if i + 1 < ProfileCatalog.FIRST_FRAME_FORM_COUNT:
			badge_max = ProfileCatalog.threshold_for_form(i + 1) - 1
		(
			badge_table
			. append(
				{
					"weight": weights[i],
					"badge_min": badge_min,
					"badge_max": badge_max,
				}
			)
		)
	return badge_table


const END_SOLO_PODIUM_RANK_MIN: int = 4
const END_SOLO_PODIUM_RANK_MAX: int = 6


static func is_end_solo_podium_rank(rank: int) -> bool:
	return rank >= END_SOLO_PODIUM_RANK_MIN and rank <= END_SOLO_PODIUM_RANK_MAX


static func reward_items(rank: int, rng: RandomNumberGenerator) -> Array:
	var items: Array = []
	if rank == 1:
		items.append(AwardItem.make_frame(ProfileCatalog.FIRST_PLACE_FRAME_ID, 1))
	match rank:
		1:
			items.append_array([AwardItem.make("locate", 2), AwardItem.make("hint", 2)])
		2:
			items.append_array([AwardItem.make("locate", 1), AwardItem.make("hint", 1)])
		3:
			var kind: String = "locate" if rng.randi_range(0, 1) == 0 else "hint"
			items.append(AwardItem.make(kind, 1))
	return items
