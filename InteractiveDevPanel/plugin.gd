@tool
extends EditorPlugin

const MET_SYS_PLUGIN_NAME = "MetSys"
const MET_SYS_PLUGIN = "MetroidvaniaSystem"

var dock_instance: Control
var initialized := false
var _metsys_check_timer: Timer

func _enter_tree() -> void:
	_init_plugin()

func _exit_tree() -> void:
	_clean_plugin()

func _enable_plugin() -> void:
	_init_plugin()

func _disable_plugin() -> void:
	_clean_plugin()

func _init_plugin() -> void:
	if not (EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN_NAME) or EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN)):
		EditorInterface.get_editor_toaster().push_toast("MetSys plugin should be installed and enabled in project settings for InteractiveDevPanel to work.")
		if not _metsys_check_timer:
			_metsys_check_timer = Timer.new()
			_metsys_check_timer.wait_time = 2.0
			_metsys_check_timer.timeout.connect(_init_plugin)
			_metsys_check_timer.autostart = true
			add_child(_metsys_check_timer)
		return
	if initialized:
		return
	_clear_check_timer()
	dock_instance = preload("res://addons/InteractiveDevPanel/dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
	initialized = true

func _clean_plugin() -> void:
	_clear_check_timer()
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()
		dock_instance = null
	initialized = false

func _clear_check_timer() -> void:
	if _metsys_check_timer:
		remove_child(_metsys_check_timer)
		_metsys_check_timer.queue_free()
		_metsys_check_timer = null
