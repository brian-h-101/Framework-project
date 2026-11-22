# Resource Attribute

`framework-tools.resource-attribute` adds a dedicated **Framework Attributes**
container with **Authored Library** and **Attribute Details** views. Browse actual
categories and `.tres` files, then open a saved container fragment to edit its
dictionaries, arrays and native value types. It uses the existing
`container_fragment_resource.gd` schema.

## Library authoring

In **Attribute Details**, click the **Manage Authored Library…** folder icon
between **Find an Attribute Resource…** and **Refresh Attributes**. The same
command is available from the Command Palette under **Resource Attribute**.

Choose an operation, then choose a destination from the searchable picker. Project
names and full relative paths distinguish entries across workspaces. The active
file's closest Godot project and its parent folder are offered first. This works
when the Authored Library tree is hidden and when no resource is open.

The toolbar offers **New Category…**, **New Subcategory…**, **New Attribute
Resource…**, **Delete Resource…**, and **Delete Empty Category…**. Delete lists
include supported container files or empty categories; the existing commands
still recheck names, references, dirty editors, and filesystem state before writing.
Escape at either picker cancels without creating or deleting anything.

Authored Library discovers Framework Godot projects in the opened workspace,
including projects beneath a parent folder and multiple workspace roots. Each
project has its own `Framework/Content/Gameplay/Authored` root. Empty categories are shown.
Opening a Resource is not required to discover the library.

Right-click a library entry and open **Authored Library**:

- **New Category…** creates a directory directly beneath Authored.
- **New Subcategory…** creates a directory beneath the selected folder.
- **New Attribute Resource…** creates a `.tres` after prompting for the filename
  and initial container name, then opens it in Attribute Details.
- **Delete Resource…** checks dependencies, requests confirmation, and sends an
  unreferenced container fragment to the Recycle Bin.
- **Delete Empty Category…** sends an empty category to the Recycle Bin.

Categories are ordinary folders, with no catalogue scripts or category registry.
Any category beneath Authored can supply starting fragments, including new names
such as `Vehicles/Statistics`. The runtime and authoring helper share the root
policy in `Framework/Env/Setup/Library/authored_library.gd`. Creating a resource makes it
available for explicit selection; it does not assign it to a starting profile or
change existing saved entity state.

New resources contain one empty StringName container. Godot creates and verifies
the schema and UID; an exclusive file write prevents overwriting existing files.
Sibling names are checked case-insensitively. Windows reserved names, traversal,
symbolic links, junctions and nested Godot projects are rejected. The authored
root itself cannot be deleted. Category deletion is nonrecursive and requires
the folder to be empty, including hidden or unsupported files.

Deletion indexes saved `.tres`, `.tscn`, `.res` and `.scn` dependencies, including
UID links. It also checks full and relative literal references in Godot scripts,
project settings and shader text. It reports consumers and provides no forced
deletion command. Dynamically constructed runtime paths are not fully discoverable;
remove those uses before deleting their resource. Scanning excludes `.git`,
`.godot`, `node_modules`, `out`, and separate nested Godot projects.

Save or revert dirty Resource, scene and Godot script editors before deletion.
Project file hashes and directory membership are checked again after confirmation.
Changed consumers, missing files or unreadable/linked dependencies reject deletion.
The extension requests the Recycle Bin and does not retry with permanent deletion.
Saved filesystem changes refresh the library; deleting the selected resource clears
Attribute Details. Creation, deletion and attribute editing share one operation gate.

## Editing

Right-click an entry and open **Framework Attributes**:

- **Edit Value…** edits a scalar, with an explicit native type selection.
- **Add Entry…** creates a named dictionary entry or appends an array item.
- **Rename Entry…** renames a dictionary key while retaining its value.
- **Remove Entry…** removes an entry and its contents after confirmation.
- **Open Resource** opens the underlying `.tres` text.

Use **Add Entry…** on the resource root to add an empty container. Container names
are nonempty String or StringName keys; container contents are dictionaries. Add
empty dictionaries and arrays, then expand them to add nested values. Array
indices are positional, so removing an item shifts later indices.

