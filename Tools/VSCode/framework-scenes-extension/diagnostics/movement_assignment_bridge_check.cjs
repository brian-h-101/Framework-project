const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash, randomBytes } = require('node:crypto');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const { loadSceneGraph } = require('../out/scene_bridge.js');
const { loadMovementConfigurations } = require('../out/movement_configuration_bridge.js');
const { editScene } = require('../out/scene_editing_bridge.js');

const project = path.resolve(process.argv[2] ?? '');
const executable = process.argv[3];
assert.ok(executable && fs.existsSync(path.join(project, 'project.godot')), 'Expected <project directory> <Godot executable>.');
const configuration = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres';
const adapter = 'res://Framework/Content/Universal/Movement/based/Physics2D/movement_body_2d.gd';
const production = [configuration, adapter, 'res://Framework/Content/Gameplay/Profiles/Movement/Behavior/move.tres',
	'res://Framework/Content/Gameplay/Presentation/Entity/Player/player_2d.tscn', 'res://Framework/Content/Gameplay/Maps/city.tscn'];
const file = resource => path.join(project, resource.slice(6));
const originals = new Map(production.map(resource => [resource, fs.readFileSync(file(resource))]));
const parent = path.join(project, '.godot/diagnostics'); fs.mkdirSync(parent, { recursive: true });
const temporary = fs.mkdtempSync(path.join(parent, 'movement_assignment_bridge_'));
const resource = name => 'res://' + path.relative(project, path.join(temporary, name)).split(path.sep).join('/');
const category = path.join(project, 'Framework/Content/Configuration', 'MovementBridge_' + randomBytes(12).toString('hex'));
assert.ok(!fs.existsSync(category)); fs.mkdirSync(category);
const selected = 'res://' + path.relative(project, path.join(category, 'faster.tres')).split(path.sep).join('/');
const scene = resource('entity.tscn');
const fixture = file(scene);
const source = '[gd_scene load_steps=2 format=3 uid="uid://d3uv0527h7efg"]\r\n\r\n'
	+ `[ext_resource type="Script" path="${adapter}" id="adapter"]\r\n\r\n`
	+ '[node name="Entity" type="Node2D" unique_id=100]\r\nmetadata/entity_key = &"player"\r\n\r\n'
	+ '[node name="Mover" type="CharacterBody2D" parent="." unique_id=101]\r\nscript = ExtResource("adapter")\r\nposition = Vector2(12, 34)\r\n';

function uri(value) {
	const absolute = path.resolve(value); const url = pathToFileURL(absolute);
	return { scheme: 'file', fsPath: absolute, path: decodeURIComponent(url.pathname), toString: () => url.href };
}
function load(name, replacements) {
	const filename = path.resolve(__dirname, '../out', name); const original = createRequire(filename);
	const module = { exports: {} };
	new Function('require', 'module', 'exports', fs.readFileSync(filename, 'utf8'))(
		key => Object.hasOwn(replacements, key) ? replacements[key] : original(key), module, module.exports);
	return module.exports;
}
const report = message => { if (/^(SCRIPT ERROR|ERROR|WARNING):/m.test(message)) { throw new Error(message); } };
const check = label => console.log(`[movement-assignment-bridge] ${label}: true`);

