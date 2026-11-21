# Configuration resources

These `.tres` files store environment configuration. Their reusable Resource schemas
live in `Framework/Env/Configuration/Resources`; the category folders here contain
the authored values.

| Folder | Configures |
| --- | --- |
| Session | Starting entity specifications, initial map path and clock settings |
| Input | Input action names, physical key codes, interactions and session commands |
| Movement | Movement actions and the runtime speed attribute to read |
| Map | Tile texture, tile size, dimensions and map creation presets |
| Lighting | Ambient/day/night lighting, point lights and shared shadow settings |
| Presentation | Attribute paths and formats for UI fields |
| Persistence | Startup mode and save file path |

Open a `.tres` file to edit its saved fields in text or in the Godot Inspector.
Input key codes are Godot `Key` enum values: for example, Space is `32` and A is `65`.
Startup entities, input bindings and UI fields use ordered arrays. Each entry has
a `key`, `action` or `id`, respectively. This preserves authored order when Godot
saves the files; consumers still receive the existing dictionaries.

Map defaults reference ground and lighting Resources. Lighting references the shared
shadow Resource. The Player presentation references its movement Resource. Keep these
as external references when configurations should share authored settings.

The initial map is a file-path String so the map coordinator can load scenes on
demand. It is not a PackedScene dependency of the startup configuration.

Consumers call `read()` to validate a configuration and obtain an `ok` / `value` /
`error` result. `to_definition()` converts valid configuration to the existing
dictionary interface. Each conversion owns its nested dictionaries and arrays;
textures and referenced configurations remain shared assets. Edit gameplay state
through GameRuntime rather than changing configuration Resources during play.

The Resource Condition extension currently displays behavior resources. Configuration
Resources remain editable through text and the Godot Inspector.

Run the configuration diagnostic from the Godot project folder:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Configuration/configuration_resource_check.gd
```
