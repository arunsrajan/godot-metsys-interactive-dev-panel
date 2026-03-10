@tool
extends TextureRect

var draw_markers = []
var current_texture_rect:TextureRect
var label:Label
func _draw():
	for draw_marker in draw_markers:
		var marker:TextureRect = TextureRect.new()
		marker.position = draw_marker.pos
		marker.texture = draw_marker.texture
		marker.mouse_entered.connect(marker_info.bind(marker, draw_marker.marker_info))
		marker.mouse_exited.connect(marker_info_clean.bind(marker))
		add_child(marker)

func append_marker(marker_texture, position: Vector2, marker_info):
	draw_markers.append({"texture":marker_texture, "pos":position, "marker_info": marker_info})


func marker_info(marker:TextureRect, info:String):
	if not label:
		label = Label.new()
		label.text = info
		var label_settings = LabelSettings.new()
		label_settings.font_color = Color.CHARTREUSE
		label_settings.font_size = 20
		label.label_settings = label_settings
		label.position = Vector2(0, 0)
		marker.add_child(label)

func marker_info_clean(marker:TextureRect):
	if label:
		marker.remove_child(label)
		label.queue_free()
		label= null
