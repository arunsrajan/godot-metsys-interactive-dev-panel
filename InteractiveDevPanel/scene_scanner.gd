# scene_scanner.gd
@tool
extends RefCounted

class_name SceneScanner

# Signal emitted when scan progress updates
signal scan_progress_updated(current: int, total: int, current_file: String)
signal scan_completed(scene_database: Dictionary)

# Scan results
var scene_database: Dictionary = {}
var scan_stats: Dictionary = {
	"total_scenes": 0,
	"total_collectibles": 0,
	"total_enemies": 0,
	"total_save_points": 0,
	"rooms_with_boss": 0,
	"rooms_with_shop": 0,
	"rooms_with_teleporter": 0,
	"rooms_with_breakable_walls": 0
}

# Feature categories for filtering
const FEATURE_CATEGORIES = {
	"boss": "Boss Rooms",
	"collectible": "Collectibles",
	"save_point": "Save Points",
	"breakable_wall": "Breakable Walls",
	"teleporter": "Teleporters",
	"shop": "Shopkeepers",
	"hidden_passage": "Hidden Passages",
	"enemy": "Enemies"
}

# Common node group names to scan for
const COLLECTIBLE_GROUPS = ["collectible", "collectibles", "item", "items", "pickup", "pickups"]
const ENEMY_GROUPS = ["enemy", "enemies", "monster", "monsters", "hostile"]
const SAVE_POINT_GROUPS = ["save_point", "savepoint", "save", "checkpoint"]
const BREAKABLE_GROUPS = ["breakable", "destroyable", "destructible", "crate"]
const TELEPORTER_GROUPS = ["teleporter", "warp", "portal", "transition"]
const SHOP_GROUPS = ["shop", "merchant", "vendor", "trader"]

# Node type patterns to recognize
const BOSS_NAME_PATTERNS = ["boss", "king", "queen", "lord", "guardian"]
const SHOP_NAME_PATTERNS = ["shop", "merchant", "vendor", "trader", "store"]
const TELEPORTER_NAME_PATTERNS = ["teleport", "warp", "portal", "gate"]
const BREAKABLE_NAME_PATTERNS = ["break", "crate", "box", "pot", "barrel", "rock"]

func _init():
	scene_database.clear()
	reset_stats()

func reset_stats():
	scan_stats = {
		"total_scenes": 0,
		"total_collectibles": 0,
		"total_enemies": 0,
		"total_save_points": 0,
		"rooms_with_boss": 0,
		"rooms_with_shop": 0,
		"rooms_with_teleporter": 0,
		"rooms_with_breakable_walls": 0
	}

func scan_all_scenes(root_path: String = "res://") -> Dictionary:
	reset_stats()
	scene_database.clear()
	
	# Find all scene files
	var scene_files: Array[String] = []
	find_scene_files(root_path, scene_files)
	
	scan_stats.total_scenes = scene_files.size()
	var scanned = 0
	
	# Scan each scene
	for scene_path in scene_files:
		scanned += 1
		scan_progress_updated.emit(scanned, scene_files.size(), scene_path.get_file())
		
		var metadata = analyze_scene(scene_path)
		if not metadata.is_empty():
			scene_database[scene_path] = metadata
			update_stats_from_metadata(metadata)
	
	scan_completed.emit(scene_database)
	return scene_database

