# InteractiveDevPanel

A Godot 4 editor plugin that visualizes Metroidvania maps by laying out actual `.tscn` scene previews onto grid cells defined in `MapData.txt`. Designed to work alongside the **MetSys** plugin.

## Requirements

- Godot 4.x
- **MetSys** (MetroidvaniaSystem) plugin must be installed and enabled

## Installation

Copy the `addons/InteractiveDevPanel` folder into your project's `addons/` directory and enable the plugin in **Project Settings > Plugins**.

## Quick Start

1. Open the **InteractiveDevPanel** dock (appears on the right side of the editor)
2. Switch to the **Quick Actions** tab and click **Open Project Folder** to select your scenes directory
3. The scanner finds all `.tscn` files and any `MapData.txt` files
4. Select a `MapData.txt` from the list that appears to load the map
5. Switch to the **Scene Browser** tab to explore the map

## Features

### Map Visualization
- **Scene previews** — each room on the map renders an actual PackedScene instance, scaled to fit the grid cell size defined by the scene's `RoomInstance.cell_size`
- **Room type color overlays** — rooms are tinted based on their metadata:
  - Red — Boss room
  - Blue — Save point
  - Gold — Shopkeeper
  - Green — Teleporter
  - Yellow — Collectibles
- **Connection indicators** — cell borders show red lines on blocked walls and green arrows on open passages pointing in the connection direction
- **Markers** — save points, collectibles, and teleporter icons are overlaid on the map when their respective filters are enabled
- **Layer navigation** — `<` `>` buttons and a text field to switch between map layers
- **Zoom slider** — scales the map view; also responds to `Ctrl + Scroll` on the dock

### Scene Browser
- **Scene list** — browse all scanned rooms with type-based icons
- **Search** — type a room name to filter the list; press **Enter** to jump the map to the first match
- **Scene details** — select a room to see its feature breakdown (collectibles, enemies, save points, boss, shopkeeper, etc.)
- **Double-click to open** — double-click any scene in the list to open it in the editor
- **Filter toggles** — filter by Collectibles, Save Points, Teleporters, and any custom elements defined in MetSys

### Map Interaction
- **Click room to open** — left-click any room on the map to open its `.tscn` in the editor
- **Room hover info** — hovering a room shows a tooltip with its feature summary (boss, shop, teleporter, collectible/enemy counts) and updates the status bar
- **Middle-mouse pan** — drag with the middle mouse button to pan the map
- **Marker tooltips** — hover over save point, collectible, or teleporter icons to see details

### Navigation
- **Auto-fit view** — click the **Fit** button next to the zoom slider to automatically scale and center the map to show everything
- **Search-and-center** — selecting a scene in the browser auto-scrolls the map to that room
- **Layer switching** — navigate layers without losing zoom or filter state

### Export
- **Export Map Data** — exports all map data, scene database, and metadata as a formatted JSON file
- **Export Map PNG** — renders the current map view (including scene previews, color overlays, connection arrows, and markers) to a PNG image

### Scene Scanner
- Recursively scans directories for `.tscn` files
- Detects `MapData.txt` files automatically during scanning
- Identifies room features by group membership and naming patterns:
  - **Collectibles** — groups: `collectible`, `collectibles`, `item`, `items`, `pickup`, `pickups`
  - **Enemies** — groups: `enemy`, `enemies`, `monster`, `monsters`, `hostile`
  - **Save points** — groups: `save_point`, `savepoint`, `save`, `checkpoint`
  - **Bosses** — name contains: `boss`, `king`, `queen`, `lord`, `guardian`
  - **Shopkeepers** — groups: `shop`, `merchant`, `vendor`, `trader` or name matches
  - **Teleporters** — groups: `teleporter`, `warp`, `portal`, `transition` or name matches
  - **Breakable walls** — groups: `breakable`, `destroyable`, `destructible`, `crate` or name matches
  - **Hidden passages** — `Area2D` nodes with `secret` or `hidden` in the name
- Displays scan progress with a progress bar
- Shows summary statistics after scan completes

### Live Reload
- Automatically reloads the map when `MapData.txt` is modified externally
- Responds to filesystem reload and reimport signals

## File Structure

```
addons/InteractiveDevPanel/
├── plugin.gd              # EditorPlugin entry point
├── dock.gd                # Main dock UI and controller
├── dock.tscn              # Dock scene layout
├── map_overlay.gd         # Map visualization and rendering
├── draw_marker.gd         # Mouse interaction handler for the map
├── scene_scanner.gd       # Scene file scanner and feature detector
├── status_bar.gd          # Status bar panel component
├── README.md
└── assets/
    ├── savepoint_idp.png
    ├── collectible_idp.png
    ├── teleporter_idp.png
    ├── labels_idp.png
    ├── BorderWall.png
    ├── PlayerLocation.png
    └── RoomFill.png
```

## Signals

### MapOverlay

| Signal | Arguments | Description |
|--------|-----------|-------------|
| `room_clicked` | `scene_path: String` | Emitted when a room is left-clicked on the map |
| `room_hovered` | `scene_path: String`, `screen_pos: Vector2` | Emitted when the mouse enters a room |
| `room_unhovered` | — | Emitted when the mouse leaves a room |

### SceneScanner

| Signal | Arguments | Description |
|--------|-----------|-------------|
| `scan_progress_updated` | `current: int`, `total: int`, `current_file: String` | Emitted during scanning with progress info |
| `scan_completed` | `scene_database: Dictionary` | Emitted when scanning finishes with the full database |
| `scan_map_data_txt_completed` | `map_data_txt_path: String` | Emitted when a `MapData.txt` file is found |

## How It Works

1. **Plugin startup** — waits for the MetSys editor components to appear in the editor UI, then creates the dock
2. **Map loading** — parses `MapData.txt` for cell coordinates, connections, colors, and scene UIDs; resolves UIDs to actual file paths via Godot's `ResourceUID` system
3. **Map rendering** — for each cell on the current layer, loads the corresponding `.tscn` as a PackedScene, instances it, and scales it to fit the grid
4. **Interaction** — a transparent `TextureRect` with `draw_marker.gd` script sits on top of the map, handling all mouse input (clicks, hovers, panning)
