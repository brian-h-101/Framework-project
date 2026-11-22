# Gameplay Resource schemas

```text
Resources/
    Actions/
        action_resource.gd
    Automation/
        automation_resource.gd
    Behavior/
        behavior_resource.gd
        behavior_configuration_resource.gd
        behavior_step_resource.gd
        action_step_resource.gd
        group_step_resource.gd
    Conditions/
        condition_resource.gd
        condition_group_resource.gd
    Interactions/
        interaction_resource.gd
```

These are the public Resource schemas referenced by authored .tres files.
Actions, Interactions and Automation contain the corresponding standalone schemas.
Conditions contains leaf predicates and ALL groups. Behavior contains the unified
Behavior, its Configuration, and the base/Action/Group step schemas.

Behavior.read() converts the nested Resource tree into independent gameplay data
and validates embedded ownership and structural limits through
Implementation/Gameplay/Behavior/behavior_definition.gd. Runtime registration adds
executor and argument-contract validation.

Authored Resource files and consumers reference the categorized schema paths.
Resource IDs, properties and conversion methods retain their existing contracts.
