@tool
extends TextureRect
class_name MapOverlay

signal room_clicked(scene_path: String)
signal room_hovered(scene_path: String, screen_pos: Vector2)
signal room_unhovered()

const SAVEPOINT_TEXTURE := preload("res://addons/InteractiveDevPanel/assets/savepoint_idp.png")
const COLLECTIBLE_TEXTURE := preload("res://addons/InteractiveDevPanel/assets/collectible_idp.png")
const TELEPORTER_TEXTURE := preload("res://addons/InteractiveDevPanel/assets/teleporter_idp.png")
const LABELS_TEXTURE := preload("res://addons/InteractiveDevPanel/assets/labels_idp.png")
const DRAW_MARKER_SCRIPT := preload("res://addons/InteractiveDevPanel/draw_marker.gd")

# Room type overlay colors
const COLOR_BOSS := Color(1.0, 0.15, 0.15, 0.25)
const COLOR_SAVE := Color(0.15, 0.4, 1.0, 0.25)
const COLOR_SHOP := Color(1.0, 0.75, 0.1, 0.25)
const COLOR_TELEPORTER := Color(0.15, 1.0, 0.3, 0.25)
const COLOR_COLLECTIBLE := Color(1.0, 0.85, 0.0, 0.2)

var current_filters: Dictionary = {}
var map_data: Dictionary = {}
var map_view_reference = null
var scale_value: float = 0.4
var room_size: Vector2 = Vector2(864, 480)
var current_layer: int = 0
var cell_max_x: float = 0
var cell_max_y: float = 0
var cell_min_x: float = 0
var cell_min_y: float = 0

var _offset_x: float = 0
var _offset_y: float = 0
var _room_transforms: Dictionary = {}
var _marker_entries: Array = []
var _room_rects: Dictionary = {}
var _scene_db: Dictionary = {}

var _panning := false
var _pan_start: Vector2 = Vector2.ZERO
var _scroll_start: Vector2 = Vector2.ZERO

func _ready():
	visibility_changed.connect(_rebuild)
	stretch_mode = TextureRect.STRETCH_SCALE
	expand_mode = ExpandMode.EXPAND_IGNORE_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_scene_database(db: Dictionary):
	_scene_db = db

func set_scale_value(value: float):
	scale_value = value
	_rebuild()

func set_room_size(size: Vector2):
	room_size = size

func set_map_view(map_view):
	map_view_reference = map_view

func set_layer(layer: int):
	current_layer = layer
	_rebuild()

func update_filters(filters: Dictionary):
	current_filters = filters
	_rebuild()

func update_from_map_data(data: Dictionary):
	map_data = data

func get_room_center(scene_path: String) -> Vector2:
	if _room_rects.has(scene_path):
		return _room_rects[scene_path].get_center()
	return Vector2.ZERO

func get_total_map_rect() -> Rect2:
	if cell_max_x <= 0 or cell_max_y <= 0:
		return Rect2()
	var room_scale_vec := Vector2(scale_value, scale_value)
	var total_size := room_size * room_scale_vec * Vector2(cell_max_x, cell_max_y)
	return Rect2(Vector2.ZERO, total_size)

func _rebuild():
	if not map_data or not map_data.has("cells") or map_data.cells.is_empty():
		return
	_clear_children()
	_compute_cell_transform()
	_spawn_rooms_and_markers()
	queue_redraw()

func _clear_children():
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _find_room_instance(node: Node) -> Node:
	if node.name == "RoomInstance" or node.is_class("RoomInstance"):
		return node
	for child in node.get_children():
		var result := _find_room_instance(child)
		if result:
			return result
	return null

