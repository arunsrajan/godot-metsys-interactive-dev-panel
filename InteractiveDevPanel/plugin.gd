@tool
extends EditorPlugin

var dock_instance
var map_overlay_instance

func _enable_plugin() -> void:  # ← Changed from _enter_tree
	# Load and instance the dock scene
	dock_instance = preload("res://addons/InteractiveDevPanel/dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
	add_map_overlay()

func _disable_plugin() -> void:  # ← Changed from _exit_tree
	# Clean up
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()
	
	if map_overlay_instance:
		map_overlay_instance.queue_free()

func add_map_overlay():
	# Find MetSys map editor and add overlay
	# This requires examining MetSys source for exact node paths
	var map_editor = find_metSys_map_editor()
	if map_editor:
		map_overlay_instance = preload("res://addons/InteractiveDevPanel/map_overlay.gd").new()
		map_editor.add_child(map_overlay_instance)

func find_metSys_map_editor():
	# Search through editor interface for MetSys map view
	# You'll need to inspect MetSys source to implement this
	return null
