## 躲猫猫奖励鱼的飞行动画数学工具；把归一化路径、时间贝塞尔和屏幕起终点组合成轨迹。

extends RefCounted
class_name FishFlightCurve

const LAUNCH_INTERVAL_SEC: float = 0.0666667

const FLIGHT_DURATION_SEC: float = 0.5666667

const FLIGHT_DURATION_FAR_SEC: float = FLIGHT_DURATION_SEC
const FLIGHT_DURATION_NEAR_SEC: float = 0.3666667

const TOTAL_SEQUENCE_SEC: float = LAUNCH_INTERVAL_SEC * 2.0 + FLIGHT_DURATION_SEC

const APPEAR_TO_FLIGHT_SEC: float = 0.8666667

const ARRIVE_HOLD_SEC: float = 0.5


static func total_span_sec(fish_count: int, duration_sec: float = FLIGHT_DURATION_SEC) -> float:
	var stagger: float = 0.0 if fish_count <= 1 else launch_delay(fish_count - 1)
	return APPEAR_TO_FLIGHT_SEC + stagger + duration_sec + ARRIVE_HOLD_SEC


static func flight_duration_for_distance(
	distance: float, near_distance: float, far_distance: float
) -> float:
	var span: float = far_distance - near_distance
	if span <= DEGENERATE_DISTANCE:
		return FLIGHT_DURATION_FAR_SEC
	var ratio: float = clampf((distance - near_distance) / span, 0.0, 1.0)
	return lerpf(FLIGHT_DURATION_NEAR_SEC, FLIGHT_DURATION_FAR_SEC, ratio)


const SHAPE_DISTANCE_CAP_RATIO: float = 1.25

const DEGENERATE_DISTANCE: float = 0.001

enum Role {
	CENTER,
	FAN_POSITIVE,
	FAN_NEGATIVE,
}

const FAMILY_LAYOUT_1: StringName = &"layout_1"
const FAMILY_LAYOUT_2: StringName = &"layout_2"

const TEMPLATE_L1_CENTER: Dictionary = {
	"family": FAMILY_LAYOUT_1,
	"reference_length": 1298.832,
	"timing_bezier": Vector4(0.6, 0.0, 1.0, 1.0),
	"segments":
	[
		{
			"p0": Vector2(0.0, 0.0),
			"c1": Vector2(-0.025773, 0.003956),
			"c2": Vector2(-0.061791, 0.025554),
			"p3": Vector2(0.052277, 0.052443),
		},
		{
			"p0": Vector2(0.052277, 0.052443),
			"c1": Vector2(0.166346, 0.079333),
			"c2": Vector2(0.308526, 0.077852),
			"p3": Vector2(0.455952, 0.077084),
		},
		{
			"p0": Vector2(0.455952, 0.077084),
			"c1": Vector2(0.603378, 0.076316),
			"c2": Vector2(0.761026, 0.046873),
			"p3": Vector2(1.0, 0.0),
		},
	],
}

const TEMPLATE_L1_FAN_POSITIVE: Dictionary = {
	"family": FAMILY_LAYOUT_1,
	"reference_length": 1380.567,
	"timing_bezier": Vector4(0.75, 0.0, 1.0, 1.0),
	"segments":
	[
		{
			"p0": Vector2(0.0, 0.0),
			"c1": Vector2(-0.100454, -0.005309),
			"c2": Vector2(-0.064758, 0.060346),
			"p3": Vector2(-0.018063, 0.099959),
		},
		{
			"p0": Vector2(-0.018063, 0.099959),
			"c1": Vector2(0.028633, 0.139573),
			"c2": Vector2(0.166681, 0.234691),
			"p3": Vector2(0.397064, 0.222958),
		},
		{
			"p0": Vector2(0.397064, 0.222958),
			"c1": Vector2(0.627447, 0.211225),
			"c2": Vector2(0.793757, 0.154357),
			"p3": Vector2(1.0, 0.0),
		},
	],
}

const TEMPLATE_L1_FAN_NEGATIVE: Dictionary = {
	"family": FAMILY_LAYOUT_1,
	"reference_length": 1415.571,
	"timing_bezier": Vector4(0.75, 0.0, 1.0, 1.0),
	"segments":
	[
		{
			"p0": Vector2(0.0, 0.0),
			"c1": Vector2(-0.198454, 0.016527),
			"c2": Vector2(0.187068, -0.097101),
			"p3": Vector2(0.347253, -0.117844),
		},
		{
			"p0": Vector2(0.347253, -0.117844),
			"c1": Vector2(0.507439, -0.138587),
			"c2": Vector2(0.781347, -0.131348),
			"p3": Vector2(1.0, 0.0),
		},
	],
}

const TEMPLATE_L2_CENTER: Dictionary = {
	"family": FAMILY_LAYOUT_2,
	"reference_length": 1071.168,
	"timing_bezier": Vector4(0.6, 0.0, 1.0, 1.0),
	"segments":
	[
		{
			"p0": Vector2(0.0, 0.0),
			"c1": Vector2(-0.302654, -0.02168),
			"c2": Vector2(0.657433, -0.047859),
			"p3": Vector2(1.0, 0.0),
		},
	],
}

const TEMPLATE_L2_FAN_POSITIVE: Dictionary = {
	"family": FAMILY_LAYOUT_2,
	"reference_length": 990.618,
	"timing_bezier": Vector4(0.75, 0.0, 1.0, 1.0),
	"segments":
	[
		{
			"p0": Vector2(0.0, 0.0),
			"c1": Vector2(-0.188079, 0.137023),
			"c2": Vector2(0.178092, 0.222707),
			"p3": Vector2(0.316272, 0.21401),
		},
		{
			"p0": Vector2(0.316272, 0.21401),
			"c1": Vector2(0.454452, 0.205312),
			"c2": Vector2(0.736169, 0.191481),
			"p3": Vector2(1.0, 0.0),
		},
	],
}

