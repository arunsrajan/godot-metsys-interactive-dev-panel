@tool
extends TextureRect

var _markers: Array = []
var _last_hovered_room: String = ""
var _panning := false
var _pan_start: Vector2 = Vector2.ZERO
var _scroll_start: Vector2 = Vector2.ZERO

func _draw():
	for marker_data in _markers:
		var tex: Texture2D = marker_data.texture
		var pos: Vector2 = marker_data.pos
		draw_texture(tex, pos)

func append_marker(marker_texture: Texture2D, position: Vector2, marker_info: String):
	_markers.append({"texture": marker_texture, "pos": position, "marker_info": marker_info})
	queue_redraw()

func clear_markers():
	_markers.clear()
	queue_redraw()

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_panning = true
				_pan_start = event.global_position
				# Walk up to find the ScrollContainer
				var node := get_parent()
				while node:
					if node is ScrollContainer:
						_scroll_start = Vector2(node.scroll_horizontal, node.scroll_vertical)
						break
					node = node.get_parent()
				accept_event()
			else:
				_panning = false
				accept_event()
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var room_rects: Dictionary = get_meta("room_rects", {})
			for scene_path in room_rects:
				if room_rects[scene_path].has_point(event.position):
					var parent = get_parent()
					if parent and parent.has_signal("room_clicked"):
						parent.room_clicked.emit(scene_path)
					accept_event()
					return
		return

	if event is InputEventMouseMotion and _panning:
		var node := get_parent()
		while node:
			if node is ScrollContainer:
				var delta = event.global_position - _pan_start
				node.scroll_horizontal = int(_scroll_start.x - delta.x)
				node.scroll_vertical = int(_scroll_start.y - delta.y)
				break
			node = node.get_parent()
		accept_event()
		return

	if not event is InputEventMouseMotion:
		return

	# Check markers first (they take priority over room hover)
	for marker_data in _markers:
		var tex: Texture2D = marker_data.texture
		var pos: Vector2 = marker_data.pos
		var size: Vector2 = tex.get_size()
		var rect := Rect2(pos, size)
		if rect.has_point(event.position):
			_show_tooltip(marker_data.marker_info, pos + Vector2(size.x + 4, 0))
			_clear_room_hover()
			accept_event()
			return

	# Check room rects for hover info
	var room_rects: Dictionary = get_meta("room_rects", {})
	var found_room := ""
	for scene_path in room_rects:
		if room_rects[scene_path].has_point(event.position):
			found_room = scene_path
			break

	if found_room != "":
		if found_room != _last_hovered_room:
			_last_hovered_room = found_room
			_show_room_tooltip(found_room, event.position)
			var parent = get_parent()
			if parent and parent.has_signal("room_hovered"):
				parent.room_hovered.emit(found_room, event.global_position)
		_remove_marker_tooltip()
		accept_event()
		return

	# Not hovering anything
	_remove_marker_tooltip()
	_clear_room_hover()
	accept_event()

func _show_tooltip(info: String, pos: Vector2):
	var tooltip_label = get_node_or_null("__tooltip_label")
	if not tooltip_label:
		tooltip_label = Label.new()
		tooltip_label.name = "__tooltip_label"
		var settings := LabelSettings.new()
		settings.font_color = Color.CHARTREUSE
		settings.font_size = 20
		tooltip_label.label_settings = settings
		add_child(tooltip_label)
	tooltip_label.text = info
	tooltip_label.position = pos

func _show_room_tooltip(scene_path: String, mouse_pos: Vector2):
	var tooltip_label = get_node_or_null("__room_tooltip")
	if not tooltip_label:
		tooltip_label = Label.new()
		tooltip_label.name = "__room_tooltip"
		var settings := LabelSettings.new()
		settings.font_color = Color.WHITE
		settings.font_size = 16
		settings.shadow_color = Color(0, 0, 0, 0.8)
		settings.shadow_size = 2
		tooltip_label.label_settings = settings
		add_child(tooltip_label)

	var scene_db: Dictionary = get_meta("scene_db", {})
	var meta = scene_db.get(scene_path, {})
	var text := scene_path.get_file()
	if not meta.is_empty():
		var parts: Array[String] = []
		if meta.get("has_boss", false):
			parts.append("Boss")
		if meta.get("has_shopkeeper", false):
			parts.append("Shop")
		if meta.get("has_teleporter", false):
			parts.append("Teleporter")
		if not meta.get("save_points", []).is_empty():
			parts.append("Save")
		if not meta.get("collectibles", []).is_empty():
			parts.append("%d Collectibles" % meta.collectibles.size())
		if not meta.get("enemies", []).is_empty():
			parts.append("%d Enemies" % meta.enemies.size())
		if not parts.is_empty():
			text += "\n" + " | ".join(parts)
	tooltip_label.text = text
	tooltip_label.position = mouse_pos + Vector2(16, 8)

func _remove_marker_tooltip():
	var tooltip_label = get_node_or_null("__tooltip_label")
	if tooltip_label:
		remove_child(tooltip_label)
		tooltip_label.queue_free()

func _clear_room_hover():
	if _last_hovered_room != "":
		var parent = get_parent()
		if parent and parent.has_signal("room_unhovered"):
			parent.room_unhovered.emit()
		_last_hovered_room = ""
	var tooltip_label = get_node_or_null("__room_tooltip")
	if tooltip_label:
		remove_child(tooltip_label)
		tooltip_label.queue_free()
