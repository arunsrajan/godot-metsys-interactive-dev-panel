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
var _metsys_check_timer = null
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
			if _metsys_check_timer:
				remove_child(_metsys_check_timer)
				_metsys_check_timer = null;
	elif EditorInterface.get_editor_toaster() != null:
		EditorInterface.get_editor_toaster().push_toast("MetSys plugin should be installed and enabled in project settings for interactive developer panel to work!")
		if not _metsys_check_timer:
			_metsys_check_timer = Timer.new()
			_metsys_check_timer.wait_time = 2.0  # Check every 3 seconds
			_metsys_check_timer.timeout.connect(_init_plugin)
			_metsys_check_timer.autostart = true
			add_child(_metsys_check_timer)
	
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
