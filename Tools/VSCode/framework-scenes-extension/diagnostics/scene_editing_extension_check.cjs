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
const layoutPreset = 'res://Framework/Content/Gameplay/Presets/Props/Outdoor/ground.layout.tres';
const layoutGenerated = 'res://Framework/Content/Gameplay/Presentation/Layouts/Props/Outdoor/ground.tscn';
const interaction = 'res://Framework/Content/Behavior/Interaction/strike.tres';
const component = 'res://Framework/Content/Universal/Interaction/based/Legacy/interaction_behavior.gd';
const automationComponent = 'res://Framework/Content/Universal/Interaction/based/Legacy/automation_behavior.gd';
const unified = 'res://Framework/Content/Behavior/Sequence/strike.tres';
const unifiedComponent = 'res://Framework/Content/Universal/Interaction/based/Bindings/behavior_binding.gd';
const automation = 'res://Framework/Content/Behavior/Automation/auto_strike.tres';
const existingInteraction = 'res://Framework/Content/Behavior/Interaction/existing.tres';
const action = 'res://Framework/Content/Behavior/Action/change_health.tres';
const movement = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared/faster.tres';
const previousMovement = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres';
const movementScript = 'res://Framework/Content/Universal/Movement/based/Physics2D/movement_body_2d.gd';
const movementAction = 'res://Framework/Content/Behavior/Action/move.tres';
const nodeScript = 'res://Scripts/node_script.gd';
const baseScript = 'res://Scripts/base_script.gd';
const resourceUri = resource => uri(path.join(project, resource.slice(6)));
const buffers = new Map([[source, Buffer.from('map bytes')], [template, Buffer.from('template bytes')]]);
for (const item of [layoutPreset, layoutGenerated]) { buffers.set(item, Buffer.from(item)); }
for (const resource of [interaction, component, existingInteraction, automationComponent, automation, unified, unifiedComponent]) { buffers.set(resource, Buffer.from(resource)); }
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
let sceneUris = [resourceUri(template), resourceUri(source)];
let projectUris = [resourceUri('res://project.godot')];
const api = {
	__esModule: true,
	Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
	RelativePattern: class { constructor(base, pattern) { this.base = base; this.pattern = pattern; } },
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
		async findFiles(pattern) {
			if (pattern === '**/*.gd') { return [resourceUri(nodeScript)]; }
			if (pattern.pattern?.endsWith('/*.layout.tres')) {
				assert.equal(pattern.pattern, 'Framework/Content/Gameplay/Presets/**/*.layout.tres');
				return [resourceUri(layoutPreset)];
			}
			assert.equal(pattern.base, project, 'instance discovery is relative to the open scene project');
			return pattern.pattern === '**/project.godot' ? projectUris : sceneUris;
		},
		asRelativePath: file => path.relative(project, file.fsPath)
	},
	window: {
		async showQuickPick(items, options) { const answer = answers.shift(); afterPrompt(); return typeof answer === 'function' ? answer(items, options) : answer; },
		async showInputBox(options) { const answer = answers.shift(); afterPrompt(); return typeof answer === 'function' ? answer(options) : answer; },
		async showWarningMessage() { const answer = answers.shift(); afterPrompt(); return answer; },
		async showErrorMessage(message) { errors.push(message); },
		async showInformationMessage(message, options, button) {
			information.push(message);
			if (button) {
				const answer = answers.shift();
				afterPrompt();
				return typeof answer === 'function' ? answer(options) : answer;
			}
		}
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
const instancePicker = load('scene_instance_picker.js', { vscode: api, './project_context': workspace });
const { SceneEditingCommands } = load('scene_editing_command.js', {
	vscode: api, './project_context': workspace,
	'./scene_tree_provider': { projectUri }, './scene_selection': selection,
	'./scene_property_prompt': load('scene_property_prompt.js', { vscode: api }),
	'./scene_instance_picker': instancePicker,
	'./scene_bridge': { async loadSceneGraph(_project, _executable, path) { return graph(path); } },
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
		isLayoutPresetPath: require('../out/scene_editing_bridge.js').isLayoutPresetPath,
		LAYOUT_PRESET_FOLDER: 'Framework/Content/Gameplay/Presets',
		LAYOUT_SUFFIX: '.layout.tres',
		async resolveLayout(_project, _executable, path) {
			assert.equal(path, layoutPreset);
			return { scene_path: layoutGenerated, dependency_hashes: { [layoutPreset]: hash(layoutPreset), [layoutGenerated]: hash(layoutGenerated) } };
		},
		async inspectNodeProperties() {
			return [
				{ name: 'position', type: 'Vector2', saved: true, value: '10, 20' },
				{ name: 'metadata/entity_spatial_root', type: 'bool', saved: false, value: 'true' }
			];
		},
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
const capabilityCalls = [];
const capabilityControls = 'res://Framework/Content/Configuration/Input/controls.tres';
const capabilityKeyboard = 'res://Framework/Content/Gameplay/Controller/player_keyboard.tres';
const capabilityAi = 'res://Framework/Content/Gameplay/Controller/enemy_ai.tres';
const capabilityGrid = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_grid.tres';
buffers.set(capabilityGrid, Buffer.from(capabilityGrid));
const capabilityToken = 'a'.repeat(64);
let includeGridProfiles = false;
const { configureMovementCapability } = load('movement_capability_command.js', {
	vscode: api, './project_context': workspace, './scene_selection': selection,
	'./scene_tree_provider': { projectUri },
	'./scene_editing_bridge': {
		async runSceneEditing(_project, _executable, [operation, scene, node], request) {
			capabilityCalls.push({ operation, scene, node, request });
			const choice = { source_path: movement, behavior_id: 'move', velocity_step_id: 'calculate_velocity' };
			if (operation === 'inspect-movement') {
				const configurations = includeGridProfiles ? [
					{ ...choice, environment: 'physics_2d' },
					{ ...choice, source_path: capabilityGrid, environment: 'grid' },
					{ ...choice, source_path: previousMovement, behavior_id: 'walk', environment: 'grid' }
				] : [choice];
				return { scene_path: template, body_path: 'MotionBody', current_configuration: '', current_controller: '',
					configurations, controllers: [
						{ source_path: capabilityKeyboard, kind: 'keyboard' }, { source_path: capabilityAi, kind: 'ai' }
					] };
			}
			if (operation === 'plan-movement') {
				return { scene_path: template, body_path: 'MotionBody', configuration_path: request.configuration_path,
					controller_path: request.controller_path, behavior_path: unified, binding_path: 'MoveBehavior',
					environment: request.environment,
					attach_script: true, assign_configuration: true, assign_controller: true, add_binding: false,
					input_actions: request.controller_path === capabilityKeyboard ? ['move_up', 'move_left'] : [],
					dependency_hashes: {
						[source]: hash(source), [template]: hash(template), [capabilityControls]: capabilityToken,
						[request.configuration_path]: hash(request.configuration_path), [unified]: hash(unified), [request.controller_path]: capabilityToken
					},
					token: capabilityToken };
			}
			return { scene_path: template, changed: true };
		}
	}
});
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
const itemNamed = label => items => {
	const item = items.find(item => item.label === label);
	assert.ok(item, 'Missing picker row: ' + label);
	return item;
};

(async () => {
	await check('Native node creation routes type, parent and dependency hashes', async () => {
		answers = ['Marker2D', 'Point 雨']; await commands.execute('add_node', select().props);
		assert.equal(writes.at(-1).node_type, 'Marker2D'); assert.equal(writes.at(-1).path, 'Props');
		assert.equal(writes.at(-1).expected_hashes[source], hash(source)); assert.equal(refreshes, 1);
	});
	await check('Folder instance selection includes candidate dependency hashes', async () => {
		answers = [itemNamed('Scenes/'), itemNamed('template.tscn'), 'Placement'];
		await commands.execute('add_instance', select().root);
		assert.equal(writes.at(-1).instance_scene, template); assert.equal(writes.at(-1).expected_hashes[template], hash(template));
	});
	await check('Layout placement uses the instance operation and includes preset hashes', async () => {
		const previous = writes.length;
		answers = [undefined];
		await commands.execute('add_layout', select().root);
		assert.equal(writes.length, previous);
		answers = [itemNamed('Props/Outdoor/ground'), 'Ground'];
		await commands.execute('add_layout', select().root);
		assert.equal(writes.length, previous + 1);
		assert.equal(writes.at(-1).operation, 'add_instance');
		assert.equal(writes.at(-1).instance_scene, layoutGenerated);
		assert.equal(writes.at(-1).layout_path, layoutPreset);
		assert.equal(writes.at(-1).layout_hashes[layoutPreset], hash(layoutPreset));
	});
	await check('Instance folders support parent navigation and searchable duplicate filenames', async () => {
		const originalScenes = sceneUris;
		const originalProjects = projectUris;
		const entity = resourceUri('res://Framework/Content/Gameplay/Presentation/Entity/body.tscn');
		const fixture = resourceUri('res://Diagnostics/Fixtures/body.tscn');
		sceneUris = [fixture, entity, resourceUri(template), resourceUri(source),
			resourceUri('res://Nested/foreign.tscn'), uri(path.join(project + '-other', 'external.tscn'))];
		projectUris = [...originalProjects, resourceUri('res://Nested/project.godot')];
		try {
			answers = [items => {
				assert.deepEqual(items.map(item => item.label), ['Diagnostics/', 'Framework/', 'Scenes/', 'Search All Scenes…']);
				return itemNamed('Framework/')(items);
			}, itemNamed('Content/'), itemNamed('Parent Folder'), itemNamed('Content/'), itemNamed('Gameplay/'),
			itemNamed('Presentation/'), itemNamed('Entity/'), itemNamed('body.tscn')];
			assert.equal(await instancePicker.pickSceneInstance(context, source), entity);
			answers = [itemNamed('Search All Scenes…'), items => {
				const duplicates = items.filter(item => item.label === 'body.tscn');
				assert.equal(duplicates.length, 2);
				assert.ok(!items.some(item => ['map.tscn', 'foreign.tscn', 'external.tscn'].includes(item.label)));
				return duplicates.find(item => item.description.startsWith('Diagnostics/'));
			}];
			assert.equal(await instancePicker.pickSceneInstance(context, source), fixture);
		} finally {
			sceneUris = originalScenes;
			projectUris = originalProjects;
		}
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
		for (const input of [[], [itemNamed('Scenes/')], [itemNamed('Scenes/'), itemNamed('template.tscn')]]) {
			answers = input.slice(); await commands.execute('add_instance', select().root);
		}
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
		answers = [itemNamed('Scenes/'), itemNamed('template.tscn'), 'Other'];
		afterPrompt = () => { api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(template) }]; };
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
	await check('Unified Behavior picker guards content and binding script', async () => {
		catalog = {version: 1, resources: [{id: 'strike', kind: 'behavior', source_path: unified}]};
		const before = writes.length;
		answers = [items => {assert.equal(items[0].description, 'behavior: strike'); return items[0];}, 'StrikeBehavior'];
		await commands.execute('attach_behavior', selectEntity());
		assert.equal(writes.length, before + 1);
		assert.equal(writes.at(-1).behavior_resource, unified);
		assert.equal(writes.at(-1).expected_hashes[unifiedComponent], hash(unifiedComponent));
		assert.equal(writes.at(-1).expected_hashes[unified], hash(unified));
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
			assert.equal(information.at(-1), 'No Behavior resources are available.');
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
		assert.match(provider.getTreeItem(body).tooltip, /movement_2d\.tres/);
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
	await check('Property picker uses saved values and submits typed native values and metadata', async () => {
		answers = [items => items[0], options => { assert.equal(options.value, '10, 20'); return '320, 360'; }];
		await commands.execute('set_property', select().lamp);
		assert.deepEqual(writes.at(-1), { operation: 'set_property', path: 'Props/Lamp',
			expected_hashes: { [source]: hash(source) }, property_name: 'position', property_type: 'Vector2', property_value: '320, 360' });
		answers = [items => items[1], 'true'];
		await commands.execute('set_property', select().lamp);
		assert.equal(writes.at(-1).property_name, 'metadata/entity_spatial_root');
		assert.equal(writes.at(-1).property_type, 'bool');
		answers = [items => items.at(-1), 'note', items => items.find(item => item.valueType === 'String'), 'Sample'];
		await commands.execute('set_property', select().lamp);
		assert.equal(writes.at(-1).property_name, 'metadata/note');
		assert.equal(writes.at(-1).property_value, 'Sample');
	});
	await check('Cancelled property prompts and inherited children perform no write', async () => {
		const before = writes.length;
		answers = [items => items[0], undefined];
		await commands.execute('set_property', select().lamp);
		const borrowed = graph();
		borrowed.nodes['Props/Lamp'].structural_scene = template;
		const lamp = select(borrowed).lamp;
		assert.doesNotMatch(provider.getTreeItem(lamp).contextValue, /_set_property/);
		await commands.execute('set_property', lamp);
		assert.equal(writes.length, before);
	});
	await check('Configure Capabilities reviews existing movement resources and sends the approved plan', async () => {
		const selected = selectEntity();
		assert.match(provider.getTreeItem(selected).contextValue, /_configure_capabilities/);
		assert.doesNotMatch(provider.getTreeItem(provider.getChildren(selected)[0]).contextValue, /_configure_capabilities/);
		answers = [items => items[0], items => items[0], options => {
			assert.match(options.detail, /Scenes\/template\.tscn/);
			assert.match(options.detail, /Reuse Behavior binding at MoveBehavior/);
			assert.match(options.detail, /player_keyboard\.tres/);
			return 'Apply Movement';
		}];
		await configureMovementCapability(provider, selected, output, async () => { refreshes++; });
		assert.deepEqual(capabilityCalls.slice(-3), [
			{ operation: 'inspect-movement', scene: source, node: 'Props', request: undefined },
			{ operation: 'plan-movement', scene: source, node: 'Props',
				request: { configuration_path: movement, controller_path: capabilityKeyboard } },
			{ operation: 'apply-movement', scene: source, node: 'Props',
				request: { configuration_path: movement, controller_path: capabilityKeyboard, token: capabilityToken } }
		]);
	});
	await check('Controller selection reuses the same profile and rejects cancelled or dirty saves', async () => {
		const before = capabilityCalls.filter(call => call.operation === 'apply-movement').length;
		answers = [items => items[0], items => items.at(-1), undefined];
		await configureMovementCapability(provider, selectEntity(), output, async () => { refreshes++; });
		assert.deepEqual(capabilityCalls.at(-1).request, {
			configuration_path: movement,
			controller_path: capabilityAi
		});
		answers = [items => items[0], items => items[0], () => {
			api.workspace.textDocuments = [{ isDirty: true, uri: resourceUri(capabilityKeyboard) }];
			return 'Apply Movement';
		}];
		try {
			await configureMovementCapability(provider, selectEntity(), output, async () => { refreshes++; });
			assert.match(errors.at(-1), /unsaved edits/i);
		} finally { api.workspace.textDocuments = []; }
		assert.equal(capabilityCalls.filter(call => call.operation === 'apply-movement').length, before);
	});
	await check('Movement selects a compatible grid profile, shared Behavior and reusable controller', async () => {
		includeGridProfiles = true;
		try {
			answers = [itemNamed('Movement'), itemNamed('Grid'), itemNamed('move'), itemNamed('enemy_ai.tres'), options => {
				assert.match(options.detail, /Environment  Grid/);
				assert.match(options.detail, /movement_grid\.tres/);
				return 'Apply Movement';
			}];
			await configureMovementCapability(provider, selectEntity(), output, async () => { refreshes++; });
			assert.deepEqual(capabilityCalls.at(-1).request, {
				configuration_path: capabilityGrid, controller_path: capabilityAi, environment: 'grid', token: capabilityToken
			});
		} finally { includeGridProfiles = false; }
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
			'./movement_capability_command': { configureMovementCapability },
			'./library/library_manager': { LibraryManager: class { async execute() { await new Promise(resolve => { finishLibrary = resolve; }); } } }
		}).activate({ subscriptions: [] });
		const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
		for (const command of manifest.contributes.commands) { assert.ok(registered.has(command.command), command.command); }
		for (const name of ['addNode', 'addInstance', 'addLayoutPreset', 'attachBehavior', 'attachScript', 'removeScript', 'renameNode', 'removeNode', 'openStructure', 'setNodeProperty']) {
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
		assert.equal(registered.get('frameworkScenes.configureCapabilities')(), library);
		assert.equal(registered.get('frameworkScenes.attachScript')(), library);
		assert.equal(registered.get('frameworkScenes.removeScript')(), library);
		assert.equal(registered.get('frameworkScenes.setNodeProperty')(), library);
		finishLibrary(); await library;
		console.log('[scene-editing-extension] Library management and structural edits share one operation gate: true');
	});
	provider.dispose();
	console.log('[scene-editing-extension] Checks passed: true');
})().catch(error => { console.error(error); process.exitCode = 1; });
