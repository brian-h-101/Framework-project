const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const Module = require('node:module');
const { randomBytes } = require('node:crypto');
const { PROFILES_ROOT } = require('../out/bridges/behavior_library_bridge.js');
const { draftConfiguration, editBehavior } = require('../out/bridges/behavior_editing_bridge.js');
const { loadResourceGraph } = require('../out/bridges/resource_bridge.js');
const { directoryFingerprint } = require('../out/library/library_paths.js');
const { LibraryService } = require('../out/library/library_service.js');

async function checkConfigurationAuthoring(project, executable, name, profile) {
	const diskPath = source => path.join(project, source.slice(6));
	const behavior = PROFILES_ROOT + '/Movement/Behavior/move.tres';
	const destination = profile + '/Shared/dash.tres';
	const typePath = profile + '/Shared/dash_settings.type.tres';
	const firstPreset = profile + '/Shared/short_dash.tres';
	const secondPreset = profile + '/Shared/long_dash.tres';
	const incomplete = diskPath(profile + '_Incomplete');
	const uri = fsPath => ({ scheme: 'file', fsPath });
	const errors = [];
	const opened = [];
	const prompts = [];
	let answers = {};
	let cancelType = true;
	const vscode = {
		Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
		EventEmitter: class { fire() {} },
		TreeItem: class { constructor(label) { this.label = label; } },
		TreeItemCollapsibleState: { Collapsed: 1, None: 0 },
		ThemeIcon: class {},
		workspace: {
			isTrusted: true, workspaceFolders: [{ uri: uri(project) }], textDocuments: [],
			findFiles: async () => [uri(path.join(project, 'project.godot'))],
			getConfiguration: () => ({ get: () => executable }),
		},
		window: {
			async showQuickPick(items, { title }) {
				prompts.push(title);
				if (Object.hasOwn(answers, title)) {
					const label = answers[title];
					if (label === undefined) { return; }
					const choice = items.find(item => (typeof item === 'string' ? item : item.label) === label);
					assert.ok(choice, title + ' must offer ' + label);
					if (title === 'New Configuration Resource — Type') { assert.ok(items.some(item => item.label === 'Movement')); }
					return choice;
				}
				switch (title) {
					case 'New Configuration Resource — Profile':
					case 'New Configuration Type — Profile':
						assert.ok(items.some(item => item.label === 'Movement'));
						assert.ok(!items.some(item => item.label === name + '_Incomplete'));
						return items.find(item => item.label === name);
					case 'New Configuration Resource — Type':
						assert.deepEqual(items.map(item => item.label), ['Movement']);
						return cancelType ? undefined : items[0];
					case 'Movement — Behavior':
						return items.find(item => item.detail === behavior);
					case 'Movement — Velocity Step':
						return items.find(item => item.description === 'calculate_velocity');
					default:
						throw new Error('Unexpected picker: ' + title);
				}
			},
			async showInputBox({ title, prompt, value, validateInput }) {
				prompts.push(title);
				if (Object.hasOwn(answers, title)) {
					const text = answers[title] === null ? value : answers[title];
					if (text !== undefined) { assert.equal(validateInput?.(text), undefined, title); }
					return text;
				}
				if (title === 'New Movement Configuration — Filename') {
					assert.ok(prompt.endsWith('/' + name + '/Shared'));
					assert.ok(validateInput('../dash.tres'));
					assert.equal(validateInput('dash.tres'), undefined);
					return 'dash.tres';
				}
				assert.equal(title, 'Movement — Pixels Per Unit');
				return '12';
			},
			showErrorMessage: async error => errors.push(error),
			showTextDocument: async document => opened.push(document.fsPath),
		}
	};
	const originalLoad = Module._load;
	let ConfigurationCommands, ResourceTreeProvider;
	try {
		Module._load = function (id, ...args) {
			return id === 'vscode' ? vscode : originalLoad.call(this, id, ...args);
		};
		({ ConfigurationCommands } = require('../out/commands/configuration_editing_command.js'));
		({ ResourceTreeProvider } = require('../out/tree/resource_tree_provider.js'));
	} finally { Module._load = originalLoad; }
	const report = message => console.error(message);
	const provider = new ResourceTreeProvider();
	const commands = new ConfigurationCommands(provider, { appendLine: report }, async () => {});
	await fs.mkdir(incomplete);
	await fs.mkdir(path.join(incomplete, 'Behavior'));
	try {
		await commands.execute('new_configuration');
		assert.deepEqual(errors, []);
		assert.deepEqual(prompts, ['New Configuration Resource — Profile', 'New Configuration Resource — Type']);
		assert.deepEqual(await fs.readdir(diskPath(profile + '/Shared')), []);

		cancelType = false;
		await commands.execute('new_configuration');
		assert.deepEqual(errors, []);
		assert.deepEqual(opened, [diskPath(destination)]);
		const graph = await loadResourceGraph(project, executable, report, destination, { mode: 'browse' });
		const movement = graph.nodes[destination];
		assert.equal(movement.configuration_type, 'movement');
		assert.equal(movement.data.children.find(item => item.label === 'Behavior').value_text, behavior);
		assert.equal(movement.data.children.find(item => item.label === 'Velocity Step').value_text, 'calculate_velocity');
		assert.equal(Number(movement.data.children.find(item => item.label === 'Pixels Per Unit').value_text), 12);
		const behaviorGraph = await loadResourceGraph(project, executable, report, behavior, { mode: 'browse' });
		const request = {
			operation: 'draft_movement_configuration', expected_hashes: behaviorGraph.dependency_hashes,
			movement_behavior_path: behavior, velocity_step_id: 'calculate_velocity', pixels_per_unit: 12
		};
		await assert.rejects(draftConfiguration(project, executable, profile + '/Behavior/invalid.tres',
			{ ...request, expected_parent: await directoryFingerprint(diskPath(profile + '/Behavior')) }, report),
		/directly in Content\/Gameplay\/Profiles\/<Profile>\/Shared/);
		await assert.rejects(draftConfiguration(project, executable, destination,
			{ ...request, expected_parent: await directoryFingerprint(diskPath(profile + '/Shared')) }, report), /already exists/);
		assert.deepEqual(await fs.readdir(diskPath(profile + '/Shared')), ['dash.tres']);
		console.log('[profiles] Configuration picker discovers eligible profiles and saves a reusable Movement configuration in the selected Shared folder');

		answers = {
			'New Configuration Type — Label': 'Dash Settings',
			'New Configuration Type — ID': null,
			'Configuration Field — Name': 'distance',
			'Configuration Field — Type for distance': 'float',
			'Configuration Field — Default for distance': '4.5',
			'New Configuration Type — 1 field(s)': 'Save Type',
		};
		const typeAnswers = { ...answers };
		answers['New Configuration Type — 1 field(s)'] = undefined;
		await commands.execute('new_configuration_type');
		assert.deepEqual(await fs.readdir(diskPath(profile + '/Shared')), ['dash.tres']);
		answers = typeAnswers;
		await commands.execute('new_configuration_type');
		assert.deepEqual(errors, []);
		assert.equal(opened.at(-1), diskPath(typePath));
		const typeGraph = await loadResourceGraph(project, executable, report, typePath, { mode: 'browse' });
		assert.equal(typeGraph.nodes[typePath].configuration_type, 'custom_type');
		const schemaBytes = await fs.readFile(diskPath(typePath));
		const typeRequest = {
			operation: 'draft_configuration_type', expected_parent: await directoryFingerprint(diskPath(profile + '/Shared')),
			type_id: 'dash_settings', type_label: 'Dash Settings', type_fields: [{ name: 'distance', type: 'float', value_text: '4.5' }]
		};
		await assert.rejects(draftConfiguration(project, executable, typePath, typeRequest, report), /with ID 'dash_settings' already exists/);
		await assert.rejects(draftConfiguration(project, executable, profile + '/Shared/duplicate.type.tres',
			{ ...typeRequest, type_id: 'duplicate', type_fields: [...typeRequest.type_fields, ...typeRequest.type_fields] }, report),
		/Duplicate configuration field: distance/);

		answers = {
			'New Configuration Resource — Type': 'Dash Settings',
			'New Dash Settings Configuration — Filename': 'short_dash.tres',
			'Dash Settings — distance': null,
		};
		await commands.execute('new_configuration');
		assert.equal(opened.at(-1), diskPath(firstPreset));
		answers['New Dash Settings Configuration — Filename'] = 'long_dash.tres';
		answers['Dash Settings — distance'] = '9.25';
		await commands.execute('new_configuration');
		assert.deepEqual(errors, []);
		assert.equal(opened.at(-1), diskPath(secondPreset));
		const inspectPreset = async source => {
			const graph = await loadResourceGraph(project, executable, report, source, { mode: 'browse' });
			const resource = graph.nodes[source];
			assert.equal(resource.configuration_type, 'custom');
			assert.equal(resource.data.children.find(row => row.label === 'Type Resource').value_text, typePath);
			assert.equal(graph.dependency_hashes[typePath], typeGraph.dependency_hashes[typePath]);
			const values = resource.data.children.find(row => row.label === 'Values');
			return { graph, distance: Number(values.children.find(row => row.label === 'distance').value_text) };
		};
		const short = await inspectPreset(firstPreset);
		assert.equal(short.distance, 4.5);
		assert.equal((await inspectPreset(secondPreset)).distance, 9.25);
		provider.setGraph(uri(project), short.graph);
		const root = provider.getChildren()[0];
		const values = provider.getChildren(root).find(row => provider.getTreeItem(row).label === 'Values');
		const distance = provider.getChildren(values)[0];
		assert.match(provider.getTreeItem(distance).contextValue, /\|configuration_value\b/);

		const shortBytes = await fs.readFile(diskPath(firstPreset));
		const longBytes = await fs.readFile(diskPath(secondPreset));
		const editRequest = { operation: 'set_custom_configuration_field', expected_hashes: short.graph.dependency_hashes,
			field: 'distance', value_text: 'invalid' };
		await assert.rejects(editBehavior(project, executable, firstPreset, editRequest, report), /distance: Expected a valid floating-point value/);
		answers = { 'Edit Configuration Value — distance': undefined };
		await commands.execute('set_custom_configuration_field', distance);
		assert.deepEqual(await fs.readFile(diskPath(firstPreset)), shortBytes);
		answers['Edit Configuration Value — distance'] = '6';
		await commands.execute('set_custom_configuration_field', distance);
		assert.deepEqual(errors, []);
		assert.equal((await inspectPreset(firstPreset)).distance, 6);
		assert.deepEqual(await fs.readFile(diskPath(secondPreset)), longBytes);
		assert.deepEqual(await fs.readFile(diskPath(typePath)), schemaBytes);
		console.log('[profiles] Authored a type, created two presets, and edited a typed field without changing the type or the other preset');
	} finally {
		for (const source of [destination, firstPreset, secondPreset, typePath]) {
			await fs.unlink(diskPath(source)).catch(error => { if (error.code !== 'ENOENT') { throw error; } });
		}
		await fs.rmdir(path.join(incomplete, 'Behavior'));
		await fs.rmdir(incomplete);
	}
}

