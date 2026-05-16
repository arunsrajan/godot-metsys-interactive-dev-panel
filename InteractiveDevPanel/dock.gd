@tool
extends Control

# UI References
@onready var filter_container := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/FilterList
@onready var scene_list := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/SceneList
@onready var scene_details := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/SceneDetails
@onready var search_box := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/SearchBox
@onready var previous_layer := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/PreviousLayer
@onready var layer_edit := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/Layer
@onready var next_layer := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/NextLayer
@onready var zoom_slider: HSlider = $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/HBoxContainer/ZoomSlider
@onready var status_label := $VBoxContainer/HBoxContainer/StatusBarContainer/HBoxContainer/StatusLabel
@onready var file_dialog := $VBoxContainer/TabContainer/QuickActions/VBoxContainer/HBoxContainer/FileDialog
@onready var project_folder_btn := $VBoxContainer/TabContainer/QuickActions/VBoxContainer/HBoxContainer/ScenesFolder
@onready var export_btn := $VBoxContainer/TabContainer/QuickActions/VBoxContainer/HBoxContainer/ExportMapData
@onready var scrollable_panel_container := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/VBoxContainer/ScrollContainer
@onready var room_width := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/RoomWidth
@onready var room_height := $VBoxContainer/TabContainer/SceneBrowser/VBoxContainer/VBoxContainer/HBoxContainer/RoomHeight
@onready var map_data_txt_group := $VBoxContainer/TabContainer/QuickActions/VBoxContainer/VBoxContainer

# Data
var current_filters: Dictionary = {}
var scene_database: Dictionary = {}
var map_data: Dictionary = {
	"layers": [],
	"cells": {},
	"labels": {},
	"room_connections": [],
	"version": "1.0",
	"source_file": ""
}
var filter_categories := ["Collectibles", "Save Points", "Teleporters"]

# State
var metsys_map_view = null
var metsys_editor = null
var _scene_scanner: SceneScanner
var overlay: MapOverlay = null
var scenes_folder: String = "res://"
var map_data_path: String = "res://"
var map_data_txts: Array[String] = []

var _last_modified: int = 0
var _check_timer: Timer
var _component_scan_timer: Timer
var _regex: RegEx

func _ready():
	_regex = RegEx.new()
	_regex.compile(r"^-?\d+,-?\d+,-?\d+/")

	var editor_filesystem = EditorInterface.get_resource_filesystem()
	if editor_filesystem:
		editor_filesystem.resources_reload.connect(_on_resources_reload)
		editor_filesystem.resources_reimported.connect(_on_resources_reimported)

	project_folder_btn.pressed.connect(_on_project_folder_btn_pressed)
	file_dialog.dir_selected.connect(_on_file_dialog_dir_selected)

	room_width.text = str(MetSys.settings.in_game_cell_size.x)
	room_height.text = str(MetSys.settings.in_game_cell_size.y)
	layer_edit.text = "0"

	previous_layer.pressed.connect(func():
		var v := int(layer_edit.text)
		if v <= 0:
			return
		layer_edit.text = str(v - 1)
		if overlay:
			overlay.set_layer(v - 1)
	)
	next_layer.pressed.connect(func():
		var v := int(layer_edit.text) + 1
		layer_edit.text = str(v)
		if overlay:
			overlay.set_layer(v)
	)
	layer_edit.text_changed.connect(func(new_text: String):
		if overlay:
			overlay.set_layer(int(new_text))
	)

	export_btn.pressed.connect(_export_map_data)

	zoom_slider.value_changed.connect(_on_zoom_changed)
	scene_list.item_selected.connect(_on_scene_selected)
	scene_list.item_activated.connect(_on_scene_activated)
	search_box.text_changed.connect(_filter_scene_list)
	search_box.text_submitted.connect(_on_search_submitted)

	scene_list.visible = true
	search_box.visible = true

	_add_fit_view_button()
	_add_export_png_button()

	setup_filters()
	load_map_data()
	find_metSys_components()
	_setup_fallback_timer()
	_setup_component_scan_timer()

	mouse_filter = Control.MOUSE_FILTER_PASS

