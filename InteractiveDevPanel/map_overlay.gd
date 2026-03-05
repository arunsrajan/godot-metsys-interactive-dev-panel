# map_overlay.gd
@tool
extends Panel

class_name MapOverlay

var current_filters = {}
var map_data = {}
var map_view_reference = null  # Reference to the MetSys MapView

# Create a Control node to handle drawing
var drawing_area
var scale_value=1.0
var room_size  = Vector2(864, 480)
var current_layer = 0;
func _ready():
	# Create a Control node for drawing if it doesn't exist
	if not has_node("DrawingArea"):
		drawing_area = TextureRect.new()
		drawing_area.name = "DrawingArea"
		drawing_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(drawing_area)
	else:
		drawing_area = $DrawingArea
	# Connect to the drawing area's draw signal
	drawing_area.draw.connect(_on_drawing_area_draw)
	visibility_changed.connect(_on_drawing_area_draw)

func set_scale_value(value:float):
	scale_value = value
func set_room_size(size:Vector2):
	room_size = size
func update_filters(filters: Dictionary):
	current_filters = filters
	# Trigger redraw through the drawing area
	if drawing_area:
		drawing_area.queue_redraw()

func update_from_map_data(data: Dictionary):
	map_data = data
	# Trigger redraw through the drawing area
	if drawing_area:
		drawing_area.queue_redraw()

func set_map_view(map_view):
	map_view_reference = map_view

func set_layer(layer:int):
	current_layer = layer
	_on_drawing_area_draw()

func _on_drawing_area_draw():
	if not map_data or not map_data.has("cells") or not map_data.cells:
		return
	var children = get_children()
	# Iterate through the list and free each child
	for child in children:
		remove_child(child)
		child.queue_free()
	# Get the actual map view position and zoom if available
	var view_offset = Vector2.ZERO
	var view_zoom = 1.0
	
	if map_view_reference:
		# Try to get view properties from MetSys MapView
		if map_view_reference.has_method("get_view_offset"):
			view_offset = map_view_reference.get_view_offset()
		if map_view_reference.has_method("get_zoom"):
			view_zoom = map_view_reference.get_zoom()
	
	# Draw markers for each cell based on filters
	print("Current Layer ", current_layer)
	var cell_transform: Dictionary = {}
	var cell_min_x=3000000;
	var cell_min_y=3000000;
	for cell_key in map_data.cells:
		var cell = map_data.cells[cell_key]
		if not cell.get("scene_path") == "" and cell.get("layer") == current_layer:
			cell_min_x = min( cell.get("x"), cell_min_x)
			cell_min_y = min( cell.get("y"), cell_min_y)
			if cell_transform.has(cell.get("scene_path")):
				cell_transform[cell.get("scene_path")].x = min(cell_transform[cell.get("scene_path")].x, cell.get("x"));
				cell_transform[cell.get("scene_path")].y = min(cell_transform[cell.get("scene_path")].y, cell.get("y"));
				cell_transform[cell.get("scene_path")].min_x = min(cell_transform[cell.get("scene_path")].min_x, cell.get("x"));
				cell_transform[cell.get("scene_path")].min_y = min(cell_transform[cell.get("scene_path")].min_y, cell.get("y"));
				cell_transform[cell.get("scene_path")].max_x = max(cell_transform[cell.get("scene_path")].max_x, cell.get("x"));
				cell_transform[cell.get("scene_path")].max_y = min(cell_transform[cell.get("scene_path")].max_y, cell.get("y"));

			else:
				cell_transform.set(cell.get("scene_path"), {"x":cell.get("x"), "y":cell.get("y"),"scene_path":cell.get("scene_path"), "min_x":cell.get("x"), "max_x":cell.get("x"), "min_y":cell.get("y"), "max_y":cell.get("y"), "width":0, "height":0})
	
	if cell_min_x < 0:
		cell_min_x = abs(cell_min_x)
	else:
		cell_min_x = 0;
	if cell_min_y < 0:
		cell_min_y = abs(cell_min_y)
	else:
		cell_min_y = 0;
	print("Room Size", room_size)
	if cell_min_y > 0 or cell_min_x > 0:
		for cell_key in cell_transform:
			cell_transform[cell_key].x += cell_min_x
			cell_transform[cell_key].y += cell_min_y
			cell_transform[cell_key].width = cell_transform[cell_key].max_x - cell_transform[cell_key].min_x
			cell_transform[cell_key].height = cell_transform[cell_key].max_y - cell_transform[cell_key].min_y
			cell_transform[cell_key].width = 1 if cell_transform[cell_key].width == 0 else cell_transform[cell_key].width
			cell_transform[cell_key].height = 1 if cell_transform[cell_key].height == 0 else cell_transform[cell_key].height
	for cell_key in cell_transform:
		draw_room(cell_transform[cell_key])
		
	for cell_key in map_data.cells:
		var cell = map_data.cells[cell_key]
		var metadata = cell.get("meta_data", {})
		if should_draw_cell(cell, metadata):
			draw_cell_marker(cell, metadata, view_offset, view_zoom)
	
func should_draw_cell(cell: Dictionary, metadata: Dictionary) -> bool:
	# If no filters active, don't draw overlays
	var any_active = false
	for filter_name in current_filters:
		if current_filters[filter_name]:
			any_active = true
			break
	
	if not any_active:
		return false
	
	# Check each active filter
	if current_filters.get("Boss Rooms", false) and metadata.get("has_boss", false):
		return true
	
	if current_filters.get("Collectibles", false) and not metadata.get("collectibles", []).is_empty():
		return true
	
	if current_filters.get("Save Points", false) and not metadata.get("save_points", []).is_empty():
		return true
	
	if current_filters.get("Breakable Walls", false) and metadata.get("has_breakable_walls", false):
		return true
	
	if current_filters.get("Teleporters", false) and metadata.get("has_teleporter", false):
		return true
	
	if current_filters.get("Shopkeepers", false) and metadata.get("has_shopkeeper", false):
		return true
	
	if current_filters.get("Connections", false) and not cell.get("connections", []).is_empty():
		return true
	
	return false