async function main() {
	const [directory, executable] = process.argv.slice(2);
	assert.ok(directory && executable, 'Expected a Godot project and executable.');
	const project = path.resolve(directory);
	const service = new LibraryService({ projectDirectory: project, workspaceDirectory: project },
		executable, message => console.error(message));
	const name = 'DiagnosticProfile_' + randomBytes(8).toString('hex');
	const source = PROFILES_ROOT + '/' + name;
	const diskPath = source => path.join(project, source.slice(6));
	const entry = async source => {
		const catalogue = await service.profileCatalogue();
		const selected = catalogue.entries.find(item => item.source_path === source);
		assert.ok(selected, source);
		return selected;
	};
	const files = new Set();
	const write = async (source, text) => {
		await fs.writeFile(diskPath(source), text, { flag: 'wx' });
		files.add(source);
	};
	const unlink = async source => {
		await fs.unlink(diskPath(source));
		files.delete(source);
	};
	const profileRoot = await entry(PROFILES_ROOT);
	await assert.rejects(service.createProfile(profileRoot, '../Escape'), /leading dot|reserved/);
	assert.equal(await service.createProfile(profileRoot, name), source);
	try {
		assert.deepEqual((await fs.readdir(diskPath(source))).sort(), ['Behavior', 'Executor', 'Shared']);
		await assert.rejects(service.createProfile(await entry(PROFILES_ROOT), name.toLowerCase()), /already exists/);
		await assert.rejects(service.previewProfileDeletion(profileRoot), /directly under Profiles/);
		assert.ok((await service.catalogue()).entries.some(item => item.source_path === source + '/Behavior'));
		console.log('[profiles] Creation and Behavior discovery verified');
		await checkConfigurationAuthoring(project, executable, name, source);

		const sidecar = 'uid://ck0guw8wj5lqm';
		const executorId = name.toLowerCase();
		const executor = source + '/Executor/probe_executor.gd';
		await write(executor, 'extends RefCounted\nconst BEHAVIOR_ID := &"' + executorId + '"\n');
		await write(executor + '.uid', sidecar + '\n');
		const settings = source + '/Shared/settings.tres';
		await write(settings, '[gd_resource type="Resource" format=3]\n\n[resource]\n');
		await write(source + '/Behavior/internal.gd', 'extends RefCounted\nconst SETTINGS = preload("' + settings + '")\n');
		await write(source + '/Shared/.note', '');
		const relativeRef = PROFILES_ROOT + '/' + name + '_relative.gd';
		const uidRef = PROFILES_ROOT + '/' + name + '_uid.gd';
		const executorRef = PROFILES_ROOT + '/' + name + '_executor.tres';
		await write(relativeRef, 'extends RefCounted\nconst SETTINGS = preload("' + name + '/Shared/settings.tres")\n');
		await write(uidRef, 'extends RefCounted\nconst SOURCE = "' + sidecar + '"\n');
		const schemas = 'res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/';
		await write(executorRef, '[gd_resource type="Resource" format=3]\n'
			+ '[ext_resource type="Script" path="' + schemas + 'behavior_resource.gd" id="1"]\n'
			+ '[ext_resource type="Script" path="' + schemas + 'action_step_resource.gd" id="2"]\n'
			+ '[sub_resource type="Resource" id="Step"]\nscript = ExtResource("2")\nexecutor_id = &"' + executorId + '"\n'
			+ '[resource]\nscript = ExtResource("1")\nid = &"probe"\nsteps = Array[Resource]([SubResource("Step")])\n');
		const profile = await entry(source);
		const preview = await service.previewProfileDeletion(profile);
		assert.equal(preview.file_count, 5);
		assert.deepEqual(preview.consumers.map(item => item.source_path).sort(), [relativeRef, uidRef, executorRef].sort());
		const trash = [];
		const move = async target => trash.push(target);
		await assert.rejects(service.deleteProfile(profile, preview, move), /dependency checking/);
		assert.deepEqual(trash, []);
		for (const consumer of [relativeRef, uidRef, executorRef]) { await unlink(consumer); }
		console.log('[profiles] Outside path, UID, and nested executor references block deletion');

		const clear = await service.previewProfileDeletion(profile);
		assert.deepEqual(clear.consumers, []);
		await fs.appendFile(diskPath(source + '/Shared/.note'), 'Changed while confirming');
		await assert.rejects(service.deleteProfile(profile, clear, move), /references changed/);
		assert.deepEqual(trash, []);
		await service.deleteProfile(profile, await service.previewProfileDeletion(profile), move);
		assert.deepEqual(trash, [diskPath(source)]);
		console.log('[profiles] Whole-profile preview includes hidden files and is revalidated before Trash');
	} finally {
		for (const file of files) { await unlink(file); }
		for (const folder of ['Behavior', 'Executor', 'Shared']) { await fs.rmdir(diskPath(source + '/' + folder)); }
		await fs.rmdir(diskPath(source));
	}
	assert.ok(!(await service.profileCatalogue()).entries.some(item => item.source_path === source));
	console.log('[profiles] Checks passed');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
