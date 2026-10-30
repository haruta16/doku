## 一组机器人生成与追赶参数；序列化后随活动池保存，避免进行中的活动被新配置直接改写。

class_name RobotConfig
extends RefCounted

var robot_count: int = 30

var min_scoring_robots: int = 0

var array_strategy: String = "closest_approach"

var base_floor: int = 118
var ceiling: int = 960

var ceiling_mult: int = 1
var bot_offset: int = 8
var rand_power: float = 1.0

var alpha_first: float = 0.08
var alpha_top10: float = 0.03
var alpha_top30: float = -0.1
var alpha_rest: float = -0.2

var target_score_strategy: String = "independent_random"

var top_score_ratio_min: float = 0.95
var top_score_ratio_max: float = 1.05

var bottom_score_min: int = 2
var bottom_score_max: int = 5

var rank_density: float = 1.0

var arr_values: Array[int] = [8, 9, 10]
var arr_weights: Array[float] = [0.1, 0.2, 0.7]

var total_minutes: int = 1440
var timeline_format: String = "30;2,60;1,120;1,240;1,1320;5,1440;1"
var first_hour_forced_count: int = 2
var first_hour_minutes: int = 60
var cooldown_minutes: int = 3

var stalk_top_pool: int = 10
var stalk_slot_div: int = 25

var stalk_min_gap: int = 2

var stalk_dn_offset: int = -2

var stalk_dt_factor: float = 8.0
var stalk_values: Array[int] = [8, 9, 10]

var stalk_delta_strategy: String = "accumulate_values"
var stalk_uniform_min: int = 2

var stalk_freeze_scope: String = "all_robots"

var stalk_dt_from_freeze: bool = true

var stalk_tick_on_query: bool = false
var stalk_overtake_delay_min: int = 5
var stalk_overtake_delay_max: int = 30


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {
		"robot_count": robot_count,
		"min_scoring_robots": min_scoring_robots,
		"array_strategy": array_strategy,
		"base_floor": base_floor,
		"ceiling": ceiling,
		"ceiling_mult": ceiling_mult,
		"bot_offset": bot_offset,
		"rand_power": rand_power,
		"alpha_first": alpha_first,
		"alpha_top10": alpha_top10,
		"alpha_top30": alpha_top30,
		"alpha_rest": alpha_rest,
		"arr_values": arr_values,
		"arr_weights": arr_weights,
		"total_minutes": total_minutes,
		"timeline_format": timeline_format,
		"first_hour_forced_count": first_hour_forced_count,
		"first_hour_minutes": first_hour_minutes,
		"cooldown_minutes": cooldown_minutes,
		"stalk_top_pool": stalk_top_pool,
		"stalk_slot_div": stalk_slot_div,
		"stalk_min_gap": stalk_min_gap,
		"stalk_dt_factor": stalk_dt_factor,
		"stalk_values": stalk_values,
		"stalk_overtake_delay_min": stalk_overtake_delay_min,
		"stalk_overtake_delay_max": stalk_overtake_delay_max,
		"target_score_strategy": target_score_strategy,
		"top_score_ratio_min": top_score_ratio_min,
		"top_score_ratio_max": top_score_ratio_max,
		"bottom_score_min": bottom_score_min,
		"bottom_score_max": bottom_score_max,
		"rank_density": rank_density,
		"stalk_dn_offset": stalk_dn_offset,
		"stalk_delta_strategy": stalk_delta_strategy,
		"stalk_uniform_min": stalk_uniform_min,
		"stalk_freeze_scope": stalk_freeze_scope,
		"stalk_dt_from_freeze": stalk_dt_from_freeze,
		"stalk_tick_on_query": stalk_tick_on_query,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> RobotConfig:
	var c := RobotConfig.new()
	c.robot_count = int(d.get("robot_count", c.robot_count))
	c.min_scoring_robots = int(d.get("min_scoring_robots", c.min_scoring_robots))
	c.array_strategy = str(d.get("array_strategy", c.array_strategy))
	c.base_floor = int(d.get("base_floor", c.base_floor))
	c.ceiling = int(d.get("ceiling", c.ceiling))
	c.ceiling_mult = int(d.get("ceiling_mult", c.ceiling_mult))
	c.bot_offset = int(d.get("bot_offset", c.bot_offset))
	c.rand_power = float(d.get("rand_power", c.rand_power))
	c.alpha_first = float(d.get("alpha_first", c.alpha_first))
	c.alpha_top10 = float(d.get("alpha_top10", c.alpha_top10))
	c.alpha_top30 = float(d.get("alpha_top30", c.alpha_top30))
	c.alpha_rest = float(d.get("alpha_rest", c.alpha_rest))
	c.arr_values = _to_int_array(d.get("arr_values", c.arr_values))
	c.arr_weights = _to_float_array(d.get("arr_weights", c.arr_weights))
	c.total_minutes = int(d.get("total_minutes", c.total_minutes))
	c.timeline_format = str(d.get("timeline_format", c.timeline_format))
	c.first_hour_forced_count = int(d.get("first_hour_forced_count", c.first_hour_forced_count))
	c.first_hour_minutes = int(d.get("first_hour_minutes", c.first_hour_minutes))
	c.cooldown_minutes = int(d.get("cooldown_minutes", c.cooldown_minutes))
	c.stalk_top_pool = int(d.get("stalk_top_pool", c.stalk_top_pool))
	c.stalk_slot_div = int(d.get("stalk_slot_div", c.stalk_slot_div))
	c.stalk_min_gap = int(d.get("stalk_min_gap", c.stalk_min_gap))
	c.stalk_dt_factor = float(d.get("stalk_dt_factor", c.stalk_dt_factor))
	c.stalk_values = _to_int_array(d.get("stalk_values", c.stalk_values))
	c.stalk_overtake_delay_min = int(d.get("stalk_overtake_delay_min", c.stalk_overtake_delay_min))
	c.stalk_overtake_delay_max = int(d.get("stalk_overtake_delay_max", c.stalk_overtake_delay_max))
	c.target_score_strategy = str(d.get("target_score_strategy", c.target_score_strategy))
	c.top_score_ratio_min = float(d.get("top_score_ratio_min", c.top_score_ratio_min))
	c.top_score_ratio_max = float(d.get("top_score_ratio_max", c.top_score_ratio_max))
	c.bottom_score_min = int(d.get("bottom_score_min", c.bottom_score_min))
	c.bottom_score_max = int(d.get("bottom_score_max", c.bottom_score_max))
	c.rank_density = float(d.get("rank_density", c.rank_density))
	c.stalk_dn_offset = int(d.get("stalk_dn_offset", c.stalk_dn_offset))
	c.stalk_delta_strategy = str(d.get("stalk_delta_strategy", c.stalk_delta_strategy))
	c.stalk_uniform_min = int(d.get("stalk_uniform_min", c.stalk_uniform_min))
	c.stalk_freeze_scope = str(d.get("stalk_freeze_scope", c.stalk_freeze_scope))
	c.stalk_dt_from_freeze = bool(d.get("stalk_dt_from_freeze", c.stalk_dt_from_freeze))
	c.stalk_tick_on_query = bool(d.get("stalk_tick_on_query", c.stalk_tick_on_query))
	return c


static func _to_int_array(v: Variant) -> Array[int]:
	var out: Array[int] = []
	for x in v:
		out.append(int(x))
	return out


static func _to_float_array(v: Variant) -> Array[float]:
	var out: Array[float] = []
	for x in v:
		out.append(float(x))
	return out
