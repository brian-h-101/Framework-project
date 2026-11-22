const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { loadResourceGraph } = require('../out/bridges/resource_bridge.js');
const { editBehavior } = require('../out/bridges/behavior_editing_bridge.js');
const { loadResourceCatalog } = require('../out/bridges/resource_catalog_bridge.js');
const { loadSceneGraph } = require('../../framework-scenes-extension/out/scene_bridge.js');
const { editScene } = require('../../framework-scenes-extension/out/scene_editing_bridge.js');

const [project, godot] = process.argv.slice(2);
if (!project || !godot) { throw Error('Supply the Godot project directory and executable.'); }
const relative = '.godot/diagnostics/behavior_bridge_' + randomUUID().replaceAll('-', '');
const folder = path.join(project, relative);
const source = 'res://' + relative + '/behavior.tres';
const scene = 'res://' + relative + '/entity.tscn';
const resourceFile = path.join(folder, 'behavior.tres');
const sceneFile = path.join(folder, 'entity.tscn');
const log = message => console.error(message);
const check = (label, valid) => { assert.ok(valid, label); console.log(`[sequence-bridge] ${label}: true`); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const owned = [];
async function main() {
	await fs.mkdir(path.dirname(folder), {recursive: true});
	await fs.mkdir(folder, { recursive: false });
	try {
		await fs.writeFile(resourceFile, `[gd_resource type="Resource" format=3]
[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd" id="1"]
[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_configuration_resource.gd" id="2"]
[sub_resource type="Resource" id="Configuration"]
script = ExtResource("2")
[resource]
script = ExtResource("1")
id = &"bridge_sequence"
configuration = SubResource("Configuration")
`, { flag: 'wx' }); owned.push(resourceFile);
		const edit = async fields => {
			const graph = await loadResourceGraph(project, godot, log, source);
			return editBehavior(project, godot, source, { expected_hashes: graph.dependency_hashes,
				catalog_paths: graph.catalog_paths, catalog_seed: source, executor_snapshot: graph.executor_snapshot, ...fields }, log);
		};
		await edit({ operation: 'sequence_add', step_kind: 'group', new_id: 'group', label: 'Group' });
		await edit({ operation: 'sequence_add', step_id: 'group', step_kind: 'action', new_id: 'damage', label: 'Damage', executor_id: 'change_health', arguments: [{ name: 'amount', value_type: 'int', value_text: '-10' }] });
		const graph = await loadResourceGraph(project, godot, log, source);
		const root = graph.nodes[source];
		check('Real graph validates embedded ownership and hierarchy', root.kind === 'behavior' && Object.keys(graph.nodes).length === 1
			&& root.data.children[1].children[0].children[1].children[0].sequence.step_id === 'damage');
		const before = await fs.readFile(resourceFile);
		await assert.rejects(() => edit({ operation: 'sequence_executor', step_id: 'damage', executor_id: 'change_health', arguments: [{name: 'amount', value_type: 'String', value_text: 'invalid'}] }), /requires a number/);
		check('Typed argument rejection preserves saved bytes', before.equals(await fs.readFile(resourceFile)));
		await fs.writeFile(sceneFile, '[gd_scene format=3]\n[node name="Entity" type="Node2D"]\nmetadata/entity_definition = &"player"\n', { flag: 'wx' }); owned.push(sceneFile);
		const sceneGraph = await loadSceneGraph(project, godot, scene, log);
		const binding = 'res://Framework/Content/Universal/Interaction/based/Bindings/behavior_binding.gd';
		const hashes = { ...sceneGraph.dependency_hashes, [source]: hash(await fs.readFile(resourceFile)), [binding]: hash(await fs.readFile(path.join(project, binding.slice(6)))) };
		await editScene(project, godot, scene, { operation: 'attach_behavior', path: '.', name: 'Behavior', behavior_resource: source, expected_hashes: hashes }, log);
		const attached = await loadSceneGraph(project, godot, scene, log);
		check('Real scene bridge attaches the unified Behavior', attached.nodes.Behavior.behavior_id === 'bridge_sequence' && attached.nodes.Behavior.script_path === binding);
		const catalog = await loadResourceCatalog(project, godot, log);
		check('Search catalogue exposes unified gameplay resources', catalog.resources.some(entry => entry.kind === 'behavior' && entry.id === 'strike'));
	} finally {
		for (const file of owned.reverse()) { await fs.unlink(file); }
		await fs.rmdir(folder);
		console.log('[sequence-bridge] Temporary files and folder removed: true');
	}
	console.log('[sequence-bridge] Checks passed: true');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
