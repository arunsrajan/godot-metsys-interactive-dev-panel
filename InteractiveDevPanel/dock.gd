@tool
extends Control

# UI References
@onready var filter_container = $VBoxContainer/TabContainer/Filters/FilterList
@onready var scene_list = $VBoxContainer/TabContainer/SceneBrowser/HBoxContainer/SceneList
@onready var scene_details = $VBoxContainer/TabContainer/SceneBrowser/HBoxContainer/SceneDetails
@onready var search_box = $VBoxContainer/TabContainer/SceneBrowser/HBoxContainer/SearchBox
@onready var zoom_slider:HSlider = $VBoxContainer/HBoxContainer/ZoomSlider
@onready var status_label = $VBoxContainer/HBoxContainer/StatusBarContainer/HBoxContainer/StatusLabel
@onready var scan_btn = $VBoxContainer/TabContainer/QuickActions/HBoxContainer/ScanAllScenes
@onready var refresh_btn = $VBoxContainer/TabContainer/QuickActions/HBoxContainer/RefreshMap
@onready var export_btn = $VBoxContainer/TabContainer/QuickActions/HBoxContainer/ExportMapData
@onready var scrollable_panel_container = $VBoxContainer/TabContainer/SceneBrowser/HBoxContainer/ScrollContainer/VBoxContainer/HScrollBar/VScrollBar/PanelContainer
@onready var room_width = $VBoxContainer/TabContainer/SceneBrowser/HBoxContainer/RoomWidth
@onready var room_height = $VBoxContainer/TabContainer/SceneBrowser/HBoxContainer/RoomHeight


# Data Structures
var current_filters = {}
var scene_database = {}  # scene_path -> metadata
var map_data = {
	"layers": [],
	"cells": {},
	"room_connections": []
}
var filter_categories = [
	"Boss Rooms",
	"Collectibles", 
	"Save Points",
	"Breakable Walls",
	"Teleporters",
	"Shopkeepers",
	"Hidden Passages",
	"Connections"
]

# Editor references (will be populated dynamically)
var metSys_map_view = null
var metSys_editor = null
var _scene_scanner:SceneScanner  # Will hold scanner instance
var overlay:MapOverlay = null
func _ready():
	# Setup UI connections
	setup_ui_connections()
	
	# Initialize filters
	setup_filters()
	
	# Load map data
	load_map_data()
	
	# Find MetSys editor components
	find_metSys_components()
	
	# Initial scan if needed
	scan_btn.pressed.connect(_scan_all_scenes)
	refresh_btn.pressed.connect(refresh_map_display)
	export_btn.pressed.connect(_export_map_data)

func setup_ui_connections():
	# Zoom controls
	zoom_slider.value_changed.connect(_on_zoom_changed)
	
	# Scene browser
	scene_list.item_selected.connect(_on_scene_selected)
	scene_list.item_activated.connect(_on_scene_activated)
	search_box.text_changed.connect(_filter_scene_list)

func setup_filters():
	# Clear existing
	for child in filter_container.get_children():
		child.queue_free()
	
	# Create filter checkboxes
	for category in filter_categories:
		var checkbox = CheckBox.new()
		checkbox.text = category
		checkbox.toggled.connect(_on_filter_toggled.bind(category))
		filter_container.add_child(checkbox)
		current_filters[category] = false

func find_node_recursive(node, node_name: String, node_type: String = "",begins_with_compare:bool = false):
	if not node:
		return null

	if not begins_with_compare and node.name == node_name or begins_with_compare and node.name.begins_with(node_name):
		return node
	
	if node_type and node.is_class(node_type) and (not begins_with_compare and node.name == node_name or begins_with_compare and node.name.begins_with(node_name)):
		return node
	
	for child in node.get_children():
		var result = find_node_recursive(child, node_name, node_type,begins_with_compare)
		if result:
			return result
	
	return null

