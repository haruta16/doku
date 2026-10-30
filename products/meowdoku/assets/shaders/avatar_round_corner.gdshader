shader_type canvas_item;

// 头像圆角裁剪：对 TextureRect 的显示按圆角矩形 SDF 裁掉四角。
// size_px  = 该 TextureRect 的显示尺寸（设计 px，如 155×155）
// radius_px= 圆角半径（每个角，设计 px，20）
// 抗锯齿：按屏幕空间导数（fwidth）做 ~1px 平滑过渡，输出连续 alpha（32-bit RGBA，边缘平滑不锯齿），
//        与分辨率 / 缩放无关。
// 位置取顶点局部坐标、不取 UV:贴图进图集(AtlasTexture)后 UV 是在大图里的坐标、不再是 0~1。
// vertex() 里的 VERTEX 是节点局部像素坐标,fragment() 里的 VERTEX 已是屏幕空间,故必须经 varying 传。
// 前提:绑定节点的绘制矩形从 (0,0) 起、尺寸 = size_px(现有使用处均为方图 + KEEP_ASPECT_COVERED)。
uniform vec2 size_px = vec2(155.0, 155.0);
uniform float radius_px = 20.0;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec2 p = local_px;                           // 当前像素在设计 px 空间的位置
	vec2 half_size = size_px * 0.5;
	float r = min(radius_px, min(half_size.x, half_size.y));
	vec2 q = abs(p - half_size) - (half_size - vec2(r));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;  // <0 在内，>0 在外
	float w = max(fwidth(d), 0.0001);            // 屏幕空间 1px 抗锯齿带
	float aa = 1.0 - smoothstep(-w, w, d);
	col.a *= aa;
	// 只吃内建 COLOR 的 alpha,rgb 一律取贴图本身：
	// canvas_item 片元里 COLOR 进入时 = modulate × self_modulate × 顶点色。
	//  - 早期 `COLOR = col` 丢掉整个 COLOR → 父节点(如领奖台 AvatarSlot)的淡入(modulate.a)失效,只剩「忽然出现」。
	//  - 之后 `COLOR = col * COLOR` 把 COLOR 整体(含 rgb)乘回 → 淡入恢复,但也把 COLOR.rgb 乘进了头像 →
	//    profile 头像被压深(变深 bug)。
	// 现改为「rgb 取贴图、alpha 乘 COLOR.a」：领奖台淡入(纯 alpha 轨道 Color(1,1,1,0)→(1,1,1,1))照常生效,
	// 头像 rgb 永不被 modulate 链压深。若将来确需对头像做 rgb 染色,再另议(当前无此需求)。
	COLOR = vec4(col.rgb, col.a * COLOR.a);
}
