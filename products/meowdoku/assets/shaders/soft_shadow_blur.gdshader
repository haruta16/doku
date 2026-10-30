shader_type canvas_item;

// 柔和投影：把挂载节点自己那张贴图的 alpha 做多 tap 近似高斯模糊，输出一块**纯色剪影**
// （rgb 取节点 modulate 的颜色、完全不读贴图 rgb）。用途是「同一张贴图复用成一份羽化投影」——
// 投影节点与本体节点用同一个 texture，只靠本 shader + modulate + 位移区分。
//
// 【与 `text_drop_shadow.gdshader` 的分工】那一份挂在 CanvasGroup 上、靠 hint_screen_texture
// 读自己合并后的缓冲，能投影任意子树（含 Spine、含多个子节点），代价是一次 backbuffer copy；
// 本份只模糊挂载节点自己的 TEXTURE，单节点、无额外 pass。只需要给一张贴图配投影时用本份。
//
// 【颜色与浓度不在本 shader 里】走节点的 modulate / self_modulate（= 内建 COLOR）。沿用
// `silhouette_fill.gdshader` 同一条约定：只吃 COLOR 的 rgb 与 alpha、不乘贴图 rgb，于是
// 父链上的淡入与变暗（纯 alpha 写入）照常生效，而投影颜色始终由 modulate 一处决定。
//
// 【必须给羽化留余量，否则光带被框边硬切】模糊在本节点的 quad 内采样，越出 UV [0,1] 记 0。
// 若 quad 恰好等于内容大小、或贴图墨迹紧贴画布边，羽化光带会在 quad 边界切出一条直边。
// 因此消费方要把节点框**放大**、再用 `content_scale` 把内容缩回原来的视觉大小：
//   content_scale = 内容边长 / 节点框边长，四周各留 (框 - 内容) / 2 个屏幕像素给羽化。
// 安全的 `blur_px` 上限 ≈ 那个余量 + 贴图自身透明边距换算到屏幕后的像素数。
// ⚠️ 别拿「贴图看着四周都有留白」当余量：留白按 `贴图边距 × 内容边长 / 贴图边长` 缩到屏幕上
// 往往只剩不到 1px（外观猫头那批就有两张墨迹只距画布边 3px），几乎全部余量得靠放大框来给。
//
// ⚠️ 【采样不能抽成自定义函数】Godot 不允许在自定义函数里访问内建（`TEXTURE` / `UV` 等），
// 抽出去会编译失败 —— 而**失败后节点会静默落回默认材质**（照样画出一张硬边剪影），看起来
// 只是「模糊没生效」，不会有任何画面报错。所以 tap 循环连采样一起留在 `fragment()` 里。
// 同理：怀疑本 shader 没生效时，先去编辑器 Output 面板找本文件名的编译报错，别先怀疑参数。

uniform float blur_px : hint_range(0.0, 32.0) = 6.0;
uniform float content_scale : hint_range(0.05, 1.0) = 1.0;

// 7×7 网格近似高斯：半径 6px 时 tap 间距 2px，小于 sigma（= 半径的一半）才不会出现可见同心环。
// 调羽化强弱改 `blur_px`，别动 GRID —— 只有把半径调到 tap 间距超过 sigma 时才需要加密网格。
const int GRID = 7;
const float GRID_HALF = float(GRID - 1) * 0.5;

void fragment() {
	vec2 uv_content = (UV - vec2(0.5)) / max(content_scale, 0.0001) + vec2(0.5);
	// 1 个屏幕像素对应多少 uv_content。用导数而不是写死贴图 / 框尺寸：节点框改大改小之后
	// `blur_px` 仍然是真实的屏幕像素数，不需要跟着换算，也不会有两处尺寸需要保持同步。
	vec2 uv_per_px = fwidth(uv_content);
	float radius = max(blur_px, 0.0);
	float sigma = max(radius * 0.5, 0.001);

	float alpha_sum = 0.0;
	float weight_sum = 0.0;
	for (int y = 0; y < GRID; y++) {
		for (int x = 0; x < GRID; x++) {
			vec2 grid_pos = vec2(float(x), float(y)) - vec2(GRID_HALF);
			vec2 tap_px = (grid_pos / GRID_HALF) * radius;
			vec2 tap_uv = uv_content + tap_px * uv_per_px;
			// 越出 [0,1] 的 tap 记 0，而不是靠 CLAMP_TO_EDGE 取边缘像素 —— 贴图边缘不保证透明，
			// 拿边缘值当外侧内容会让羽化在框边糊出一条直边。用 step 而非 if：分支在这里没有收益。
			vec2 inside_xy = step(vec2(0.0), tap_uv) * step(tap_uv, vec2(1.0));
			float weight = exp(-dot(tap_px, tap_px) / (2.0 * sigma * sigma));
			alpha_sum += texture(TEXTURE, tap_uv).a * inside_xy.x * inside_xy.y * weight;
			weight_sum += weight;
		}
	}
	// `blur_px == 0` 时全部 tap 落在同一点 ⇒ 逐像素等于没挂本 shader 的硬边剪影，
	// 所以同一个节点可以在「硬边 / 羽化」之间只靠这一个参数来回切，不需要装卸 material。
	COLOR = vec4(COLOR.rgb, alpha_sum / max(weight_sum, 0.0001) * COLOR.a);
}
