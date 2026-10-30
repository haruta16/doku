## CSS 风格三次贝塞尔缓动；先由输入进度反求曲线参数，再取得纵向值供排行榜动画使用。

class_name CssBezier
extends RefCounted


## 输入的是横轴时间进度；通过二分逼近对应曲线参数，再返回纵轴缓动值，不能直接把进度当参数。
static func evaluate(t: float, curve: Vector4) -> float:
	var clamped: float = clampf(t, 0.0, 1.0)
	var low: float = 0.0
	var high: float = 1.0
	var u: float = clamped
	for i in 20:
		u = (low + high) * 0.5
		var inv: float = 1.0 - u
		var bx: float = 3.0 * u * inv * inv * curve.x + 3.0 * u * u * inv * curve.z + u * u * u
		if bx < clamped:
			low = u
		else:
			high = u
	var inv_u: float = 1.0 - u
	return 3.0 * u * inv_u * inv_u * curve.y + 3.0 * u * u * inv_u * curve.w + u * u * u
