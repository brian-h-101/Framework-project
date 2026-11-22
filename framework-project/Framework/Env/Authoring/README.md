# Godot authoring helpers

```text
Authoring/
    Attributes/
        attribute_cli.gd
        attribute_editing.gd
        attribute_inspection.gd
        attribute_library.gd
        attribute_library_cli.gd
        attribute_values.gd
    Resources/
        Behavior/
            behavior_schema.gd
            behavior_editing.gd
            behavior_editing_cli.gd
            sequence_authoring.gd
        Conditions/
            condition_assignment.gd
            condition_assignment_cli.gd
            condition_editing.gd
            condition_editing_cli.gd
        Inspection/
            behavior_inspection.gd
            resource_catalog_export.gd
            resource_graph_export.gd
            resource_browse_worker.gd
            executor_catalog.gd
        Library/
            behavior_library.gd
            behavior_library_authoring.gd
            behavior_library_cli.gd
            behavior_renaming.gd
    Shared/
        collection_editing.gd
        resource_files.gd
        resource_library_files.gd
        resource_values.gd
        value_tree.gd
    Scenes/
        Creation/
            entity_scene_authoring.gd
            map_scene_authoring.gd
            scene_templates.gd
        Editing/
            scene_document.gd
            scene_references.gd
            scene_script.gd
            scene_editing.gd
            scene_editing_cli.gd
        Inspection/
            scene_graph.gd
            scene_graph_export.gd
        Configuration/
            movement_configuration_catalog.gd
            movement_configuration_catalog_export.gd
        Library/
            scene_library.gd
            scene_library_cli.gd
```

Resources are grouped into Behavior (schema and step editing), Conditions
(assignments and comparisons), Inspection (graphs and catalogues), and Library
(discovery, drafts, deletion and file renaming).

Scenes are grouped into Creation (assembly and templates), Editing (document,
reference, script and structural operations), Inspection (saved hierarchies),
Configuration (movement configuration catalogues), and Library (scene file management).
CLI scripts stay beside the implementation they invoke.

`Attributes` inspects and edits container fragment `.tres` files for the Resource
Attribute extension. It preserves typed keys and values, verifies staged saves,
and rejects requests whose source file hash has changed.
The library helper discovers folders and supported resources beneath Authored,
drafts validated container files with UIDs, and builds dependency snapshots before
deletion. Resource Attribute 0.0.3 publishes new files exclusively and requests
Recycle Bin deletion through VS Code. `Env/Setup/Library/authored_library.gd` supplies the
same authored-root policy to starting-attribute composition and the library helper.
New top-level categories require no new hardcoded library registration.

`Resources/Library/behavior_library_authoring.gd` provides the corresponding Behavior library
catalogue, validated drafts for all six gameplay Resource schemas, and reference
inspection for deletion. `behavior_library_cli.gd` exposes `catalogue`, `draft`,
`deletion-preview`, `rename-preview`, and `rename` with the `[behavior-library]`
result prefix. Creation
requires a current catalogue snapshot; interaction drafts require a valid Action
and all of its arguments. Deletion also detects stored authored-ID references in
interaction availability, input bindings, and scripts. The VS Code extension publishes
new files exclusively and performs confirmed, nonrecursive Recycle Bin deletion.

`Resources/Library/behavior_renaming.gd` plans literal-reference changes from a project
snapshot, preserves authored IDs/UIDs, stages reference updates and validates the
renamed Resource and consumers. It rejects stale plans, collisions, UID-only and
binary consumers, and known composed paths. Filename labels and comments are
preserved. Reference creation/replacement uses `behavior_editing.gd`'s typed
`set_reference` operation; optional unlinking preserves the referenced file.

`Resources` handles `.tres` inspection, catalogue discovery, assignments, condition
comparison editing, and structural behavior editing. Graph protocol v2 includes
typed data paths, relationship roles/indices, and dependency hashes. Structural
editing protects required schema fields and checks action consumers before saving.
Unlinking edits a parent Resource reference and preserves shared child files.
Runtime definitions and assignment catalogues scan the whole Behavior root recursively
and use Resource types rather than directory names. Gameplay permissions remain authored.

`Shared` supplies native value parsing, typed collection operations, value-tree
inspection, and staged Resource file handling. `Attributes` retains its public
entry points while using these shared helpers.
Both library adapters use `Shared/resource_library_files.gd` for directory fingerprints,
draft verification, and project dependency snapshots. `Env/Setup/Library/library_path_policy.gd`
supplies shared project/name rules and resource-aware recursive listing; the Authored
and Behavior policy wrappers retain separate write boundaries.

