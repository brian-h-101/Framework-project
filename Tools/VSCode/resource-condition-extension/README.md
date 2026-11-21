# Resource Condition Extension

Displays Godot resource relationships in the Framework Resources view.

## Source structure

```text
src/
    extension.ts        Extension activation and command registration
    bridges/            Godot process calls and response validation
    commands/           Assignment and condition-editing workflows
    library/            Behavior library management and typed Resource creation
    resources/          Resource selection and searchable pickers
    tree/               Tree rendering and drag-and-drop handling
    workspace/          Godot project and workspace resolution
```

Source and package folder: `Tools/VSCode/resource-condition-extension`.
The Framework Resources view and existing `customTreeView.*` command identifiers
are retained. Command Palette entries are grouped under Resource Conditions.

## Replacing the previous installation

Renaming the package changes its extension ID to
`framework-tools.resource-condition-extension`. Before installing the renamed
package, uninstall `framework-tools.custom-tree-view-extension` so that only one
extension registers the shared Framework Resources view and commands.

Run these commands from the outer `Framework-project` folder:

```powershell
code.cmd --uninstall-extension framework-tools.custom-tree-view-extension
code.cmd --install-extension '.\Tools\VSCode\resource-condition-extension\resource-condition-extension-0.0.11.vsix'
```

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
That project must provide Framework/Env/Authoring/Resources/resource_graph_export.gd.

Resource paths and Godot process paths use the resolved project directory.
Multiple workspace folders and projects nested beneath a workspace folder are supported.

## Resource tree

Framework Resources follows the opened action, interaction, condition,
condition-group, or Automation resource and displays its relationships and nested data.
Resource rows identify their owning `.tres` file. Nested rows show native types,
including the distinction between String and StringName and exact 64-bit integers.

Opening another supported .tres changes the displayed root.
Opening a non-resource editor retains the last resource tree.
Opening a valid attribute, configuration, presentation, or other non-behavior
Resource clears this view and shows guidance without an error notification.
Schema recognition uses the loaded Resource type, regardless of its folder or
filename. Supported behavior Resources with missing IDs or broken references
still report errors. Version 0.0.7 adds this distinction to graph protocol v2.

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

## Structural editing

Version 0.0.11 supports Automation resources. Manage Behavior Library can create
them with an Interaction reference and finite interval/cooldown durations.
Open an Automation to edit its timing rows, or choose **Set Automation Interaction**
from its Framework Resources context menu. Its linked Interaction expands into
the existing Action and Condition hierarchy. Gameplay activation remains an
explicit per-entity scene attachment through Framework Scenes.

Version 0.0.5 requires resource graph protocol v2 and the matching Godot helpers.
Right-click a resource or data row and open **Framework Resources**:

- **Add Entry**, **Rename Entry**, **Remove Entry**, and **Edit Value** operate on
  nested dictionaries and arrays. Rename changes a dictionary key; array indices,
  resource filenames, authored IDs, and required schema fields remain stable.
- **Add Effect** collects a complete `set` or `add` effect. Effects can be edited
  or removed individually. Existing interactions must still supply every argument
  used by the action; `add` arguments must remain numeric.
- **Remove Condition from Group** appears on a condition linked beneath a group.
  It updates that parent group and preserves the condition file and other groups.
- **Clear Requirements** removes an interaction's optional group reference. The
  required action can be replaced through the existing picker, but cannot be cleared.

Condition comparisons remain numeric. Groups retain the framework's `all` operator
and contain condition references; nested Boolean groups are outside this schema.
Native vector, color, and Resource values are displayed read-only and preserved.
Adding a Dictionary or Array creates an empty collection to populate through its rows.

Prompts can be cancelled with Escape. Removing entries and clearing requirements
require confirmation. Save or revert dirty related resources before editing.
Edits reject stale tree rows, changed file hashes, changed catalogue membership,
invalid native types, and broken action argument references. Saves use a temporary
staging file, verify values and UIDs, then replace the owning file.
File deletion is available separately through library management.

