# Content authoring

`Gameplay` contains the authored attribute library, controllers, maps,
presentations, profiles, and HUD scenes. Reusable components live in
`Universal` and host settings live in `Configuration`.

The original demonstration game has been cleared so new content can be authored
through the framework extensions. The framework schemas, authoring backends,
Authored attribute library, reusable [Universal components](Universal/README.md), and configuration
templates remain available.

The City rebuild also clears `Gameplay/Maps/city.tscn`, the Player and Enemy
presentations and their starting-attribute presets, the Movement profile, and the
keyboard and AI controller resources. Startup opens an empty session during
authoring.

The cleanup removed 11 Behavior Resources, 10 Presentation Resources, 12 Content
scenes (Maps, Presentation, Camera and UI/HUD), and two gameplay executor scripts.
It also removed the old per-player Movement resource because it referenced
the deleted movement Action. No backups were created. Existing user save files
were not modified or deleted.

Startup uses the discovery helpers in `Framework/Env/Setup/Definitions` to
register authored Resources from `Content/Gameplay/Profiles/<category>/Behavior`. Category-specific
gameplay executors live in `Content/Gameplay/Profiles/<category>/Executor`. The framework
provides the built-in `attribute_effects` executor.

## Starting an empty project

Framework/Env/Bootstrap/main.gd starts GameHost. The host reads the persistence
configuration, which now selects a new session. GameSetup registers the available
executors, discovers content, and spawns the configured startup entities. The empty
libraries and empty startup entity list therefore produce an empty runtime.

Configuration/Session/startup.tres contains three authoring choices:

| Field | Empty value | Configured value |
| --- | --- | --- |
| initial_map | Start without a map | Load the selected project .tscn |
| ui_scene | Start without a HUD | Load a scene with a CanvasLayer root |
| entities | Spawn no startup entities | Spawn the selected definitions |

Nonempty missing scene paths remain errors. GameSetup returns structured scene
selection results to GameHost. The host attaches only configured scenes and passes
the runtime, world bridge, entity IDs and display definitions to configure_session
components in the HUD. The HUD and its root can both receive this configuration.

`Configuration/Input/controls.tres` defines the configured input bindings.
Persistence starts in new mode. A restored save that references City requires
the map to be recreated. Legacy map paths can be redirected once their
destination scenes exist.

## Rebuilding

1. In Framework Scenes, use Manage Authored Library to create the first map under
   Content/Gameplay/Maps. The map template retains configurable ground and lighting; the
   empty 2D template starts with only its root.
2. Recreate presentation scenes and their starting-attribute selections, using the
   retained Authored library as the source of available containers and attributes.
3. Add gameplay executor scripts under `Content/Gameplay/Profiles/<category>/Executor`, then
   use Framework Resources to create Behaviors under that category’s `Behavior` folder.
4. Recreate the keyboard and AI controller resources under `Gameplay/Controller`.
   Assign them to the corresponding entity presentations, then attach the
   presentation instances and Behavior Resources through Framework Scenes.
5. Set initial_map and ui_scene in startup.tres to the newly authored scene paths.
   Author startup entities and input bindings for the rebuilt game as needed.

The bootstrap can be run throughout authoring without fabricating placeholder
maps, entities, behaviors or UI scenes.

## Verification of the cleared state

From the Godot project directory:

```powershell
& Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://Diagnostics/Content/empty_content_startup_check.gd
```

This milestone diagnostic expects empty game libraries. It checks discovery,
extension catalogues, blank startup, snapshots, replacement map/HUD attachment,
invalid HUD cleanup and verified scene drafts. Its replacement scenes stay in
memory; drafting publishes no Content file.

Existing diagnostics and visual fixtures that refer to the deleted demonstration
content remain historical examples. They require replacement fixtures as the game
is rebuilt. Their old Player/Enemy presets, behavior paths and map expectations no
longer describe the current content state.
