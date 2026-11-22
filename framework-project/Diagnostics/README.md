# Diagnostics

Runnable Godot checks are grouped by the subsystem they verify. Run these scripts
from the `framework-project` directory using the Godot console executable.

| Category | Checks | Purpose |
| --- | ---: | --- |
| [Authoring](Authoring/) | 15 | Resource assignment/editing/renaming, executor authoring, and scene inspection/editing. |
| [Configuration](Configuration/) | 2 | Configuration and presentation profile resources. |
| [Content](Content/) | 20 | Content discovery, authored libraries, resource conversion, and fragment composition. |
| [Entity](Entity/) | 5 | Container/attribute insertion, entity snapshots/restoration, and node bindings. |
| [Executor](Executor/) | 6 | Executor registry, discovery, startup, and behavior execution. |
| [Gameplay](Gameplay/) | 9 | Actions, interactions, requirements, attached behaviors, and an Automation visual preview. |
| [Input](Input/) | 3 | Input bindings and interaction target discovery/selection. |
| [Map](Map/) | 6 | Map lifecycle, entity placement, spatial roots, and map-relative positions. |
| [Persistence](Persistence/) | 8 | Session snapshots/restoration, codecs, save files, and host persistence. |
| [Runtime](Runtime/) | 6 | Session startup, lifecycle, clocks, and Automation evaluation/persistence. |
| [UI](UI/) | 1 | Entity UI-anchor discovery. |

## Running a check

For example, check the scene script authoring workflow:

```powershell
& Godot_v4.7.1-stable_win64_console.exe `
    --headless `
    --path . `
    --script res://Diagnostics/Authoring/scene_script_attachment_check.gd
