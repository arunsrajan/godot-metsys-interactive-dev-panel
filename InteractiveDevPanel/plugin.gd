@tool
extends EditorPlugin

class_name InteractiveDevPanel

const INTERACTIVE_DEV_PANEL_EXTENTION_PATH = "InteractiveDevPanel/Extension"
var dock_instance
var map_overlay_instance
var initialized = false

func _enable_plugin() -> void:  # ← Changed from _enter_tree
	_init_plugin()
	
func _disable_plugin() -> void:  # ← Changed from _exit_tree
	_clean_plugin()
	
func _init_plugin() -> void:
	if not initialized:
		# Load and instance the dock scene
		dock_instance = preload("res://addons/InteractiveDevPanel/dock.tscn").instantiate()
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
		initialized = true
	
func _clean_plugin() -> void:
	# Clean up
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()
	initialized = false
	
func _enter_tree() -> void:
	_init_plugin()

func _exit_tree() -> void:
	_clean_plugin()