func _setup_component_scan_timer():
	_component_scan_timer = Timer.new()
	_component_scan_timer.wait_time = 2.0
	_component_scan_timer.timeout.connect(_check_metsys_components)
	_component_scan_timer.autostart = true
	add_child(_component_scan_timer)

func _check_metsys_components():
	if not metsys_map_view or not metsys_editor:
		find_metSys_components()
	else:
		_component_scan_timer.queue_free()
		_component_scan_timer = null

func _setup_fallback_timer():
	_destroy_fallback_timer()
	if not map_data_path.ends_with("MapData.txt"):
		return
	_check_timer = Timer.new()
	_check_timer.wait_time = 2.0
	_check_timer.timeout.connect(_check_file_direct)
	_check_timer.autostart = true
	add_child(_check_timer)

func _destroy_fallback_timer():
	if _check_timer:
		remove_child(_check_timer)
		_check_timer.queue_free()
		_check_timer = null

func _check_file_direct():
	if map_data_path.is_empty() or not FileAccess.file_exists(map_data_path):
		return
	var current_modified := FileAccess.get_modified_time(map_data_path)
	if current_modified != _last_modified:
		_last_modified = current_modified
		_reload_map_data()

func _reload_map_data():
	on_checkbox_selected(true, map_data_path)

func _on_resources_reload(resources: PackedStringArray):
	_deferred_check_map_data(resources[0])

func _on_resources_reimported(resources: Array):
	for resource_path in resources:
		if resource_path.ends_with("MapData.txt"):
			_deferred_check_map_data(resource_path)
			return

func _deferred_check_map_data(resource_path: String):
	if resource_path.ends_with("MapData.txt"):
		call_deferred("load_map_data", resource_path)

func _on_project_folder_btn_pressed():
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.popup()

func _on_file_dialog_dir_selected(dir: String):
	scenes_folder = dir
	_scan_all_scenes(scenes_folder)

func setup_filters():
	for child in filter_container.get_children():
		filter_container.remove_child(child)
		child.queue_free()
	for element in MetSys.map_data.custom_elements:
		var element_data := MetSys.map_data.custom_elements[element]
		var category_name := element_data.name.capitalize()
		if not filter_categories.has(category_name):
			filter_categories.append(category_name)
	for category in filter_categories:
		var checkbox := CheckBox.new()
		checkbox.text = category
		checkbox.toggled.connect(_on_filter_toggled.bind(category))
		filter_container.add_child(checkbox)
		current_filters[category] = false

func find_node_recursive(node: Node, node_name: String, node_type: String = "", begins_with_compare: bool = false):
	if not node:
		return null
	if not begins_with_compare and node.name == node_name:
		return node
	if begins_with_compare and node.name.begins_with(node_name):
		return node
	if node_type and node.is_class(node_type):
		if not begins_with_compare and node.name == node_name:
			return node
		if begins_with_compare and node.name.begins_with(node_name):
			return node
	for child in node.get_children():
		var result = find_node_recursive(child, node_name, node_type, begins_with_compare)
		if result:
			return result
	return null