```

Add `--check-only` to validate syntax without running the diagnostic. For map and
session integration checks, use the same command with the corresponding path below.

`Content/behavior_library_runtime_check.gd` is a bridge helper that requires an
interaction ID (or `expect-duplicate`) after `--`. Its temporary content is prepared
by `Tools/VSCode/resource-condition-extension/diagnostics/behavior_library_bridge_check.cjs`.
`Content/authored_library_check.gd` also accepts an optional fragment resource path;
the attribute-library bridge supplies that argument when testing generated content.

## Fixtures

`Fixtures/` contains supporting data and scripts rather than standalone checks:

- `Baselines/`: captured entity defaults used for composition comparisons.
- `Setup/`: custom startup, failure, executor, and restoration setups.
- `Helpers/`: shared access to baseline starting attributes.
- Other fixture folders group authored resources, scene examples, and intentional failures by test scenario.

Script `.uid` companions stay beside the scripts they identify. Their UID values
are preserved when files move.

## Check index

### Authoring

- [action_assignment_check.gd](Authoring/action_assignment_check.gd)
- [attribute_authoring_check.gd](Authoring/attribute_authoring_check.gd)
- [behavior_editing_check.gd](Authoring/behavior_editing_check.gd)
- [behavior_sequence_editing_check.gd](Authoring/behavior_sequence_editing_check.gd)
- [behavior_sequence_attachment_check.gd](Authoring/behavior_sequence_attachment_check.gd)
- [condition_assignment_check.gd](Authoring/condition_assignment_check.gd)
- [condition_editing_check.gd](Authoring/condition_editing_check.gd)
- [condition_editing_cli_check.gd](Authoring/condition_editing_cli_check.gd)
- [executor_authoring_check.gd](Authoring/executor_authoring_check.gd)
- [movement_configuration_assignment_check.gd](Authoring/movement_configuration_assignment_check.gd)
- [requirements_assignment_check.gd](Authoring/requirements_assignment_check.gd)
- [resource_renaming_check.gd](Authoring/resource_renaming_check.gd)
- [scene_editing_check.gd](Authoring/scene_editing_check.gd)
- [scene_graph_check.gd](Authoring/scene_graph_check.gd)
- [scene_script_attachment_check.gd](Authoring/scene_script_attachment_check.gd)

### Configuration

- [configuration_resource_check.gd](Configuration/configuration_resource_check.gd)
- [profile_resource_check.gd](Configuration/profile_resource_check.gd)

### Content

- [action_resource_check.gd](Content/action_resource_check.gd)
- [authored_library_check.gd](Content/authored_library_check.gd)
- [authored_library_composition_check.gd](Content/authored_library_composition_check.gd)
- [automation_discovery_check.gd](Content/automation_discovery_check.gd)
- [automation_resource_check.gd](Content/automation_resource_check.gd)
- [behavior_library_runtime_check.gd](Content/behavior_library_runtime_check.gd)
- [behavior_resource_identity_check.gd](Content/behavior_resource_identity_check.gd)
- [body_part_composition_check.gd](Content/body_part_composition_check.gd)
- [condition_group_resource_check.gd](Content/condition_group_resource_check.gd)
- [condition_resource_check.gd](Content/condition_resource_check.gd)
- [container_composition_check.gd](Content/container_composition_check.gd)
- [container_fragment_resource_check.gd](Content/container_fragment_resource_check.gd)
- [content_discovery_check.gd](Content/content_discovery_check.gd)
- [fragment_composition_check.gd](Content/fragment_composition_check.gd)
- [interaction_resource_check.gd](Content/interaction_resource_check.gd)
- [narrative_composition_check.gd](Content/narrative_composition_check.gd)
- [resource_definition_discovery_check.gd](Content/resource_definition_discovery_check.gd)
- [starting_attributes_check.gd](Content/starting_attributes_check.gd)
- [state_composition_check.gd](Content/state_composition_check.gd)
- [status_effects_composition_check.gd](Content/status_effects_composition_check.gd)

### Entity

- [attribute_insertion_check.gd](Entity/attribute_insertion_check.gd)
- [container_insertion_check.gd](Entity/container_insertion_check.gd)
- [entity_restore_check.gd](Entity/entity_restore_check.gd)
- [entity_snapshot_check.gd](Entity/entity_snapshot_check.gd)
- [world_bridge_binding_check.gd](Entity/world_bridge_binding_check.gd)

### Executor

- [attribute_effects_executor_check.gd](Executor/attribute_effects_executor_check.gd)
- [executor_content_check.gd](Executor/executor_content_check.gd)
- [executor_discovery_check.gd](Executor/executor_discovery_check.gd)
- [executor_registry_check.gd](Executor/executor_registry_check.gd)
- [executor_startup_check.gd](Executor/executor_startup_check.gd)
- [movement_executor_check.gd](Executor/movement_executor_check.gd)

### Gameplay

- [automation_session_check.gd](Gameplay/automation_session_check.gd)
- [automation_visual_check.gd](Gameplay/automation_visual_check.gd) — interactive preview, starts fresh without the normal save slot.
- [condition_editing_runtime_check.gd](Gameplay/condition_editing_runtime_check.gd)
- [direct_action_check.gd](Gameplay/direct_action_check.gd)
- [entity_behavior_attachment_check.gd](Gameplay/entity_behavior_attachment_check.gd)
- [interaction_behavior_check.gd](Gameplay/interaction_behavior_check.gd)
- [world_bridge_action_check.gd](Gameplay/world_bridge_action_check.gd)

### Input

- [input_configuration_check.gd](Input/input_configuration_check.gd)
- [nearest_target_check.gd](Input/nearest_target_check.gd)
- [target_point_discovery_check.gd](Input/target_point_discovery_check.gd)

### Map

- [item_object_placement_check.gd](Map/item_object_placement_check.gd)
- [map_lifecycle_check.gd](Map/map_lifecycle_check.gd)
- [map_position_capture_check.gd](Map/map_position_capture_check.gd)
- [map_position_snapshot_check.gd](Map/map_position_snapshot_check.gd)
- [placed_entity_lifecycle_check.gd](Map/placed_entity_lifecycle_check.gd)
- [spatial_root_discovery_check.gd](Map/spatial_root_discovery_check.gd)

### Persistence

- [host_session_persistence_check.gd](Persistence/host_session_persistence_check.gd)
- [session_codec_check.gd](Persistence/session_codec_check.gd)
- [session_codec_failure_check.gd](Persistence/session_codec_failure_check.gd)
- [session_restore_check.gd](Persistence/session_restore_check.gd)
- [session_restore_failure_check.gd](Persistence/session_restore_failure_check.gd)
- [session_snapshot_check.gd](Persistence/session_snapshot_check.gd)
- [session_store_check.gd](Persistence/session_store_check.gd)
- [session_store_failure_check.gd](Persistence/session_store_failure_check.gd)

### Runtime

- [automation_runtime_check.gd](Runtime/automation_runtime_check.gd)
- [content_startup_failure_check.gd](Runtime/content_startup_failure_check.gd)
- [runtime_clock_check.gd](Runtime/runtime_clock_check.gd)
- [session_clock_check.gd](Runtime/session_clock_check.gd)
- [session_driver_check.gd](Runtime/session_driver_check.gd)

### UI

- [ui_anchor_discovery_check.gd](UI/ui_anchor_discovery_check.gd)

Unified Behavior runtime, host and interactive checks are documented in
[Behavior authoring](../Framework/Content/Gameplay/Profiles/README.md). The visual preview
starts fresh and disables saving to protect normal save slots.
