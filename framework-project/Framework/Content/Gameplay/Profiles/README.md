# Unified Behaviors

The demo Resource files and Content scenes described below have been intentionally
removed. These are conceptual examples; see [Content authoring](../README.md) for
the cleared startup state and rebuilding workflow.

Create **Behavior (Configuration + Steps)** with the Framework Resources library
folder button. Choose a destination under `Profiles/<category>/Behavior`. For
example, Player and Enemy both reference `Movement/Behavior/move.tres`. Startup
scans each category’s `Behavior` folder recursively and requires unique Behavior
IDs across all categories.

## Authoring flow

1. Open the Behavior `.tres` file in Explorer. Framework Resources displays that file.
2. Expand Configuration. Right-click a field, expand Framework Resources' menu,
   then choose **Edit Configuration**. Triggers are `manual`, `event`, or `interval`.
   `event_id = on_attack` identifies the event Space emits. Interval is used only
   for an interval trigger; cooldown is shared by every invocation of this Behavior
   on the same entity. Durations use session seconds.
3. Right-click **Steps [SEQUENCE]** to add an Action or Group. Give every step a
   unique stable ID. Display labels may change without changing IDs. Groups own
   their own ordered Steps. Move Up/Down changes sibling execution order.
4. An Action step selects a registered executor and typed arguments. Expand its
   Executor to edit nested Arguments and Effects through the usual typed data
   commands. Required arguments are checked before publishing edits. The
   `attribute_effects` executor supports Add Effect after supplying its arguments.
   Open Executor Script navigates to the registered script.
5. Requirements are ALL predicates. Add an inline Condition or assign a searchable
   existing Condition file. Clicking a shared Condition opens that file. Editing
   the step's condition makes an embedded replacement and preserves the shared
   file. Removing a requirement does not delete its referenced file.
6. In Framework Scenes, right-click the owning entity and use **Attach Behavior
   Resource**. Choose the entry whose kind is `behavior`. It adds a
   `Content/Universal/Interaction/based/Bindings/behavior_binding.gd` component. Remove that component
   to remove future scene activation; use `unbind_behavior` to revoke an existing
   session binding immediately. Unloading a map intentionally preserves bindings.

Configuration and steps are embedded subresources, not extra files or folders.
Condition files and Condition Groups may be shared. The writer verifies the
entire embedded definition, shared references, UID, dependency hashes, catalogue,
and executor snapshot before publishing a change. No backup files are created.

## Runtime flow

`GameEntry.start/restore_session` calls `GameSetup.register_executors`, then content
registration. Discovery converts each Behavior Resource to copied data and validates
executor IDs and argument contracts. Registration alone grants no entity activation.
Map component configuration calls `WorldBridge.bind_behavior` for each attached
Behavior. Rebinding preserves saved enabled state and timers.

Player's `behavior_input.gd` reads configured input and emits `on_attack` through
WorldBridge. The session driver configures targeting and advances interval triggers.
The runtime resolves one actor/target pair, then visits steps in authored order.
Each reached requirement reads current entity state. A false predicate skips its
Action or entire Group and continues with the next sibling. An invalid address or
executor failure stops that invocation and returns the partial execution report.
Earlier effects remain applied. There is no transaction rollback across executors.

Cooldown starts immediately before the first eligible executor attempt, including
an attempt that fails. An all-skipped invocation spends no cooldown. Manual calls,
named events, and interval dispatch share that entity/Behavior timer. Interval
dispatch performs at most one attempt per update; disabled timers freeze.

Use an outer Group if a requirement should gate an entire attack. A requirement
on Damage alone does not gate its later sibling Groups. Boolean predicates accept
`==`/`!=` with boolean data; numeric predicates also support ordering. A value such
as `health.current > 0` can express a living target without adding a boolean flag.

Targeting supports `nearest`, `selected`, and `self`. Selected targeting never falls
back to nearest. Player input selects a target by clicking within 40 viewport
pixels of its target marker; clicking empty space clears selection. Runtime code
can call `select_target(actor_id, target_id)` or
`WorldBridge.select_behavior_target(actor_node, target_node)`. Selection is transient;
only bound, enabled target markers in the active map can be selected for execution.

`invoke_behavior(id, actor_id, resolver)` invokes an enabled binding explicitly.
`emit_behavior_event(actor_id, event_id, resolver)` dispatches matching event bindings.
Reports identify entered Groups, executed/skipped/error steps and executor results.

## Persistence and compatibility

Session snapshots store `behaviors[stable_entity_key][behavior_id]` with enabled,
interval_remaining and cooldown_remaining. Restore validates the whole collection
before replacing bindings and clamps timers to current authored durations. Invalid
records reject session restoration; retry remains possible. No scripts or Nodes are
serialized. Older snapshots with no `behaviors` section remain valid; authored scene
attachments activate their Behaviors when that map loads.

Legacy Action, Interaction and Automation Resources and APIs remain available for
existing content and saves. They use separate registrations and activation records;
IDs are not automatically converted into permissions or new Behavior activations.
Keep a legacy and unified automatic rule from both being enabled for the same
gameplay purpose during a manual migration. Direct Action execution still supplies
movement velocity and is unaffected by Behavior cooldowns. Player's current prefab
uses unified Strike; legacy automation fixtures exercise compatibility separately.

The nested preview uses the existing Change Health executor for bonus effects.
Knockback and Stun in the design example are separate gameplay executors to author;
the sequence engine does not invent their physics or status rules or wait for a
duration argument. Registering such executors makes them available in the picker.

## Checkpoints

From the Godot project directory:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Runtime/behavior_sequence_check.gd
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Authoring/behavior_sequence_editing_check.gd
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Authoring/behavior_sequence_attachment_check.gd
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Gameplay/behavior_sequence_session_check.gd
```

For the visual checkpoint, reload VS Code and open
`Diagnostics/Fixtures/BehaviorSequence/nested_strike.tres`. Expand the tree and
confirm the Damage, Strong Attack and Critical Effect nesting. Edit a label or
reorder two siblings, save, and reopen the file to confirm persistence. This is a
diagnostic fixture, so gameplay content remains unchanged.

```powershell
& Godot_v4.7.1-stable_win64_console.exe --path . --script res://Diagnostics/Gameplay/behavior_sequence_visual_check.gd
```

The preview starts a fresh session with strength 45 and Enemy selected. Space runs
three damage steps, totaling 15 damage, once per 1.5 seconds. WASD still moves and
labels follow entities. Clearing selection prevents attacks until Enemy is selected
again. Saving is disabled in this preview. Close the window when finished.
