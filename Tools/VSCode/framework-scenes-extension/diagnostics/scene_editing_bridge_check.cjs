const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { loadSceneGraph } = require('../out/scene_bridge.js');
const { editScene, nodeTypes, inspectScript } = require('../out/scene_editing_bridge.js');

const project = path.resolve(process.argv[2] ?? ''); const executable = process.argv[3];
assert.ok(executable && fs.existsSync(path.join(project, 'project.godot')), 'Expected <project directory> <Godot executable>.');
const parent = path.join(project, '.godot/diagnostics'); fs.mkdirSync(parent, { recursive: true });
const temporary = fs.mkdtempSync(path.join(parent, 'scene_editing_bridge_'));
const resource = name => 'res://' + path.relative(project, path.join(temporary, name)).split(path.sep).join('/');
const fixture = path.join(temporary, 'map.tscn'); const templateFile = path.join(temporary, 'template.tscn');
const scene = resource('map.tscn'); const template = resource('template.tscn');
const script = resource('probe.gd');
const production = path.join(project, 'Framework/Content/Gameplay/Maps/city_recreated.tscn');
const productionBytes = fs.readFileSync(production);
fs.writeFileSync(fixture, '[gd_scene format=3]\n[node name="Map" type="Node2D" unique_id=100]\nmetadata/entity_key = &"stable_key"\n[node name="Props" type="Node2D" parent="." unique_id=101]\n[node name="Lamp" type="Node2D" parent="Props" unique_id=102]\nposition = Vector2(3, 4)\n[node name="Watcher" type="RemoteTransform2D" parent="."]\nremote_path = NodePath("../Props/Lamp")\n');
fs.writeFileSync(templateFile, '[gd_scene format=3]\n[node name="Template" type="Node2D"]\n[node name="Marker" type="Marker2D" parent="."]\n');
fs.writeFileSync(path.join(temporary, 'probe.gd'), 'extends Node2D\n@export var note: String = "default"\n');
const report = message => { if (/^(SCRIPT ERROR|ERROR|WARNING):/m.test(message)) { throw new Error(message); } };
const check = label => console.log(`[scene-editing-bridge] ${label}: true`);
(async () => {
	try {
		const types = await nodeTypes(project, executable, report); assert.ok(types.includes('Node2D') && types.includes('Node3D'));
		check('Godot supplies the searchable native type catalogue');
		let graph = await loadSceneGraph(project, executable, scene, report);
		const edit = async (operation, target, extra = {}) => {
			const hashes = { ...graph.dependency_hashes };
			if (operation === 'add_instance') {
				const candidate = await loadSceneGraph(project, executable, extra.instance_scene, report);
				Object.assign(hashes, candidate.dependency_hashes);
			}
			if (operation === 'attach_script' || operation === 'remove_script') {
				const source = operation === 'attach_script' ? extra.script_path : graph.nodes[target].script_path;
				const inspected = await inspectScript(project, executable, source, graph.nodes[target].type, report);
				Object.assign(hashes, inspected.dependency_hashes);
			}
			const result = await editScene(project, executable, scene, { operation, path: target, expected_hashes: hashes, ...extra }, report);
			assert.equal(result.content_hash, createHash('sha256').update(fs.readFileSync(fixture)).digest('hex'));
			graph = await loadSceneGraph(project, executable, scene, report);
		};
		await edit('attach_script', 'Props/Lamp', { script_path: script });
		assert.equal(graph.nodes['Props/Lamp'].script_path, script);
		assert.equal(graph.nodes['Props/Lamp'].can_remove_script, true);
		assert.equal(graph.nodes['Props/Lamp'].can_attach_script, false);
		const attachedBytes = fs.readFileSync(fixture);
		await assert.rejects(inspectScript(project, executable, script, 'Node', report), /cannot attach to Node/);
		assert.deepEqual(fs.readFileSync(fixture), attachedBytes);
		await edit('remove_script', 'Props/Lamp');
		assert.equal(graph.nodes['Props/Lamp'].has_script, false);
		assert.equal(graph.nodes['Props/Lamp'].can_attach_script, true);
		assert.ok(fs.readFileSync(fixture, 'utf8').includes('position = Vector2(3, 4)'));
		check('Real script inspection, attachment and detachment preserve the saved node');
		await edit('add_node', 'Props', { name: 'Point 雨', node_type: 'Marker2D' }); assert.equal(graph.nodes['Props/Point 雨'].type, 'Marker2D');
		await edit('rename', 'Props/Lamp', { name: 'Torch' });
		assert.ok(fs.readFileSync(fixture, 'utf8').includes('NodePath("../Props/Torch")'));
		assert.ok(fs.readFileSync(fixture, 'utf8').includes('metadata/entity_key = &"stable_key"'));
		check('Nested native edits repair paths and preserve entity metadata');
		const before = fs.readFileSync(fixture);
		await assert.rejects(editScene(project, executable, scene, { operation: 'remove', path: 'Props/Torch', expected_hashes: graph.dependency_hashes }, report), /surviving node references/i);
		assert.deepEqual(fs.readFileSync(fixture), before);
		check('Dangling references reject removal without writing');
		await edit('remove', 'Watcher'); await edit('remove', 'Props/Torch'); assert.ok(!graph.nodes['Props/Torch']);
		await edit('add_instance', 'Props', { name: 'Placed', instance_scene: template });
		assert.equal(graph.nodes['Props/Placed'].can_rename, true); assert.equal(graph.nodes['Props/Placed/Marker'].can_rename, false);
		await edit('add_node', 'Props/Placed', { name: 'LocalTag', node_type: 'Node3D' });
		await edit('rename', 'Props/Placed', { name: 'RenamedPlacement' });
		assert.ok(graph.nodes['Props/RenamedPlacement/Marker'] && graph.nodes['Props/RenamedPlacement/LocalTag']);
		check('Scene placements retain their instance and local additions');
		const saved = fs.readFileSync(fixture);
		await assert.rejects(editScene(project, executable, scene, { operation: 'rename', path: 'Props/RenamedPlacement/Marker', name: 'Other', expected_hashes: graph.dependency_hashes }, report), /structure belongs/i);
		await assert.rejects(editScene(project, executable, scene, { operation: 'add_instance', path: '.', name: 'Cycle', instance_scene: scene, expected_hashes: graph.dependency_hashes }, report), /dependency cycle/i);
		fs.appendFileSync(templateFile, '\n; Changed dependency\n');
		await assert.rejects(editScene(project, executable, scene, { operation: 'add_node', path: '.', name: 'Stale', node_type: 'Node', expected_hashes: graph.dependency_hashes }, report), /dependency changed/i);
		assert.deepEqual(fs.readFileSync(fixture), saved);
		check('Borrowed nodes, cycles and stale dependencies are rejected');
		const malformed = spawnSync(executable, ['--headless', '--path', project, '--script',
			'res://Framework/Env/Authoring/Scenes/Editing/scene_editing_cli.gd', '--', 'edit', scene],
			{ input: '{invalid json', encoding: 'utf8', windowsHide: true, timeout: 30000 });
		assert.equal(malformed.status, 1); assert.match(malformed.stdout, /Expected a scene edit JSON object/);
		assert.deepEqual(fs.readFileSync(fixture), saved);
		check('Malformed requests leave saved scenes unchanged');
		assert.deepEqual(fs.readFileSync(production), productionBytes);
		assert.deepEqual(fs.readdirSync(temporary).sort(), ['map.tscn', 'probe.gd', 'template.tscn']);
		check('Production scenes are unchanged and no staging files remain');
	} finally {
		assert.equal(path.dirname(path.resolve(temporary)), path.resolve(parent));
		assert.ok(path.basename(temporary).startsWith('scene_editing_bridge_'));
		assert.equal(fs.realpathSync(temporary), temporary);
		for (const file of [fixture, templateFile, path.join(temporary, 'probe.gd')]) { if (fs.existsSync(file)) { fs.unlinkSync(file); } }
		fs.rmdirSync(temporary); check('Temporary scenes and folder removed');
	}
	check('Checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
