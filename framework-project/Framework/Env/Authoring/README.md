# Godot authoring helpers

```text
Authoring/
    Resources/
        condition_assignment.gd
        condition_assignment_cli.gd
        condition_editing.gd
        condition_editing_cli.gd
        resource_catalog_export.gd
        resource_graph_export.gd
    Scenes/
        entity_scene_authoring.gd
        map_scene_authoring.gd
        scene_graph.gd
        scene_graph_export.gd
```

`Resources` handles `.tres` inspection, catalogue discovery, assignments, and
condition comparison editing. The Resource Condition extension calls these helpers.

`Scenes` handles saved `.tscn` hierarchy inspection, presentation assembly and
placement, and map creation. The Framework Scenes extension uses the scene graph
exporter. Presentation assembly reads `starting_attributes.tres` and `presentation.tres`.

Run CLI entry points from the Godot project folder with a Godot console executable:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Resources/resource_graph_export.gd -- res://Framework/Content/Behavior/Interaction/strike.tres

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Scenes/scene_graph_export.gd -- res://Games/ExampleGame/World/city_recreated.tscn

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Scenes/entity_scene_authoring.gd -- catalogue
```

The CLI argument formats and result prefixes are preserved. Inspection reads saved
data. Assignment and assembly helpers write only when their write commands are invoked.

The extension bridges now use these categorized paths. Compatible package versions
start at Resource Condition Extension 0.0.4 and Framework Scenes 0.0.2.