func load_map_data(p_map_data_path: String = "res://MapData.txt"):
	if not p_map_data_path.ends_with("MapData.txt"):
		status_label.text = "Unable to load map data..."
		return

	map_data_path = p_map_data_path
	map_data = {
		"layers": [],
		"cells": {},
		"labels": {},
		"room_connections": [],
		"version": "1.0",
		"source_file": map_data_path
	}

	if not FileAccess.file_exists(map_data_path):
		status_label.text = "No MapData.txt found at %s" % map_data_path
		return

	var file := FileAccess.open(map_data_path, FileAccess.READ)
	if not file:
		status_label.text = "Cannot open MapData.txt"
		return

	var current_cell: Dictionary = {}
	var layers_sorted: Array[int] = []

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if _regex.search(line) != null:
			parse_label_data_line(line, map_data.labels)
		elif line.begins_with("[") and line.ends_with("]"):
			var coord_str := line.substr(1, line.length() - 2)
			var coord_parts := coord_str.split(",")
			if coord_parts.size() == 3:
				current_cell = {
					"x": int(coord_parts[0]),
					"y": int(coord_parts[1]),
					"layer": int(coord_parts[2]),
					"connections": [0, 0, 0, 0],
					"cell_color": "#000000",
					"border_colors": ["#000000", "#000000", "#000000", "#000000"],
					"scene_uid": "",
					"scene_path": "",
					"has_data": false,
					"meta_data": {}
				}
				if not current_cell.layer in map_data.layers:
					map_data.layers.append(current_cell.layer)
		else:
			if current_cell:
				parse_cell_data_line(line, current_cell)
				var cell_key := "%d,%d,%d" % [current_cell.layer, current_cell.x, current_cell.y]
				map_data.cells[cell_key] = current_cell.duplicate()
				if not layers_sorted.has(current_cell.layer):
					layers_sorted.append(current_cell.layer)
				current_cell = {}

	file.close()

	layers_sorted.sort()
	map_data.layers.clear()
	for layer_idx in layers_sorted:
		map_data.layers.append({"idx": layer_idx, "layer_name": MetSys.get_layer_name(layer_idx)})

	resolve_scene_uids_proper()
	status_label.text = "Map data loaded: %d cells found" % map_data.cells.size()

func parse_label_data_line(line: String, label_array: Dictionary):
	var parts := line.split("/")
	if parts.size() < 2:
		return
	var axis_and_layer := parts[0].split(",")
	var cell := {"x": int(axis_and_layer[0]), "y": int(axis_and_layer[1]), "layer": int(axis_and_layer[2]), "label": "", "dimension": [], "label_info": ""}
	var cell_key := "%d,%d,%d" % [cell.layer, cell.x, cell.y]
	var cell_label := label_array.get(cell_key, [])
	cell_label.append(cell)
	label_array.set(cell_key, cell_label)
	if parts.size() > 1:
		cell.label = parts[1]
	if parts.size() > 2:
		var cell_dimension := parts[2].split("x")
		cell.dimension.append(int(cell_dimension[0]))
		cell.dimension.append(int(cell_dimension[1]))
	if parts.size() > 3:
		cell.label_info = parts[3]

func parse_cell_data_line(line: String, cell: Dictionary):
	var parts := line.split("|")
	if parts.size() < 2:
		return

	var connections_str := parts[0]
	var colors_str := parts[1]
	var scene_uid := parts[3] if parts.size() >= 4 else ""

	cell.scene_uid = scene_uid.strip_edges()

	var connection_values := connections_str.split(",")
	for i in range(min(4, connection_values.size())):
		cell.connections[i] = int(connection_values[i])

	var color_values := colors_str.split(",")
	if color_values.size() >= 1:
		cell.cell_color = "#" + color_values[0]
		for i in range(1, min(5, color_values.size())):
			if i <= 4:
				cell.border_colors[i - 1] = "#" + color_values[i]

	cell.has_data = true