func draw_cell_marker(cell: Dictionary, metadata: Dictionary, view_offset: Vector2, view_zoom: float):
	if not drawing_area:
		return
	
	# Get cell screen position (depends on your MetSys map view)
	var screen_pos = get_cell_screen_position(cell, view_offset, view_zoom)
	
	# Draw marker based on type
	if metadata.get("has_boss", false):
		draw_boss_marker(screen_pos)
	
	var collectible_count = metadata.get("collectibles", []).size()
	if collectible_count > 0:
		draw_collectible_marker(screen_pos, collectible_count)
	
	if metadata.get("has_shopkeeper", false):
		draw_shop_marker(screen_pos)
	
	if metadata.get("has_save_points", false) or not metadata.get("save_points", []).is_empty():
		draw_save_marker(screen_pos)

func draw_room(cell):
	if not cell.get("scene_path") == "":
		var room = load(cell.get("scene_path")).instantiate()
		add_child(room)
		print(cell.get("x"), " ", cell.get("y"), " ", cell.get("scene_path"))
		var position = room_size * Vector2(cell.get("x"), cell.get("y"))
		room.position = Vector2(position.x, position.y)

func get_room_cell_screen_position(cell: Dictionary, view_offset: Vector2, view_zoom: float) -> Vector2:
	# This assumes each cell is 256x256 (default RoomInstance cell_size)
	var cell_size = 256
	var base_pos = Vector2(cell.x * cell_size, cell.y * cell_size)
	
	# Apply view transform
	var view_transform = (base_pos - view_offset) * view_zoom + get_viewport().size * 0.5
	print("View After Transformed", view_transform)
	return view_transform

func get_cell_screen_position(cell: Dictionary, view_offset: Vector2, view_zoom: float) -> Vector2:
	# Try to use MetSys MapView for conversion if available
	if map_view_reference and map_view_reference.has_method("cell_to_screen"):
		return map_view_reference.cell_to_screen(cell.layer, cell.coords)
	
	# Fallback: calculate approximate position
	# This assumes each cell is 256x256 (default RoomInstance cell_size)
	var cell_size = 20
	var base_pos = Vector2(cell.x * cell_size, cell.y * cell_size)
	
	# Apply view transform
	return (base_pos - view_offset) * view_zoom + get_viewport().size * 0.5

func draw_boss_marker(pos: Vector2):
	if not drawing_area:
		return
	
	# Draw outer circle
	drawing_area.draw_circle(pos, 15, Color(1, 0, 0, 0.7))  # Semi-transparent red
	drawing_area.draw_circle(pos, 12, Color(1, 0.2, 0.2, 0.9))  # Brighter inner
	
	# Draw skull symbol (simple X)
	drawing_area.draw_line(pos + Vector2(-6, -6), pos + Vector2(6, 6), Color.WHITE, 2)
	drawing_area.draw_line(pos + Vector2(6, -6), pos + Vector2(-6, 6), Color.WHITE, 2)
	
	# Draw label if zoomed in enough
	if drawing_area.get_global_transform().get_scale().x > 0.8:
		drawing_area.draw_string(ThemeDB.fallback_font, pos + Vector2(20, -10), "BOSS", 
								HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.RED)

func draw_collectible_marker(pos: Vector2, count: int):
	if not drawing_area:
		return
	
	# Draw star/gem shape
	var points = get_star_points(pos, 10, 5, 5)
	drawing_area.draw_colored_polygon(points, Color(1, 0.8, 0, 0.8))  # Gold
	
	# Draw count
	var count_text = "x%d" % count
	drawing_area.draw_string(ThemeDB.fallback_font, pos + Vector2(15, 5), count_text,
							HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.YELLOW)

func draw_shop_marker(pos: Vector2):
	if not drawing_area:
		return
	
	# Draw coin shape
	drawing_area.draw_circle(pos + Vector2(0, 30), 8, Color(0.8, 0.6, 0, 0.8))  # Gold
	drawing_area.draw_string(ThemeDB.fallback_font, pos + Vector2(15, 25), "$",
							HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.GOLD)

func draw_save_marker(pos: Vector2):
	if not drawing_area:
		return
	
	# Draw bench/save icon
	var bench_rect = Rect2(pos + Vector2(-8, 45), Vector2(16, 4))
	drawing_area.draw_rect(bench_rect, Color(0.6, 0.3, 0, 0.8))  # Brown
	
	# Draw flame/soul symbol
	drawing_area.draw_circle(pos + Vector2(0, 40), 5, Color(0, 0.8, 1, 0.7))  # Blue

func get_star_points(center: Vector2, radius: float, points: int, inner_radius_ratio: float) -> PackedVector2Array:
	var result = PackedVector2Array()
	var angle = -PI / 2  # Start from top
	
	for i in range(points * 2):
		var r = radius if i % 2 == 0 else radius * inner_radius_ratio
		var x = center.x + r * cos(angle)
		var y = center.y + r * sin(angle)
		result.append(Vector2(x, y))
		angle += PI / points
	
	return result

func clear_markers():
	if drawing_area:
		drawing_area.queue_redraw()

# Optional: Handle viewport resizing
func _on_drawing_area_resized():
	drawing_area.queue_redraw()
