## 通关结算可变上下文：GameState 提供局内事实，选题策略回写策略升降、恢复状态和 Elo 结算。
class_name LevelSettlementContext
extends RefCounted

var level_num: int # 正在结算的主线关号。

var min_strategy: int # 基础 DDA 结算使用的最低策略层，作为本次策略上下文传入。

var strategy_before_all: int # 执行各项结算调整前的策略层，用于计算升降幅度或记住待恢复层级。

var retried: bool # 本关是否发生重试，参与干净通关与升档资格判断。

var revive_used: bool # 本关是否使用复活；与一般道具消耗保留独立事实。

var tool_or_revive_used: bool # 本关是否动用道具或复活，供策略判断辅助使用。

var is_daily_first_easy_level: bool # 本关是否消耗每日首次降档机会。
var elo_v2_attempt: Dictionary = {} # 交付题目对应的 Elo V2 尝试事实，含题目身份、资格和局内行为。
var elo_v2_settlement: Dictionary = {} # 策略计算后回填的 Elo V2 结算结果。

var elo_original_delivery: Dictionary = {} # 按原交付段位汇集的题目评分及结算前玩家评分、局数等事实。

var strategy: int # 可变输出：策略逐步调整后的最终层级，提交方据此写入候选。

var demoted_this_level: bool # 输入/输出：本关是否已经降档，防止同一关重复降档。
var pending_restore_strategy: int # 输入/输出：暂时降档后待恢复的层级，0 表示没有待恢复目标。