func _compute_cell_transform():
	_room_transforms.clear()
	_marker_entries.clear()
	_room_rects.clear()
	cell_min_x = 0
	cell_min_y = 0
	cell_max_x = 0
	cell_max_y = 0
	_offset_x = 0
	_offset_y = 0

	var raw_min_x := 0
	var raw_min_y := 0
	var raw_max_x := 0
	var raw_max_y := 0
	var first := true

	for cell_key in map_data.cells:
		var cell: Dictionary = map_data.cells[cell_key]
		if cell.get("layer") != current_layer:
			continue
		var cx: int = cell.get("x", 0)
		var cy: int = cell.get("y", 0)
		if first:
			raw_min_x = cx
			raw_max_x = cx
			raw_min_y = cy
			raw_max_y = cy
			first = false
		else:
			raw_min_x = min(cx, raw_min_x)
			raw_min_y = min(cy, raw_min_y)
			raw_max_x = max(cx, raw_max_x)
			raw_max_y = max(cy, raw_max_y)

	if first:
		return

	if raw_min_x < 0:
		_offset_x = float(abs(raw_min_x))
	if raw_min_y < 0:
		_offset_y = float(abs(raw_min_y))

	cell_min_x = _offset_x
	cell_min_y = _offset_y
	cell_max_x = float(raw_max_x) + _offset_x + 1.0
	cell_max_y = float(raw_max_y) + _offset_y + 1.0

	for cell_key in map_data.cells:
		var cell: Dictionary = map_data.cells[cell_key]
		if cell.get("layer") != current_layer:
			continue
		var scene_path: String = cell.get("scene_path", "")
		if scene_path.is_empty():
			continue
		var cx: float = float(cell.get("x", 0)) + _offset_x
		var cy: float = float(cell.get("y", 0)) + _offset_y
		if _room_transforms.has(scene_path):
			var t: Dictionary = _room_transforms[scene_path]
			t.x = min(t.x, cx)
			t.y = min(t.y, cy)
			t.min_x = min(t.min_x, cx)
			t.min_y = min(t.min_y, cy)
			t.max_x = max(t.max_x, cx + 1.0)
			t.max_y = max(t.max_y, cy + 1.0)
		else:
			_room_transforms[scene_path] = {
				"x": cx, "y": cy,
				"min_x": cx, "min_y": cy,
				"max_x": cx + 1.0, "max_y": cy + 1.0,
				"scene_path": scene_path,
				"cell_room": cell
			}

	for scene_path in _room_transforms:
		var t: Dictionary = _room_transforms[scene_path]
		t.width = max(1.0, t.max_x - t.min_x)
		t.height = max(1.0, t.max_y - t.min_y)

func _get_room_type_overlay(cell: Dictionary) -> Color:
	var meta = cell.get("meta_data", {})
	if meta is Dictionary and not meta.is_empty():
		if meta.get("has_boss", false):
			return COLOR_BOSS
		if meta.get("has_shopkeeper", false):
			return COLOR_SHOP
		if meta.get("has_teleporter", false):
			return COLOR_TELEPORTER
		if not meta.get("save_points", []).is_empty():
			return COLOR_SAVE
		if not meta.get("collectibles", []).is_empty():
			return COLOR_COLLECTIBLE
	return Color.TRANSPARENT

func _spawn_rooms_and_markers():
	var room_scale_vec := Vector2(scale_value, scale_value)
	var room_scaled := room_size * room_scale_vec

	for scene_path in _room_transforms:
		var t: Dictionary = _room_transforms[scene_path]
		if not ResourceLoader.exists(scene_path):
			continue
		var packed: PackedScene = load(scene_path)
		if not packed:
			continue
		var instance := packed.instantiate()
		if not instance:
			continue

		var cell_size := room_size
		var room_inst := instance.get_node_or_null("RoomInstance")
		if not room_inst:
			room_inst = _find_room_instance(instance)
		if room_inst and "cell_size" in room_inst:
			var cs: Vector2 = room_inst.cell_size
			if cs.x > 0 and cs.y > 0:
				cell_size = cs

		var instance_scale := room_scaled / cell_size
		instance.scale = instance_scale
		instance.position = room_scaled * Vector2(t.x, t.y)
		add_child(instance)

		# Store room rect for click/hover detection
		var room_pixel_size := room_scaled * Vector2(t.width, t.height)
		_room_rects[scene_path] = Rect2(instance.position, room_pixel_size)

		# Apply room type color overlay
		var overlay_color := _get_room_type_overlay(t.cell_room)
		if overlay_color != Color.TRANSPARENT:
			var color_rect := ColorRect.new()
			color_rect.color = overlay_color
			color_rect.size = room_pixel_size
			color_rect.position = instance.position
			color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(color_rect)

		var pos = instance.position
		if instance.has_node("SavePoint") and current_filters.get("Save Points", false):
			var sp := instance.get_node("SavePoint")
			var sp_pos = pos + sp.position * instance_scale - Vector2(SAVEPOINT_TEXTURE.get_width() / 2.0, SAVEPOINT_TEXTURE.get_height())
			_marker_entries.append({"texture": SAVEPOINT_TEXTURE, "pos": sp_pos, "info": "Save Points:\n" + scene_path})
		if instance.has_node("Collectible") and current_filters.get("Collectibles", false):
			var cp := instance.get_node("Collectible")
			var cp_pos = pos + cp.position * instance_scale - Vector2(COLLECTIBLE_TEXTURE.get_width() / 2.0, COLLECTIBLE_TEXTURE.get_height())
			_marker_entries.append({"texture": COLLECTIBLE_TEXTURE, "pos": cp_pos, "info": "Collectible:\n" + scene_path})
		var cell_key_label := "%d,%d,%d" % [current_layer, int(t.x - _offset_x), int(t.y - _offset_y)]
		if map_data.labels.has(cell_key_label):
			for lbl in map_data.labels[cell_key_label]:
				if not lbl.label_info.is_empty() and current_filters.get("Teleporters", false):
					_marker_entries.append({"texture": TELEPORTER_TEXTURE, "pos": pos + Vector2(10, 10), "info": "Teleportation Point:\n" + lbl.label_info})

	var layers_local: Array[String] = []
	for layer in map_data.layers:
		layers_local.append(layer.layer_name)

	for cell_key_label in map_data.labels:
		for idx in range(map_data.labels[cell_key_label].size()):
			var cell_label: Dictionary = map_data.labels[cell_key_label][idx]
			if cell_label.layer != current_layer:
				continue
			if not current_filters.get(cell_label.label.capitalize(), false):
				continue
			if layers_local.has(cell_label.label_info):
				continue
			var label_x: float = float(cell_label.get("x", 0)) + _offset_x
			var label_y: float = float(cell_label.get("y", 0)) + _offset_y
			var label_pos := room_scaled * Vector2(label_x, label_y) + Vector2(10, 10)
			var label_info: String = cell_label.label_info if not cell_label.label_info.is_empty() else cell_label.label.capitalize()
			_marker_entries.append({"texture": LABELS_TEXTURE, "pos": label_pos, "info": label_info})

	var layer_label := Label.new()
	layer_label.text = MetSys.get_layer_name(current_layer)
	layer_label.custom_minimum_size = Vector2(100, 100)
	layer_label.position = Vector2.ZERO
	add_child(layer_label)

	if not _marker_entries.is_empty():
		var marker_rect := TextureRect.new()
		marker_rect.set_script(DRAW_MARKER_SCRIPT)
		marker_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		marker_rect.size = room_scaled * Vector2(cell_max_x, cell_max_y)
		marker_rect.set_meta("room_rects", _room_rects)
		marker_rect.set_meta("scene_db", _scene_db)
		for entry in _marker_entries:
			marker_rect.append_marker(entry.texture, entry.pos, entry.info)
		add_child(marker_rect)
		marker_rect.queue_redraw()

