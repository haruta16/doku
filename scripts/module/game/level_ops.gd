class_name LevelOps
extends RefCounted


















static func confirm_level_failed_main(end_params: Dictionary, lv: int) -> void :
    GameState.clear_endgame_snapshot()
    GameState.on_game_finished()
    Tracker.track_game_end(end_params)
    if lv > 0:
        GameState.on_level_failed(lv)




static func confirm_level_failed_daily(end_params: Dictionary) -> void :
    GameState.on_game_finished()
    Tracker.track_game_end(end_params)







static func on_restart_click() -> void :
    Tracker.on_restart()
