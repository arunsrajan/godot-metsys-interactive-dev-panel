@tool
extends TextureRect

var draw_markers = []

func _draw():
	for draw_marker in draw_markers:
		draw_texture(draw_marker.texture, draw_marker.pos)

func append_marker(marker_texture, position: Vector2):
	draw_markers.append({"texture":marker_texture, "pos":position})