const TEMPLATE_L2_FAN_NEGATIVE: Dictionary = {
	"family": FAMILY_LAYOUT_2,
	"reference_length": 1041.679,
	"timing_bezier": Vector4(0.75, 0.0, 1.0, 1.0),
	"segments":
	[
		{
			"p0": Vector2(0.0, 0.0),
			"c1": Vector2(-0.230107, -0.094165),
			"c2": Vector2(0.755449, -0.307247),
			"p3": Vector2(1.0, 0.0),
		},
	],
}


static func get_template(family: StringName, role: Role) -> Dictionary:
	if family == FAMILY_LAYOUT_2:
		match role:
			Role.FAN_POSITIVE:
				return TEMPLATE_L2_FAN_POSITIVE
			Role.FAN_NEGATIVE:
				return TEMPLATE_L2_FAN_NEGATIVE
			_:
				return TEMPLATE_L2_CENTER
	match role:
		Role.FAN_POSITIVE:
			return TEMPLATE_L1_FAN_POSITIVE
		Role.FAN_NEGATIVE:
			return TEMPLATE_L1_FAN_NEGATIVE
		_:
			return TEMPLATE_L1_CENTER


static func role_for_index(index: int) -> Role:
	match index:
		1:
			return Role.FAN_POSITIVE
		2:
			return Role.FAN_NEGATIVE
		_:
			return Role.CENTER


static func launch_delay(index: int) -> float:
	return LAUNCH_INTERVAL_SEC * float(maxi(index, 0))


static func map_uv_point(
	uv: Vector2,
	start_position: Vector2,
	end_position: Vector2,
	reference_length: float,
	side_sign: float = 1.0
) -> Vector2:
	var delta: Vector2 = end_position - start_position
	var distance: float = delta.length()
	if distance < DEGENERATE_DISTANCE:
		return end_position

	var forward: Vector2 = delta / distance
	var side: Vector2 = Vector2(-forward.y, forward.x)
	var shape_distance: float = minf(distance, reference_length * SHAPE_DISTANCE_CAP_RATIO)

	var along_distance: float
	if uv.x < 0.0:
		along_distance = uv.x * shape_distance
	elif uv.x > 1.0:
		along_distance = distance + (uv.x - 1.0) * shape_distance
	else:
		along_distance = uv.x * distance

	return start_position + forward * along_distance + side * uv.y * shape_distance * side_sign


## 把模板的归一化控制点映射到实际起点、终点与方向，得到当前屏幕上的飞行轨迹。
static func build_runtime_curve(
	template: Dictionary, start_position: Vector2, end_position: Vector2, side_sign: float = 1.0
) -> Curve2D:
	var runtime_curve: Curve2D = Curve2D.new()
	var segments: Array = template.get("segments", [])
	var reference_length: float = float(template.get("reference_length", 1000.0))

	for segment_index in segments.size():
		var segment: Dictionary = segments[segment_index]
		var point_0: Vector2 = map_uv_point(
			segment["p0"], start_position, end_position, reference_length, side_sign
		)
		var control_1: Vector2 = map_uv_point(
			segment["c1"], start_position, end_position, reference_length, side_sign
		)
		var control_2: Vector2 = map_uv_point(
			segment["c2"], start_position, end_position, reference_length, side_sign
		)
		var point_3: Vector2 = map_uv_point(
			segment["p3"], start_position, end_position, reference_length, side_sign
		)

		if segment_index == 0:
			runtime_curve.add_point(point_0, Vector2.ZERO, control_1 - point_0)
		else:
			runtime_curve.set_point_out(runtime_curve.point_count - 1, control_1 - point_0)

		runtime_curve.add_point(point_3, control_2 - point_3, Vector2.ZERO)

	return runtime_curve


static func cubic_unit_value(control_1: float, control_2: float, parameter: float) -> float:
	var inverse: float = 1.0 - parameter
	return (
		3.0 * inverse * inverse * parameter * control_1
		+ 3.0 * inverse * parameter * parameter * control_2
		+ parameter * parameter * parameter
	)


## 由归一化播放时间求缓动进度；时间曲线与空间路径分离，可独立调整速度感。
static func sample_timing_bezier(time_ratio: float, controls: Vector4) -> float:
	var lower_parameter: float = 0.0
	var upper_parameter: float = 1.0

	for _iteration in 24:
		var test_parameter: float = (lower_parameter + upper_parameter) * 0.5
		var test_x: float = cubic_unit_value(controls.x, controls.z, test_parameter)
		if test_x < time_ratio:
			lower_parameter = test_parameter
		else:
			upper_parameter = test_parameter

	var solved_parameter: float = (lower_parameter + upper_parameter) * 0.5
	return clampf(cubic_unit_value(controls.y, controls.w, solved_parameter), 0.0, 1.0)


static func sample_flight_position(
	runtime_curve: Curve2D,
	timing_bezier: Vector4,
	elapsed_sec: float,
	duration_sec: float = FLIGHT_DURATION_SEC
) -> Vector2:
	if runtime_curve == null or runtime_curve.point_count == 0:
		return Vector2.ZERO
	var time_ratio: float = clampf(elapsed_sec / maxf(duration_sec, DEGENERATE_DISTANCE), 0.0, 1.0)
	var distance_ratio: float = sample_timing_bezier(time_ratio, timing_bezier)
	var path_offset: float = runtime_curve.get_baked_length() * distance_ratio
	return runtime_curve.sample_baked(path_offset, true)