(async () => {
	try {
		fs.writeFileSync(fixture, source);
		fs.writeFileSync(file(selected), originals.get(configuration).toString('utf8').replace('pixels_per_unit = 10.0', 'pixels_per_unit = 20.0'));
		const catalog = await loadMovementConfigurations(project, executable, report);
		const candidate = catalog.find(entry => entry.source_path === selected);
		assert.ok(candidate); assert.equal(candidate.action_id, 'calculate_velocity'); assert.equal(candidate.behavior_id, 'move');
		assert.ok(Object.hasOwn(candidate.dependency_hashes, 'res://Framework/Content/Gameplay/Profiles/Movement/Behavior/move.tres'));
		check('Real catalogue discovers a nested profile and its Behavior dependency');
		const context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
		const errors = []; let cancel = false; let refreshes = 0; let prompts = 0;
		const disposable = () => ({ dispose() {} });
		const api = { __esModule: true,
			Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
			TreeItem: class { constructor(label) { this.label = label; } }, ThemeIcon: class {},
			TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
			EventEmitter: class { event = disposable; fire() {} dispose() {} },
			workspace: { isTrusted: true, workspaceFolders: [{ uri: uri(context.workspaceDirectory) }], textDocuments: [],
				getConfiguration: () => ({ get: () => executable }),
				fs: { readFile: value => fs.promises.readFile(value.fsPath) } },
			window: { async showQuickPick(items, options) {
				prompts++; assert.equal(options.title, 'Assign Movement Configuration');
				assert.equal(options.matchOnDescription, true); assert.equal(options.matchOnDetail, true);
				return cancel ? undefined : items.find(item => item.entry.source_path === selected);
			}, async showInputBox() { throw new Error('Assignment must not ask for a node name.'); },
			async showErrorMessage(message) { errors.push(message); }, async showInformationMessage() {} }
		};
		const { SceneTreeProvider, projectUri } = load('scene_tree_provider.js', { vscode: api });
		const provider = new SceneTreeProvider();
		const { ensureWorkspace } = load('scene_selection.js', { vscode: api, './scene_tree_provider': { projectUri } });
		const { SceneEditingCommands } = load('scene_editing_command.js', { vscode: api,
			'./scene_tree_provider': { projectUri }, './scene_selection': { ensureWorkspace },
			'./scene_property_prompt': load('scene_property_prompt.js', { vscode: api }),
			'./scene_instance_picker': load('scene_instance_picker.js', { vscode: api })
		});
		let graph = await loadSceneGraph(project, executable, scene, report);
		provider.setGraph(context, graph);
		const command = new SceneEditingCommands(provider, { appendLine: report }, async () => {
			refreshes++; graph = await loadSceneGraph(project, executable, scene, report); provider.setGraph(context, graph);
		});
		const body = () => provider.getChildren(provider.getChildren()[0])[0];
		assert.match(provider.getTreeItem(body()).contextValue, /_assign_movement/);
		await command.execute('assign_movement', body());
		assert.deepEqual(errors, []); assert.equal(refreshes, 1); assert.equal(prompts, 1);
		assert.equal(graph.nodes.Mover.movement_configuration_path, selected);
		const saved = fs.readFileSync(fixture, 'utf8');
		assert.ok(saved.includes(`path="${selected}"`));
		assert.ok(saved.includes('uid="uid://d3uv0527h7efg"') && saved.includes('unique_id=101') && saved.includes('position = Vector2(12, 34)'));
		assert.ok(saved.indexOf('script = ') < saved.indexOf('content = '));
		check('Compiled picker command assigns through real Godot and refreshes the saved scene');
		const bytes = fs.readFileSync(fixture);
		cancel = true; await command.execute('assign_movement', body());
		assert.deepEqual(errors, []); assert.equal(refreshes, 1); assert.deepEqual(fs.readFileSync(fixture), bytes);
		check('Cancelled real picker leaves the scene unchanged');
		const hashes = { ...graph.dependency_hashes, ...candidate.dependency_hashes,
			[adapter]: createHash('sha256').update(fs.readFileSync(file(adapter))).digest('hex') };
		await assert.rejects(editScene(project, executable, scene, { operation: 'assign_movement', path: 'Mover',
			movement_configuration: selected, expected_hashes: hashes }, report), /already assigned/i);
		assert.deepEqual(fs.readFileSync(fixture), bytes);
		check('Duplicate backend assignment preserves the saved scene');
		provider.dispose();
		assert.deepEqual(fs.readdirSync(temporary), ['entity.tscn']);
		check('Successful and rejected edits leave no staging files');
	} finally {
		assert.equal(path.dirname(path.resolve(temporary)), path.resolve(parent));
		assert.equal(path.dirname(path.resolve(category)), path.join(project, 'Framework/Content/Configuration'));
		for (const target of [fixture, file(selected)]) { if (fs.existsSync(target)) { fs.unlinkSync(target); } }
		fs.rmdirSync(temporary); fs.rmdirSync(category);
		for (const [resource, bytes] of originals) { assert.deepEqual(fs.readFileSync(file(resource)), bytes); }
		check('Owned fixtures removed and production files preserved');
	}
	check('Checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
