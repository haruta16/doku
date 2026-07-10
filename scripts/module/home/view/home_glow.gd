extends Control


func _draw() -> void :
    var cx: float = size.x * 0.5
    var cy: float = size.y * 0.35
    draw_circle(Vector2(cx, cy), 581.0, Color(1.0, 1.0, 1.0, 0.18))
    draw_circle(Vector2(cx, cy), 443.0, Color(1.0, 1.0, 1.0, 0.28))
    draw_circle(Vector2(cx, cy), 332.0, Color(1.0, 1.0, 1.0, 0.42))