func resolve_scene_uids_proper():
	for cell_key in map_data.cells:
		var cell = map_data.cells[cell_key]
		if cell.scene_uid.is_empty():
			continue
		if ResourceUID.has_id(ResourceUID.text_to_id(cell.scene_uid)):
			var uid_int := ResourceUID.text_to_id(cell.scene_uid)
			cell.scene_path = ResourceUID.get_id_path(uid_int)
		elif ResourceLoader.exists(cell.scene_uid):
			cell.scene_path = ResourceUID.ensure_path(cell.scene_uid)

	var unresolved := 0
	for cell_key in map_data.cells:
		var cell = map_data.cells[cell_key]
		if not cell.scene_uid.is_empty() and cell.scene_path.is_empty():
			unresolved += 1
			printerr("Could not resolve UID: %s for cell [%d,%d] layer %d" % [cell.scene_uid, cell.x, cell.y, cell.layer])
	if unresolved > 0:
		printerr("Warning: %d UIDs could not be resolved" % unresolved)

func _on_zoom_changed(value: float):
	if not overlay:
		return
	var room_size_vec := Vector2(float(room_width.text), float(room_height.text))
	var scale_val := value / float(zoom_slider.max_value)
	overlay.set_scale_value(scale_val)
	overlay.custom_minimum_size = room_size_vec * Vector2(overlay.cell_max_x, overlay.cell_max_y) * Vector2(scale_val, scale_val)
	scrollable_panel_container.custom_minimum_size = room_size_vec
	scrollable_panel_container.set_deferred("scroll_horizontal", room_size_vec.x)
	scrollable_panel_container.set_deferred("scroll_vertical", room_size_vec.y)

func _on_filter_toggled(checked: bool, filter_name: String):
	current_filters[filter_name] = checked
	if overlay:
		overlay.update_filters(current_filters)

func _scan_all_scenes(p_scenes_folder: String = ""):
	status_label.text = "Initializing scanner..."
	_scene_scanner = preload("res://addons/InteractiveDevPanel/scene_scanner.gd").new()
	_remove_overlay()
	_scene_scanner.scan_progress_updated.connect(_on_scan_progress)
	_scene_scanner.scan_completed.connect(_on_scan_completed)
	map_data_txts.clear()
	_scene_scanner.scan_map_data_txt_completed.connect(func(path: String):
		map_data_path = path
		map_data_txts.append(path)
	)
	var folder := p_scenes_folder if not p_scenes_folder.is_empty() else scenes_folder
	_scene_scanner.scan_all_scenes(folder)

func update_scene_browser():
	scene_list.clear()
	var search_text = search_box.text.to_lower()
	for scene_path in scene_database:
		var metadata: Dictionary = scene_database[scene_path]
		if not _passes_filters(metadata):
			continue
		if not search_text.is_empty() and not scene_path.get_file().to_lower().contains(search_text):
			continue
		var icon = _get_scene_icon(metadata)
		scene_list.add_item(scene_path.get_file(), icon)
		scene_list.set_item_metadata(scene_list.item_count - 1, scene_path)

func _passes_filters(metadata: Dictionary) -> bool:
	var any_active := false
	for filter_name in current_filters:
		if current_filters[filter_name]:
			any_active = true
			break
	if not any_active:
		return true
	if current_filters.get("Boss Rooms", false) and metadata.has_boss:
		return true
	if current_filters.get("Collectibles", false) and not metadata.collectibles.is_empty():
		return true
	if current_filters.get("Save Points", false) and not metadata.save_points.is_empty():
		return true
	if current_filters.get("Breakable Walls", false) and metadata.has_breakable_walls:
		return true
	if current_filters.get("Teleporters", false) and metadata.has_teleporter:
		return true
	if current_filters.get("Shopkeepers", false) and metadata.has_shopkeeper:
		return true
	if current_filters.get("Hidden Passages", false) and metadata.has_breakable_walls:
		return true
	return false

func _get_scene_icon(metadata: Dictionary):
	if metadata.has_boss:
		return preload("res://addons/InteractiveDevPanel/assets/BorderWall.png")
	if not metadata.collectibles.is_empty():
		return preload("res://addons/InteractiveDevPanel/assets/PlayerLocation.png")
	if not metadata.save_points.is_empty():
		return preload("res://addons/InteractiveDevPanel/assets/RoomFill.png")
	return null

