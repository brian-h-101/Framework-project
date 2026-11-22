# Universal components

This library contains the Godot components attached to game scenes, their resource
schemas, and their scene helpers. Authored configuration values live in
`Content/Configuration` and shared profiles in `Content/Gameplay/Profiles/<category>/Shared`.
Category-specific gameplay executors live in `Content/Gameplay/Profiles/<category>/Executor`.
Authored movement profiles live in `Content/Gameplay/Profiles/Movement/Shared`.
Reusable movement controllers, scene body scripts, and environment implementations
live in `Content/Universal/Movement/based`. Controller settings are authored in
`Content/Gameplay/Controller`.

| Folder | Components |
| --- | --- |
| `Interaction/based/` | Scene behavior bindings, 2D input, and legacy Interaction and Automation components. |
| `Lighting/based/` | Day/night sampling, 2D lighting and shadows, and lighting configuration schemas. |
| `Map/based/` | 2D ground rendering, map configuration schemas, and 2D and 3D spatial roles and positions. |
| `Movement/based/` | Movement intent, controller rules, execution, and 2D, 3D, and Grid implementations. |
| `Presentation/based/` | The resource schema for 2D entity assembly. |
| `Targeting/based/` | 2D target markers and target resolution for 2D and 3D scenes. |
| `UI/based/` | Attribute labels, 2D anchors, and entity status widgets. |

## Control and data flow

`Env/Host/game_host.gd` starts the session, loads maps, and attaches the UI.
`Env/Map/map_coordinator.gd` binds placed nodes to persistent runtime entities and
provides context through `configure_entity`, `configure_controls`,
`configure_runtime`, and `configure_map` where supported.

Movement follows this flow.

```text
Godot input or a target observation supplies the controller with its inputs
  -> the controller produces lateral, forward and vertical intent
  -> movement_adapter.gd invokes the shared move Behavior through WorldBridge
  -> movement_executor.gd reads runtime speed and returns velocity in gameplay units
  -> the per-entity environment driver applies the result to the body or grid
```

The profile's `environment_spec` holds shared settings. Each 2D or 3D scene
component binds a fresh driver to its body and map. Grid motion advances in
whole cells and checks board bounds and authored blocked cells. The save system
records map-relative positions as `positions_2d` for 2D and Grid and
`positions_3d` for 3D.

`Interaction/based/Bindings/behavior_binding.gd` binds a Behavior resource's
registered ID to an entity through WorldBridge. The legacy
`Interaction/based/Legacy/interaction_input.gd` resolves a target and invokes the
attached Interaction through its `interaction_behavior.gd` component.

Lighting reads session time from GameRuntime and applies the configured ambient
colors, sun energy and rotation, point lights, and shared shadows. UI components
in `Content/Universal/UI/based` listen to runtime attribute notifications and
track entity anchors. HUD scenes are authored in `Content/Gameplay/UI/HUD`.

## Framework responsibilities

`Env/` coordinates session lifecycle, persistence, map binding, content discovery
and composition, and authoring. `MapCoordinator` uses `Env/Map/map_positions.gd`
to select the 2D or 3D position handler in `Content/Universal/Map/based`.
The same library contains the 2D ground renderer and map configuration schemas.
`SessionDriver` registers the WorldBridge targeting callback and selects a 2D or
3D resolver from `Content/Universal/Targeting/based` for the active map.

The 2D entity assembler loads its optional presentation preset through the schema
in `Content/Universal/Presentation/based/Configuration`.

Scene scripts are selected through Framework Scenes. A node's native type must
support the chosen script's base class; for example, the movement component extends
`CharacterBody2D`. Gameplay executor scripts extend the executor contract and are
selected through Behavior resources.
