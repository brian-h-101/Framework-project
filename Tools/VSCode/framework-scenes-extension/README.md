# Framework Scenes

Shows and structurally edits the saved node hierarchy of the opened Godot `.tscn` scene in VS Code.
Nested scene instances expand inline, including inherited scene nodes and local overrides.
Runs independently alongside the Framework Resources extension.

## Setup

1. Install the VSIX in VS Code.
2. Open the Godot project, its parent folder, or a workspace containing the project.
3. In Workspace settings, set `frameworkScenes.godotExecutable` to the full Godot console executable path. If empty, the extension uses `godotTools.editorPath.godot4`.
4. Open a `.tscn` file and expand **Framework Scenes** in Explorer.

The nearest `project.godot` must have these helpers:

```text
Framework/Env/Authoring/Scenes/Inspection/scene_graph.gd
Framework/Env/Authoring/Scenes/Inspection/scene_graph_export.gd
Framework/Env/Authoring/Scenes/Inspection/scene_property_preview.gd
Framework/Env/Authoring/Scenes/Editing/scene_document.gd
Framework/Env/Authoring/Scenes/Editing/scene_references.gd
Framework/Env/Authoring/Scenes/Editing/scene_editing.gd
Framework/Env/Authoring/Scenes/Editing/scene_editing_cli.gd
Framework/Env/Authoring/Scenes/Editing/scene_script.gd
Framework/Env/Authoring/Scenes/Configuration/movement_configuration_catalog.gd
Framework/Env/Authoring/Scenes/Configuration/movement_configuration_catalog_export.gd
Framework/Env/Authoring/Scenes/Configuration/movement_capability.gd
Framework/Env/Authoring/Scenes/Configuration/movement_controller_catalog.gd
Framework/Env/Authoring/Scenes/Library/scene_library.gd
Framework/Env/Authoring/Scenes/Library/scene_library_cli.gd
Framework/Env/Authoring/Scenes/Creation/scene_templates.gd
```

The extension supports trusted local workspaces, parent folders, multiple workspace folders,
and multiple Godot projects. It resolves the project from the opened file.

## Browsing

- Expand and collapse nodes to inspect the hierarchy.
- Descriptions show native Godot types and instance filenames.
- Expand a node's **Properties** group to see its saved native properties, resource references, and metadata.
- Property tooltips show the native type and the scene that supplied the displayed value. Local overrides take precedence, and large values show compact previews.
- Click a node to open its declaring scene at the saved declaration when available.
- Right-click a node and open **Framework Scenes** for navigation commands.
- **Open Instanced Scene**, **Open Base Scene**, and **Open Attached Script** appear when applicable.
- **Open Structure Source** opens the scene that created the node, even when a local property override is displayed.
- Use **Framework Scenes: Find a Scene...** to search existing scene filenames and paths.
- **Refresh Scene** reloads the selected saved scene. Saving a dependency also refreshes it.
- Opening another `.tscn` changes the tree root. Other editor types retain the last scene.

Godot reads `PackedScene.get_state()`; the exporter does not instantiate gameplay nodes.
The view shows saved data. An unsaved-scene message explains when editor changes are absent.
External `.tscn` instances and inheritance are supported. Embedded PackedScene subresources
are reported as unsupported rather than instantiated. Instance placeholders remain unexpanded.

## Structural editing

Version 0.0.9 adds Automation resources to **Attach Behavior Resource**. Select an
editable entity root, choose the Automation by ID or path, and name the component.
Its tooltip identifies the attached Automation. Repeated attachment of the same
Automation to one entity is rejected. Use Remove Node to remove the scene component;
runtime activation remains session state until explicitly disabled or unbound.
Automations use the same Interaction permission and requirements as manual input.

Right-click a node and open **Framework Scenes**:

- **Add Child Node...** searches instantiable built-in Godot Node types, including plain, 2D, 3D and UI nodes.
- **Add Scene Instance...** browses the selected project's folders. Choose **Parent Folder** to go up or **Search All Scenes...** at the project root to search by filename or path.
- **Add Layout Preset...** lists `.layout.tres` files from `Gameplay/Presets` and its subcategories.
  Build the selected preset in Framework Resources first. Linked placements use
  the generated scene in the matching subcategory of `Gameplay/Presentation/Layouts` and keep their local
  position overrides across rebuilds.
- **Set Node Property...** adds or replaces a supported native value or metadata entry on a locally declared node.
- **Rename Node...** changes a local node or local scene placement name and repairs supported local references.
- **Remove Node...** removes a local subtree and its associated signal connections after confirmation.

Commands follow structural ownership. Local nodes and instance placements are editable.
Inherited and instanced descendants must be edited in their structure source scene. A local
property override does not grant structural ownership. Local additions remain editable even
when their parent originated in another scene. Children can be added to the opened scene's
root and locally owned nodes, including local instance roots. The scene root cannot be
renamed or removed. Duplicate sibling names and cyclic scene placements are rejected.

The writer edits selected document spans, retaining other declarations, comments, resource
references, scene UIDs, existing node IDs, transforms, groups and metadata. New nodes receive
fresh node IDs. Renaming a gameplay node preserves `metadata/entity_key`; adding a generic
scene instance does not generate gameplay entity keys or other framework metadata.

