## 色盲图案配色：围绕区域底色生成深色或浅色纹理，浅色方案按感知明度控制对比。
class_name ColorblindPatternVariants
extends RefCounted

enum Variant {
	CONTROL,
	DARK_1,
	DARK_2,
	DARK_3,
	LIGHT_1,
	LIGHT_2,
}


## 按配色实验方案选择纹理颜色，未知方案警告后回退对照组。
static func color_for(background_color: Color, variant: int) -> Color:
	match variant:
		Variant.CONTROL:
			return _dark_pattern_color(background_color, 0.026, 0.0345)
		Variant.DARK_1:
			return _dark_pattern_color(background_color, 0.04, 0.065)
		Variant.DARK_2:
			return _dark_pattern_color(background_color, 0.055, 0.105)
		Variant.DARK_3:
			return _dark_pattern_color(background_color, 0.07, 0.15)
		Variant.LIGHT_1:
			return _light_pattern_color(background_color, 0.0)
		Variant.LIGHT_2:
			return _light_pattern_color(background_color, 3.0)
		_:
			push_warning("ColorblindPatternVariants: 未知 variant=%d,回落对照组" % variant)
			return _dark_pattern_color(background_color, 0.026, 0.0345)


## 保持色相，适度提高饱和度并降低明度，得到不透明的深色纹理。
static func _dark_pattern_color(
	background_color: Color, saturation_offset: float, value_offset: float
) -> Color:
	var pattern_saturation: float = background_color.s
	if pattern_saturation > 0.02:
		pattern_saturation = clampf(pattern_saturation + saturation_offset, 0.0, 1.0)
	var pattern_value: float = clampf(background_color.v - value_offset, 0.0, 1.0)
	return Color.from_hsv(background_color.h, pattern_saturation, pattern_value, 1.0)


## 计算目标感知明度，再通过十二次二分寻找底色与白色的混合比例。
static func _light_pattern_color(background_color: Color, overall_lift: float) -> Color:
	var base_lightness: float = _cie_lightness(background_color)

	var light_factor: float = smoothstep(65.0, 88.0, base_lightness)

	var lightness_delta: float = lerpf(10.0 + overall_lift, 5.5 + overall_lift, light_factor)

	var target_lightness: float = minf(base_lightness + lightness_delta, 98.0)

	var low: float = 0.0
	var high: float = 1.0
	for _i in range(12):
		var middle: float = (low + high) * 0.5
		if _cie_lightness(background_color.lerp(Color.WHITE, middle)) < target_lightness:
			low = middle
		else:
			high = middle

	var result: Color = background_color.lerp(Color.WHITE, (low + high) * 0.5)
	result.a = 1.0
	return result


## 把 sRGB 转为线性亮度，再换算 CIE 感知明度，供浅色方案比较。
static func _cie_lightness(color: Color) -> float:
	var linear_color: Color = color.srgb_to_linear()
	var luminance: float = (
		0.2126 * linear_color.r + 0.7152 * linear_color.g + 0.0722 * linear_color.b
	)
	if luminance > 216.0 / 24389.0:
		return 116.0 * pow(luminance, 1.0 / 3.0) - 16.0
	return (24389.0 / 27.0) * luminance