Supported editable values are int, float, String, StringName, bool and null (Nil).
Native values such as Vector2, Color and resource references are shown read-only;
they are retained when sibling entries change. Integer values and integer keys
travel as text, preserving Godot's signed 64-bit range. Typed collections retain
their constraints. Duplicate keys are rejected, including String/StringName keys
that Godot considers equal.

This edits shared authored defaults. Starting-profile overrides may supersede those
defaults. Existing saved entity state remains separate. Configuration Resources and
`starting_attributes.tres` use different schemas and are not edited by this version.

## Workspace and Godot

Open the project folder, its parent folder, or a multi-folder workspace containing
the project. The extension finds the nearest `project.godot` for the selected file.
Set **Resource Attribute: Godot Executable** to the full Godot console executable
path, or use the existing `godotTools.editorPath.godot4` setting. Godot 4.7.1 and
VS Code 1.146 or newer match this project's toolchain. Workspace trust is required
because inspection and editing run the project's Godot scripts.

Attribute Details follows opened `.tres` files. **Find an Attribute Resource…** searches
Authored resource names and paths. Save text edits to refresh the tree. Commands
reject dirty text buffers, stale tree selections and changed files. Writes are
validated in a temporary staging file before replacing the selected file, retaining
its UID, native values, references and line-ending convention. Staging files are
removed; no backup copies are created.

## Build and diagnostics

From this extension folder:

```powershell
npm.cmd ci
npm.cmd test
npm.cmd run package:vsix
```

From the Godot project folder:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Authoring/attribute_authoring_check.gd
```

Run the real bridge check from this extension folder:

```powershell
$attributeProject = (Resolve-Path -LiteralPath '..\..\..\framework-project').Path
$attributeGodot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
node.exe .\diagnostics\attribute_bridge_check.cjs $attributeProject $attributeGodot
node.exe .\diagnostics\attribute_library_bridge_check.cjs $attributeProject $attributeGodot
```

The VSIX includes compiled extension code. The Godot helpers must remain available
under `Framework/Env/Authoring/Attributes` in the project being edited.
Version 0.0.3 adds `attribute_library_cli.gd` and the shared authored-root policy.
Version 0.0.4 adds the toolbar management workflow using those same helpers.
The library bridge diagnostic creates a unique temporary authored category, verifies
runtime composition and dependency protection, and cleans its own fixtures. Existing
authored resources must remain byte-for-byte unchanged.

## Visual checkpoint

Install the packaged VSIX, run **Developer: Reload Window**, and open
`Content/Gameplay/Authored/Entity/Attributes/Needs/needs.tres`. Expand `needs → hunger` and
verify the values and types. Open `Diagnostics/Fixtures/Attributes/visual_check.tres`
to exercise edit, add, rename, remove and Escape cancellation. This fixture is
separate from gameplay content. Verify the saved text and refreshed tree
agree, and that switching files follows the selected Resource. Repeat with the
outer repository opened as the workspace root.

For the library checkpoint, expand **Authored Library**, create a temporary top-level
category and a subcategory, then create `durability.tres` with container `durability`.
Use the existing data editor to add a value, save, and verify the tree refreshes.
Try creating the same sibling name with different capitalization; it should be
rejected. Confirm that cancelling creation or deletion leaves files untouched.
Attempting to delete Player's referenced `precognition.tres` should show its
consumers and preserve it. Delete only the temporary unreferenced resource, then
its empty subcategory and category. Confirm the Recycle Bin operation clears the
selected details. Repeat browsing with the outer repository as workspace root.

For the toolbar checkpoint, reload VS Code and open **Attribute Details**. Confirm
the folder icon appears between Search and Refresh and its tooltip is **Manage
Authored Library…**. Hide the Authored Library tree, then use the folder icon to
create a temporary category, subcategory, and Resource. Cancel an operation at each
picker and verify no files change. Use the menu to delete the temporary Resource
and its empty categories, confirming the normal reference checks and Recycle Bin
dialogs appear. In a workspace with multiple projects, verify the destination list
identifies the project before selecting an entry.
