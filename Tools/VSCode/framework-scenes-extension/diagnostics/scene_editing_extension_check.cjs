const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { createHash } = require('node:crypto');
const { pathToFileURL } = require('node:url');

function load(file, mocks) {
	const filename = path.resolve(__dirname, '../out', file);
	const original = createRequire(filename);
	const module = { exports: {} };
	new Function('require', 'module', 'exports', fs.readFileSync(filename, 'utf8'))(
		name => Object.hasOwn(mocks, name) ? mocks[name] : original(name), module, module.exports);
	return module.exports;
}
function uri(file) {
	const absolute = path.resolve(file); const url = pathToFileURL(absolute);
	return { scheme: 'file', path: decodeURIComponent(url.pathname), fsPath: absolute, toString: () => url.href };
}
const project = path.resolve(__dirname, '../../../../framework-project');
const context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
const source = 'res://Scenes/map.tscn';
const template = 'res://Scenes/template.tscn';
const interaction = 'res://Framework/Content/Behavior/Interaction/strike.tres';
const component = 'res://Framework/Content/God/Interaction/interaction_behavior.gd';
const automationComponent = 'res://Framework/Content/God/Interaction/automation_behavior.gd';
const automation = 'res://Framework/Content/Behavior/Automation/auto_strike.tres';
const existingInteraction = 'res://Framework/Content/Behavior/Interaction/existing.tres';
const action = 'res://Framework/Content/Behavior/Action/change_health.tres';
const movement = 'res://Framework/Content/Configuration/Movement/faster.tres';
const previousMovement = 'res://Framework/Content/Configuration/Movement/player_movement.tres';
const movementScript = 'res://Framework/Content/God/Movement/movement_2d.gd';
const movementAction = 'res://Framework/Content/Behavior/Action/move.tres';
const nodeScript = 'res://Scripts/node_script.gd';
const baseScript = 'res://Scripts/base_script.gd';
const resourceUri = resource => uri(path.join(project, resource.slice(6)));
const buffers = new Map([[source, Buffer.from('map bytes')], [template, Buffer.from('template bytes')]]);
for (const resource of [interaction, component, existingInteraction, automationComponent, automation]) { buffers.set(resource, Buffer.from(resource)); }
for (const resource of [movement, previousMovement, movementScript, movementAction]) { buffers.set(resource, Buffer.from(resource)); }
for (const resource of [nodeScript, baseScript]) { buffers.set(resource, Buffer.from(resource)); }
const hash = resource => createHash('sha256').update(buffers.get(resource)).digest('hex');
function graph(resource = source) {
	const node = (nodePath, children, extras = {}) => ({
		path: nodePath, name: nodePath === '.' ? 'Map' : nodePath.split('/').pop(), type: 'Node2D',
		source_path: resource, source_node_path: nodePath, structural_scene: resource, structural_node_path: nodePath,
		instance_boundary: '', script_path: '', instance_path: '', base_scene_path: '', references: {}, children,
		can_add: true, can_rename: nodePath !== '.', can_remove: nodePath !== '.',
		is_entity: false,
		interaction_resource_path: '',
		interaction_id: '',
		movement_configuration_path: '', can_assign_movement: false,
		has_script: false, script_source_path: '', can_attach_script: true, can_remove_script: false,
		...extras
	});
	return { version: 2, source_path: resource, root: '.', dependencies: [resource],
		dependency_hashes: { [resource]: hash(resource) },
		nodes: { '.': node('.', ['Props']), Props: node('Props', ['Props/Lamp']), 'Props/Lamp': node('Props/Lamp', []) }
	};
}
let answers = [];
let afterPrompt = () => {};
let writes = [];
let refreshes = 0;
const errors = [];
const information = [];
const defaultCatalog = { version: 1, resources: [
	{ id: 'strike', kind: 'interaction', source_path: interaction },
	{ id: 'change_health', kind: 'action', source_path: action }
] };
let catalog = defaultCatalog;
let catalogError;
let editError;
let catalogLoads = 0;
let movementCatalogError;
let movementCatalogEmpty = false;
let scriptInspectionError;
const api = {
	__esModule: true,
	Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
	EventEmitter: class { event = () => ({ dispose() {} }); fire() {} dispose() {} },
	TreeItem: class { constructor(label) { this.label = label; } },
	ThemeIcon: class { constructor(id) { this.id = id; } },
	TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
	workspace: {
		isTrusted: true, workspaceFolders: [{ uri: uri(context.workspaceDirectory) }], textDocuments: [],
		getConfiguration: () => ({ get: () => 'godot-console.exe' }),
		fs: { async readFile(file) {
			const relative = path.relative(project, file.fsPath).split(path.sep).join('/');
			return buffers.get('res://' + relative);
		} },
		async findFiles(pattern) { return pattern === '**/*.gd' ? [resourceUri(nodeScript)] : [resourceUri(template)]; },
		asRelativePath: file => path.relative(project, file.fsPath)
	},
	window: {
		async showQuickPick(items, options) { const answer = answers.shift(); afterPrompt(); return typeof answer === 'function' ? answer(items, options) : answer; },
		async showInputBox(options) { const answer = answers.shift(); afterPrompt(); return typeof answer === 'function' ? answer(options) : answer; },
		async showWarningMessage() { const answer = answers.shift(); afterPrompt(); return answer; },
		async showErrorMessage(message) { errors.push(message); }, async showInformationMessage(message) { information.push(message); }
	}
};
const workspace = {
	validateResourcePath(resource, extension) {
		if (!resource.startsWith('res://') || resource.includes('..') || (extension && !resource.endsWith(extension))) { throw new Error('Invalid resource path.'); }
	},
	isInside: (root, file) => !path.relative(root, file).startsWith('..'),
	async scenePathInProject(_context, file) {
		const relative = path.relative(project, file);
		if (relative.startsWith('..') || !relative.endsWith('.tscn')) { throw new Error('Choose the same Godot project.'); }
		return 'res://' + relative.split(path.sep).join('/');
	},
	async resolveProjectContext() { return context; }
};
const { SceneTreeProvider, projectUri } = load('scene_tree_provider.js', { vscode: api });
const provider = new SceneTreeProvider();
const selection = load('scene_selection.js', { vscode: api, './scene_tree_provider': { projectUri } });
const { SceneEditingCommands } = load('scene_editing_command.js', {
	vscode: api, './project_context': workspace,
	'./scene_tree_provider': { projectUri }, './scene_selection': selection,
	'./scene_bridge': { async loadSceneGraph() { return graph(template); } },
	'./resource_catalog_bridge': { async loadResourceCatalog() {
		catalogLoads++;
		if (catalogError) { throw new Error(catalogError); }
		return structuredClone(catalog);
	} },
	'./movement_configuration_bridge': { async loadMovementConfigurations() {
		if (movementCatalogError) { throw new Error(movementCatalogError); }
		return movementCatalogEmpty ? [] : [{ source_path: movement, action_id: 'move', behavior_id: 'movement_2d',
			dependency_hashes: { [movement]: hash(movement), [movementAction]: hash(movementAction) } }];
	} },
	'./scene_editing_bridge': {
		async inspectScript(_project, _executable, script) {
			if (scriptInspectionError) { throw new Error(scriptInspectionError); }
			return { script_path: script, base_type: 'Node2D', dependency_hashes: { [script]: hash(script), [baseScript]: hash(baseScript) } };
		},
		async nodeTypes() { return ['Node', 'Node2D', 'Node3D', 'Marker2D']; },
		async editScene(_project, _executable, file, request) {
			writes.push(structuredClone(request));
			if (editError) { throw new Error(editError); }
			return { scene_path: file, operation: request.operation, path: request.path, new_path: request.name ?? '', content_hash: hash(source) };
		}
	}
});
const output = { appendLine() {} };
const commands = new SceneEditingCommands(provider, output, async () => { refreshes++; });
function select(value = graph()) {
	provider.setGraph(context, value);
	const root = provider.getChildren()[0]; const props = provider.getChildren(root)[0];
	return { root, props, lamp: provider.getChildren(props)[0] };
}
function selectEntity(value = graph()) {
	value.nodes.Props.is_entity = true;
	return select(value).props;
}
function selectMovement(value = graph()) {
	Object.assign(value.nodes['Props/Lamp'], { type: 'CharacterBody2D', script_path: movementScript,
		can_assign_movement: true, movement_configuration_path: previousMovement });
	return select(value).lamp;
}
async function check(label, operation) { await operation(); console.log(`[scene-editing-extension] ${label}: true`); }

