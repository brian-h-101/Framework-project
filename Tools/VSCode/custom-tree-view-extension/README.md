# Custom Tree View Extension

Displays Godot resource relationships in the Framework Resources view.

## Requirements

- VS Code compatible with package.json's engines.vscode setting.
- Godot 4.7.1, used for verification.
- A trusted local workspace containing the framework project.
- The framework's Godot authoring helpers.

## Setup

1. Open the framework project folder, a parent folder, or a workspace containing it.
2. Configure godotTools.editorPath.godot4 with the Godot console executable in Workspace settings.
3. Open a supported .tres resource.

## Workspace support

The opened resource determines its nearest Godot project inside the workspace.
That project must provide Framework/Env/Authoring/resource_graph_export.gd.

Resource paths and Godot process paths use the resolved project directory.
Multiple workspace folders and projects nested beneath a workspace folder are supported.

## Resource tree

Framework Resources follows the opened action, interaction, condition,
or condition-group resource and displays its relationships.

Opening another supported .tres changes the displayed root.
Opening a non-resource editor retains the last resource tree.

Click a tree item to open its resource file.
Refresh Resources reloads the currently selected resource.

## Assignment and editing

Right-click a tree item and open the Framework Resources submenu.
Available commands depend on the clicked resource's type.

Assignment commands use the clicked resource as their destination.
A searchable picker lists existing source resources of the required type.
Search matches filenames, authored IDs, and resource paths.

Selecting a source saves the assignment and refreshes the tree.
Escape cancels selection.
Save or revert unsaved resource edits before assigning resources.

Drag-and-drop assignment and Command Palette commands are also supported.

Edit Condition reads the saved comparison before showing its prompts.
Enter at the final message prompt saves the comparison.
Escape cancels the edit.

The destination resource determines the assignment's Godot project.
Catalogue searches use that project, and source resources must belong to it.

Command Palette assignment commands ask for the destination first.
Condition editing resolves its project from the selected condition.

## Framework integration

Godot authoring helpers are loaded from Framework/Env/Authoring
inside the resolved Godot project.