func _draw():
	var room_scale_vec := Vector2(scale_value, scale_value)
	var room_scaled := room_size * room_scale_vec
	var arrow_size := 8.0 * scale_value

	for cell_key in map_data.cells:
		var cell: Dictionary = map_data.cells[cell_key]
		if cell.get("layer") != current_layer:
			continue
		var connections: Array = cell.get("connections", [0, 0, 0, 0])
		var cx: float = float(cell.get("x", 0)) + cell_min_x
		var cy: float = float(cell.get("y", 0)) + cell_min_y
		var top_left := room_scaled * Vector2(cx, cy)
		var top_right := room_scaled * Vector2(cx + 1.0, cy)
		var bottom_left := room_scaled * Vector2(cx, cy + 1.0)
		var bottom_right := room_scaled * Vector2(cx + 1.0, cy + 1.0)
		# Right wall
		if connections[0] == 0:
			draw_line(top_right, bottom_right, Color.RED, 3)
		else:
			_draw_connection_arrow(top_right, bottom_right, Vector2.RIGHT, arrow_size)
		# Bottom wall
		if connections[1] == 0:
			draw_line(bottom_right, bottom_left, Color.RED, 3)
		else:
			_draw_connection_arrow(bottom_right, bottom_left, Vector2.DOWN, arrow_size)
		# Left wall
		if connections[2] == 0:
			draw_line(bottom_left, top_left, Color.RED, 3)
		else:
			_draw_connection_arrow(bottom_left, top_left, Vector2.LEFT, arrow_size)
		# Top wall
		if connections[3] == 0:
			draw_line(top_left, top_right, Color.RED, 3)
		else:
			_draw_connection_arrow(top_left, top_right, Vector2.UP, arrow_size)

func _draw_connection_arrow(from: Vector2, to: Vector2, direction: Vector2, arrow_size: float):
	var mid := (from + to) / 2.0
	var perp := Vector2(-direction.y, direction.x)
	var shaft_end := mid + direction * arrow_size
	var wing_base := mid + direction * arrow_size * 0.5
	draw_line(mid, shaft_end, Color.GREEN, 2)
	draw_line(shaft_end, wing_base + perp * arrow_size * 0.6, Color.GREEN, 2)
	draw_line(shaft_end, wing_base - perp * arrow_size * 0.6, Color.GREEN, 2)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_panning = true
				_pan_start = event.global_position
				var parent_scroll = get_parent()
				if parent_scroll and parent_scroll is ScrollContainer:
					_scroll_start = Vector2(parent_scroll.scroll_horizontal, parent_scroll.scroll_vertical)
				accept_event()
			else:
				_panning = false
				accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for scene_path in _room_rects:
				if _room_rects[scene_path].has_point(event.position):
					room_clicked.emit(scene_path)
					accept_event()
					return
	elif event is InputEventMouseMotion and _panning:
		var parent_scroll = get_parent()
		if parent_scroll and parent_scroll is ScrollContainer:
			var delta = event.global_position - _pan_start
			parent_scroll.scroll_horizontal = int(_scroll_start.x - delta.x)
			parent_scroll.scroll_vertical = int(_scroll_start.y - delta.y)
		accept_event()
