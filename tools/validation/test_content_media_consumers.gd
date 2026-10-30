## 在 tools/run_validation.py 的隔离工程中验证真实 SoundManager 和主页纹理槽位。
extends SceneTree

var _checks: int = 0

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const Store = preload("res://scripts/framework/content/content_store.gd")
var _failures := 0


func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(99))
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var directory := "user://content-consumer-test"
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		push_error("TEST_FAILED: run this test with tools/run_validation.py")
		quit(2)
		return
	var source := directory.path_join("source")
	DirAccess.make_dir_recursive_absolute(source)
	var png := source.path_join("paw.png")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	image.save_png(png)
	# 固定场景绑定保留原像素尺寸，保护 NinePatch 裁剪/边距。
	for asset: Dictionary in [{"name": "logo.png", "original": "res://products/meowdoku/assets/sprites/common/logo.png", "color": Color.CORNFLOWER_BLUE}, {"name": "mark.png", "original": "res://products/meowdoku/assets/sprites/game/icon_mark_white_2.png", "color": Color.CORNFLOWER_BLUE}, {"name": "season.png", "original": "res://products/meowdoku/assets/sprites/game/icon_mark_white_2.png", "color": Color.HOT_PINK}]:
		var original: Texture2D = load(asset.original)
		var replacement := Image.create(original.get_width(), original.get_height(), false, Image.FORMAT_RGBA8)
		replacement.fill(asset.color)
		replacement.save_png(source.path_join(asset.name))
	var wav := source.path_join("tone.wav")
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_8_BITS
	sound.mix_rate = 8000
	var samples := PackedByteArray()
	samples.resize(80)
	sound.data = samples
	sound.save_to_wav(wav)
	var pack := PCKPacker.new()
	pack.pck_start(source.path_join("assets.pck"))
	pack.add_file("res://content/test/consumers/paw.png", png)
	pack.add_file("res://content/test/consumers/tone.wav", wav)
	for filename: String in ["logo.png", "mark.png", "season.png"]:
		pack.add_file("res://content/test/consumers/" + filename, source.path_join(filename))
	pack.flush()
	var mapping := {"textures": {"ui/home/daily_paw_dim": "paw.png", "ui/home/daily_paw_lit": "paw.png", "ui/home/logo": "logo.png", "game/mark": "mark.png", "season/mark": "season.png"}, "audio": {"sfx/mark_cat": "tone.wav", "bgm/default": "tone.wav"}}
	Store._write_bytes(source.path_join("media.json"), JSON.stringify(mapping).to_utf8_buffer())
	var manifest := {"format": 1, "product": "test", "release": "consumers", "runtime": "test-runtime", "files": [_entry(source, "media.json", "media", "json"), _entry(source, "assets.pck", "raw-assets", "raw_pck")]}
	var bytes := JSON.stringify(manifest).to_utf8_buffer()
	var key := Crypto.new().generate_rsa(2048)
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, Manifest.digest(bytes), key)
	var store := Store.new(directory.path_join("cache"), "test", "test-runtime", key.save_to_string(true))
	_check(store.install(source, bytes, signature).ok and store.stage("consumers").ok, "install published media")
	var boot: Dictionary = store.begin_cold_start()
	_check(boot.ok and boot.has("resource_catalog"), "mount selected media")
	if not boot.ok:
		quit(1)
		return
	ContentContext.publish(boot.catalog, boot.resource_catalog)
	_check(ContentSceneBindings.validate_media(boot.resource_catalog).ok, "fixed scene texture dimensions validate after mounting")
	_check(not ContentSceneBindings.validate_media(boot.resource_catalog, {"game/mark": "ui/home/daily_paw_dim"}).ok, "wrong-sized override rejected before presentation")
	var sound_script: Script = get_root().get_node("SoundManager").get_script()
	var sound_kinds: Dictionary = sound_script.get_script_constant_map()["Kind"]
	var manager: Node = sound_script.new()
	get_root().add_child(manager)
	_check(manager._players[sound_kinds.MARK_CAT].stream is AudioStreamWAV, "real SoundManager SFX uses override")
	_check(manager._players[sound_kinds.BTN_CLICK].stream is AudioStreamOggVorbis, "unconfigured SFX retains builtin")
	_check(manager._ensure_bgm_stream("res://products/meowdoku/assets/audio/sfx/mark_cat.ogg"), "BGM resolves published override")
	_check(manager._bgm_player.stream is AudioStreamWAV and manager._bgm_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGM override keeps looping")
	var state := get_root().get_node("GameState")
	state.set_current_level(21)
	var experiments := get_root().get_node("ABTestManager")
	experiments.dc_tag_ui.set_debug_override(1)
	var scene: PackedScene = load("res://products/meowdoku/app/features/home/ui/home_page.tscn")
	var home := scene.instantiate()
	ContentSceneBindings.apply(home)
	get_root().add_child(home)
	var logo: TextureRect = home.get_node("Root/LogoImage")
	_check(logo.texture is ImageTexture, "fixed home scene texture uses content slot before ready")
	var cell_scene: PackedScene = load("res://products/meowdoku/assets/prefab/cell.tscn")
	var cell: Node = cell_scene.instantiate()
	get_root().add_child(cell)
	var cross: NinePatchRect = cell.get_node("Crosses/CrossOut/NinePatchRect")
	_check(cross.texture is ImageTexture and cross.texture.get_image().get_pixel(0, 0).is_equal_approx(Color.CORNFLOWER_BLUE), "dynamically created cell binds default mark slot")
	ContentSceneBindings.apply(cell, {"game/mark": "season/mark"})
	_check(cross.texture.get_image().get_pixel(0, 0).is_equal_approx(Color.HOT_PINK), "per-level alias overrides actual cell texture")
	ContentSceneBindings.apply(cell)
	_check(cross.texture.get_image().get_pixel(0, 0).is_equal_approx(Color.CORNFLOWER_BLUE), "reused cell resolves default slot from original resource")
	# on_show 在首次刷新前保存原始样式；这里只验证消费者，按相同顺序准备该前置状态。
	home._daily_sf_normal = home._daily_bg.get_theme_stylebox("normal")
	home._daily_sf_pressed = home._daily_sf_normal
	home._refresh_daily_btn_state()
	var paw: TextureRect = home.get_node("Root/DailyBtn/UnlockBox/Paw")
	_check(paw.texture is ImageTexture and paw.texture.get_size() == Vector2(2, 2), "real home daily-entry image uses override")
	state.mark_daily_completed(Time.get_date_string_from_system(), 60, 80.0)
	home._refresh_daily_btn_state()
	_check(paw.texture is ImageTexture and paw.texture.get_size() == Vector2(2, 2), "completed daily-entry image uses override")
	_check(store.confirm_healthy("consumers").ok, "confirm actual usable media")
	home.queue_free()
	manager.queue_free()
	ContentContext.publish(null)
	ContentSceneBindings.apply(cell)
	ContentSceneBindings.apply(home)
	_check(cross.texture.resource_path == "res://products/meowdoku/assets/sprites/game/icon_mark_white_2.png" and logo.texture.resource_path == "res://products/meowdoku/assets/sprites/common/logo.png", "removed catalog restores original resources on reused nodes")
	cell.queue_free()
	print("CONTENT_CONSUMER_TEST checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _entry(directory: String, filename: String, logical_id: String, kind: String) -> Dictionary:
	var file := FileAccess.open(directory.path_join(filename), FileAccess.READ)
	var size := file.get_length()
	file.close()
	return {"id": logical_id, "path": filename, "kind": kind, "bytes": size, "sha256": FileAccess.get_sha256(directory.path_join(filename))}


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("TEST_FAILED: " + label)
