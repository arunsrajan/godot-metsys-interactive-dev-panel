@tool
extends Panel

@onready var status_label: Label = $HBoxContainer/StatusMessage
@onready var progress_bar: ProgressBar = $HBoxContainer/ScanProgress
@onready var zoom_label: Label = $HBoxContainer/ZoomLabel

func set_status_message(text: String):
	if status_label:
		status_label.text = text

func set_progress(value: float, max_value: float = 100.0):
	if not progress_bar:
		return
	progress_bar.max_value = max_value
	progress_bar.value = value
	progress_bar.visible = value < max_value

func set_zoom_level(zoom: float):
	if zoom_label:
		zoom_label.text = "%d%%" % (zoom * 100)
