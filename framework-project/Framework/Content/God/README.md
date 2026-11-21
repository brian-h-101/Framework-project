# Godot components

This library contains the authored Godot components attached to game scenes and
their rendering helpers. Configuration values stay in `Content/Configuration`;
gameplay calculations and mutations stay in `Content/Executor`.

| Folder | Components |
| --- | --- |
| `Interaction/` | Configured interaction input, scene-attached Interaction invocation, and persistent Automation activation. |
| `Lighting/` | Ambient lighting, point lights, sun presentation, and polygon occluders. |
| `Lighting/Shadows/` | Shared shadow rendering, SDF debugging, and shadow shaders. |
| `Map/` | Configured temporary tile-ground generation. |
| `Movement/` | Configured input, Action invocation, pixel conversion, and character physics. |
| `UI/` | Attribute labels, entity-following status widgets, and their persistent status layer. |

## Control and data flow

`Env/Host/game_host.gd` starts the session, loads maps, and attaches the UI.
`Env/Map/map_coordinator.gd` binds placed nodes to persistent runtime entities and
provides context through `configure_entity`, `configure_controls`,
`configure_runtime`, and `configure_map` where supported.

For movement:

```text
God/Movement/movement_2d.gd reads configured input
  -> WorldBridge executes the configured Action
  -> Content/Executor/movement_2d_executor.gd reads runtime speed and calculates velocity
  -> the component applies pixel scaling and move_and_slide()
```

For interactions, `God/Interaction/interaction_input.gd` resolves a target and finds
the attached `interaction_behavior.gd` component. That component invokes the
Interaction resource's registered ID through WorldBridge.

Lighting reads session time from GameRuntime and applies the configured ambient
colors, sun energy and rotation, point lights, and shared shadows. UI components
listen to runtime attribute notifications and track the framework's discovered
entity anchors.

## Framework responsibilities

`Env/` retains session lifecycle, persistence coordination, map binding and position
restoration, resource schemas, content discovery/composition, marker discovery,
target resolution, and authoring tools. The component configuration hooks are
unchanged by this relocation.

Scene scripts are selected through Framework Scenes. A node's native type must
support the chosen script's base class; for example, the movement component extends
`CharacterBody2D`. Gameplay executor scripts extend the executor contract and are
selected through Behavior resources.
