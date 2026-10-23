## 广告调试页签：展示库存与奖励状态，并提供广告开关和实验条件绕过选项。
class_name CheatTabAd
extends CheatTabBase

const _AD_TAB_FONT_SIZE: int = 36

const _AD_CHECK_ICON_PX: int = 56

var _ad_check_icon_checked: ImageTexture = null
var _ad_check_icon_unchecked: ImageTexture = null


func title() -> String:
	return "广告"


func build(content: ScrollContainer, _panel: CheatPanel) -> void:
	ScrollDragHelper.attach(content)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	content.add_child(vbox)

	var status_label := _make_ad_label()
	var recent_label := _make_ad_label()
	var save_label := _make_ad_label()
	var other_label := _make_ad_label()
	var refresh := func() -> void:
		save_label.text = _ad_text_save()
		recent_label.text = _ad_text_recent()
		other_label.text = await _ad_text_other()
		status_label.text = await _ad_text_status()

	var refresh_btn := Button.new()
	refresh_btn.text = "刷新"
	refresh_btn.custom_minimum_size = Vector2(0, 90)
	refresh_btn.add_theme_font_size_override("font_size", 44)
	refresh_btn.pressed.connect(refresh)
	vbox.add_child(refresh_btn)

	vbox.add_child(status_label)
	_add_ad_gap(vbox)

	_build_ad_show_toggles(vbox)
	_add_ad_gap(vbox)

	vbox.add_child(recent_label)
	_add_ad_gap(vbox)

	_build_bypass_section(
		vbox,
		"插屏广告 bypass:",
		[
			["inter_unlock_level", [ABTestManager.inter_unlock_level]],
			["inter_unlock_session", [ABTestManager.inter_unlock_session]],
			["inter_unlock_memory", [ABTestManager.inter_unlock_memory]],
			["inter_extra_protect_lc", [ABTestManager.inter_extra_protect_lc]],
		],
		refresh
	)
	_add_ad_gap(vbox)

	_build_bypass_section(
		vbox,
		"banner 广告 bypass:",
		[
			["banner_unlock_session", [ABTestManager.banner_unlock_session]],
			["banner_unlock_level", [ABTestManager.banner_unlock_level]],
			["banner_extra_protect_lc", [ABTestManager.banner_extra_protect_lc]],
			["banner_unlock_diff_lc", [ABTestManager.banner_unlock_diff_lc]],
		],
		refresh
	)
	_add_ad_gap(vbox)

	vbox.add_child(save_label)
	_add_ad_gap(vbox)

	vbox.add_child(other_label)

	refresh.call()


func _add_ad_gap(parent: VBoxContainer) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 28)
	parent.add_child(sp)


func _make_ad_label() -> Label:
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", _AD_TAB_FONT_SIZE)
	return l


func _build_ad_show_toggles(parent: VBoxContainer) -> void:
	var title_label := Label.new()
	title_label.text = "广告展示开关:"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", _AD_TAB_FONT_SIZE)
	parent.add_child(title_label)
	var grid := _make_check_grid()
	parent.add_child(grid)
	grid.add_child(
		_make_ad_check(
			"展示插屏广告",
			UniKitManager.cheat_show_interstitial,
			func(v: bool) -> void: UniKitManager.cheat_show_interstitial = v
		)
	)
	grid.add_child(
		_make_ad_check(
			"展示视频广告",
			UniKitManager.cheat_show_reward,
			func(v: bool) -> void: UniKitManager.cheat_show_reward = v
		)
	)
	grid.add_child(
		_make_ad_check(
			"展示 banner 广告",
			UniKitManager.cheat_show_banner,
			func(v: bool) -> void: UniKitManager.cheat_show_banner = v
		)
	)


func _make_check_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 16)
	return grid


func _ensure_ad_check_icons() -> void:
	if _ad_check_icon_checked != null and _ad_check_icon_unchecked != null:
		return
	var tmp := CheckBox.new()
	_ad_check_icon_checked = _scale_check_icon(tmp.get_theme_icon("checked"))
	_ad_check_icon_unchecked = _scale_check_icon(tmp.get_theme_icon("unchecked"))
	tmp.free()