The property picker shows native and framework metadata keys suitable for the
node type. It prefills saved values. For a `Polygon2D`, enter `color` as
comma-separated red, green, blue and alpha, and enter `polygon` as successive
X, Y coordinates. It also accepts typed custom metadata. Use **Open Structure
Source** to edit a child owned by another scene. Script and resource references
continue to use their dedicated commands.

Supported reference repairs include descendant parent/owner paths, editable-instance paths,
signal connection endpoints and relative NodePath values within node properties, including
arrays and dictionaries. Removal is rejected if a surviving property would reference the
deleted subtree. Absolute paths, unique-name NodePaths, resource-owned paths such as animation
tracks, and foreign references that need a shared-source change are rejected rather than
rewritten. This first version can conservatively reject an unsupported reference even when
it appears unrelated. Arbitrary paths stored in script strings are not rewritten; review
script references when renaming nodes used by code.

The tree records hashes for scene dependencies. Editing checks these hashes and rejects dirty
scene buffers, stale selections, and changed dependencies before saving. Godot validates a
temporary staged scene without instantiating nodes, then publishes it only if the guards still
pass. Staging files are cleaned up and no backup copies are created. These are saved-file
operations; use Git or text editing for reverting a completed structural change.

Version 0.0.3 uses scene graph protocol version 2 and requires the matching project helpers.

## Configure Movement

Right-click an entity root and choose **Framework Scenes → Configure Capabilities... →
Movement**. Choose an environment when the marked body has multiple compatible
profiles, then choose a shared Behavior
and profile when there are multiple compatible choices. Select a controller
for the entity. For the example game,
Player uses `player_keyboard.tres` and Enemy uses `enemy_ai.tres`. Both use
`Profiles/Movement/Shared/movement_2d.tres` and the `move` Behavior.
The example Grid and 3D Physics profiles use the same Behavior. A grid is
defined in map coordinates, with cell centers at multiples of the cell size.

The review names the scene that will be saved. Selecting a Player instance in a map
configures its shared Player presentation. The profile's environment specification
selects a compatible adapter for a local `CharacterBody2D` or `CharacterBody3D`
marked with `metadata/entity_spatial_root = true`. An enabled
binding for the same Behavior is reused even if its node has a different name. Framework
Resources edits reusable Behavior, Movement, and input definitions. The keyboard controller
uses action names from the project's Controls resource. Add additional controller resources
under `Framework/Content/Gameplay/Controller` for the picker to discover.

Use `npm.cmd run test:movement:capability` from the extension directory to run the
Godot authoring and keyboard checks in a temporary copy of the ExampleGame project.

## Manage Authored Library

Version 0.0.5 adds the **Manage Authored Library…** folder icon between **Find a Scene**
and **Refresh**. The same command is available in the Command Palette. It works without
an open scene, including parent-folder and multi-root workspaces.

The searchable management menu offers **New Category**, **New Subcategory**, **New Scene**,
**Delete Scene**, and **Delete Empty Category**. Project and destination paths are shown
in the picker; the active Godot project is offered first. All library operations are
restricted to these roots and their descendants:

```text
Framework/Content/Gameplay/Maps
Framework/Content/Gameplay/Presentation
Framework/Content/Gameplay/UI/HUD
```

Categories are ordinary folders. The three library roots cannot be deleted. Empty-folder
deletion counts every file, including hidden files and presentation `.tres` files.
The Resource extensions manage reusable Resource libraries. Windows reserved names,
duplicate sibling names, links, junctions, traversal, and nested Godot projects are rejected.
Existing scene browsing and node editing retain their existing project scope.

New Scene collects a filename, root-node identifier, and a template suitable for its library:

| Library | Templates |
| --- | --- |
| Maps | 2D map with shared ground and lighting configuration; empty Node2D; empty Node3D |
| Presentation | Empty presentation with a searchable, instantiable native Node root |
| UI/HUD | Unshaded Control widget; CanvasLayer at layer 10 with a full-rect, unshaded Control root |

For a folder directly under `Presentation/Entity`, `Presentation/Items`, or
`Presentation/Objects`, **Entity Presentation — With Starting Attributes**
creates the scene and a sibling `starting_attributes.tres`. Choose a native root,
scene filename, root name, definition ID, and shared Authored fragments. Entity
folders preselect identity, health, and speed when available. The preset sets
the display name from the root name, and the root carries the same definition ID.

The extension verifies that Godot discovers the saved preset. Each folder has one
starting preset, and definition IDs are unique across the three categories.
Use **Presentation — Native Root** for additional scenes in the same folder.

Creation packs new detached native nodes, saves and validates a temporary scene, assigns a
UID, and publishes a new file exclusively. Verification reads saved scene state without
running scene-tree callbacks. New files use tabs and CRLF. Existing files are never
overwritten, and the new scene opens in Framework Scenes. An empty presentation can be
populated with the existing structural editor. Entity keys, presentation roles, starting
attributes, and the starting map remain authored gameplay choices.

