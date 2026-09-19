# 调试 HTTP API 的自动加载入口（project.godot 里注册为 DebugApiServerManager）：只在 debug 构建里监听 8090 端口并挂上内置路由
extends Node

# ---- 配置 ----
const DEFAULT_PORT: int = 8090 # 固定端口，脚本按这个端口连
const ROUTE_PREFIX: String = "/meowdoku/api" # 所有路由的公共前缀

# ---- 运行时状态 ----
var _server: DebugApiServer = null # null 表示没起来（非 debug 构建或端口被占）


# ================= 生命周期 =================
# 启动服务器；非 debug 构建直接关掉 _process，连端口都不监听
func _ready() -> void:
	# 只有编辑器 / 调试版才有这套 API，正式包完全不存在
	if not OS.is_debug_build():
		set_process(false)
		return

	# 先建服务器并挂好路由，再 listen
	_server = DebugApiServer.new()
	_register_default_routes()

	# 端口被占就报错放弃，不重试
	var err: int = _server.start(DEFAULT_PORT)
	if err != OK:
		push_error(
			"DebugApiServerManager: failed to start on port %d, err=%d" % [DEFAULT_PORT, err]
		)
		_server = null
		set_process(false)
		return

	# 启动成功，打印一行可用地址
	print(
		(
			"DebugApiServerManager: routes available at http://127.0.0.1:%d%s/..."
			% [DEFAULT_PORT, ROUTE_PREFIX]
		)
	)


# 每帧驱动一次 poll：收连接、回包
func _process(_delta: float) -> void:
	if _server != null:
		_server.poll()


# 退出场景树时停掉服务器，释放端口
func _exit_tree() -> void:
	if _server != null:
		_server.stop()
		_server = null


# ================= 对外接口 =================
# 供其他模块动态补路由：自动补 /meowdoku/api 前缀，服务器没起就静默忽略
func register_route(path: String, handler: Callable) -> void:
	if _server == null:
		return
	_server.register_route(_with_prefix(path), handler)


# 查询服务器是否可用（_server 为 null 就是没起）
func is_running() -> bool:
	return _server != null and _server.is_running()


# ================= 默认路由 =================
# 注册内置的 9 条路由，全部挂在 /meowdoku/api 前缀下
func _register_default_routes() -> void:
	_server.register_route(_with_prefix("/ping"), _handle_ping)
	_server.register_route(_with_prefix("/routes"), _handle_routes)
	_server.register_route(_with_prefix("/version"), _handle_version)
	_server.register_route(_with_prefix("/trigger-crash"), _handle_trigger_crash)
	_server.register_route(_with_prefix("/trigger-anr"), _handle_trigger_anr)
	_server.register_route(_with_prefix("/cheat-set-active"), _handle_cheat_set_active)
	_server.register_route(_with_prefix("/cat-positions"), _handle_cat_positions)
	_server.register_route(_with_prefix("/ad-debug-enabled"), _handle_ad_debug_enabled)
	_server.register_route(_with_prefix("/skip-tutorial"), _handle_skip_tutorial)


# GET /ping：存活探针，回 pong
func _handle_ping(ctx: DebugApiContext) -> void:
	ctx.set_json({"result": "pong"})


# GET /routes：列出当前所有路由（已排序），方便脚本自省
func _handle_routes(ctx: DebugApiContext) -> void:
	# 排序后回给调用方，便于对比
	var routes: Array = _server.get_routes()
	routes.sort()
	ctx.set_json({"result": "success", "routes": routes})


# GET /version：回报引擎版本、系统名、是否 debug 构建
func _handle_version(ctx: DebugApiContext) -> void:
	# 引擎版本三元组加平台信息
	var info: Dictionary = Engine.get_version_info()
	(
		ctx
		. set_json(
			{
				"result": "success",
				"godot": "%d.%d.%d" % [info.major, info.minor, info.patch],
				"os": OS.get_name(),
				"debug_build": OS.is_debug_build(),
			}
		)
	)


# GET /trigger-crash：先回包，0.1 秒后真的崩一次，用来验证崩溃上报
func _handle_trigger_crash(ctx: DebugApiContext) -> void:
	ctx.set_json({"result": "success", "message": "Crash will be triggered in 0.1s"})
	# 延后 0.1 秒，保证 HTTP 响应先发出去
	get_tree().create_timer(0.1).timeout.connect(_actually_crash)


# 定时器回调：调 OS.crash 主动崩溃
func _actually_crash() -> void:
	OS.crash("Triggered crash for testing via debug API")


# GET /trigger-anr：先回包，0.1 秒后卡死主线程 100 秒，用来验证 ANR 上报
func _handle_trigger_anr(ctx: DebugApiContext) -> void:
	ctx.set_json(
		{"result": "success", "message": "ANR will be triggered, main thread will freeze 100s"}
	)
	get_tree().create_timer(0.1).timeout.connect(_actually_anr)


# 定时器回调：安卓交给原生插件，其他平台用 OS.delay_msec 硬卡
func _actually_anr() -> void:
	if OS.has_feature("android") and Engine.has_singleton("ShortcutPlugin"):
		Engine.get_singleton("ShortcutPlugin").triggerAnr(100000)
	else:
		OS.delay_msec(100000) # 单位毫秒，等于 100 秒


