# Gameplay implementation

```text
Gameplay/
    Automation/
        automation_system.gd
    Behavior/
        behavior_definition.gd
        behavior_evaluator.gd
        behavior_system.gd
    Execution/
        action_executor.gd
        interaction_executor.gd
        effect_executor.gd
        execution_context_core.gd
    Registry/
        executor_contract.gd
        executor_registry_core.gd
    Executors/
        attribute_effects_executor.gd
```

RuntimeCore assembles these services and exposes them through GameRuntime.

Behavior contains definition validation, ordered step evaluation, and the Behavior
system that owns registrations, entity activation, targeting state and timers.
The evaluator reads requirements as steps are reached, skips unmet branches and
dispatches eligible Action steps through Execution/action_executor.gd.

Registry contains the executor registry and the shared metadata/argument contract.
Execution contains Action dispatch, legacy Interaction checks, the execution
context implementation and attribute-effect operations. Executors contains built-in
executor implementations. Automation contains the legacy interval scheduler.

The execution flow is BehaviorSystem -> BehaviorEvaluator -> ActionExecutor ->
registered GameplayExecutor -> ExecutionContextCore -> EffectExecutor/AttributeConnector.
Legacy InteractionExecutor performs availability and requirement checks before
using the same ActionExecutor. Gameplay data and persistence formats are unchanged.

UID companions stay beside their scripts and keep their original values.