func load_map_data():
	status_label.text = "Loading map data..."
	
	# Get map root folder from MetSys settings
	var map_root = get_metSys_setting("map_root_folder", "res://SampleProject/Maps/")
	var map_data_path = map_root.path_join("MapData.txt")
	
	# Clear existing map data
	map_data = {
		"layers": [],
		"cells": {},
		"room_connections": [],
		"version": "1.0",
		"source_file": map_data_path
	}
	
	if not FileAccess.file_exists(map_data_path):
		status_label.text = "No MapData.txt found at %s" % map_data_path
		return
	
	var file = FileAccess.open(map_data_path, FileAccess.READ)
	if not file:
		status_label.text = "Cannot open MapData.txt"
		return
	
	var line_number = 0
	var current_cell = null
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		line_number += 1
		
		# Skip empty lines and comments
		if line.is_empty() or line.begins_with("#"):
			continue
		
		# Check if this is a coordinate line [x,y,layer]
		if line.begins_with("[") and line.ends_with("]"):
			# Parse coordinates
			var coord_str = line.substr(1, line.length() - 2)
			var coord_parts = coord_str.split(",")
			if coord_parts.size() == 3:
				current_cell = {
					"x": int(coord_parts[0]),
					"y": int(coord_parts[1]),
					"layer": int(coord_parts[2]),
					"connections": [0, 0, 0, 0],  # right, bottom, left, top
					"cell_color": "#000000",
					"border_colors": ["#000000", "#000000", "#000000", "#000000"],
					"scene_uid": "",
					"scene_path": "",
					"has_data": false,
					"meta_data": {}
				}
				
				# Track layers
				if not current_cell.layer in map_data.layers:
					map_data.layers.append(current_cell.layer)
		else:
			# This should be the data line for the current cell
			if current_cell:
				parse_cell_data_line(line, current_cell)
				
				# Store the cell in map_data
				var cell_key = "%d,%d,%d" % [current_cell.layer, current_cell.x, current_cell.y]
				map_data.cells[cell_key] = current_cell.duplicate()
				
				# Reset current cell
				current_cell = null
	
	file.close()
	print("Map Data Cells", map_data.cells)
	# Resolve UIDs to actual scene paths
	resolve_scene_uids_proper()
	
	status_label.text = "Map data loaded: %d cells found" % map_data.cells.size()
	
	# Also try to load through MetSys API if available
	#if Engine.has_singleton("MetSys"):
	#	var metSys = Engine.get_singleton("MetSys")
	#	if metSys and metSys.has_method("get_map_data"):
	#		var api_data = metSys.get_map_data()
	#		if api_data:
				# Merge with file-based data
	#			merge_map_data(api_data)
	#			status_label.text = "Map data loaded via MetSys API"

func parse_cell_data_line(line: String, cell: Dictionary):
	# Split by double pipe first (separates scene UID)
	var parts = line.split("|")
	if parts.size() < 2:
		return
	
	var connections_str = parts[0]  # 0,0,1,0
	var colors_str = parts[1]       # 008a4c,94ff8b,94ff8b,94ff8b,94ff8b
	var collectibles_or_teleporter = "" if parts.size() > 2 else parts[2]
	var scene_uid = "" if parts.size() > 4 else parts[3]
	
	# Store scene UID
	cell.scene_uid = scene_uid.strip_edges()
	
	
	
	# Parse connections (right, bottom, left, top)
	var connection_values = connections_str.split(",")
	for i in range(min(4, connection_values.size())):
		cell.connections[i] = int(connection_values[i])
	
	# Parse colors
	var color_values = colors_str.split(",")
	if color_values.size() >= 1:
		# First color is cell color
		cell.cell_color = "#" + color_values[0]
		
		# Next four colors are border colors (left, top, right, bottom)
		for i in range(1, min(5, color_values.size())):
			if i <= 4:  # border colors
				cell.border_colors[i-1] = "#" + color_values[i]
	
	cell.has_data = true

func resolve_scene_uids_proper():
	for cell_key in map_data.cells:
		var cell = map_data.cells[cell_key]
		if cell.scene_uid and not cell.scene_uid.is_empty():
			# Method 1: Use ResourceUID singleton (most efficient)
			if ResourceUID.has_id(ResourceUID.text_to_id(cell.scene_uid)):
				var uid_int = ResourceUID.text_to_id(cell.scene_uid)
				cell.scene_path = ResourceUID.get_id_path(uid_int)
				print("Resolved %s -> %s" % [cell.scene_uid, cell.scene_path])
				continue
			
			# Method 2: Try loading directly with the UID string
			# This works because load() accepts uid:// paths directly! [citation:3]
			if ResourceLoader.exists(cell.scene_uid):
				# Get the path without loading the full resource
				# Note: ResourceLoader.has_cached() would load it, so we use exists()
				cell.scene_path = cell.scene_uid  # Store the UID for later loading
				# You can also use ensure_path() to convert UID to path [citation:4]
				cell.scene_path = ResourceUID.ensure_path(cell.scene_uid)
	
	# Validate results
	var unresolved = 0
	for cell_key in map_data.cells:
		var cell = map_data.cells[cell_key]
		if cell.scene_uid and not cell.scene_uid.is_empty() and cell.scene_path.is_empty():
			unresolved += 1
			printerr("Could not resolve UID: %s for cell [%d,%d] layer %d" % [
				cell.scene_uid, cell.x, cell.y, cell.layer])
	
	if unresolved > 0:
		printerr("Warning: %d UIDs could not be resolved" % unresolved)

