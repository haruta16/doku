## 仅用于隔离测试：经过真实原生桥分支，不启动单例初始化。
extends "res://products/meowdoku/app/platform/unikit_manager.gd"


func _ready() -> void:
	pass


func _is_ad_mock_enabled() -> bool:
	return false


func _query_identified_reward_ready(placement_id: String, position: String, show_id: String) -> bool:
	return _plugin.isAdReady(placement_id, position, show_id)


func _query_identified_reward_valid(placement_id: String, position: String) -> bool:
	return _plugin.isAdValid(placement_id, position)


func _is_native_ad_available() -> bool:
	return _plugin != null


func _query_interstitial_ready(placement_id: String, position: String, show_id: String) -> bool:
	return _plugin.isAdReady(placement_id, position, show_id)


func _show_native_interstitial(placement_id: String, position: String, show_id: String) -> void:
	_plugin.showAd(placement_id, position, show_id)
