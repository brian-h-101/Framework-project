# Configuration schemas

```text
Resources/
    Shared/
        configuration_resource.gd
    Input/
        controls_resource.gd
    Persistence/
        session_persistence_resource.gd
    Presentation/
        displays_resource.gd
    Session/
        startup_resource.gd
        world_time_resource.gd
```

`Shared/configuration_resource.gd` supplies validation, typed entry conversion
and attribute-address helpers. Each Content `.tres` file references its schema
script, whose `read()` method validates the authored data before returning a
definition to its consumer.

Input, persistence, display, and session schemas support host configuration.
Lighting, shadow, map, movement, and 2D presentation schemas live next to their
Godot components in [Content/Universal](../../Content/Universal/README.md).
