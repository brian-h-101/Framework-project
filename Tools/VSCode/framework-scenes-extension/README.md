# Framework Scenes

Shows the saved node hierarchy of the opened Godot `.tscn` scene in VS Code.
Nested scene instances expand inline, including inherited scene nodes and local overrides.
Runs independently alongside the Framework Resources extension.

## Setup

1. Install the VSIX in VS Code.
2. Open the Godot project, its parent folder, or a workspace containing the project.
3. In Workspace settings, set `frameworkScenes.godotExecutable` to the full Godot console executable path. If empty, the extension uses `godotTools.editorPath.godot4`.
4. Open a `.tscn` file and expand **Framework Scenes** in Explorer.

The nearest `project.godot` must have these helpers:

```text
Framework/Env/Authoring/Scenes/scene_graph.gd
Framework/Env/Authoring/Scenes/scene_graph_export.gd
```

The extension supports trusted local workspaces, parent folders, multiple workspace folders,
and multiple Godot projects. It resolves the project from the opened file.

## Browsing

- Expand and collapse nodes to inspect the hierarchy.
- Descriptions show native Godot types and instance filenames.
- Click a node to open its declaring scene at the saved declaration when available.
- Right-click a node and open **Framework Scenes** for navigation commands.
- **Open Instanced Scene**, **Open Base Scene**, and **Open Attached Script** appear when applicable.
- Use **Framework Scenes: Find a Scene...** to search existing scene filenames and paths.
- **Refresh Scene** reloads the selected saved scene. Saving a dependency also refreshes it.
- Opening another `.tscn` changes the tree root. Other editor types retain the last scene.

Godot reads `PackedScene.get_state()`; the exporter does not instantiate gameplay nodes.
The view shows saved data. An unsaved-scene message explains when editor changes are absent.
This version browses scenes and opens files; it does not modify scenes or place entities.
External `.tscn` instances and inheritance are supported. Embedded PackedScene subresources
are reported as unsupported rather than instantiated. Instance placeholders remain unexpanded.

## Development

```powershell
npm.cmd install
npm.cmd test
npm.cmd run package:vsix
```

Open this extension folder in VS Code and press F5 for the development host.
The launch configuration opens the adjacent framework project.
Godot 4.7.1 and VS Code 1.146.0 were used for verification.
