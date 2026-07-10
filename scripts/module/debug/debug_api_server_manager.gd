extends Node






















const DEFAULT_PORT: int = 8090
const ROUTE_PREFIX: String = "/meowdoku/api"

var _server: DebugApiServer = null


func _ready() -> void :
    if not OS.is_debug_build():

        set_process(false)
        return

    _server = DebugApiServer.new()
    _register_default_routes()

    var err: int = _server.start(DEFAULT_PORT)
    if err != OK:
        push_error("DebugApiServerManager: failed to start on port %d, err=%d" % [DEFAULT_PORT, err])
        _server = null
        set_process(false)
        return

    print("DebugApiServerManager: routes available at http://127.0.0.1:%d%s/..." % [DEFAULT_PORT, ROUTE_PREFIX])


func _process(_delta: float) -> void :
    if _server != null:
        _server.poll()


func _exit_tree() -> void :
    if _server != null:
        _server.stop()
        _server = null






func register_route(path: String, handler: Callable) -> void :
    if _server == null:
        return
    _server.register_route(_with_prefix(path), handler)


func is_running() -> bool:
    return _server != null and _server.is_running()




func _register_default_routes() -> void :
    _server.register_route(_with_prefix("/ping"), _handle_ping)
    _server.register_route(_with_prefix("/routes"), _handle_routes)
    _server.register_route(_with_prefix("/version"), _handle_version)
    _server.register_route(_with_prefix("/trigger-crash"), _handle_trigger_crash)
    _server.register_route(_with_prefix("/trigger-anr"), _handle_trigger_anr)
    _server.register_route(_with_prefix("/cheat-set-active"), _handle_cheat_set_active)
    _server.register_route(_with_prefix("/cat-positions"), _handle_cat_positions)
    _server.register_route(_with_prefix("/ad-debug-enabled"), _handle_ad_debug_enabled)
    _server.register_route(_with_prefix("/skip-tutorial"), _handle_skip_tutorial)


func _handle_ping(ctx: DebugApiContext) -> void :
    ctx.set_json({"result": "pong"})


func _handle_routes(ctx: DebugApiContext) -> void :
    var routes: Array = _server.get_routes()
    routes.sort()
    ctx.set_json({"result": "success", "routes": routes})


func _handle_version(ctx: DebugApiContext) -> void :
    var info: Dictionary = Engine.get_version_info()
    ctx.set_json({
        "result": "success", 
        "godot": "%d.%d.%d" % [info.major, info.minor, info.patch], 
        "os": OS.get_name(), 
        "debug_build": OS.is_debug_build(), 
    })




func _handle_trigger_crash(ctx: DebugApiContext) -> void :
    ctx.set_json({"result": "success", "message": "Crash will be triggered in 0.1s"})
    get_tree().create_timer(0.1).timeout.connect(_actually_crash)


func _actually_crash() -> void :
    OS.crash("Triggered crash for testing via debug API")






func _handle_trigger_anr(ctx: DebugApiContext) -> void :
    ctx.set_json({"result": "success", "message": "ANR will be triggered, main thread will freeze 100s"})
    get_tree().create_timer(0.1).timeout.connect(_actually_anr)


func _actually_anr() -> void :
    if OS.has_feature("android") and Engine.has_singleton("ShortcutPlugin"):
        Engine.get_singleton("ShortcutPlugin").triggerAnr(100000)
    else:
        OS.delay_msec(100000)





func _handle_cheat_set_active(ctx: DebugApiContext) -> void :
    if not ctx.query_params.has("active"):
        ctx.set_error("active parameter is required (0 or 1)")
        return
    var raw: String = ctx.get_query("active")
    if raw != "0" and raw != "1":
        ctx.set_error("active must be 0 or 1, got: %s" % raw)
        return
    var active: bool = raw == "1"


    var overlay: Node = get_tree().root.find_child("CheatOverlay", true, false)
    if overlay == null:
        ctx.set_error("CheatOverlay not found in scene tree (release build?)", 404)
        return
    overlay.visible = active
    ctx.set_json({
        "result": "success", 
        "active": active, 
        "message": "CheatOverlay %s" % ("shown" if active else "hidden"), 
    })





func _handle_cat_positions(ctx: DebugApiContext) -> void :
    var page: Node = _find_active_game_page()
    if page == null:
        ctx.set_error("No active game page (open game or daily_game first)")
        return
    if not page.has_method("get_solution_cat_positions"):
        ctx.set_error("Active page %s does not expose get_solution_cat_positions" % page.name, 500)
        return
    ctx.set_json({
        "result": "success", 
        "cats": page.get_solution_cat_positions(), 
    })





func _handle_ad_debug_enabled(ctx: DebugApiContext) -> void :
    if not ctx.query_params.has("enabled"):
        ctx.set_error("enabled parameter is required (0 or 1)")
        return
    var raw: String = ctx.get_query("enabled")
    if raw != "0" and raw != "1":
        ctx.set_error("enabled must be 0 or 1, got: %s" % raw)
        return
    var enabled: bool = raw == "1"
    UniKitManager.set_debug_ad_enabled(enabled)
    ctx.set_json({
        "result": "success", 
        "enabled": enabled, 
        "message": "Debug ads %s. Interstitial/banner %s." % [
            "enabled" if enabled else "disabled", 
            "will show normally" if enabled else "blocked (current banner destroyed)", 
        ], 
    })






func _handle_skip_tutorial(ctx: DebugApiContext) -> void :
    var done: bool = true
    if ctx.query_params.has("done"):
        var raw: String = ctx.get_query("done")
        if raw != "0" and raw != "1":
            ctx.set_error("done must be 0 or 1, got: %s" % raw)
            return
        done = raw == "1"

    var tutorial: Node = UIManager.get_ui(UiName.TUTORIAL)
    var in_tutorial: bool = tutorial != null and tutorial.visible
    if in_tutorial and done:
        if tutorial.has_method("complete_tutorial"):
            tutorial.complete_tutorial()
        else:
            GameState.set_tutorial_done(true)
        ctx.set_json({
            "result": "success", 
            "tutorial_done": true, 
            "in_tutorial": true, 
            "message": "Tutorial in progress, completed via tutorial_page.complete_tutorial() (switched to game)", 
        })
        return

    GameState.set_tutorial_done(done)
    ctx.set_json({
        "result": "success", 
        "tutorial_done": done, 
        "in_tutorial": false, 
        "message": "Tutorial marked as %s" % ("done (skipped)" if done else "not done (will trigger again)"), 
    })



func _find_active_game_page() -> Node:
    for page_name in ["game", "daily_game"]:
        var page: Node = UIManager.get_ui(page_name)
        if page != null and page.visible:
            return page
    return null



func _with_prefix(path: String) -> String:
    if not path.begins_with("/"):
        path = "/" + path
    return ROUTE_PREFIX + path
