## 仅在 run_validation.prepare 的隔离副本中，以真实图形渲染器截取 1.22 页面。
## godot --path <fixture/project> --resolution 540x1200 --script res://tools/validation/capture_v122_ui.gd -- --output <temporary-output>
extends SceneTree
var ui: Node
var game: Node
var ab: Node
var rows: Array = []
var OUT: String = "user://visual-qa-122"
var failed: bool = false
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-") or not ProjectSettings.get_setting("doku/validation/offline", false):
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("VISIBLE_QA_FAILED: a visible renderer is required")
		quit(2)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output":
		OUT = args[1]
	DirAccess.make_dir_recursive_absolute(OUT)
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	ui = root.get_node("UIManager")
	game = root.get_node("GameState")
	ab = root.get_node("ABTestManager")
	game.reset_all()
	game.set_music_on(false)
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(31)
	game.set_tool_count("hint", 20)
	game.set_tool_count("locate", 20)
	game.set_tool_count("mouse", 20)
	game.set_tool_count("draft", 20)
	ab.normal_start_toast.set_debug_override(0)
	ab.draft_mode.set_debug_override(5)
	ab.prop_mouse.set_debug_override(1)
	ab.dc_start_toast.set_debug_override(0)
	ab.home_companion_cat.set_debug_override(0)
	ab.dc_costume.set_debug_override(0)
	ab.peekaboo_cat.set_debug_override(0)
	root.get_node("RankActivityManager").maybe_open(true)
	root.get_node("RankActivityManager").confirm_participation()
	TranslationServer.set_locale("en")
	await _show_capture("home", {}, "01-home-en")
	var page: Variant = await _show_capture("game", {"level_index":31}, "02-main-en")
	if page != null and page._entry_ready:
		page._entry_anim_playing = false
		page._tool_btns_locked = false
		page._on_draft_btn_pressed()
		await create_timer(0.5).timeout
		if not page._draft_mode:
			failed = true
			push_error("VISIBLE_QA_FAILED: real draft handler did not activate")
		await _capture("03-main-draft", page)
	await _show_capture("daily_game", {}, "04-daily-en")
	ab.nu_guide.set_debug_override(2)
	await _show_capture("tutorial", {}, "05-tutorial-new-en")
	ab.home_companion_cat.set_debug_override(1)
	await _show_capture("home", {}, "06-home-companion-en")
	await _show_capture("dc_costume_unlock", {"costume_id":1,"beat_percent":88.2}, "07-costume-unlock-en")
	await _show_capture("reward_claim_popup", {"items":[AwardItem.make("hint",2),AwardItem.make("locate",3)],"reason":"visual_fixture"}, "08-reward-claim-en")
	TranslationServer.set_locale("zh_CN")
	await _show_capture("daily_game", {}, "09-daily-zh")
	ui.hide_all()
	await create_timer(0.5).timeout
	for name: StringName in UIRegistry.PAGES:
		await ui.destroy_ui(name)
	await process_frame
	await process_frame
	var f := FileAccess.open(OUT+"/capture.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	print("VISIBLE UI QA CAPTURES: ", rows.size())
	quit(1 if failed else 0)
func _show_capture(name: String, params: Dictionary, label: String) -> Variant:
	ui.hide_all()
	await create_timer(0.5).timeout
	var page: Variant = ui.show_ui(name, params)
	await create_timer(3.5).timeout
	await _capture(label, page)
	return page
func _capture(label: String, page: Variant) -> void:
	await process_frame
	RenderingServer.force_draw()
	var im: Image = root.get_texture().get_image()
	var error: int = im.save_png(OUT+"/"+label+".png")
	var colors: Dictionary = {}
	for y: int in range(0, im.get_height(), maxi(1, im.get_height() / 20)):
		for x: int in range(0, im.get_width(), maxi(1, im.get_width() / 20)):
			colors[im.get_pixel(x, y).to_rgba32()] = true
	var valid: bool = error == OK and page != null and page.is_showing() and colors.size() > 16
	if not valid:
		failed = true
		push_error("VISIBLE_QA_FAILED: missing, hidden or blank capture " + label)
	rows.append({"valid":valid,"sampled_colors":colors.size(),"name":label,"saved":error==OK,"width":im.get_width(),"height":im.get_height(),"visible":page != null and page.is_showing()})