func _filter_scene_list(_text: String):
	update_scene_browser()

func _on_search_submitted(text: String):
	if text.is_empty() or not overlay:
		return
	var search_lower := text.to_lower()
	for i in range(scene_list.item_count):
		var item_text = scene_list.get_item_text(i).to_lower()
		if search_lower in item_text:
			scene_list.select(i)
			var scene_path = scene_list.get_item_metadata(i)
			_center_map_on_room(scene_path)
			return

func _on_scene_selected(index: int):
	var scene_path = scene_list.get_item_metadata(index)
	if scene_path and scene_path in scene_database:
		display_scene_details(scene_path, scene_database[scene_path])
		_center_map_on_room(scene_path)

func _on_scene_activated(index: int):
	var scene_path = scene_list.get_item_metadata(index)
	if scene_path:
		EditorInterface.open_scene_from_path(scene_path)
		status_label.text = "Opened: " + scene_path.get_file()

func display_scene_details(scene_path: String, metadata: Dictionary):
	var text := "[b]Scene:[/b] %s\n" % scene_path.get_file()
	text += "[b]Path:[/b] %s\n\n" % scene_path
	text += "[b]Features:[/b]\n"
	text += "* Collectibles: %d\n" % metadata.collectibles.size()
	text += "* Enemies: %d\n" % metadata.enemies.size()
	text += "* Save Points: %d\n" % metadata.save_points.size()
	text += "* Has Boss: %s\n" % ("Yes" if metadata.has_boss else "No")
	text += "* Has Shopkeeper: %s\n" % ("Yes" if metadata.has_shopkeeper else "No")
	text += "* Breakable Walls: %s\n" % ("Yes" if metadata.has_breakable_walls else "No")
	text += "* Teleporter: %s\n" % ("Yes" if metadata.has_teleporter else "No")
	if metadata.room_instance:
		text += "\n[b]RoomInstance:[/b]\n"
		text += "* Position: %s\n" % metadata.room_instance.position
		text += "* Cell Size: %s\n" % metadata.room_instance.cell_size
	scene_details.text = text

func _export_map_data():
	var export_data := {
		"layers": map_data.layers,
		"cells": map_data.cells,
		"scene_database": scene_database,
		"filter_categories": filter_categories,
		"export_date": Time.get_datetime_string_from_system()
	}
	var json_string := JSON.stringify(export_data, "\t")
	var file_path := "res://map_export_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		status_label.text = "Exported to: %s" % file_path
		EditorInterface.get_file_system_dock().navigate_to_path(file_path)
	else:
		status_label.text = "Export failed"

func setup_map_overlay():
	if not metsys_map_view:
		return null
	if not overlay:
		overlay = preload("res://addons/InteractiveDevPanel/map_overlay.gd").new()
		overlay.name = "InteractiveDevOverlay"
		scrollable_panel_container.call_deferred("add_child", overlay)
		overlay.set_map_view(metsys_map_view)
		overlay.set_room_size(Vector2(float(room_width.text), float(room_height.text)))
		overlay.set_layer(int(layer_edit.text))
		overlay.set_scene_database(scene_database)
		overlay.update_from_map_data(map_data)
		overlay.update_filters(current_filters)
		overlay.room_clicked.connect(_on_overlay_room_clicked)
		overlay.room_hovered.connect(_on_overlay_room_hovered)
		overlay.room_unhovered.connect(_on_overlay_room_unhovered)
		_on_zoom_changed(float(zoom_slider.value))
	return overlay

func _on_overlay_room_clicked(scene_path: String):
	EditorInterface.open_scene_from_path(scene_path)
	status_label.text = "Opened: " + scene_path.get_file()

