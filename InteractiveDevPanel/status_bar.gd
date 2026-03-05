# status_bar.gd - Attach to your status bar Panel
extends Panel

@onready var status_label = $HBoxContainer/StatusMessage
@onready var progress_bar = $HBoxContainer/ScanProgress
@onready var zoom_label = $HBoxContainer/ZoomLabel

func set_status_message(text: String):
	if status_label:
		status_label.text = text

func set_progress(value: float, max_value: float = 100.0):
	if progress_bar:
		progress_bar.value = (value / max_value) * 100.0
		progress_bar.visible = value < max_value

func set_zoom_level(zoom: float):
	if zoom_label:
		zoom_label.text = "%d%%" % (zoom * 100)
