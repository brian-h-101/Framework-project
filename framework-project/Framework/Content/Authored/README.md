# Authored container fragments

Entity, Items, and Objects contain reusable `.tres` container fragments. Each uses
`Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd`.
The schema exports a `containers` dictionary with named dictionary containers.

```text
Authored/
    Entity/Attributes/Abilities/precognition.tres
    Entity/Attributes/Abilities/reflex.tres
    Entity/Container/inventory.tres
    Items/Attributes/Physical/physical.tres
    Objects/State/Access/access.tres
```

For example, the resource section of `precognition.tres` contains:

```ini
[resource]
script = ExtResource("1_schema")
containers = {
	&"abilities": {
		"precognition": 0
	}
}
```

Starting profiles under `Content/Presentation` select an ordered, typed array of
external fragment references. See TownGuard's `starting_attributes.tres` for a
small complete example. A fragment must be saved under one of the three Authored
libraries. Starting overrides apply after the selected fragments.

Composition preserves sibling attributes. Later fragments replace matching
attributes; dictionary and array attribute values are replaced as a whole.
The resource converter and composer deep-copy collections before registration.
Runtime writes and acquired containers remain independent of these templates.

Composition and discovery logic live in `Framework/Env/Setup`:

- `fragment_composition.gd` loads and validates fragments or composes references.
- `content_composition.gd` merges container dictionaries.
- `starting_attributes.gd` enforces library boundaries and applies final overrides.
- `starting_definitions.gd` discovers all starting profiles.
- `entity_definitions.gd` discovers the Entity starting profiles.
- `common_attributes.gd` provides the shared health/speed composition helper.

The Framework Resources extension currently displays behavior resources. Supporting
fragment and starting-profile relationships in that tree is a separate feature.