# GET /cheat-set-active?active=0|1：显示 / 隐藏场景树里的 CheatOverlay
func _handle_cheat_set_active(ctx: DebugApiContext) -> void:
	# active 必填且只能是 0 或 1
	if not ctx.query_params.has("active"):
		ctx.set_error("active parameter is required (0 or 1)")
		return
	var raw: String = ctx.get_query("active")
	if raw != "0" and raw != "1":
		ctx.set_error("active must be 0 or 1, got: %s" % raw)
		return
	var active: bool = raw == "1"

	# 作弊浮层用全场景查找，正式包里找不到就回 404
	var overlay: Node = get_tree().root.find_child("CheatOverlay", true, false)
	if overlay == null:
		ctx.set_error("CheatOverlay not found in scene tree (release build?)", 404)
		return
	overlay.visible = active
	(
		ctx
		. set_json(
			{
				"result": "success",
				"active": active,
				"message": "CheatOverlay %s" % ("shown" if active else "hidden"),
			}
		)
	)


# GET /cat-positions：回报当前游戏页答案里每只猫的屏幕坐标，给自动化点击用
func _handle_cat_positions(ctx: DebugApiContext) -> void:
	# 必须有正在显示的游戏页才拿得到答案
	var page: Node = _find_active_game_page()
	if page == null:
		ctx.set_error("No active game page (open game or daily_game first)")
		return
	# 页面类型不对（没继承 base_game_page）时明确回 500
	if not page.has_method("get_solution_cat_positions"):
		ctx.set_error("Active page %s does not expose get_solution_cat_positions" % page.name, 500)
		return
	(
		ctx
		. set_json(
			{
				"result": "success",
				"cats": page.get_solution_cat_positions(),
			}
		)
	)


# GET /ad-debug-enabled?enabled=0|1：开关广告调试模式，关掉时会顺手销毁当前 banner
func _handle_ad_debug_enabled(ctx: DebugApiContext) -> void:
	# enabled 必填且只能是 0 或 1
	if not ctx.query_params.has("enabled"):
		ctx.set_error("enabled parameter is required (0 or 1)")
		return
	var raw: String = ctx.get_query("enabled")
	if raw != "0" and raw != "1":
		ctx.set_error("enabled must be 0 or 1, got: %s" % raw)
		return
	var enabled: bool = raw == "1"
	# 走 UniKitManager 的调试开关（banner 的销毁由它负责）
	UniKitManager.set_debug_ad_enabled(enabled)
	(
		ctx
		. set_json(
			{
				"result": "success",
				"enabled": enabled,
				"message":
				(
					"Debug ads %s. Interstitial/banner %s."
					% [
						"enabled" if enabled else "disabled",
						"will show normally" if enabled else "blocked (current banner destroyed)",
					]
				),
			}
		)
	)


# GET /skip-tutorial[?done=0|1]：改新手引导完成标记；正在引导中且要标记完成时让它当场结算
func _handle_skip_tutorial(ctx: DebugApiContext) -> void:
	# 不带 done 参数默认按「标记为已完成」处理
	var done: bool = true
	if ctx.query_params.has("done"):
		var raw: String = ctx.get_query("done")
		if raw != "0" and raw != "1":
			ctx.set_error("done must be 0 or 1, got: %s" % raw)
			return
		done = raw == "1" # 只认 0 和 1

	# 引导页正开着且要标记完成，就让它当场结算并切到游戏页
	var tutorial: Node = UIManager.get_ui(UiName.TUTORIAL)
	var in_tutorial: bool = tutorial != null and tutorial.visible
	if in_tutorial and done:
		if tutorial.has_method("complete_tutorial"):
			tutorial.complete_tutorial()
		else:
			GameState.set_tutorial_done(true) # 引导页没有 complete_tutorial 时的兜底
		(
			ctx
			. set_json(
				{
					"result": "success",
					"tutorial_done": true,
					"in_tutorial": true,
					"message":
					"Tutorial in progress, completed via tutorial_page.complete_tutorial() (switched to game)",
				}
			)
		)
		return

	# 否则只改存档标记
	GameState.set_tutorial_done(done)
	(
		ctx
		. set_json(
			{
				"result": "success",
				"tutorial_done": done,
				"in_tutorial": false,
				"message":
				(
					"Tutorial marked as %s"
					% ("done (skipped)" if done else "not done (will trigger again)")
				),
			}
		)
	)


# ================= 工具函数 =================
# 找当前可见的游戏页（普通关 game / 每日关 daily_game），都没有就返回 null
func _find_active_game_page() -> Node:
	for page_name in ["game", "daily_game"]:
		var page: Node = UIManager.get_ui(page_name)
		if page != null and page.visible:
			return page
	return null


# 给 path 补上 /meowdoku/api 前缀，缺前导斜杠会自动补
func _with_prefix(path: String) -> String:
	if not path.begins_with("/"):
		path = "/" + path
	return ROUTE_PREFIX + path
