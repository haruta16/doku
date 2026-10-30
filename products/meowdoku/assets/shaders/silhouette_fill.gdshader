shader_type canvas_item;

// 剪影填色：把贴图的不透明区域整片刷成 `fill_color`，形状（alpha）保留、内部明暗细节全部抹平。
// 用在「只要轮廓、不要长相」的态上（如外观网格里未持有的那只猫）。
//
// 【为什么不能用 modulate 代替】modulate 是**乘算**。乘一个浅色只是给贴图染色，
// 原有的明暗层次（眼睛 / 胸斑 / 帽子）全都还在 —— 得到的是「染过色的猫」而不是「纯色剪影」。
// 只有把 rgb 整体换掉才是填充。
//
// 【fill_amount = 0 时逐像素等于没挂本 shader】rgb 原样、alpha 只乘 COLOR.a。
// 所以同一个节点可以在两态间来回切而不需要装卸 material。
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float fill_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 只吃内建 COLOR 的 alpha，rgb 一律不乘回去 —— 与 `avatar_round_corner.gdshader` 同一条约定
	// （它的文件头记着这条的来历）：乘 COLOR.rgb 会让父链上任意 modulate 把填充色压深，
	// 只乘 alpha 则父节点的淡入（纯 alpha 轨道）照常生效。
	COLOR = vec4(mix(tex.rgb, fill_color.rgb, fill_amount), tex.a * COLOR.a);
}
