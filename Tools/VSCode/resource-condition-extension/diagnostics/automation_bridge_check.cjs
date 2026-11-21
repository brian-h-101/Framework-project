const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const { LibraryService } = require('../out/library/library_service.js');
const { loadResourceGraph } = require('../out/bridges/resource_bridge.js');
const { editBehavior } = require('../out/bridges/behavior_editing_bridge.js');
const { loadResourceCatalog } = require('../out/bridges/resource_catalog_bridge.js');
const { loadSceneGraph } = require('../../framework-scenes-extension/out/scene_bridge.js');
const { editScene } = require('../../framework-scenes-extension/out/scene_editing_bridge.js');

const check = label => console.log(`[automation-bridge] ${label}: true`);
const report = message => { if (/^(SCRIPT ERROR|ERROR):/m.test(message)) { throw new Error(message); } };
async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected project directory and Godot executable.');
	const project = path.resolve(projectArg);
	const root = 'res://Framework/Content/Behavior';
	const name = 'DiagnosticAutomation_' + randomBytes(8).toString('hex');
	const folder = root + '/' + name;
	const owned = path.join(project, folder.slice(6));
	const diagnostics = path.join(project, 'Diagnostics/Fixtures/Automation');
	await fs.mkdir(diagnostics, { recursive: true });
	const temporary = await fs.mkdtemp(path.join(diagnostics, 'automation_bridge_'));
	const sceneFile = path.join(temporary, 'entity.tscn');
	const scene = 'res://' + path.relative(project, sceneFile).split(path.sep).join('/');
	await fs.writeFile(sceneFile, '[gd_scene format=3]\n[node name="Entity" type="Node2D"]\nmetadata/entity_key = &"player"\n');
	const service = new LibraryService({ projectDirectory: project, workspaceDirectory: path.dirname(project) }, executable, report);
	const initial = await service.catalogue();
	const production = new Map(await Promise.all(initial.entries.filter(entry => entry.kind === 'resource')
		.map(async entry => [entry.source_path, await fs.readFile(path.join(project, entry.source_path.slice(6)))])));
	let created = false;
	let source;
	try {
		await service.createCategory(initial.entries[0], name); created = true;
		let catalog = await service.catalogue();
		const parent = catalog.entries.find(entry => entry.source_path === folder);
		source = await service.createResource(parent, 'automatic.tres', { resource_kind: 'automation', id: name,
			interaction_path: root + '/Interaction/strike.tres', interval_seconds: 0.25, cooldown_seconds: 1.0 }, catalog);
		check('Manage Library creates a valid Automation Resource');
		const automaticFile = path.join(project, source.slice(6));
		const inspect = () => loadResourceGraph(project, executable, report, source);
		let graph = await inspect();
		assert.equal(graph.nodes[source].kind, 'automation');
		assert.equal(graph.nodes[source].links[0].role, 'interaction');
		assert.equal(graph.nodes[graph.nodes[source].links[0].target].kind, 'interaction');
		const field = graph.nodes[source].data.children.find(row => row.label === 'interval_seconds');
		assert.ok(field.editable && !field.can_remove && !field.can_rename && field.allowed_types.includes('float'));
		check('Graph exposes the Interaction chain and protected timing settings');
		const request = extra => ({ expected_hashes: graph.dependency_hashes, catalog_paths: graph.catalog_paths,
			catalog_seed: source, executor_snapshot: graph.executor_snapshot, ...extra });
		await editBehavior(project, executable, source, request({operation: 'set', path: field.path, value_type: 'float', value_text: '0.5'}), report);
		graph = await inspect();
		assert.equal(graph.nodes[source].data.children.find(row => row.label === 'interval_seconds').value_text, '0.5');
		const saved = await fs.readFile(automaticFile);
		await assert.rejects(editBehavior(project, executable, source, request({operation: 'set', path: field.path,
			value_type: 'float', value_text: '-1'}), report), /greater than zero/);
		await assert.rejects(editBehavior(project, executable, source, request({operation: 'set', path: field.path,
			value_type: 'bool', value_text: 'true'}), report), /incompatible/);
		assert.deepEqual(await fs.readFile(automaticFile), saved);
		check('Timing edits persist and rejected values preserve saved bytes');
		await editBehavior(project, executable, source, request({operation: 'set_interaction', interaction_path: root + '/Interaction/drag_check.tres'}), report);
		graph = await inspect();
		assert.equal(graph.nodes[source].links[0].target, root + '/Interaction/drag_check.tres');
		await assert.rejects(editBehavior(project, executable, source, request({operation: 'set_interaction', interaction_path: root + '/Condition/can_strike.tres'}), report), /Expected an Interaction/);
		check('Searchable Interaction reassignment validates the Resource type');
		const available = await loadResourceCatalog(project, executable, report);
		assert.ok(available.resources.some(entry => entry.kind === 'automation' && entry.source_path === source));
		let sceneGraph = await loadSceneGraph(project, executable, scene, report);
		const component = 'res://Framework/Content/God/Interaction/automation_behavior.gd';
		const hashes = {...sceneGraph.dependency_hashes};
		for (const file of [source, component]) { hashes[file] = createHash('sha256').update(await fs.readFile(path.join(project, file.slice(6)))).digest('hex'); }
		await editScene(project, executable, scene, {operation: 'attach_behavior', path: '.', name: 'AutomaticBehavior',
			automation_resource: source, expected_hashes: hashes}, report);
		sceneGraph = await loadSceneGraph(project, executable, scene, report);
		assert.equal(sceneGraph.nodes.AutomaticBehavior.automation_id, name);
		assert.equal(sceneGraph.nodes.AutomaticBehavior.script_path, component);
		const sceneBytes = await fs.readFile(sceneFile);
		await assert.rejects(editScene(project, executable, scene, {operation: 'attach_behavior', path: '.', name: 'Duplicate',
			automation_resource: source, expected_hashes: {...hashes, ...sceneGraph.dependency_hashes}}, report), /already attached/);
		assert.deepEqual(await fs.readFile(sceneFile), sceneBytes);
		check('Framework Scenes attaches Automation and rejects duplicate activation components');
		const preview = await service.previewDeletion((await service.catalogue()).entries.find(entry => entry.source_path === source));
		assert.ok(preview.consumers.some(consumer => consumer.source_path === scene));
		await editScene(project, executable, scene, {operation: 'remove', path: 'AutomaticBehavior', expected_hashes: sceneGraph.dependency_hashes}, report);
		assert.ok(!(await loadSceneGraph(project, executable, scene, report)).nodes.AutomaticBehavior);
		check('Deletion detects scene consumers and scene removal detaches the component');
		for (const [file, bytes] of production) { assert.deepEqual(await fs.readFile(path.join(project, file.slice(6))), bytes); }
		check('Production behavior resources remain unchanged');
	} finally {
		if (created) {
			assert.equal(path.dirname(path.resolve(owned)), path.resolve(project, 'Framework/Content/Behavior'));
			assert.equal(await fs.realpath(owned), owned);
			for (const file of await fs.readdir(owned)) { assert.equal(file, 'automatic.tres'); await fs.unlink(path.join(owned, file)); }
			await fs.rmdir(owned);
		}
		assert.equal(path.dirname(path.resolve(temporary)), path.resolve(diagnostics));
		assert.equal(await fs.realpath(temporary), temporary);
		for (const file of await fs.readdir(temporary)) { assert.equal(file, 'entity.tscn'); await fs.unlink(path.join(temporary, file)); }
		await fs.rmdir(temporary);
		check('Owned fixtures removed');
	}
	check('Checks passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
