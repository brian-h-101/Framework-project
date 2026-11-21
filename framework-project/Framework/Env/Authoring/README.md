# Godot authoring helpers

```text
Authoring/
    Attributes/
        attribute_values.gd
        attribute_inspection.gd
        attribute_editing.gd
        attribute_cli.gd
        attribute_library.gd
        attribute_library_cli.gd
    Resources/
        behavior_schema.gd
        behavior_library.gd
        behavior_library_authoring.gd
        behavior_library_cli.gd
        behavior_inspection.gd
        behavior_editing.gd
        behavior_editing_cli.gd
        condition_assignment.gd
        condition_assignment_cli.gd
        condition_editing.gd
        condition_editing_cli.gd
        resource_catalog_export.gd
        resource_graph_export.gd
    Shared/
        resource_values.gd
        value_tree.gd
        collection_editing.gd
        resource_files.gd
        resource_library_files.gd
    Scenes/
        entity_scene_authoring.gd
        map_scene_authoring.gd
        scene_graph.gd
        scene_graph_export.gd
        scene_document.gd
        scene_references.gd
        scene_editing.gd
        scene_editing_cli.gd
        scene_library.gd
        scene_library_cli.gd
        scene_templates.gd
```

`Attributes` inspects and edits container fragment `.tres` files for the Resource
Attribute extension. It preserves typed keys and values, verifies staged saves,
and rejects requests whose source file hash has changed.
The library helper discovers folders and supported resources beneath Authored,
drafts validated container files with UIDs, and builds dependency snapshots before
deletion. Resource Attribute 0.0.3 publishes new files exclusively and requests
Recycle Bin deletion through VS Code. `Env/Setup/authored_library.gd` supplies the
same authored-root policy to starting-attribute composition and the library helper.
New top-level categories require no new hardcoded library registration.

`Resources/behavior_library_authoring.gd` provides the corresponding Behavior library
catalogue, validated drafts for all four gameplay Resource schemas, and reference
inspection for deletion. `behavior_library_cli.gd` exposes `catalogue`, `draft`, and
`deletion-preview` operations with the `[behavior-library]` result prefix. Creation
requires a current catalogue snapshot; interaction drafts require a valid Action
and all of its arguments. Deletion also detects stored authored-ID references in
interaction availability, input bindings, and scripts. The VS Code extension publishes
new files exclusively and performs confirmed, nonrecursive Recycle Bin deletion.

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
draft verification, and project dependency snapshots. `Env/Setup/library_path_policy.gd`
supplies shared project/name rules and resource-aware recursive listing; the Authored
and Behavior policy wrappers retain separate write boundaries.

`Scenes` handles saved `.tscn` hierarchy inspection, presentation assembly and
placement, and map creation. The Framework Scenes extension uses the scene graph
exporter. Presentation assembly reads `starting_attributes.tres` and `presentation.tres`.
Game maps are stored in `Framework/Content/Maps`. The persistence configuration's
`map_path_redirects` retains compatibility with saves made before a map relocation;
subsequent saves capture the loaded scene's current path.
Structural scene editing uses a syntax-aware document writer, ownership metadata,
dependency hashes, and staged validation. It preserves shared scene boundaries and
does not instantiate gameplay nodes. Framework Scenes 0.0.3 uses graph protocol v2.

Run CLI entry points from the Godot project folder with a Godot console executable:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Resources/resource_graph_export.gd -- res://Framework/Content/Behavior/Interaction/strike.tres

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Scenes/scene_graph_export.gd -- res://Framework/Content/Maps/city_recreated.tscn

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Scenes/entity_scene_authoring.gd -- catalogue

& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Framework/Env/Authoring/Attributes/attribute_cli.gd -- inspect res://Framework/Content/Authored/Entity/Attributes/Needs/needs.tres
```

The CLI argument formats and result prefixes are preserved. Inspection reads saved
data. Assignment and assembly helpers write only when their write commands are invoked.

The extension bridges use these categorized paths. Resource Condition Extension
uses version 0.0.5 or newer for resource graph v2. The current scene graph protocol requires Framework
Scenes 0.0.3 or newer.

Framework Scenes 0.0.5 adds scene library authoring beneath Content/Maps,
Content/Presentation, and Content/UI/HUD. `scene_library_cli.gd` provides `catalogue`,
`draft`, and `deletion-preview` with the `[scene-library]` result prefix. Templates
pack new detached native nodes; validation reads SceneState without entering the
scene tree. The extension publishes new UID-bearing `.tscn` files exclusively and
requests confirmed, nonrecursive Recycle Bin deletion after checking references.
The shared library helper accepts a file checker and extension so the Resource
library entry points retain their existing `.tres` defaults. Dependency scans also
detect literal scene paths stored inside configuration Resources and scripts.

Executor metadata and authoring use Resources/executor_catalog.gd. It creates an
isolated GameRuntime, runs the same GameSetup.register_executors() hook as session
startup, copies the validated executor descriptions, and closes the runtime. It
does not register content, create entities, attach scenes, or execute behaviors.
The runtime registry owns frozen descriptions; caller edits cannot change them.

GameplayExecutor.describe() supplies a label, description, supports_effects flag,
and typed required/optional argument specifications. The shared executor_contract.gd
validates Action fields and Interaction arguments both during runtime registration
and authoring. Action replacement checks existing consumers before mutation.
The built-in attribute_effects behavior derives arguments from its effects.

Resource graph v2 and the Behavior library catalogue include registered executors
and a source snapshot. Resource Condition 0.0.9 uses this for searchable behavior
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