# Alternative: If you need to actually load the scene later
func get_scene_from_cell(cell: Dictionary):
	if cell.scene_uid and not cell.scene_uid.is_empty():
		# This works because load() accepts uid:// paths! [citation:3]
		return load(cell.scene_uid)
	elif cell.scene_path and not cell.scene_path.is_empty():
		return load(cell.scene_path)
	return null

func hex_color_to_color(hex_string: String) -> Color:
	if hex_string.begins_with("#"):
		hex_string = hex_string.substr(1)
	
	if hex_string.length() == 6:
		var r = int("0x" + hex_string.substr(0, 2)) / 255.0
		var g = int("0x" + hex_string.substr(2, 2)) / 255.0
		var b = int("0x" + hex_string.substr(4, 2)) / 255.0
		return Color(r, g, b)
	
	return Color.WHITE

func get_connection_direction(connections: Array) -> Dictionary:
	return {
		"right": connections[0],
		"bottom": connections[1],
		"left": connections[2],
		"top": connections[3]
	}

func get_metSys_setting(setting_name: String, default_value):
	# Check project settings first
	if ProjectSettings.has_setting("MetSys/" + setting_name):
		return ProjectSettings.get_setting("MetSys/" + setting_name)
	
	# Look for MetSysSettings.tres
	var settings_paths = [
		"res://MetSysSettings.tres",
        "res://addons/MetroidvaniaSystem/MetSysSettings.tres"
	]
	
	for path in settings_paths:
		if ResourceLoader.exists(path):
			var settings = load(path)
			if settings and settings.has(setting_name):
				return settings.get(setting_name)
	
	return default_value

func merge_map_data(api_data):
	# This is a placeholder - actual implementation depends on MetSys API structure
	if api_data.has("cells"):
		for cell in api_data.cells:
			var key = "%d,%d,%d" % [cell.layer, cell.x, cell.y]
			if key in map_data.cells:
				map_data.cells[key].merge(cell)
			else:
				map_data.cells[key] = cell

func refresh_map_display():
	if metSys_map_view and metSys_map_view.has_method("queue_redraw"):
		# Trigger redraw
		metSys_map_view.queue_redraw()
		
		# If we have overlay, update it
		if overlay:
			overlay.update_filters(current_filters)
			overlay.update_from_map_data(map_data)
	
	status_label.text = "Map display refreshed"

func _on_zoom_changed(value: float):
	if overlay:
		overlay.set_scale_value(value)
		overlay.set_room_size(Vector2(float(room_width.text), float(room_height.text)))
		overlay.scale = Vector2(value / 100.0, value / 100.0)

func _on_filter_toggled(checked: bool, filter_name: String):
	current_filters[filter_name] = checked
	refresh_map_display()
	_filter_scene_list(filter_name)

func _scan_all_scenes():
	status_label.text = "Initializing scanner..."
	
	# Create scanner instance
	_scene_scanner = preload("res://addons/InteractiveDevPanel/scene_scanner.gd").new()
	
	# Connect signals
	_scene_scanner.scan_progress_updated.connect(_on_scan_progress)
	_scene_scanner.scan_completed.connect(_on_scan_completed)
	
	# Start scan (optionally specify subfolder)
	_scene_scanner.scan_all_scenes("res://SampleProject/Maps/")

func find_scene_files(dir_path: String, result_array: Array):
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and file_name != "." and file_name != "..":
				find_scene_files(dir_path.path_join(file_name), result_array)
			elif file_name.ends_with(".tscn"):
				result_array.append(dir_path.path_join(file_name))
			file_name = dir.get_next()
		dir.list_dir_end()

func find_room_instance(node) -> Node:
	if node.name == "RoomInstance" or node.is_class("RoomInstance"):
		return node
	
	for child in node.get_children():
		var result = find_room_instance(child)
		if result:
			return result
	
	return null