The view refreshes after successful edits and saved dependency changes. Unsaved
editor text is identified as a saved-data view. Newly added resources in the standard
Behavior library or the selected resource's directory trigger refresh as well.

## Manage Behavior Library

Version 0.0.8 adds the **Manage Behavior Library…** folder icon beside Refresh in
the Framework Resources toolbar. It also appears in the Command Palette. It works
without an open resource, including parent-folder and multi-root workspaces.

The searchable menu offers five operations:

- **New Category** creates a folder directly beneath `Framework/Content/Behavior`.
- **New Subcategory** creates a folder inside an existing category.
- **New Behavior Resource** creates an Action, Condition, Condition Group, Interaction, or Automation.
- **Delete Resource** checks dependencies before offering Recycle Bin deletion.
- **Delete Empty Category** offers only empty folders and preserves the Behavior root.

Destination pickers show the project and full resource path. Resource type is
independent of its category name. Runtime startup and assignment searches discover
the entire Behavior library recursively, in sorted path order. Duplicate IDs within
the same type are rejected. A new category organizes existing schemas; it does not
introduce a new runtime Resource type.

Actions select a registered executor behavior and start with an empty effects array;
**Add Effect** is available when that behavior supports it. Condition
creation collects an actor/target address, numeric comparison, and rejection message.
Groups start with an empty condition list. Interaction creation requires an existing
valid Action, collects every required action argument, and optionally selects a
requirements group. Adding an effect later still checks its existing interaction
consumers. Registering an interaction does not grant entities permission to invoke it.

New files have a UID, tab indentation and CRLF line endings. Publishing uses exclusive
creation and verifies the saved native Resource. Existing files are never overwritten.
Assignment and comparison edits preserve the existing UID and line endings.
Escape cancels a prompt. Save or revert unsaved project Resource, scene, and script
edits before managing the library. Changed files, directories, references, workspace
trust, or executable settings require retrying the operation.

Deletion checks project file/UID dependencies, literal script paths, stored action
and interaction IDs, interaction availability lists, and input bindings. Matching
quoted IDs in scripts are treated conservatively as references. Remove consumers
before deleting a Resource; they are listed in the confirmation guidance and output.
Dynamically computed IDs cannot be inferred. Only empty categories can be deleted;
hidden files count as contents. Paths cannot escape Behavior or cross a nested
Godot project, link, or junction. Confirmed deletion uses the Recycle Bin and is
nonrecursive. No backups are created.

## Verification

From this extension folder:

```powershell
npm.cmd test
node.exe .\diagnostics\behavior_editing_bridge_check.cjs $projectPath $godotExecutable
node.exe .\diagnostics\behavior_library_bridge_check.cjs $projectPath $godotExecutable
```

The bridge diagnostic uses a unique temporary directory and verifies production
resources remain unchanged. The Godot diagnostic is
`res://Diagnostics/Authoring/behavior_editing_check.gd`.

The library diagnostic creates a unique temporary category, exercises all four
schemas through Godot, checks recursive runtime registration and deletion guards,
then removes only its own fixtures. It verifies existing Behavior Resources remain
byte-for-byte unchanged. The runtime probe is
`res://Diagnostics/Content/behavior_library_runtime_check.gd`.
`res://Diagnostics/Content/behavior_resource_identity_check.gd` verifies UID and line-ending
preservation through condition assignment, comparison edits, requirements assignment,
and action replacement.

For the library visual checkpoint, run **Developer: Reload Window**, open Framework
Resources, and click its folder icon. Create a temporary category and subcategory,
then an Action, Condition, Group, and Interaction. The new file should open in the
resource tree. Assign a condition to the group with the existing searchable command.
Deletion should list consumers until their references are removed. Delete the
unreferenced temporary files and empty folders through the same management menu.

