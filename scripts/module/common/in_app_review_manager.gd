







class_name InAppReviewManager
extends RefCounted


static func _plugin() -> Object:
    if Engine.has_singleton("InAppReviewPlugin"):
        return Engine.get_singleton("InAppReviewPlugin")
    return null







static func request_review() -> void :
    if OS.has_feature("ios"):


        UniKitManager.request_store_review()
        return
    var p: Object = _plugin()
    if p == null:
        return
    p.requestReview()