func scan_node_for_features(node, metadata: Dictionary):
	# Check node groups
	if node.is_in_group("collectible") or node.is_in_group("collectibles"):
		metadata.collectibles.append({
			"name": node.name,
			"position": node.position,
			"type": "collectible"
		})
	
	if node.is_in_group("enemy"):
		metadata.enemies.append({
			"name": node.name,
			"position": node.position,
			"type": "enemy"
		})
	
	if node.is_in_group("save_point") or node.name.to_lower().contains("save"):
		metadata.save_points.append({
			"name": node.name,
			"position": node.position
		})
	
	# Check by name patterns
	var name_lower = node.name.to_lower()
	if name_lower.contains("boss"):
		metadata.has_boss = true
	if name_lower.contains("shop") or name_lower.contains("merchant"):
		metadata.has_shopkeeper = true
	if name_lower.contains("break") or name_lower.contains("destroy"):
		metadata.has_breakable_walls = true
	if name_lower.contains("teleport") or name_lower.contains("warp"):
		metadata.has_teleporter = true
	
	# Check children
	for child in node.get_children():
		scan_node_for_features(child, metadata)

func match_scene_to_map_cell(scene_path: String, metadata: Dictionary):
	for cell_key in map_data.cells:
		var cell = map_data.cells[cell_key]
		if cell.scene_path == scene_path:
			cell.metadata = metadata
			break

func update_scene_browser():
	scene_list.clear()
	
	var search_text = search_box.text.to_lower()
	
	for scene_path in scene_database:
		var metadata = scene_database[scene_path]
		# Apply filters
		if not passes_filters(metadata):
			continue
		
		# Apply search
		if search_text and not scene_path.get_file().to_lower().contains(search_text):
			continue
		# Add to list
		var icon = get_scene_icon(metadata)
		scene_list.add_item(scene_path.get_file(), icon)
		
		# Store scene path in item metadata
		var item_idx = scene_list.item_count - 1
		scene_list.set_item_metadata(item_idx, scene_path)

func passes_filters(metadata: Dictionary) -> bool:
	# If no filters active, show all
	var any_active = false
	for filter_name in current_filters:
		if current_filters[filter_name]:
			any_active = true
			break
	
	if not any_active:
		return true
	
	# Check each active filter
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
		
	if current_filters.get("Connections", false):
		return true
	
	return false

func get_scene_icon(metadata: Dictionary):
	if metadata.has_boss:
		return preload("res://addons/InteractiveDevPanel/assets/BorderWall.png")
	elif not metadata.collectibles.is_empty():
		return preload("res://addons/InteractiveDevPanel/assets/PlayerLocation.png")
	elif not metadata.save_points.is_empty():
		return preload("res://addons/InteractiveDevPanel/assets/RoomFill.png")
	else:
		return null

func _filter_scene_list(scene:String):
	update_scene_browser()

func _on_scene_selected(index: int):
	var scene_path = scene_list.get_item_metadata(index)
	if scene_path and scene_path in scene_database:
		display_scene_details(scene_path, scene_database[scene_path])

func _on_scene_activated(index: int):
	var scene_path = scene_list.get_item_metadata(index)
	if scene_path:
		EditorInterface.open_scene_from_path(scene_path)
		status_label.text = "Opened: " + scene_path.get_file()

func display_scene_details(scene_path: String, metadata: Dictionary):
	var text = "[b]Scene:[/b] %s\n" % scene_path.get_file()
	text += "[b]Path:[/b] %s\n\n" % scene_path
	
	text += "[b]Features:[/b]\n"
	text += "• Collectibles: %d\n" % metadata.collectibles.size()
	text += "• Enemies: %d\n" % metadata.enemies.size()
	text += "• Save Points: %d\n" % metadata.save_points.size()
	text += "• Has Boss: %s\n" % ("Yes" if metadata.has_boss else "No")
	text += "• Has Shopkeeper: %s\n" % ("Yes" if metadata.has_shopkeeper else "No")
	text += "• Breakable Walls: %s\n" % ("Yes" if metadata.has_breakable_walls else "No")
	text += "• Teleporter: %s\n" % ("Yes" if metadata.has_teleporter else "No")
	
	if metadata.room_instance:
		text += "\n[b]RoomInstance:[/b]\n"
		text += "• Position: %s\n" % metadata.room_instance.position
		text += "• Cell Size: %s\n" % metadata.room_instance.cell_size
	
	scene_details.text = text