For the visual checkpoint, reload VS Code and open
`Diagnostics/Fixtures/BehaviorEditing/visual_interaction.tres`. Expand its action's
effects and its arguments. Try adding, renaming, editing, and removing a key under
`arguments/notes`, and appending/removing an item under `notes/tags`. Required effect
fields should have no rename/remove commands. To test unlinking safely, use
**Remove Condition from Group** on `actor_strength.tres` beneath `visual_group.tres`;
only the fixture group changes. Use the existing searchable **Add Condition to Group**
command to reassign it. Opening production child resources edits those shared files,
so use the fixture's own data and action for write checks.

## Framework integration

Godot authoring helpers are loaded from Framework/Env/Authoring/Resources
inside the resolved Godot project.

## Executor behaviors (0.0.9)

Action rows display their `behavior_id`. Right-click an Action, choose
**Framework Resources → Set Executor Behavior…**, and search by behavior ID,
label, or description. Editing the nested `behavior_id` row opens the same picker.
The new Action workflow includes this selection too. Unknown IDs remain visible
with an explanatory tooltip so they can be repaired.

The picker uses the same built-in registrations and `GameSetup.register_executors()`
hook as session startup. Inspection creates an isolated runtime, runs that hook,
copies its metadata, and closes it. It never registers gameplay content, spawns
entities, loads maps, or calls `execute()`. Keep registration and `describe()` free
of gameplay side effects. Hooks that choose registrations should depend on saved
project configuration rather than transient game state.

Custom executors extend `GameplayExecutor` and override `describe()`:

```gdscript
func describe() -> Dictionary:
	return {
		"label": "Heal",
		"description": "Restore the target's health.",
		"supports_effects": false,
		"arguments": [
			{"name": "amount", "allowed_types": ["int", "float"], "required": true},
			{"name": "note", "allowed_types": ["String"], "required": false},
		],
	}
```

Register an instance through `runtime.register_executor(&"heal", HealExecutor.new())`
in `Framework/Env/Setup/game_setup.gd`'s `register_executors()` override, returning
its standard result. Each session and each restore creates fresh executor instances.
The built-in `attribute_effects` registration is already present. Behavior IDs and
Action IDs are independent; several Actions may use the same behavior.

Supported argument types are `int`, `float`, `String`, `StringName`, `bool`, `Nil`,
`Array`, and `Dictionary`. `Variant` alone allows any authorable value type. Optional
arguments may be skipped when creating an Interaction. Required arguments cannot
be renamed or removed from its data tree. Extra named arguments remain allowed.
The built-in behavior derives required arguments from each effect's `value_from`;
an `add` effect requires a finite number.

The runtime and authoring tools share the same validation contract. Behavior
changes preserve existing fields and reject unsupported effects or incompatible
Interaction consumers. Remove effects explicitly before selecting a behavior
that does not support them. Missing or mistyped arguments fail before execution.
Invalid replacements preserve the previous valid registration or saved file.

Inspections include project file hashes and directory membership. Saved changes
to executor scripts, setup, configuration, or catalogue membership invalidate
pending edits and creation drafts. Save or revert related unsaved edits first.

Run `res://Diagnostics/Authoring/executor_authoring_check.gd` for metadata, runtime/editor
validation, behavior switching, consumer protection, source-change rejection,
UID preservation, and cleanup checks. `npm.cmd test` covers the picker commands,
optional argument prompts, cancellation, dirty scripts, and menu capabilities.

After installing, run **Developer: Reload Window**. Open
`Diagnostics/Fixtures/BehaviorEditing/visual_action.tres` and verify its behavior
appears beside the Action. Open **Set Executor Behavior…**, search for
`attribute_effects`, then cancel. Use **Manage Behavior Library → New Behavior
Resource → Action** to verify the creation picker too; cancel to keep fixtures
unchanged. Additional registered behaviors appear automatically.
