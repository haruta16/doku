## 传递给各存档模块的合并决策：use_cloud 决定采用云端，by_player_choice 标记是否由玩家明确选择。

class_name MergeContext
extends RefCounted

var use_cloud: bool = false

var by_player_choice: bool = false


static func from_comparison(cloud_ahead: bool) -> MergeContext:
	var context := MergeContext.new()
	context.use_cloud = cloud_ahead
	return context


static func from_player_choice(chose_cloud: bool) -> MergeContext:
	var context := MergeContext.new()
	context.use_cloud = chose_cloud
	context.by_player_choice = true
	return context
