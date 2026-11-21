# Automation resources

An Interaction is an available capability. An Automation is an explicit request
to evaluate an Interaction for a particular entity on a schedule. Registering a
Resource does not activate it or grant its Interaction permission.

## Authoring

In Framework Resources, use Manage Behavior Library to create an Automation.
Choose its Interaction and set `interval_seconds` and `cooldown_seconds`. Open
the Resource to edit these values or use Set Automation Interaction to replace
its reference. Version one supports `interval` triggers and `nearest` targeting.

In Framework Scenes, open an entity's structure source scene and choose Attach
Behavior Resource. Selecting an Automation adds a plain Node with
`Content/God/Interaction/automation_behavior.gd` and its `content` reference.
The component's exported `enabled` flag supplies the initial activation state.
Removing a scene component uses the existing Remove Node command.

## Runtime flow

```text
GameEntry -> GameSetup registers executors, Actions, Interactions, Automations
MapCoordinator binds entities -> automation_behavior.configure_entity()
WorldBridge.bind_automation() -> RuntimeCore -> AutomationSystem
SessionDriver._process(delta) -> GameRuntime.advance_automations(delta, resolver)
TargetResolver finds the nearest bound, marked entity -> runtime.interact()
Interaction permission and requirements -> Action -> registered Executor
```

Gameplay code can call `bind_automation`, `set_automation_enabled`,
`automation_bindings`, and `unbind_automation` through GameRuntime. Rebinding
preserves the current enabled state and timers. Removing a scene component
does not erase persistent activation; use `unbind_automation` to remove that
session state, or `set_automation_enabled` to pause it.

Timers use elapsed running-session seconds, independent of the day/night clock.
The first check waits for the interval. Success starts the cooldown; failed
requirements retry after the interval. Each evaluation step attempts at most
once per enabled binding in entity-ID/Automation-ID order. Disabled timers freeze.
Unrepresented entities skip execution, and missed intervals do not replay.

Session snapshots save activations under stable entity keys, including enabled
state and both remaining durations. Restoration validates the complete batch
before replacing activations, owns its dictionaries, and clamps remaining times
to current authored durations. Old saves without an `automations` field remain
valid. Definitions and executable code are registered again, not serialized.

## Checks

- `Diagnostics/Runtime/automation_runtime_check.gd`: registration, permissions,
  timing, activation lifecycle, codec round trip, and restoration failures.
- `Diagnostics/Gameplay/automation_session_check.gd`: real session scheduling,
  nearest targeting, map reload, and host save/restore.
- `Tools/VSCode/resource-condition-extension/diagnostics/automation_bridge_check.cjs`:
  real resource creation/editing, scene attachment, duplicate guards and consumers.
- `Diagnostics/Gameplay/automation_visual_check.gd`: fresh playable preview using
  the city layout; it does not load or write the normal save slot.
