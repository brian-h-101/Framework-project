# Environment setup

```text
Setup/
    Bootstrap/
        game_setup.gd
    Composition/
        common_attributes.gd
        content_composition.gd
        fragment_composition.gd
        starting_attributes.gd
    Definitions/
        entity_definitions.gd
        starting_definitions.gd
    Discovery/
        content_discovery.gd
        executor_discovery.gd
        resource_definition_discovery.gd
    Library/
        authored_library.gd
        behavior_library_policy.gd
        library_path_policy.gd
```

Bootstrap/game_setup.gd is the environment's GameSetup implementation.
GameEntry.start() calls register_executors(), then register_content(), then
create_entities(). Session restoration uses the same registration hooks and
restores saved entity data instead of spawning startup entities.
The Bootstrap implementation coordinates those calls without owning the reusable
discovery, composition or library policy helpers.

Discovery contains directory scanning and executor/Resource definition discovery.
Definitions exposes the entity and starting-preset catalogues that use discovery.
Composition builds independent container dictionaries from fragments, common
defaults and selected starting attributes, preserving the existing override order.
Library contains the shared path/listing rules and separate Authored/Behavior
write-boundary policies.

Script UID companions stay beside their scripts and retain their UID values.
Diagnostics, content Resources and editor backend imports use the categorized paths.