`Scenes` handles saved `.tscn` hierarchy inspection, presentation assembly and
placement, and map creation. The Framework Scenes extension uses the scene graph
exporter. Presentation assembly reads `starting_attributes.tres` and `presentation.tres`.
Game maps are stored in `Framework/Content/Gameplay/Maps`. The persistence configuration's
`map_path_redirects` retains compatibility with saves made before a map relocation;
subsequent saves capture the loaded scene's current path.
Structural scene editing uses a syntax-aware document writer, ownership metadata,
dependency hashes, and staged validation. It preserves shared scene boundaries and
does not instantiate gameplay nodes. Framework Scenes 0.0.3 uses graph protocol v2.

Run CLI entry points from the Godot project folder with a Godot console executable:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Resources/Inspection/resource_graph_export.gd -- res://Framework/Content/Gameplay/Profiles/Movement/Behavior/move.tres

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Scenes/Inspection/scene_graph_export.gd -- res://Framework/Content/Gameplay/Maps/city.tscn

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Scenes/Creation/entity_scene_authoring.gd -- catalogue

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Attributes/attribute_cli.gd -- inspect res://Framework/Content/Gameplay/Authored/Entity/Attributes/Needs/needs.tres
```

The CLI argument formats and result prefixes are preserved. Inspection reads saved
data. Assignment and assembly helpers write only when their write commands are invoked.

Behavior library authoring in profile folders requires Framework Resources
0.0.26 or newer. Both graph protocols remain at version 2.

Framework Scenes 0.0.5 adds scene library authoring beneath Content/Gameplay/Maps,
Content/Gameplay/Presentation, and Content/Gameplay/UI/HUD. `scene_library_cli.gd` provides `catalogue`,
`draft`, and `deletion-preview` with the `[scene-library]` result prefix. Templates
pack new detached native nodes; validation reads SceneState without entering the
scene tree. The extension publishes new UID-bearing `.tscn` files exclusively and
requests confirmed, nonrecursive Recycle Bin deletion after checking references.
The shared library helper accepts a file checker and extension so the Resource
library entry points retain their existing `.tres` defaults. Dependency scans also
detect literal scene paths stored inside configuration Resources and scripts.

Executor metadata and authoring use Resources/Inspection/executor_catalog.gd. It creates an
isolated GameRuntime, runs the same GameSetup.register_executors() hook as session
startup, copies the validated executor descriptions, and closes the runtime. It
does not register content, create entities, attach scenes, or execute behaviors.
The runtime registry owns frozen descriptions; caller edits cannot change them.

GameplayExecutor.describe() supplies a label, description, supports_effects flag,
and typed required/optional argument specifications. The shared executor_contract.gd
validates Action fields and Interaction arguments both during runtime registration
and authoring. Action replacement checks existing consumers before mutation.
The built-in attribute_effects behavior derives arguments from its effects.

Full Resource graph v2 inspections and the Behavior library catalogue include
registered executors and a source snapshot. Resource Condition 0.0.9 uses this for searchable behavior
selection, typed prompts, and stale-edit rejection. Source snapshots cover project
script/configuration/resource hashes and directory membership while excluding
Godot caches and nested projects. Schema inspection can show an unknown behavior
for repair; saving or startup requires a registered behavior. See the extension
README for the custom registration example and visual checkpoint.

Diagnostics/Authoring/executor_authoring_check.gd verifies metadata isolation, required and
optional arguments, runtime/editor agreement, consumer protection, safe behavior
changes, stale scripts and new files, preserved UIDs, and fixture cleanup. Run it
sequentially with other authoring diagnostics because they inspect project-wide
snapshots. No backups are made.

Resource Condition 0.0.16 uses Inspection.browse() for selection. This read-only
mode hashes only the selected Resource dependency graph and returns mode: browse,
an empty catalogue list and no executor snapshot. resource_graph_export.gd accepts
-- browse <res://path.tres> for one-shot inspection. resource_browse_worker.gd serves
the same operation over stdin/stdout, reusing executor descriptions until the
extension restarts it after saved source changes or idle expiry. Requests use a
4-byte little-endian UTF-8 payload length followed by JSON (maximum 64 KiB); each
response is a [resource-browse] JSON line with protocol 1 and its request ID.

Full graph() inspection remains separate. The extension upgrades a displayed
browsing graph before structural edits and checks its dependency hashes, nodes and
executor metadata against the fresh full inspection. Existing snapshot checks in
executor_catalog.unchanged() continue to reject stale writes; browsing metadata
cannot authorize them. No gameplay session is started by either inspection mode.