func _on_overlay_room_hovered(scene_path: String, _screen_pos: Vector2):
	var meta: Dictionary = scene_database.get(scene_path, {})
	var parts: Array[String] = [scene_path.get_file()]
	if meta.get("has_boss", false):
		parts.append("Boss")
	if meta.get("has_shopkeeper", false):
		parts.append("Shop")
	if meta.get("has_teleporter", false):
		parts.append("Teleport")
	if not meta.get("collectibles", []).is_empty():
		parts.append("%d items" % meta.collectibles.size())
	status_label.text = " | ".join(parts)

func _on_overlay_room_unhovered():
	if _scene_scanner and not scene_database.is_empty():
		var stats := _scene_scanner.get_stats()
		status_label.text = "%d scenes | %d collectibles | %d enemies" % [stats.total_scenes, stats.total_collectibles, stats.total_enemies]
	else:
		status_label.text = "Map data loaded: %d cells" % map_data.cells.size()

func find_metSys_components():
	var editor_root = EditorInterface.get_base_control()
	if not editor_root:
		push_error("Could not get editor base control")
		return

	if not metsys_map_view:
		var possible_names := ["MapView", "MapEditorView", "MetSysMapView", "RoomMapView"]
		for name in possible_names:
			metsys_map_view = find_node_recursive(editor_root, name, "Control")
			if metsys_map_view:
				break

	if not metsys_editor:
		metsys_editor = find_node_recursive(editor_root, "Main", "VBoxContainer", true)

	if metsys_map_view:
		status_label.text = "Connected to MetSys editor"
		setup_map_overlay()
	else:
		status_label.text = "Warning: MetSys editor not found. Make sure plugin is enabled."

func _on_scan_progress(current: int, total: int, current_file: String):
	status_label.text = "Scanning %d/%d: %s" % [current, total, current_file]
	if has_node("ProgressBar"):
		$ProgressBar.value = (float(current) / total) * 100

func _on_scan_completed(scene_db: Dictionary):
	scene_database = scene_db
	var stats := _scene_scanner.get_stats()
	status_label.text = "Scan complete: %d scenes, %d collectibles, %d enemies" % [stats.total_scenes, stats.total_collectibles, stats.total_enemies]

	for key in map_data.cells.keys():
		for key_scene_db in scene_database.keys():
			if map_data.cells[key].scene_path == key_scene_db:
				map_data.cells[key].meta_data = scene_db[key_scene_db]
				break

	if overlay:
		overlay.set_scene_database(scene_database)
	update_scene_browser()
	show_scan_summary()

	for child in map_data_txt_group.get_children():
		map_data_txt_group.remove_child(child)
	_destroy_fallback_timer()

	var button_group := ButtonGroup.new()
	for map_data_path_local in map_data_txts:
		var checkbox := CheckBox.new()
		checkbox.button_group = button_group
		checkbox.toggle_mode = true
		checkbox.text = map_data_path_local
		checkbox.toggled.connect(on_checkbox_selected.bind(map_data_path_local))
		map_data_txt_group.add_child(checkbox)

func on_checkbox_selected(toggle: bool, map_data_path_local: String):
	if not toggle:
		return
	_remove_overlay()
	load_map_data(map_data_path_local)
	setup_map_overlay()
	_setup_fallback_timer()

func _remove_overlay():
	if not overlay:
		return
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	scrollable_panel_container.remove_child(overlay)
	overlay = null

func show_scan_summary():
	var summary := _scene_scanner.get_feature_summary()
	var text := "Scan Summary:\n"
	text += "Total Scenes: %d\n" % summary.total_scenes
	text += "Scenes with Bosses: %d\n" % summary.scenes_with_boss
	text += "Scenes with Shops: %d\n" % summary.scenes_with_shop
	text += "Total Collectibles: %d\n" % summary.total_collectibles
	text += "Total Enemies: %d\n" % summary.total_enemies
	scene_details.text = text

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.ctrl_pressed):
		return
	var delta: float = 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		delta = 0.5
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		delta = -0.5
	else:
		return
	var new_val := zoom_slider.value + delta
	new_val = clamp(new_val, 0.0, 100.0)
	zoom_slider.value = new_val
	_on_zoom_changed(new_val)

