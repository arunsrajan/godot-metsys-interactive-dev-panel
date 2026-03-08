@tool
extends EditorPlugin

class_name InteractiveDevPanel
const MET_SYS_PLUGIN_NAME = "MetSys"
const MET_SYS_PLUGIN = "MetroidvaniaSystem"
const INTERACTIVE_DEV_PANEL_PLUGIN_NAME = "InteractiveDevPanel"

var dock_instance
var map_overlay_instance
var initialized = false
var idp_plugin_initialized = false

func _enable_plugin() -> void:  # ← Changed from _enter_tree
	_init_plugin()
	
func _disable_plugin() -> void:  # ← Changed from _exit_tree
	_clean_plugin()
	
func _init_plugin() -> void:
	if EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN_NAME) or EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN):
		if not initialized:
			# Load and instance the dock scene
			dock_instance = preload("res://addons/InteractiveDevPanel/dock.tscn").instantiate()
			add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
			initialized = true
	elif EditorInterface.get_editor_toaster() != null:
		EditorInterface.get_editor_toaster().push_toast("MetSys plugin should be installed and enabled in project settings for interactive developer panel to work!")
	
func _clean_plugin() -> void:
	# Clean up
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()
		dock_instance = null
	initialized = false
	
func _enter_tree() -> void:
	_init_plugin()

func _exit_tree() -> void:
	_clean_plugin()
