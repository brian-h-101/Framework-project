const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { LibraryService } = require('../out/library/library_service.js');
const { BEHAVIOR_ROOT, libraryRequest } = require('../out/bridges/behavior_library_bridge.js');
const { loadResourceCatalog } = require('../out/bridges/resource_catalog_bridge.js');
const { checkedBehaviorPath, nameError } = require('../out/library/library_paths.js');
const { addConditionToGroup } = require('../out/bridges/condition_assignment_bridge.js');
const { loadResourceGraph } = require('../out/bridges/resource_bridge.js');
const { editBehavior } = require('../out/bridges/behavior_editing_bridge.js');

const check = label => console.log(`[behavior-library] ${label}: true`);
async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected project and Godot executable.');
	const project = path.resolve(projectArg);
	const context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
	const service = new LibraryService(context, executable, message => { if (/^(SCRIPT ERROR|ERROR):/m.test(message)) { throw new Error(message); } });
	const before = await service.catalogue();
	const production = new Map(await Promise.all(before.entries.filter(e => e.kind === 'resource')
		.map(async e => [e.source_path, await fs.readFile(path.join(project, e.source_path.slice(6)))])));
	const name = 'DiagnosticBehavior_' + randomBytes(8).toString('hex');
	const root = BEHAVIOR_ROOT + '/' + name;
	const ownedRoot = path.join(project, root.slice(6));
	let created = false;
	const current = () => service.catalogue();
	const get = async source => { const value = (await current()).entries.find(e => e.source_path === source); assert.ok(value, source); return value; };
	const create = async (folder, filename, request) => {
		const catalog = await current();
		return service.createResource(catalog.entries.find(e => e.source_path === folder), filename, request, catalog);
	};
	const trashCalls = [];
	const trash = async file => { trashCalls.push(file); await fs.unlink(file); };
	try {
		await service.createCategory(before.entries[0], name); created = true;
		await service.createCategory(await get(root), 'Nested');
		const nested = root + '/Nested';
		await assert.rejects(service.createCategory(await get(BEHAVIOR_ROOT), name.toUpperCase()), /already exists/);
		await assert.rejects(service.createCategory(await get(root), '../escape'), /leading dot|reserved/);
		assert.ok(nameError('COM¹')); assert.ok(nameError('NUL.tres')); assert.ok(nameError('bad.'));
		check('Categories, nested categories, Windows names, and duplicate siblings');
		const actionId = name.toLowerCase() + '_action';
		const interactionId = name.toLowerCase() + '_interaction';
		assert.ok(before.executors.some(executor => executor.id === 'attribute_effects' && executor.supports_effects));
		const action = await create(nested, 'action.tres', { resource_kind: 'action', id: actionId, behavior_id: 'attribute_effects' });
		const inspect = () => loadResourceGraph(project, executable, () => {}, action);
		let behaviorGraph = await inspect();
		const behaviorRequest = id => ({ operation: 'set_behavior', behavior_id: id,
			expected_hashes: behaviorGraph.dependency_hashes, catalog_paths: behaviorGraph.catalog_paths,
			catalog_seed: action, executor_snapshot: behaviorGraph.executor_snapshot });
		await editBehavior(project, executable, action, behaviorRequest('attribute_effects'), () => {});
		behaviorGraph = await inspect();
		assert.equal(behaviorGraph.nodes[action].behavior_id, 'attribute_effects');
		const unchangedAction = await fs.readFile(path.join(project, action.slice(6)));
		await assert.rejects(editBehavior(project, executable, action, behaviorRequest('unknown_behavior'), () => {}), /Unknown executor/);
		assert.deepEqual(await fs.readFile(path.join(project, action.slice(6))), unchangedAction);
		await assert.rejects(create(nested, 'unknown_behavior.tres', {resource_kind: 'action', id: name + '_unknown', behavior_id: 'unknown_behavior'}), /Unknown executor/);
		check('Registered behavior selection crosses the real bridge; unknown IDs preserve files');
		const condition = await create(nested, 'condition.tres', { resource_kind: 'condition', id: name + '_condition', requirement: {
			entity: 'actor', container: 'health', path: ['current'], operator: '>=', value_type: 'int', value_text: '10', message: 'Requires health.' } });
		const group = await create(nested, 'group.tres', { resource_kind: 'condition_group', id: name + '_group' });
		const groupFile = path.join(project, group.slice(6));
		const emptyGroupText = await fs.readFile(groupFile, 'utf8');
		await addConditionToGroup(project, executable, group, condition, () => {});
		for (const source of [action, condition, group]) {
			const text = await fs.readFile(path.join(project, source.slice(6)), 'utf8');
			assert.match(text, /uid="uid:\/\/[a-z0-9]+"/); assert.ok(!/(?<!\r)\n/.test(text)); assert.ok(!/^ +\S/m.test(text));
		}
		check('Action, numeric Condition, and empty Group drafts have UIDs, tabs, and CRLF');
		const actionFile = path.join(project, action.slice(6));
		const actionText = await fs.readFile(actionFile, 'utf8');
		await fs.writeFile(actionFile, actionText.replace('effects = []', 'effects = [{"operation": &"add", "entity": &"target", "container": &"health", "path": ["current"], "value_from": &"amount"}]'));
		// Empty defaults may be omitted by ResourceSaver.
		if (!(await fs.readFile(actionFile, 'utf8')).includes('value_from')) {
			await fs.appendFile(actionFile, 'effects = [{"operation": &"add", "entity": &"target", "container": &"health", "path": ["current"], "value_from": &"amount"}]\r\n');
		}
		const actionMeta = await get(action);
		assert.deepEqual(actionMeta.argument_specs, [{ name: 'amount', numeric: true, required: true, allowed_types: ['int', 'float'] }]);
		const argumentsValue = [{ name: 'amount', value_type: 'int', value_text: '-7' }];
		await assert.rejects(create(nested, 'missing_action.tres', { resource_kind: 'interaction', id: interactionId }), /reference/);
		await assert.rejects(create(nested, 'missing_argument.tres', { resource_kind: 'interaction', id: interactionId, action_path: action }), /argument/i);
		await assert.rejects(create(nested, 'text_amount.tres', { resource_kind: 'interaction', id: interactionId, action_path: action,
			arguments: [{ name: 'amount', value_type: 'String', value_text: 'bad' }] }), /number|numeric/i);
		const interaction = await create(nested, 'interaction.tres', { resource_kind: 'interaction', id: interactionId,
			action_path: action, requirements_path: group, arguments: argumentsValue });
		check('Interactions require a saved Action and all correctly typed arguments');
		await assert.rejects(create(nested, 'duplicate.tres', { resource_kind: 'action', id: actionId }), /Duplicate/);
		await assert.rejects(create(nested, 'ACTION.tres', { resource_kind: 'action', id: name + '_new' }), /already exists/);
		await assert.rejects(create(nested, 'wrong_type.tres', { resource_kind: 'interaction', id: name + '_new', action_path: condition }), /wrong behavior type/);
		await assert.rejects(create(nested, 'invalid_condition.tres', { resource_kind: 'condition', id: name + '_new', requirement: {
			entity: 'actor', container: 'health', path: ['current'], operator: '>=', value_type: 'int', value_text: '9223372036854775808' } }), /64-bit/);
		check('Invalid schemas, duplicate IDs, and collisions leave no new files');
		const catalog = await loadResourceCatalog(project, executable, () => {});
		assert.ok(catalog.resources.some(e => e.source_path === interaction));
		const runtime = execFileSync(executable, ['--headless', '--path', project, '--script', 'res://Diagnostics/Content/behavior_library_runtime_check.gd', '--', interactionId],
			{ encoding: 'utf8', windowsHide: true, timeout: 30000 });
		assert.match(runtime, /Checks passed: true/); assert.ok(!/^(ERROR|SCRIPT ERROR):/m.test(runtime));
		check('Nested Resources are catalogued and execute through runtime discovery');
		const duplicate = path.join(ownedRoot, 'duplicate.tres');
		await fs.writeFile(duplicate, actionText, { flag: 'wx' });
		await assert.rejects(loadResourceCatalog(project, executable, () => {}), /Duplicate action/);
		const rejectedRuntime = execFileSync(executable, ['--headless', '--path', project, '--script', 'res://Diagnostics/Content/behavior_library_runtime_check.gd', '--', 'expect-duplicate'],
			{ encoding: 'utf8', windowsHide: true, timeout: 30000 });
		assert.match(rejectedRuntime, /Checks passed: true/);
		await fs.unlink(duplicate);
		check('Duplicate IDs anywhere in the Behavior tree are rejected');
		let entry = await get(action);
		let preview = await service.previewDeletion(entry);
		assert.ok(preview.consumers.some(c => c.source_path === interaction));
		await assert.rejects(service.deleteResource(entry, preview, trash), /still referenced/);
		assert.equal(trashCalls.length, 0);
		preview = await service.previewDeletion(await get(group));
		assert.ok(preview.consumers.some(c => c.source_path === interaction));
		preview = await service.previewDeletion(await get(condition));
		assert.ok(preview.consumers.some(c => c.source_path === group));
		await fs.writeFile(groupFile, emptyGroupText);
		check('Action, Condition, and Group references prevent deletion');
		const consumer = path.join(ownedRoot, 'permissions.tres');
		await fs.writeFile(consumer, `[gd_resource type="Resource" script_class="ContainerFragment" load_steps=2 format=3]\n[ext_resource type="Script" path="res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd" id="1"]\n[resource]\nscript = ExtResource("1")\ncontainers = {&"interactions": {"available": [&"${interactionId}"]}}\n`, { flag: 'wx' });
		preview = await service.previewDeletion(await get(interaction));
		assert.ok(preview.consumers.some(c => c.source_path.endsWith('/permissions.tres') && c.kind === 'authored_id'));
		await fs.unlink(consumer);
		const script = path.join(ownedRoot, 'consumer.gd');
		await fs.writeFile(script, `extends RefCounted\nconst INTERACTION = &"${interactionId}"\n`, { flag: 'wx' });
		preview = await service.previewDeletion(await get(interaction));
		assert.ok(preview.consumers.some(c => c.source_path.endsWith('/consumer.gd'))); await fs.unlink(script);
		check('Interaction permissions and ID-only script consumers prevent deletion');
		const bindings = path.join(ownedRoot, 'bindings.tres');
		await fs.writeFile(bindings, `[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://Framework/Infrastructure/API/Configuration/controls_resource.gd" id="1"]\n[resource]\nscript = ExtResource("1")\nbindings = [{"interaction": &"${interactionId}"}]\n`, { flag: 'wx' });
		// Use the saved project's real input schema path to avoid coupling this fixture to a filename.
		const inputSource = await fs.readFile(path.join(project, 'Framework/Content/Configuration/Input/controls.tres'), 'utf8');
		const inputScript = inputSource.match(/path="([^"]+\.gd)"/)[1];
		await fs.writeFile(bindings, (await fs.readFile(bindings, 'utf8')).replace('res://Framework/Infrastructure/API/Configuration/controls_resource.gd', inputScript));
		preview = await service.previewDeletion(await get(interaction));
		assert.ok(preview.consumers.some(c => c.source_path.endsWith('/bindings.tres') && c.kind === 'authored_id'));
		await fs.unlink(bindings);
		check('Input bindings using only an interaction ID prevent deletion');
		entry = await get(condition); preview = await service.previewDeletion(entry); assert.equal(preview.consumers.length, 0);
		await fs.writeFile(script, 'extends RefCounted\n');
		await assert.rejects(service.deleteResource(entry, preview, trash), /directories changed/); await fs.unlink(script);
		preview = await service.previewDeletion(entry);
		await fs.appendFile(path.join(project, condition.slice(6)), '# external edit\r\n');
		await assert.rejects(service.deleteResource(entry, preview, trash), /references changed/);
		check('New consumers and changed file bytes invalidate deletion previews');
		await assert.rejects(service.deleteEmptyCategory(await get(root), trash), /empty category/);
		await assert.rejects(service.deleteEmptyCategory(await get(BEHAVIOR_ROOT), trash), /root cannot/);
		await assert.rejects(checkedBehaviorPath(context, BEHAVIOR_ROOT + '/../Authored', 'directory'), /canonical/);
		check('Nonempty folders, root deletion, and traversal are protected');
		const empty = root + '/Empty'; await service.createCategory(await get(root), 'Empty');
		const hiddenFile = path.join(project, empty.slice(6), '.keep'); await fs.writeFile(hiddenFile, 'hidden');
		await assert.rejects(service.deleteEmptyCategory(await get(empty), trash), /empty category/); await fs.unlink(hiddenFile);
		const linked = path.join(ownedRoot, 'Linked');
		await fs.symlink(path.join(project, 'Diagnostics'), linked, process.platform === 'win32' ? 'junction' : 'dir');
		try { await assert.rejects(checkedBehaviorPath(context, root + '/Linked', 'directory'), /link|junction/); }
		finally { if (process.platform === 'win32') { await fs.rmdir(linked); } else { await fs.unlink(linked); } }
		check('Hidden contents and linked categories cannot be deleted through empty-folder operations');
		const staleCatalog = await current(); const staleEntry = staleCatalog.entries.find(e => e.source_path === nested);
		await fs.appendFile(actionFile, '# changed\r\n');
		await assert.rejects(service.createResource(staleEntry, 'stale.tres', { resource_kind: 'action', id: name + '_stale' }, staleCatalog), /(?:library|catalogue) changed/);
		check('A changed library snapshot prevents stale creation');
		entry = await get(interaction); preview = await service.previewDeletion(entry);
		assert.equal(preview.consumers.length, 0); await service.deleteResource(entry, preview, trash);
		assert.equal(trashCalls.length, 1);
		check('An unreferenced Resource reaches the supplied Trash operation');
	} finally {
		if (created) {
			assert.equal(await fs.realpath(ownedRoot), ownedRoot);
			assert.equal(path.dirname(ownedRoot), path.join(project, BEHAVIOR_ROOT.slice(6)));
			await fs.rm(ownedRoot, { recursive: true });
		}
		for (const [source, bytes] of production) { assert.deepEqual(await fs.readFile(path.join(project, source.slice(6))), bytes); }
	}
	check('Unique diagnostic files cleaned and production Resources unchanged');
	check('Checks passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