func _export_map_data():
	var export_data = {
		"layers": map_data.layers,
		"cells": map_data.cells,
		"scene_database": scene_database,
		"filter_categories": filter_categories,
		"export_date": Time.get_datetime_string_from_system()
	}
	
	var json_string = JSON.stringify(export_data, "\t")
	
	# Save to file
	var file_path = "res://map_export_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		status_label.text = "Exported to: %s" % file_path
		EditorInterface.get_file_system_dock().navigate_to_path(file_path)
	else:
		status_label.text = "Export failed"

func highlight_cell(layer: int, cell_coords: Vector2i):
	if metSys_map_view and metSys_map_view.has_method("highlight_cell"):
		metSys_map_view.highlight_cell(layer, cell_coords)

func center_on_cell(layer: int, cell_coords: Vector2i):
	if metSys_map_view and metSys_map_view.has_method("center_on"):
		metSys_map_view.center_on(layer, cell_coords)

# Add this function to dock.gd
func setup_map_overlay():
	if not metSys_map_view:
		return null
	
	# Create overlay instance
	overlay = preload("res://addons/InteractiveDevPanel/map_overlay.gd").new()
	overlay.name = "InteractiveDevOverlay"
	overlay.set_scale_value(zoom_slider.value / 100.0)
	# Add as child of map view
	scrollable_panel_container.call_deferred("add_child", overlay)
	# Pass reference to map view
	overlay.set_map_view(metSys_map_view)
	# Initial update with current data
	overlay.update_from_map_data(map_data)
	overlay.update_filters(current_filters)
	return overlay

# Update the find_metSys_components function
func find_metSys_components():
	var editor_root = EditorInterface.get_base_control()
	if not editor_root:  # ← Add this check
		push_error("Could not get editor base control")
		return
	if editor_root:
		# Look for MetSys map view (common names used in MetSys)
		var possible_names = ["MapView", "MapEditorView", "MetSysMapView", "RoomMapView"]
		for name in possible_names:
			metSys_map_view = find_node_recursive(editor_root, name, "Control")
			if metSys_map_view:
				break
		
	var possible_window_names = [
		"Main"
		]
	
	for window_name in possible_window_names:
		# Look for MetSys editor main window
		metSys_editor = find_node_recursive(editor_root, window_name, "VBoxContainer", true)
		if metSys_editor:
				# Find the TabContainer within the window
				var tab_container = find_node_recursive(metSys_editor, "TabContainer")
				if tab_container:
					# Access specific tabs by index
					var map_editor_tab = tab_container.get_child(0)  # Map Editor
					var map_viewer_tab = tab_container.get_child(1)  # Map Viewer
					var manage_tab = tab_container.get_child(2)
				break
	
	if metSys_map_view:
		status_label.text = "Connected to MetSys editor"
		# Setup overlay after finding map view
		setup_map_overlay()
	else:
		status_label.text = "Warning: MetSys editor not found. Make sure plugin is enabled."

func _on_scan_progress(current: int, total: int, current_file: String):
	status_label.text = "Scanning %d/%d: %s" % [current, total, current_file]
	
	# Optional: Update a progress bar if you have one
	if has_node("ProgressBar"):
		$ProgressBar.value = (float(current) / total) * 100

func _on_scan_completed(scene_db: Dictionary):
	scene_database = scene_db
	var stats = _scene_scanner.get_stats()
	status_label.text = "Scan complete: %d scenes, %d collectibles, %d enemies" % [
		stats.total_scenes,
		stats.total_collectibles,
		stats.total_enemies
	]
	
	for key in map_data.cells.keys():
		for key_scene_db in scene_database.keys():
			if map_data.cells[key].scene_path == key_scene_db:
				map_data.cells[key].meta_data = scene_db[key_scene_db]
				break;

	# Update scene browser
	update_scene_browser()
	
	# Optional: Show summary
	show_scan_summary()

func show_scan_summary():
	var summary = _scene_scanner.get_feature_summary()
	var text = "Scan Summary:\n"
	text += "Total Scenes: %d\n" % summary.total_scenes
	text += "Scenes with Bosses: %d\n" % summary.scenes_with_boss
	text += "Scenes with Shops: %d\n" % summary.scenes_with_shop
	text += "Total Collectibles: %d\n" % summary.total_collectibles
	text += "Total Enemies: %d\n" % summary.total_enemies
	scene_details.size.x = 100
	scene_details.size.y = 100
	# Display in your details panel
	scene_details.text = text
