const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { loadResourceGraph } = require('../out/bridges/resource_bridge.js');
const { editBehavior } = require('../out/bridges/behavior_editing_bridge.js');

async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected project directory and Godot executable.');
	const project = path.resolve(projectArg);
	const diagnostics = path.join(project, '.godot', 'diagnostics');
	await fs.mkdir(diagnostics, { recursive: true });
	const folder = await fs.mkdtemp(path.join(diagnostics, 'behavior_bridge_'));
	const root = 'res://.godot/diagnostics/' + path.basename(folder);
	const source = root + '/interaction.tres';
	const productionPaths = ['Action/change_health.tres', 'Condition/actor_strength.tres', 'Condition/can_strike.tres']
		.map(name => path.join(project, 'Framework/Content/Behavior', name));
	const productionBefore = await Promise.all(productionPaths.map(file => fs.readFile(file)));
	const group = root + '/group.tres';
	const part = text => ({ kind: 'String', text });
	const report = message => { throw new Error(message); };
	try {
		await fs.writeFile(path.join(folder, 'interaction.tres'), `[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd" id="1"]
[ext_resource type="Resource" path="res://Framework/Content/Behavior/Action/change_health.tres" id="2"]
[ext_resource type="Resource" path="res://Framework/Content/Behavior/Condition/can_strike.tres" id="3"]

[resource]
script = ExtResource("1")
id = &"bridge_structural"
action = ExtResource("2")
requirements = ExtResource("3")
arguments = {&"amount": -10, "nested": {"text": "original"}}
`, { flag: 'wx' });
		// Copy the typed group syntax while assigning an independent fixture identity.
		let groupText = (await fs.readFile(productionPaths[2], 'utf8')).replace(/ uid="[^"]+"/, '').replace('id = &"can_strike"', 'id = &"bridge_group"');
		await fs.writeFile(path.join(folder, 'group.tres'), groupText);
		const inspect = file => loadResourceGraph(project, executable, report, file);
		const request = (graph, fields) => ({ ...fields, expected_hashes: graph.dependency_hashes,
			catalog_paths: graph.catalog_paths, catalog_seed: graph.roots[0], executor_snapshot: graph.executor_snapshot });
		let graph = await inspect(source);
		const stale = request(graph, { operation: 'clear_requirements' });
		const edited = await editBehavior(project, executable, source, request(graph, {
			operation: 'set', path: [part('arguments'), part('nested'), part('text')],
			value_type: 'String', value_text: '雪\n  second\r\n\tline'
		}), report);
		assert.equal(edited.source_path, source);
		graph = await inspect(source);
		const value = graph.nodes[source].data.children[0].children.find(node => node.label === 'nested').children[0];
		assert.equal(value.value_text, '雪\n  second\r\n\tline');
		console.log('[behavior-bridge] Nested edit survives real stdin and ResourceSaver round trip: true');
		const before = await fs.readFile(path.join(folder, 'interaction.tres'));
		await assert.rejects(() => editBehavior(project, executable, source, stale, report), /changed|inspected/);
		assert.deepEqual(await fs.readFile(path.join(folder, 'interaction.tres')), before);
		console.log('[behavior-bridge] Stale request preserves saved bytes: true');
		await editBehavior(project, executable, source, request(graph, { operation: 'clear_requirements' }), report);
		graph = await inspect(source);
		assert.ok(!graph.nodes[source].links.some(link => link.role === 'requirements'));
		assert.ok(graph.nodes[source].links.some(link => link.role === 'action'));
		console.log('[behavior-bridge] Optional requirements clear while required action remains: true');
		const groupGraph = await inspect(group);
		await editBehavior(project, executable, group, request(groupGraph, { operation: 'remove_condition',
			condition_index: 0, condition_path: 'res://Framework/Content/Behavior/Condition/actor_strength.tres' }), report);
		assert.equal((await inspect(group)).nodes[group].links.length, 0);
		console.log('[behavior-bridge] Relationship removal writes only the temporary parent group: true');
		for (let index = 0; index < productionPaths.length; index++) {
			assert.deepEqual(await fs.readFile(productionPaths[index]), productionBefore[index]);
		}
		console.log('[behavior-bridge] Shared production resources remain unchanged: true');
	} finally {
		// Remove only the two files this diagnostic owns, without recursive deletion.
		for (const file of await fs.readdir(folder)) {
			assert.ok(['group.tres', 'interaction.tres'].includes(file), 'Unexpected temporary file: ' + file);
			await fs.unlink(path.join(folder, file));
		}
		await fs.rmdir(folder);
		console.log('[behavior-bridge] Temporary resources cleaned: true');
	}
	console.log('[behavior-bridge] Checks passed: true');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