func _center_map_on_room(scene_path: String):
	if not overlay:
		return
	var center := overlay.get_room_center(scene_path)
	if center == Vector2.ZERO:
		return
	var view_size = scrollable_panel_container.size
	scrollable_panel_container.scroll_horizontal = int(center.x - view_size.x / 2.0)
	scrollable_panel_container.scroll_vertical = int(center.y - view_size.y / 2.0)

func _add_fit_view_button():
	var btn := Button.new()
	btn.name = "FitViewButton"
	btn.text = "Fit"
	btn.tooltip_text = "Fit entire map in view"
	var hbox := zoom_slider.get_parent()
	if hbox:
		hbox.add_child(btn)
		btn.pressed.connect(_fit_view)

func _fit_view():
	if not overlay:
		return
	var total_rect := overlay.get_total_map_rect()
	if total_rect.size == Vector2.ZERO:
		return
	var view_size = scrollable_panel_container.size
	if view_size.x <= 0 or view_size.y <= 0:
		return
	var scale_x = view_size.x / total_rect.size.x
	var scale_y = view_size.y / total_rect.size.y
	var fit_scale = min(scale_x, scale_y) * 0.9
	var new_val = fit_scale * zoom_slider.max_value
	zoom_slider.value = clamp(new_val, 0.0, float(zoom_slider.max_value))
	scrollable_panel_container.scroll_horizontal = 0
	scrollable_panel_container.scroll_vertical = 0

func _add_export_png_button():
	var btn := Button.new()
	btn.name = "ExportMapPNG"
	btn.text = "Export Map PNG"
	btn.tooltip_text = "Save current map view as PNG image"
	var hbox := export_btn.get_parent()
	if hbox:
		hbox.add_child(btn)
		btn.pressed.connect(func(): _export_map_png())

var _export_viewport: SubViewport = null
var _export_file_path: String = ""

func _export_map_png():
	if not overlay:
		return
	if _export_viewport:
		status_label.text = "Export already in progress..."
		return
	var total_rect := overlay.get_total_map_rect()
	if total_rect.size == Vector2.ZERO:
		status_label.text = "Export failed: empty map"
		return

	_export_file_path = "res://map_view_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")

	# Build an off-screen clone of the overlay inside a SubViewport
	_export_viewport = SubViewport.new()
	_export_viewport.size = Vector2i(total_rect.size)
	_export_viewport.transparent_bg = true
	_export_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var clone := MapOverlay.new()
	clone.size = total_rect.size
	clone.set_room_size(overlay.room_size)
	clone.update_from_map_data(overlay.map_data)
	clone.set_scene_database(scene_database)
	clone.set_layer(overlay.current_layer)
	clone.update_filters(overlay.current_filters)
	clone.set_scale_value(overlay.scale_value)

	_export_viewport.add_child(clone)
	add_child(_export_viewport)

	# Wait a short time for the viewport to render, then capture
	var tree := get_tree()
	if not tree:
		_cleanup_export()
		return
	var timer := tree.create_timer(0.15)
	timer.timeout.connect(_capture_export_viewport)

func _capture_export_viewport():
	if not _export_viewport:
		return
	var img := _export_viewport.get_texture().get_image()
	if not img:
		status_label.text = "Export failed: could not capture viewport"
		_cleanup_export()
		return

	var result := img.save_png(_export_file_path)
	if result == OK:
		status_label.text = "Exported: %s" % _export_file_path
		EditorInterface.get_file_system_dock().navigate_to_path(_export_file_path)
	else:
		status_label.text = "Export failed: error %d" % result
	_cleanup_export()

func _cleanup_export():
	if _export_viewport:
		remove_child(_export_viewport)
		_export_viewport.queue_free()
		_export_viewport = null
	_export_file_path = ""
