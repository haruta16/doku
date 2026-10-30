## 通关结算可变上下文：GameState 提供局内事实，选题策略回写策略升降、恢复状态和 Elo 结算。
class_name LevelSettlementContext
extends RefCounted

var level_num: int

var min_strategy: int

var strategy_before_all: int

var retried: bool

var revive_used: bool

var tool_or_revive_used: bool

var is_daily_first_easy_level: bool
var elo_v2_attempt: Dictionary = {}
var elo_v2_settlement: Dictionary = {}

var elo_original_delivery: Dictionary = {}

var strategy: int

var demoted_this_level: bool
var pending_restore_strategy: int