func find_scene_files(dir_path: String, result_array: Array[String]):
	var dir = DirAccess.open(dir_path)
	if not dir:
		printerr("Cannot open directory: ", dir_path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and file_name != "." and file_name != "..":
			# Recursively scan subdirectories
			find_scene_files(dir_path.path_join(file_name), result_array)
		elif file_name.ends_with(".tscn"):
			result_array.append(dir_path.path_join(file_name))
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func analyze_scene(scene_path: String) -> Dictionary:
	var metadata = {
		"type": "room",
		"collectibles": [],
		"enemies": [],
		"save_points": [],
		"has_boss": false,
		"has_shopkeeper": false,
		"has_breakable_walls": false,
		"has_teleporter": false,
		"has_hidden_passage": false,
		"room_instance": null,
		"connections": [],
		"node_count": 0,
		"groups": [],
		"features": {}
	}
	
	if not ResourceLoader.exists(scene_path):
		return metadata
	
	# Load the scene as PackedScene
	var packed_scene: PackedScene = load(scene_path)
	if not packed_scene:
		return metadata
	
	# Instantiate to analyze node tree
	var instance = packed_scene.instantiate()
	if not instance:
		return metadata
	
	# Scan for RoomInstance (MetSys specific)
	var room_instance = find_room_instance(instance)
	if room_instance:
		metadata.room_instance = extract_room_instance_data(room_instance)
	
	# Recursively scan all nodes for features
	scan_node_for_features(instance, metadata)
	
	# Get scene groups (from root node)
	metadata.groups = instance.get_groups()
	
	# Count total nodes
	metadata.node_count = count_nodes(instance)
	
	# Clean up
	instance.free()
	
	return metadata

func find_room_instance(node: Node) -> Node:
	if node.name == "RoomInstance" or node.is_class("RoomInstance"):
		return node
	
	for child in node.get_children():
		var result = find_room_instance(child)
		if result:
			return result
	
	return null

func extract_room_instance_data(room_node: Node) -> Dictionary:
	var data = {
		"position": room_node.position if room_node.has_method("get_position") else Vector2.ZERO,
		"cell_size": Vector2(256, 256),  # Default MetSys cell size
		"connections": []
	}
	
	# Try to get cell size if property exists
	if room_node.has_method("get_cell_size"):
		data.cell_size = room_node.get_cell_size()
	elif "cell_size" in room_node:
		data.cell_size = room_node.cell_size
	
	# Look for connection exports (MetSys uses @export_file for room links) [citation:2]
	var properties = room_node.get_property_list()
	for prop in properties:
		if prop.name.ends_with("_room") or prop.name.begins_with("connected_"):
			var value = room_node.get(prop.name)
			if value is String and not value.is_empty():
				data.connections.append({
					"name": prop.name,
					"scene_path": value
				})
	
	return data

func scan_node_for_features(node: Node, metadata: Dictionary):
	# Check node groups first (most reliable method)
	var node_groups = node.get_groups()
	metadata.groups.append_array(node_groups)
	
	# Check for collectibles
	for group in COLLECTIBLE_GROUPS:
		if node.is_in_group(group):
			metadata.collectibles.append(create_feature_entry(node, "collectible"))
			break
	
	# Check for enemies
	for group in ENEMY_GROUPS:
		if node.is_in_group(group):
			metadata.enemies.append(create_feature_entry(node, "enemy"))
			break
	
	# Check for save points
	for group in SAVE_POINT_GROUPS:
		if node.is_in_group(group):
			metadata.save_points.append(create_feature_entry(node, "save_point"))
			break
	
	# Check for breakable objects
	for group in BREAKABLE_GROUPS:
		if node.is_in_group(group):
			metadata.has_breakable_walls = true
			break
	
	# Check for teleporters
	for group in TELEPORTER_GROUPS:
		if node.is_in_group(group):
			metadata.has_teleporter = true
			break
	
	# Check for shops
	for group in SHOP_GROUPS:
		if node.is_in_group(group):
			metadata.has_shopkeeper = true
			break
	
	# Name-based detection (fallback for nodes without groups)
	var node_name_lower = node.name.to_lower()
	
	# Boss detection by name pattern
	if not metadata.has_boss:
		for pattern in BOSS_NAME_PATTERNS:
			if node_name_lower.contains(pattern):
				metadata.has_boss = true
				break
	
	# Shop detection by name pattern
	if not metadata.has_shopkeeper:
		for pattern in SHOP_NAME_PATTERNS:
			if node_name_lower.contains(pattern):
				metadata.has_shopkeeper = true
				break
	
	# Teleporter detection by name pattern
	if not metadata.has_teleporter:
		for pattern in TELEPORTER_NAME_PATTERNS:
			if node_name_lower.contains(pattern):
				metadata.has_teleporter = true
				break
	
	# Breakable detection by name pattern
	if not metadata.has_breakable_walls:
		for pattern in BREAKABLE_NAME_PATTERNS:
			if node_name_lower.contains(pattern):
				metadata.has_breakable_walls = true
				break
	
	# Check for Area2D triggers (potential hidden passages)
	if node.is_class("Area2D") and node_name_lower.contains("secret") or node_name_lower.contains("hidden"):
		metadata.has_hidden_passage = true
	
	# Recursively scan children
	for child in node.get_children():
		scan_node_for_features(child, metadata)

func create_feature_entry(node: Node, feature_type: String) -> Dictionary:
	return {
		"name": node.name,
		"type": feature_type,
		"position": node.position if node.has_method("get_position") else Vector2.ZERO,
		"global_position": node.global_position if node.has_method("get_global_position") else Vector2.ZERO,
		"scene_file": node.scene_file_path if node.has_method("get_scene_file_path") else "",
		"groups": node.get_groups(),
		"node_class": node.get_class(),
		"script": node.get_script() if node.has_method("get_script") else null
	}

func count_nodes(node: Node) -> int:
	var count = 1  # Count current node
	for child in node.get_children():
		count += count_nodes(child)
	return count

func update_stats_from_metadata(metadata: Dictionary):
	scan_stats.total_collectibles += metadata.collectibles.size()
	scan_stats.total_enemies += metadata.enemies.size()
	scan_stats.total_save_points += metadata.save_points.size()
	
	if metadata.has_boss:
		scan_stats.rooms_with_boss += 1
	if metadata.has_shopkeeper:
		scan_stats.rooms_with_shop += 1
	if metadata.has_teleporter:
		scan_stats.rooms_with_teleporter += 1
	if metadata.has_breakable_walls:
		scan_stats.rooms_with_breakable_walls += 1

func get_scenes_by_feature(feature: String) -> Array[String]:
	var result: Array[String] = []
	
	for scene_path in scene_database:
		var metadata = scene_database[scene_path]
		
		match feature:
			"boss":
				if metadata.has_boss:
					result.append(scene_path)
			"collectible":
				if not metadata.collectibles.is_empty():
					result.append(scene_path)
			"enemy":
				if not metadata.enemies.is_empty():
					result.append(scene_path)
			"save_point":
				if not metadata.save_points.is_empty():
					result.append(scene_path)
			"shop":
				if metadata.has_shopkeeper:
					result.append(scene_path)
			"teleporter":
				if metadata.has_teleporter:
					result.append(scene_path)
			"breakable":
				if metadata.has_breakable_walls:
					result.append(scene_path)
	
	return result

func get_feature_summary() -> Dictionary:
	return {
		"total_scenes": scene_database.size(),
		"scenes_with_boss": scan_stats.rooms_with_boss,
		"scenes_with_shop": scan_stats.rooms_with_shop,
		"scenes_with_teleporter": scan_stats.rooms_with_teleporter,
		"scenes_with_breakable": scan_stats.rooms_with_breakable_walls,
		"total_collectibles": scan_stats.total_collectibles,
		"total_enemies": scan_stats.total_enemies,
		"total_save_points": scan_stats.total_save_points,
		"average_collectibles_per_scene": float(scan_stats.total_collectibles) / max(1, scene_database.size())
	}

func export_to_json(file_path: String = "res://scene_scan_results.json") -> bool:
	var export_data = {
		"scan_date": Time.get_datetime_string_from_system(),
		"statistics": scan_stats,
		"feature_summary": get_feature_summary(),
		"scenes": {}
	}
	
	# Convert scene database to serializable format
	for scene_path in scene_database:
		export_data.scenes[scene_path] = serialize_metadata(scene_database[scene_path])
	
	var json_string = JSON.stringify(export_data, "\t")
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		return true
	
	return false

func serialize_metadata(metadata: Dictionary) -> Dictionary:
	var serialized = metadata.duplicate(true)
	
	# Remove non-serializable objects
	if serialized.has("room_instance") and serialized.room_instance != null:
		# Keep only serializable parts
		var room_data = serialized.room_instance
		serialized.room_instance = {
			"position": room_data.position,
			"cell_size": room_data.cell_size,
			"connections": room_data.connections
		}
	
	return serialized

func get_stats() -> Dictionary:
	return scan_stats.duplicate()

func clear_database():
	scene_database.clear()
	reset_stats()