func _scale_check_icon(tex: Texture2D) -> ImageTexture:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	img.resize(_AD_CHECK_ICON_PX, _AD_CHECK_ICON_PX, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _make_ad_check(
	text: String, pressed: bool, on_toggled: Callable, font_size: int = _AD_TAB_FONT_SIZE
) -> CheckBox:
	_ensure_ad_check_icons()
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = pressed
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_font_size_override("font_size", font_size)
	if _ad_check_icon_checked != null:
		cb.add_theme_icon_override("checked", _ad_check_icon_checked)
	if _ad_check_icon_unchecked != null:
		cb.add_theme_icon_override("unchecked", _ad_check_icon_unchecked)
	cb.custom_minimum_size = Vector2(0, 90)
	cb.toggled.connect(on_toggled)
	return cb


func _ad_text_status() -> String:
	var lines: Array[String] = []
	lines.append("广告 SDK 已初始化: %s" % str(UniKitManager.is_ad_inited()))
	lines.append(
		(
			"插屏已 ready(有填充): %s"
			% str(await UniKitManager.is_interstitial_valid(AdPlacement.INTERSTITIAL, "cheat"))
		)
	)
	lines.append(
		(
			"激励视频已 ready(有填充): %s"
			% str(await UniKitManager.is_reward_valid(AdPlacement.REWARD, "cheat"))
		)
	)
	return "\n".join(lines)


func _ad_text_recent() -> String:
	return (
		"最近插屏未展示原因: %s\n最近插屏概率闸掷骰: %s\n最近 banner 未展示原因: %s\n最近补发判定结果: %s\n%s"
		% [
			BaseGamePage.last_interstitial_status,
			BaseGamePage.last_reward_view_prob_roll,
			BaseGamePage.last_banner_status,
			HomePage.last_restore_status,
			_ad_text_pending_rewards()
		]
	)


func _ad_text_pending_rewards() -> String:
	var counts: Dictionary = {}
	for r in GameState.get_pending_rewards():
		var items: Array = UniKitManager.restore_items_for_position(str(r.get("source", "")))
		if items.is_empty():
			var other: String = "其它(%s)" % str(r.get("source", "?"))
			counts[other] = int(counts.get(other, 0)) + 1
			continue
		for it in items:
			var kind: String = str(it.get("kind", ""))
			counts[kind] = int(counts.get(kind, 0)) + int(it.get("count", 0))
	if counts.is_empty():
		return "当前待补发道具: 无"
	var parts: Array[String] = []
	for k in counts:
		parts.append("%s x%d" % [k, int(counts[k])])
	return "当前待补发道具: %s" % " / ".join(parts)


func _ad_text_save() -> String:
	var lines: Array[String] = []
	lines.append("【进度 / 关卡】")
	lines.append("当前关卡: %d" % GameState.get_current_level())
	lines.append("当前策略等级: %d" % GameState.get_current_strategy())
	lines.append("")
	lines.append("【Session / 活跃】")
	lines.append("session 计数: %d" % GameState.get_session_count())
	lines.append("本 session 完局数: %d" % GameState.get_session_played_count())
	lines.append("今日完局数: %d" % GameState.get_today_played_count())
	lines.append("今日前台活跃: %d 秒" % SessionManager.get_today_active_sec())
	lines.append("本 session 前台活跃: %d 秒" % SessionManager.get_session_active_sec())
	lines.append("")
	lines.append("【首启 / 生命周期】")

	var install_days: int = ABTestManager.living_days.days_since_first_open()
	lines.append("安装天数: %s" % ("%d 天" % install_days if install_days >= 0 else "未知(拿不到首启时间)"))

	lines.append("活跃天数: %d 天" % GameState.get_active_days())
	lines.append(
		(
			"生命周期段: 第 %d 段 / 共 %d 段"
			% [
				ABTestManager.living_days.current_segment_index() + 1,
				ABTestManager.living_days.segment_count()
			]
		)
	)
	return "\n".join(lines)


func _ad_text_other() -> String:
	var lines: Array[String] = []
	var page: Node = get_active_game_page()
	lines.append("【插屏 AB 门槛(当前值)】")
	lines.append(
		(
			"inter_unlock_level: %s%s"
			% [
				str(ABTestManager.inter_unlock_level.value()),
				_bypass_tag(ABTestManager.inter_unlock_level)
			]
		)
	)
	lines.append(
		(
			"inter_unlock_session: %s (已解锁=%s)%s"
			% [
				str(ABTestManager.inter_unlock_session.value()),
				str(ABTestManager.inter_unlock_session.is_unlocked()),
				_bypass_tag(ABTestManager.inter_unlock_session)
			]
		)
	)
	lines.append(
		(
			"inter_unlock_memory: %s MB (设备通过=%s)%s"
			% [
				str(ABTestManager.inter_unlock_memory.value()),
				str(ABTestManager.inter_unlock_memory.is_unlocked_for_device()),
				_bypass_tag(ABTestManager.inter_unlock_memory)
			]
		)
	)
	lines.append("插屏冷却秒数: %d 秒(inter_cd_lc)" % UniKitManager.get_interstitial_cd_sec())
	lines.append(
		(
			"inter_extra_protect_lc: %s%s"
			% [
				str(ABTestManager.inter_extra_protect_lc.value()),
				_bypass_tag(ABTestManager.inter_extra_protect_lc)
			]
		)
	)
	(
		lines
		. append(
			(
				"激励视频减少插屏(固化组3): 本 session 激励视频次数=%d, 阈值=1, 概率=80%%, 闸位置=最前置"
				% [
					GameState.get_session_reward_view_count(),
				]
			)
		)
	)

	var iv_cfg: AbConfigBase = ABTestManager.is_vip
	var inter_cnt: int = GameState.get_session_interstitial_count()
	var quota_ok: bool = PurchaseManager.can_show_sub_inter_today()
	var entry_ok: bool = PurchaseManager.is_subscription_entry_enabled()
	var last_shown: String = PurchaseManager.get_vip_sub_inter_last_show_date()
	lines.append(
		(
			"is_vip: %s%s (2=完局第%d次插屏位替换订阅页)"
			% [str(iv_cfg.value()), _bypass_tag(iv_cfg), IsVipConfig.INTERSTITIAL_REPLACE_AT_COUNT]
		)
	)
	lines.append("  ├ 本 session 插屏真实触发次数: %d (下一发是第 %d 次)" % [inter_cnt, inter_cnt + 1])
	lines.append(
		(
			"  ├ 当天配额(每天最多一次): %s%s"
			% [
				"未用" if quota_ok else "已用完",
				"" if last_shown.is_empty() else "，上次出现 %s" % last_shown
			]
		)
	)
	lines.append(
		(
			"  ├ 订阅入口闸门(is_vip!=0 且 vip_price!=0): %s (vip_price=%s)"
			% [str(entry_ok), str(ABTestManager.vip_price.value())]
		)
	)
	lines.append(
		(
			"  └ 下一发插屏会否替换: %s%s"
			% [
				str(
					(
						entry_ok
						and ABTestManager.is_vip.should_replace_interstitial_at(inter_cnt + 1)
						and quota_ok
					)
				),
				"" if entry_ok else "（入口闸门未过 → 照常播插屏,不替换）"
			]
		)
	)
	lines.append("")
	lines.append("【插屏运行态】")
	lines.append("dev 广告开关: %s" % str(UniKitManager.is_debug_ad_enabled()))
	lines.append("插屏冷却中(CD): %s" % str(UniKitManager.is_interstitial_in_cd()))
	lines.append("")
	lines.append("【最终判定 _eval_start_interstitial】")
	if page != null and page.has_method("_eval_start_interstitial"):
		var r: Dictionary = await page.call("_eval_start_interstitial", {}, "cheat", true)
		var reason: String = r.get("reason", "")
		lines.append("eligible: %s" % str(r.get("eligible", false)))
		lines.append("reason: %s" % (reason if reason != "" else "(可播)"))
	else:
		lines.append("(无活跃游戏页,进游戏页后点刷新可见判定结果)")
	lines.append("")

	var b_level: int = -1
	var b_size: int = -1
	if page != null:
		var lc: Variant = page.get("_level_config")
		if lc is Dictionary:
			b_level = int(lc.get("level", -1))
			b_size = int(lc.get("size", -1))
	lines.append("【Banner AB 门槛(当前值)】")
	lines.append(
		(
			"banner_unlock_level: %s%s%s"
			% [
				str(ABTestManager.banner_unlock_level.value()),
				(
					(
						" (当前关 %d 解锁=%s)"
						% [b_level, str(ABTestManager.banner_unlock_level.is_unlocked_at(b_level))]
					)
					if b_level >= 0
					else " (无活跃关)"
				),
				_bypass_tag(ABTestManager.banner_unlock_level)
			]
		)
	)
	lines.append(
		(
			"banner_unlock_session: %s (已解锁=%s)%s"
			% [
				str(ABTestManager.banner_unlock_session.value()),
				str(ABTestManager.banner_unlock_session.is_unlocked()),
				_bypass_tag(ABTestManager.banner_unlock_session)
			]
		)
	)
	var b_protect: Dictionary = ABTestManager.banner_extra_protect_lc.eval_start_banner()
	lines.append(
		(
			"banner_extra_protect_lc: %s (当前阻拦=%s%s)%s"
			% [
				str(ABTestManager.banner_extra_protect_lc.value()),
				str(b_protect.get("blocked", false)),
				(
					""
					if str(b_protect.get("reason", "")) == ""
					else " / " + str(b_protect.get("reason"))
				),
				_bypass_tag(ABTestManager.banner_extra_protect_lc)
			]
		)
	)
	lines.append(
		(
			"banner_unlock_diff_lc: %s%s%s"
			% [
				str(ABTestManager.banner_unlock_diff_lc.value()),
				(
					(
						" (当前 size %d 允许=%s)"
						% [
							b_size,
							str(ABTestManager.banner_unlock_diff_lc.is_unlocked_for_size(b_size))
						]
					)
					if b_size >= 0
					else " (无活跃题)"
				),
				_bypass_tag(ABTestManager.banner_unlock_diff_lc)
			]
		)
	)
	lines.append("")
	lines.append("【最终判定 _eval_start_banner】")
	if page != null and page.has_method("_eval_start_banner"):
		var br: Dictionary = page.call("_eval_start_banner")
		var b_reason: String = br.get("reason", "")
		lines.append("eligible: %s" % str(br.get("eligible", false)))
		lines.append("reason: %s" % (b_reason if b_reason != "" else "(可展示)"))
	else:
		lines.append("(无活跃游戏页,进游戏页后点刷新可见判定结果)")
	return "\n".join(lines)


func _build_bypass_section(
	parent: VBoxContainer, section_text: String, groups: Array, refresh: Callable
) -> void:
	var section_title := Label.new()
	section_title.text = section_text
	section_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_title.add_theme_font_size_override("font_size", _AD_TAB_FONT_SIZE)
	parent.add_child(section_title)
	var grid := _make_check_grid()
	parent.add_child(grid)
	for group: Array in groups:
		var cb_text: String = group[0]
		var cfgs: Array = group[1]
		var any_disabled: bool = false
		for c: AbConfigBase in cfgs:
			if c.is_debug_disabled():
				any_disabled = true
				break
		var captured_cfgs: Array = cfgs
		var captured_refresh: Callable = refresh
		var on_toggled := func(pressed: bool) -> void:
			for c: AbConfigBase in captured_cfgs:
				c.set_debug_disabled(not pressed)
			captured_refresh.call()
		grid.add_child(_make_ad_check(cb_text, not any_disabled, on_toggled))


func _bypass_tag(cfg: AbConfigBase) -> String:
	return " [已 bypass]" if cfg != null and cfg.is_debug_disabled() else ""