Delete Scene scans project scene instances, inheritance, Resource dependencies, UIDs,
literal script paths, and paths stored as strings in configuration Resources, including
startup maps and map redirects. Referenced scenes remain protected and their consumers
are listed. Dynamically computed paths and external `user://` save files cannot be inferred
by this project scan. After references are removed, confirmed deletion uses the Recycle Bin.
Folder deletion is nonrecursive and requires an unchanged, empty folder. No backups are created.

Save or revert unsaved project scene, Resource, and script edits before managing the library.
Changed library snapshots, template dependencies, reference snapshots, workspace trust, or
Godot executable settings require retrying. Library management and structural editing share
one operation gate; file watchers wait for the active operation. Deleting the displayed
scene clears the tree and discards pending inspection results.

Implementation is in `src/library/`, using the shared Godot path, directory fingerprint,
and dependency helpers. This extension has no runtime dependency on the Resource extensions.

## Visual checkpoint

After installing the VSIX, run **Developer: Reload Window** and open
`Diagnostics/Fixtures/SceneGraph/structural_visual_check.tscn`:

1. Add a Marker2D beneath `LocalNodes`, rename it, then remove it.
2. Add a scene instance and confirm its children expand.
3. Rename the `Placement` root and verify the instance remains linked.
4. Inspect a child inside `Placement`: structural commands are unavailable; **Open Structure Source** opens its definition.
5. Cancel a naming dialog and verify the file is unchanged.
6. Repeat with the outer repository opened as the workspace root.

This fixture is separate from gameplay scenes.

For the library checkpoint, reload VS Code and click **Manage Authored Library**:

1. Create a temporary category and subcategory under Maps.
2. Create a 2D map and verify Ground and Lighting appear in its hierarchy.
3. Under Presentation, create a temporary scene with a Node2D or Node3D root.
4. Under UI/HUD, create a widget or HUD parent and inspect its root type.
5. Cancel a creation dialog and verify no file appears.
6. Attempt deletion of the configured starting map: its configuration references should block it.
7. Delete your unreferenced temporary scenes, then their empty categories.
8. Confirm no destinations outside the three roots are offered; repeat with the outer repository open.

## Attached scripts

Right-click a locally owned node and use **Framework Scenes > Attach Script...**
to search existing project `.gd` files by filename or path. Godot validates the
script's native base class against the selected node without instantiating it.
A node holds one script; remove its current attachment before attaching another.

**Remove Attached Script...** asks for confirmation, then clears the node's script
reference. Saved properties and shared script declarations remain intact. Reattaching
places the script before retained exported properties so Godot applies those values
when instantiating the node. Embedded scripts can also be removed.

Scripts inherited from another scene are edited in their declaring scene; use
**Open Instanced Scene**, **Open Base Scene**, or **Open Structure Source** as appropriate.
The command checks scene and inherited script hashes, unsaved edits, workspace trust,
and selection again before writing. Scene UIDs and unrelated node text are preserved.

The expanded right-click menu no longer includes **Assign Movement Configuration**.
Existing movement configuration references and the assignment backend remain available.

For the visual checkpoint:

1. Reload VS Code and open `Diagnostics/Fixtures/SceneScriptAttachment/visual_scene.tscn`.
2. Right-click `ScriptTarget`, choose **Attach Script...**, and search for `visual_script.gd`.
3. Verify **Open Attached Script** and **Remove Attached Script...** become available.
4. Remove the script, confirm the dialog, and verify the node's `caption` and position remain saved.
5. Reattach the script; cancel another removal and verify the file is unchanged.
6. Confirm **Assign Movement Configuration** is absent from the expanded menu.

The backend diagnostic is `res://Diagnostics/Authoring/scene_script_attachment_check.gd`.

## Development

```powershell
npm.cmd install
npm.cmd test
npm.cmd run package:vsix
```

Open this extension folder in VS Code and press F5 for the development host.
The launch configuration opens the adjacent framework project.
Godot 4.7.1 and VS Code 1.146.0 were used for verification.

Run Godot structural diagnostics from the project folder:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Authoring/scene_editing_check.gd
```

Run the real bridge diagnostic from this extension folder:

```powershell
$sceneProject = (Resolve-Path -LiteralPath '..\..\..\framework-project').Path
$sceneGodot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
node.exe .\diagnostics\scene_editing_bridge_check.cjs $sceneProject $sceneGodot
node.exe .\diagnostics\scene_library_bridge_check.cjs $sceneProject $sceneGodot
```

The library diagnostic creates unique temporary categories under all three roots, checks
all templates and deletion guards with real Godot processes, then removes only its own
fixtures. Existing scene bytes are checked before and after the run.

Unified Behavior Resources now appear in Attach Behavior Resource alongside
legacy Interactions and Automations. A unified attachment uses
`Content/Universal/Interaction/based/Bindings/behavior_binding.gd`; its Behavior ID and source appear
in the scene graph tooltip. Duplicate bindings within an entity are rejected.

Authoring backend scripts are grouped beneath Scenes/Creation, Editing,
Inspection, Configuration and Library. This version uses those categorized
entry-point paths.