(async () => {
	await check('Native node creation routes type, parent and dependency hashes', async () => {
		answers = ['Marker2D', 'Point 雨']; await commands.execute('add_node', select().props);
		assert.equal(writes.at(-1).node_type, 'Marker2D'); assert.equal(writes.at(-1).path, 'Props');
		assert.equal(writes.at(-1).expected_hashes[source], hash(source)); assert.equal(refreshes, 1);
	});
	await check('Searchable instance selection includes candidate dependency hashes', async () => {
		answers = [items => items[0], 'Placement']; await commands.execute('add_instance', select().root);
		assert.equal(writes.at(-1).instance_scene, template); assert.equal(writes.at(-1).expected_hashes[template], hash(template));
	});
	await check('Rename and remove use the selected nested node', async () => {
		answers = ['Renamed']; await commands.execute('rename', select().lamp);
		assert.equal(writes.at(-1).path, 'Props/Lamp'); assert.equal(writes.at(-1).name, 'Renamed');
		answers = ['Remove Node']; await commands.execute('remove', select().lamp);
		assert.equal(writes.at(-1).operation, 'remove');
	});
	await check('Every cancelled dialog leaves files untouched', async () => {
		const before = writes.length;
		for (const input of [[], ['Node2D']]) { answers = input.slice(); await commands.execute('add_node', select().props); }
		for (const input of [[], [items => items[0]]]) { answers = input.slice(); await commands.execute('add_instance', select().root); }
		answers = []; await commands.execute('rename', select().lamp);
		answers = []; await commands.execute('remove', select().lamp);
		assert.equal(writes.length, before);
	});
	await check('Roots, borrowed nodes and stale tree items cannot be renamed or removed', async () => {
		const before = writes.length;
		await commands.execute('rename', select().root);
		await commands.execute('remove', select().root);
		const borrowed = graph(); Object.assign(borrowed.nodes['Props/Lamp'], { structural_scene: template, can_add: false, can_rename: false, can_remove: false });
		await commands.execute('rename', select(borrowed).lamp);
		const old = select().lamp; provider.clear(); await commands.execute('rename', old);
		assert.equal(writes.length, before);
	});
	await check('Dirty dependencies and untrusted workspaces reject edits', async () => {
		const before = writes.length;
		api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(source) }];
		await commands.execute('rename', select().lamp); api.workspace.textDocuments = [];
		api.workspace.isTrusted = false; await commands.execute('rename', select().lamp); api.workspace.isTrusted = true;
		assert.equal(writes.length, before);
	});
	await check('Changes and dirty candidate scenes during dialogs reject pending writes', async () => {
		const before = writes.length; const original = buffers.get(source);
		answers = ['Other']; afterPrompt = () => buffers.set(source, Buffer.from('changed during prompt'));
		await commands.execute('rename', select().lamp); buffers.set(source, original);
		answers = [items => items[0], 'Other']; afterPrompt = () => { api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(template) }]; };
		await commands.execute('add_instance', select().root);
		api.workspace.textDocuments = []; afterPrompt = () => {};
		assert.equal(writes.length, before); assert.ok(errors.some(error => /dependency changed/i.test(error)));
	});
	await check('Refreshed selection and removed workspace cancel pending writes', async () => {
		const before = writes.length;
		answers = ['Other']; afterPrompt = () => provider.clear(); await commands.execute('rename', select().lamp);
		const folders = api.workspace.workspaceFolders;
		answers = ['Other']; afterPrompt = () => { api.workspace.workspaceFolders = []; };
		await commands.execute('rename', select().lamp);
		api.workspace.workspaceFolders = folders; afterPrompt = () => {};
		assert.equal(writes.length, before);
	});
	await check('One structural edit dialog runs at a time', async () => {
		const before = writes.length; const element = select().lamp; answers = [];
		await Promise.all([commands.execute('rename', element), commands.execute('remove', element)]);
		assert.equal(writes.length, before);
	});
	await check('Attachment picker routes Interactions with entity context and dependency hashes', async () => {
		const before = writes.length; const previousRefreshes = refreshes;
		const entity = selectEntity();
		assert.match(provider.getTreeItem(entity).contextValue, /_attach_behavior/);
		answers = [(items, options) => {
			assert.equal(items.length, 1); assert.equal(items[0].description, 'interaction: strike');
			assert.equal(items[0].label, 'strike.tres'); assert.equal(items[0].detail, interaction);
			assert.equal(options.matchOnDescription, true); assert.equal(options.matchOnDetail, true);
			return items[0];
		}, options => { assert.equal(options.value, 'StrikeBehavior'); return options.value; }];
		await commands.execute('attach_behavior', entity);
		assert.equal(writes.length, before + 1);
		assert.equal(writes.at(-1).operation, 'attach_behavior'); assert.equal(writes.at(-1).path, 'Props');
		assert.equal(writes.at(-1).name, 'StrikeBehavior'); assert.equal(writes.at(-1).interaction_resource, interaction);
		for (const resource of [source, interaction, component]) {
			assert.equal(writes.at(-1).expected_hashes[resource], hash(resource));
		}
		assert.equal(refreshes, previousRefreshes + 1);
	});
	await check('Automation picker selects the activation component and guarded Resource', async () => {
		catalog = { version: 1, resources: [{ id: 'auto_strike', kind: 'automation', source_path: automation }] };
		const before = writes.length;
		answers = [items => { assert.equal(items[0].description, 'automation: auto_strike'); return items[0]; }, 'AutoStrikeBehavior'];
		await commands.execute('attach_behavior', selectEntity());
		assert.equal(writes.length, before + 1);
		assert.equal(writes.at(-1).automation_resource, automation);
		assert.equal(writes.at(-1).interaction_resource, undefined);
		assert.equal(writes.at(-1).expected_hashes[automationComponent], hash(automationComponent));
		assert.equal(writes.at(-1).expected_hashes[automation], hash(automation));
		catalog = defaultCatalog;
	});
	await check('Non-entity, borrowed, and stale rows cannot start attachment', async () => {
		const before = writes.length; const previousLoads = catalogLoads;
		const plain = select().props;
		assert.doesNotMatch(provider.getTreeItem(plain).contextValue, /_attach_behavior/);
		await commands.execute('attach_behavior', plain);
		const borrowed = graph(); Object.assign(borrowed.nodes.Props, { can_add: false, is_entity: true });
		const locked = select(borrowed).props;
		assert.doesNotMatch(provider.getTreeItem(locked).contextValue, /_attach_behavior/);
		await commands.execute('attach_behavior', locked);
		const stale = selectEntity(); provider.clear(); await commands.execute('attach_behavior', stale);
		assert.equal(writes.length, before); assert.equal(catalogLoads, previousLoads);
	});
	await check('Cancelling either attachment prompt leaves the scene untouched', async () => {
		const before = writes.length; const previousRefreshes = refreshes;
		for (const input of [[], [items => items[0]]]) {
			answers = input.slice(); await commands.execute('attach_behavior', selectEntity());
		}
		assert.equal(writes.length, before); assert.equal(refreshes, previousRefreshes);
	});
	await check('Attachment guards owned resources and excludes nested entity attachments', async () => {
		const value = graph(); const lamp = value.nodes['Props/Lamp'];
		Object.assign(lamp, { interaction_id: 'existing', interaction_resource_path: existingInteraction,
			children: ['Props/Lamp/Nested'] });
		value.nodes['Props/Lamp/Nested'] = { ...lamp, path: 'Props/Lamp/Nested', name: 'Nested',
			children: [], is_entity: true, interaction_id: 'nested', interaction_resource_path: 'res://Nested/only.tres' };
		answers = [items => items[0], 'StrikeBehavior'];
		await commands.execute('attach_behavior', selectEntity(value));
		assert.equal(writes.at(-1).expected_hashes[existingInteraction], hash(existingInteraction));
		assert.equal(Object.hasOwn(writes.at(-1).expected_hashes, 'res://Nested/only.tres'), false);
	});
	await check('Changed Interaction or component bytes reject pending attachment', async () => {
		const before = writes.length;
		for (const resource of [interaction, component]) {
			const original = buffers.get(resource);
			try {
				answers = [items => items[0], 'StrikeBehavior'];
				afterPrompt = () => buffers.set(resource, Buffer.from('changed during attachment'));
				await commands.execute('attach_behavior', selectEntity());
			} finally { buffers.set(resource, original); afterPrompt = () => {}; }
		}
		assert.equal(writes.length, before);
	});
	await check('Unsaved Interaction or component text blocks attachment', async () => {
		const before = writes.length;
		try {
			api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(component) }];
			answers = [items => items[0], 'StrikeBehavior']; await commands.execute('attach_behavior', selectEntity());
			api.workspace.textDocuments = [];
			afterPrompt = () => { api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(interaction) }]; };
			answers = [items => items[0], 'StrikeBehavior']; await commands.execute('attach_behavior', selectEntity());
		} finally { api.workspace.textDocuments = []; afterPrompt = () => {}; }
		assert.equal(writes.length, before);
	});
	await check('An Interaction from another Godot project is rejected', async () => {
		const before = writes.length; const previousResolve = workspace.resolveProjectContext;
		try {
			workspace.resolveProjectContext = async file => path.relative(file, resourceUri(interaction).fsPath) === ''
				? { ...context, projectDirectory: path.join(project, 'Nested') } : context;
			answers = [items => items[0], 'StrikeBehavior']; await commands.execute('attach_behavior', selectEntity());
		} finally { workspace.resolveProjectContext = previousResolve; }
		assert.equal(writes.length, before); assert.match(errors.at(-1), /same Godot project/);
	});
	await check('Selection, workspace, and trust changes during attachment prevent writes', async () => {
		const before = writes.length; const folders = api.workspace.workspaceFolders;
		try {
			for (const change of [() => provider.clear(), () => { api.workspace.workspaceFolders = []; },
				() => { api.workspace.isTrusted = false; }]) {
				api.workspace.workspaceFolders = folders; api.workspace.isTrusted = true;
				afterPrompt = change; answers = [items => items[0], 'StrikeBehavior'];
				await commands.execute('attach_behavior', selectEntity());
			}
		} finally { api.workspace.workspaceFolders = folders; api.workspace.isTrusted = true; afterPrompt = () => {}; }
		assert.equal(writes.length, before);
	});
	await check('Catalogue failures and empty Interaction catalogues produce no edits', async () => {
		const before = writes.length;
		try {
			catalogError = 'Catalogue probe failed'; answers = []; await commands.execute('attach_behavior', selectEntity());
			assert.equal(errors.at(-1), catalogError);
			catalogError = undefined; catalog = { version: 1, resources: defaultCatalog.resources.filter(entry => entry.kind === 'action') };
			await commands.execute('attach_behavior', selectEntity());
			assert.equal(information.at(-1), 'No Interaction or Automation resources are available.');
		} finally { catalogError = undefined; catalog = defaultCatalog; }
		assert.equal(writes.length, before);
	});
	await check('Backend attachment rejection is reported without refreshing the tree', async () => {
		const previousRefreshes = refreshes;
		try {
			editError = "Interaction 'strike' is already attached at Props/StrikeBehavior.";
			answers = [items => items[0], 'AnotherStrike']; await commands.execute('attach_behavior', selectEntity());
			assert.equal(errors.at(-1), editError); assert.equal(refreshes, previousRefreshes);
		} finally { editError = undefined; }
	});
	await check('Movement picker routes configuration, body and complete dependency hashes without a node name', async () => {
		const before = writes.length; const previousRefreshes = refreshes; const body = selectMovement();
		assert.match(provider.getTreeItem(body).contextValue, /_assign_movement/);
		assert.match(provider.getTreeItem(body).tooltip, /player_movement.tres/);
		answers = [(items, options) => {
			assert.equal(items.length, 1); assert.equal(items[0].label, 'faster.tres');
			assert.equal(items[0].description, 'move'); assert.match(items[0].detail, /movement_2d/);
			assert.equal(options.matchOnDescription, true); assert.equal(options.matchOnDetail, true);
			return items[0];
		}];
		await commands.execute('assign_movement', body);
		assert.equal(writes.length, before + 1); assert.equal(writes.at(-1).path, 'Props/Lamp');
		assert.equal(writes.at(-1).operation, 'assign_movement'); assert.equal(writes.at(-1).movement_configuration, movement);
		assert.equal(writes.at(-1).name, undefined); assert.equal(answers.length, 0);
		for (const dependency of [source, movement, previousMovement, movementScript, movementAction]) {
			assert.equal(writes.at(-1).expected_hashes[dependency], hash(dependency));
		}
		assert.equal(refreshes, previousRefreshes + 1);
	});
	await check('Movement cancellation, unrelated nodes and borrowed bodies produce no writes', async () => {
		const before = writes.length; answers = []; await commands.execute('assign_movement', selectMovement());
		await commands.execute('assign_movement', select().props);
		const value = graph(); const body = selectMovement(value); value.nodes['Props/Lamp'].can_assign_movement = false;
		assert.doesNotMatch(provider.getTreeItem(body).contextValue, /_assign_movement/);
		await commands.execute('assign_movement', body); assert.equal(writes.length, before);
	});
	await check('Changed and dirty movement configurations, scripts and Actions reject pending writes', async () => {
		const before = writes.length;
		for (const dependency of [movement, previousMovement, movementScript, movementAction]) {
			const saved = buffers.get(dependency);
			try {
				answers = [items => items[0]]; afterPrompt = () => buffers.set(dependency, Buffer.from('changed'));
				await commands.execute('assign_movement', selectMovement());
				buffers.set(dependency, saved);
				answers = [items => items[0]]; afterPrompt = () => { api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(dependency) }]; };
				await commands.execute('assign_movement', selectMovement());
			} finally { buffers.set(dependency, saved); api.workspace.textDocuments = []; afterPrompt = () => {}; }
		}
		assert.equal(writes.length, before);
	});
	await check('Movement picker rejects stale selection, lost trust and foreign project dependencies', async () => {
		const before = writes.length; const folders = api.workspace.workspaceFolders;
		try {
			for (const change of [() => provider.clear(), () => { api.workspace.isTrusted = false; }, () => { api.workspace.workspaceFolders = []; }]) {
				api.workspace.isTrusted = true; api.workspace.workspaceFolders = folders;
				answers = [items => items[0]]; afterPrompt = change;
				await commands.execute('assign_movement', selectMovement());
			}
		} finally { api.workspace.isTrusted = true; api.workspace.workspaceFolders = folders; afterPrompt = () => {}; }
		const resolve = workspace.resolveProjectContext;
		try {
			workspace.resolveProjectContext = async file => file.endsWith('move.tres')
				? { ...context, projectDirectory: path.join(project, 'nested') } : context;
			answers = [items => items[0]]; await commands.execute('assign_movement', selectMovement());
		} finally { workspace.resolveProjectContext = resolve; }
		assert.equal(writes.length, before);
	});
	await check('Movement catalogue and backend errors are reported without refreshing', async () => {
		const previousRefreshes = refreshes;
		try {
			movementCatalogError = 'Movement catalogue failed'; await commands.execute('assign_movement', selectMovement());
			assert.equal(errors.at(-1), movementCatalogError);
			movementCatalogError = undefined; movementCatalogEmpty = true;
			await commands.execute('assign_movement', selectMovement()); assert.match(information.at(-1), /No other movement configurations/);
			movementCatalogEmpty = false; editError = 'Assignment rejected'; answers = [items => items[0]];
			await commands.execute('assign_movement', selectMovement()); assert.equal(errors.at(-1), editError);
		} finally { movementCatalogError = undefined; movementCatalogEmpty = false; editError = undefined; }
		assert.equal(refreshes, previousRefreshes);
	});
	await check('Attach Script searches project files, inspects compatibility and forwards inherited hashes', async () => {
		const before = writes.length; const selected = select().lamp;
		assert.match(provider.getTreeItem(selected).contextValue, /_attach_script/);
		answers = [(items, options) => {
			assert.equal(items.length, 1); assert.equal(items[0].label, 'node_script.gd');
			assert.equal(options.title, 'Attach Script'); assert.equal(options.matchOnDescription, true);
			return items[0];
		}];
		await commands.execute('attach_script', selected);
		assert.equal(writes.length, before + 1); assert.equal(writes.at(-1).operation, 'attach_script');
		assert.equal(writes.at(-1).path, 'Props/Lamp'); assert.equal(writes.at(-1).script_path, nodeScript);
		for (const dependency of [nodeScript, baseScript]) { assert.equal(writes.at(-1).expected_hashes[dependency], hash(dependency)); }
		assert.equal(writes.at(-1).name, undefined);
	});
	const scripted = () => {
		const value = graph(); Object.assign(value.nodes['Props/Lamp'], {
			has_script: true, script_path: nodeScript, script_source_path: source, can_attach_script: false, can_remove_script: true
		}); return select(value).lamp;
	};
	await check('Remove Script confirms detachment and preserves script context', async () => {
		const before = writes.length; const selected = scripted();
		assert.match(provider.getTreeItem(selected).contextValue, /_detach_script/);
		answers = ['Remove Script']; await commands.execute('remove_script', selected);
		assert.equal(writes.length, before + 1); assert.equal(writes.at(-1).operation, 'remove_script');
		assert.equal(writes.at(-1).path, 'Props/Lamp'); assert.equal(writes.at(-1).expected_hashes[baseScript], hash(baseScript));
		const value = graph(); Object.assign(value.nodes['.'], {
			has_script: true, script_path: nodeScript, script_source_path: source, can_attach_script: false, can_remove_script: true
		});
		const root = select(value).root;
		assert.match(provider.getTreeItem(root).contextValue, /_detach_script/);
		assert.doesNotMatch(provider.getTreeItem(root).contextValue, /_remove/);
	});
	await check('Cancelling either script command and protected nodes leave scenes untouched', async () => {
		const before = writes.length;
		answers = []; await commands.execute('attach_script', select().lamp);
		answers = []; await commands.execute('remove_script', scripted());
		await commands.execute('attach_script', scripted());
		await commands.execute('remove_script', select().lamp);
		const value = graph(); value.nodes['Props/Lamp'].can_attach_script = false;
		await commands.execute('attach_script', select(value).lamp);
		assert.equal(writes.length, before);
	});
	await check('Script compatibility failures, dirty dependencies and stale inheritance reject pending edits', async () => {
		const before = writes.length; const original = buffers.get(baseScript);
		try {
			scriptInspectionError = 'Script extends Node3D and cannot attach to Node2D.';
			answers = [items => items[0]]; await commands.execute('attach_script', select().lamp);
			assert.equal(errors.at(-1), scriptInspectionError); scriptInspectionError = undefined;
			answers = [items => items[0]]; afterPrompt = () => { api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(nodeScript) }]; };
			await commands.execute('attach_script', select().lamp); api.workspace.textDocuments = []; afterPrompt = () => {};
			answers = ['Remove Script']; afterPrompt = () => buffers.set(baseScript, Buffer.from('changed inheritance'));
			await commands.execute('remove_script', scripted());
		} finally { scriptInspectionError = undefined; buffers.set(baseScript, original); api.workspace.textDocuments = []; afterPrompt = () => {}; }
		assert.equal(writes.length, before);
	});
	await check('Script dialogs reject changed selection, workspace trust and foreign projects', async () => {
		const before = writes.length; const folders = api.workspace.workspaceFolders;
		try {
			for (const change of [() => provider.clear(), () => { api.workspace.isTrusted = false; }, () => { api.workspace.workspaceFolders = []; }]) {
				api.workspace.isTrusted = true; api.workspace.workspaceFolders = folders;
				answers = [items => items[0]]; afterPrompt = change; await commands.execute('attach_script', select().lamp);
			}
		} finally { api.workspace.isTrusted = true; api.workspace.workspaceFolders = folders; afterPrompt = () => {}; }
		const resolve = workspace.resolveProjectContext;
		try {
			workspace.resolveProjectContext = async file => file.endsWith('.gd')
				? { ...context, projectDirectory: path.join(project, 'nested') } : context;
			answers = [items => items[0]]; await commands.execute('attach_script', select().lamp);
		} finally { workspace.resolveProjectContext = resolve; }
		assert.equal(writes.length, before);
	});
	await check('Activation registers structural commands and their menus', async () => {
		let finishLibrary;
		const registered = new Map(); const disposable = () => ({ dispose() {} });
		api.commands = { registerCommand(id, action) { registered.set(id, action); return disposable(); } };
		api.window.createOutputChannel = () => ({ ...output, dispose() {} });
		api.window.createTreeView = () => disposable();
		api.window.onDidChangeActiveTextEditor = disposable;
		for (const event of ['onDidSaveTextDocument', 'onDidChangeTextDocument', 'onDidChangeWorkspaceFolders', 'onDidChangeConfiguration']) { api.workspace[event] = disposable; }
		api.workspace.createFileSystemWatcher = () => ({ dispose() {}, onDidChange: disposable, onDidCreate: disposable, onDidDelete: disposable });
		class Selection { follow() {} dispose() {} }
		load('extension.js', {
			vscode: api, './scene_selection': { SceneSelection: Selection }, './project_context': workspace,
			'./scene_tree_provider': { SceneTreeProvider, projectUri }, './scene_editing_command': { SceneEditingCommands },
			'./library/library_manager': { LibraryManager: class { async execute() { await new Promise(resolve => { finishLibrary = resolve; }); } } }
		}).activate({ subscriptions: [] });
		const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
		for (const command of manifest.contributes.commands) { assert.ok(registered.has(command.command), command.command); }
		for (const name of ['addNode', 'addInstance', 'attachBehavior', 'attachScript', 'removeScript', 'renameNode', 'removeNode', 'openStructure']) {
			assert.ok(manifest.contributes.menus['frameworkScenes.nodeMenu'].some(item => item.command === 'frameworkScenes.' + name));
		}
		assert.equal(manifest.contributes.menus['frameworkScenes.nodeMenu']
			.find(item => item.command === 'frameworkScenes.attachBehavior').when, 'viewItem =~ /_attach_behavior/');
		assert.equal(manifest.contributes.menus.commandPalette
			.find(item => item.command === 'frameworkScenes.attachBehavior').when, 'false');
		assert.equal(manifest.contributes.menus['frameworkScenes.nodeMenu']
			.some(item => item.command === 'frameworkScenes.assignMovement'), false);
		assert.equal(manifest.contributes.menus['frameworkScenes.nodeMenu']
			.find(item => item.command === 'frameworkScenes.attachScript').when, 'viewItem =~ /_attach_script/');
		assert.equal(manifest.contributes.menus['frameworkScenes.nodeMenu']
			.find(item => item.command === 'frameworkScenes.removeScript').when, 'viewItem =~ /_detach_script/');
		assert.equal(manifest.contributes.menus.commandPalette
			.find(item => item.command === 'frameworkScenes.assignMovement').when, 'false');
		const library = registered.get('frameworkScenes.manageAuthoredLibrary')();
		const attemptedEdit = registered.get('frameworkScenes.addNode')();
		assert.equal(attemptedEdit, library);
		assert.equal(registered.get('frameworkScenes.attachBehavior')(), library);
		assert.equal(registered.get('frameworkScenes.assignMovement')(), library);
		assert.equal(registered.get('frameworkScenes.attachScript')(), library);
		assert.equal(registered.get('frameworkScenes.removeScript')(), library);
		finishLibrary(); await library;
		console.log('[scene-editing-extension] Library management and structural edits share one operation gate: true');
	});
	provider.dispose();
	console.log('[scene-editing-extension] Checks passed: true');
})().catch(error => { console.error(error); process.exitCode = 1; });
