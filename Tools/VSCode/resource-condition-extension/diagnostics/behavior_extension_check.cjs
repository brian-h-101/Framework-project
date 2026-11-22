const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createHash } = require('node:crypto');
const { pathToFileURL, fileURLToPath } = require('node:url');

const project = path.resolve(__dirname, 'mock-project');
const bytes = Buffer.from('inspected fixture');
const hash = createHash('sha256').update(bytes).digest('hex');
const calls = [], errors = [], picks = [], inputs = [], confirms = [];
let onPrompt;
let readBytes = bytes;
let refreshes = 0;
const loads = [];
const editInspections = [];
let editGraph;
let fragmentSelection;
const uri = file => {
	const value = pathToFileURL(file);
	return { scheme: 'file', fsPath: fileURLToPath(value), path: value.pathname, toString: () => value.href };
};
const api = {
	EventEmitter: class { event = () => ({ dispose() {} }); fire() {} dispose() {} },
	TreeItem: class { constructor(label, collapsibleState) { Object.assign(this, { label, collapsibleState }); } },
	ThemeIcon: class { static File = 'file'; constructor(id) { this.id = id; } },
	TreeItemCollapsibleState: { None: 0, Collapsed: 1 },
	Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
	workspace: { isTrusted: true, workspaceFolders: [{ uri: uri(project) }], textDocuments: [],
		fs: { readFile: async () => readBytes }, getConfiguration: () => ({ get: () => 'godot.exe' }) },
	window: {
		showErrorMessage: async message => { errors.push(message); },
		showQuickPick: async () => { onPrompt?.(); return picks.shift(); },
		showInputBox: async options => {
			onPrompt?.();
			const value = inputs.shift();
			if (value !== undefined && options.validateInput) { assert.equal(options.validateInput(value), undefined); }
			return value;
		},
		showWarningMessage: async () => confirms.shift()
	}
};
const cache = new Map();
function load(file) {
	file = path.resolve(file);
	if (cache.has(file)) { return cache.get(file).exports; }
	const mod = { exports: {} };
	cache.set(file, mod);
	const localRequire = name => {
		if (name === 'vscode') { return api; }
		if (name.endsWith('/resource_browse_bridge') && file.endsWith('resource_selection.js')) {
			return { ResourceBrowsePool: class { load(...args) { return new Promise((resolve, reject) => loads.push({ args, resolve, reject })); } invalidate() {} dispose() {} } };
		}
		if (name.endsWith('/resource_bridge') && file.endsWith('edit_context.js')) {
			return { loadResourceGraph: async (...args) => { editInspections.push(args); return editGraph; } };
		}
		if (name.endsWith('/behavior_editing_bridge')) {
			return { editBehavior: async (projectArg, executable, source, request) => {
				calls.push({ projectArg, executable, source, request }); return { source_path: source, content_hash: hash };
			} };
		}
		if (name.endsWith('/preset_fragment_picker')) {
			return { pickPresetFragments: async () => fragmentSelection };
		}
		if (name.endsWith('/project_context')) {
			return { resolveProjectContext: async () => ({ projectDirectory: project, workspaceDirectory: project }), isInside: (base, file) => !path.relative(base, file).startsWith("..") };
		}
		if (name.startsWith('.')) { return load(path.resolve(path.dirname(file), name + '.js')); }
		return require(name);
	};
	vm.runInThisContext('(function(require,module,exports){' + fs.readFileSync(file, 'utf8') + '\n})', { filename: file })(localRequire, mod, mod.exports);
	return mod.exports;
}
const out = path.resolve(__dirname, '../out');
const { ResourceTreeProvider } = load(path.join(out, 'tree/resource_tree_provider.js'));
const { editTreeEntry } = load(path.join(out, 'commands/behavior_editing_command.js'));
const { scalarError } = load(path.join(out, 'resources/value_prompts.js'));
const { ResourceSelection } = load(path.join(out, 'resources/resource_selection.js'));
const base = 'res://Framework/Content/Gameplay/Profiles/Movement/Behavior/';
const names = { interaction: base + 'Interaction/test.tres', action: base + 'Action/test.tres', group: base + 'Condition/group.tres', condition: base + 'Condition/test.tres' };
const part = (text, kind = 'String') => ({ kind, text });
const node = (label, kind, route, flags = {}, children = []) => ({ label, kind, path: route,
	value_text: kind === 'int' ? '-10' : '', children, editable: false, mutable: route.length > 0,
	can_add: false, can_remove: false, can_rename: false, can_add_effect: false, allowed_types: [], choices: [], ...flags });
const amount = node('amount', 'int', [part('arguments'), part('amount', 'StringName')], { editable: true, can_remove: true, can_rename: true });
const bag = node('bag', 'Dictionary', [part('arguments'), part('bag')], { can_add: true, can_remove: true, can_rename: true });
const argumentsNode = node('arguments', 'Dictionary', [part('arguments')], { can_add: true }, [amount, bag]);
const effects = node('effects', 'Array', [part('effects')], { can_add_effect: true });
const graph = { version: 2, roots: [names.interaction], nodes: {},
	dependency_hashes: Object.fromEntries(Object.values(names).map(name => [name, hash])), catalog_paths: Object.values(names).sort() };
const resource = (source, kind, links, fields) => ({ id: kind, kind, source_path: source, content_hash: hash,
	links, data: node('data', 'Dictionary', [], {}, fields), ...(kind === 'condition_group' ? { operator: 'all' }
		: kind === 'condition' ? { operator: '>=', value_text: '20' } : {}) });
graph.nodes[names.interaction] = resource(names.interaction, 'interaction', [
	{ role: 'action', target: names.action, index: -1 }, { role: 'requirements', target: names.group, index: -1 }
], [argumentsNode]);
graph.nodes[names.action] = resource(names.action, 'action', [], [effects]);
graph.nodes[names.group] = resource(names.group, 'condition_group', [{ role: 'condition', target: names.condition, index: 0 }], []);
graph.nodes[names.condition] = resource(names.condition, 'condition', [], []);
const provider = new ResourceTreeProvider();
const report = { appendLine() {} };
const run = (element, operation) => editTreeEntry(provider, element, operation, report, async () => { refreshes++; });
function rows() {
	provider.setGraph(uri(project), structuredClone(graph));
	const root = provider.getChildren()[0];
	const [action, group, args] = provider.getChildren(root);
	const [amountRow, bagRow] = provider.getChildren(args);
	const condition = provider.getChildren(group)[0];
	return { root, action, group, args, amount: amountRow, bag: bagRow, condition };
}
function check(label, condition) { assert.ok(condition, label); console.log(`[behavior-extension] ${label}: true`); }

async function main() {
	let r = rows();
	check('Links retain parent ownership and array index', r.condition.parentSource === names.group && r.condition.linkIndex === 0);
	check('Context distinguishes relationship and data operations', provider.getTreeItem(r.condition).contextValue.includes('|condition_link')
		&& provider.getTreeItem(r.bag).contextValue.includes('|add') && !provider.getTreeItem(r.args).contextValue.includes('|remove'));
	check('Scalar row opens the resource that owns its data', provider.getTreeItem(r.amount).command.arguments[0].fsPath === uri(path.join(project, names.interaction.slice(6))).fsPath);
	picks.push('int'); inputs.push('9223372036854775807');
	await run(r.amount, 'set');
	check('Int64 text and typed data path reach the backend intact', calls.at(-1).request.value_text === '9223372036854775807'
		&& calls.at(-1).request.path[1].kind === 'StringName');
	picks.push('String', 'Dictionary'); inputs.push('new');
	await run(r.bag, 'add');
	check('Nested insertion sends a typed key and valid empty collection', calls.at(-1).request.key.text === 'new' && calls.at(-1).request.value_text === '{}');
	picks.push('StringName'); inputs.push('renamed');
	await run(r.bag, 'rename');
	check('Rename addresses the selected dictionary key', calls.at(-1).request.operation === 'rename' && calls.at(-1).request.key.kind === 'StringName');
	confirms.push('Remove Link'); await run(r.condition, 'remove_condition');
	check('Unlink writes the parent group, preserving the child file', calls.at(-1).source === names.group && calls.at(-1).request.condition_path === names.condition);
	confirms.push('Clear Requirements'); await run(r.group, 'clear_requirements');
	check('Requirements link clears its owning interaction', calls.at(-1).source === names.interaction && calls.at(-1).request.operation === 'clear_requirements');
	picks.push('add', 'target'); inputs.push('health', '["current"]', 'amount');
	await run(r.action, 'add_effect');
	check('Add Effect submits one complete definition', calls.at(-1).request.effect.value_from === 'amount' && calls.at(-1).request.effect.path[0] === 'current');
	const beforeCancel = calls.length;
	await run(r.amount, 'set');
	check('Cancelling a prompt performs no write', calls.length === beforeCancel);
	api.workspace.textDocuments = [{ isDirty: true, uri: uri(path.join(project, names.action.slice(6))) }];
	await run(r.amount, 'set');
	check('Dirty dependencies block editing', calls.length === beforeCancel && errors.at(-1).includes('Save or revert'));
	api.workspace.textDocuments = [];
	readBytes = Buffer.from('external changes'); await run(r.amount, 'set');
	check('Changed dependency hashes block editing', calls.length === beforeCancel && errors.at(-1).includes('Resource changed'));
	readBytes = bytes;
	onPrompt = () => { provider.clear(); onPrompt = undefined; }; picks.push('int'); inputs.push('5');
	await run(r.amount, 'set');
	check('Selection changing during prompts prevents a stale write', calls.length === beforeCancel && errors.at(-1).includes('stale'));
	r = rows(); await run(r.args, 'remove');
	check('Required field rows reject removal commands', calls.length === beforeCancel && errors.at(-1).includes('unavailable'));
	api.workspace.isTrusted = false; await run(r.amount, 'set');
	check('Trust changes prevent editing', calls.length === beforeCancel);
	api.workspace.isTrusted = true;
	assert.equal(scalarError('int', '9223372036854775808'), 'Enter a signed 64-bit integer.');
	assert.ok(scalarError('int', '20.0')); assert.ok(scalarError('float', '1e999'));
	check('Integer range and numeric syntax are checked before submission', true);
	check('Successful edits refresh the tree', refreshes === calls.length);
	const stale = r.root; provider.setGraph(uri(project), structuredClone(graph));
	assert.throws(() => provider.resolve(stale), /stale/);
	check('Old tree revisions are rejected', true);
	const browsing = { ...structuredClone(graph), mode: 'browse', catalog_paths: [], executors: [] };
	editGraph = { ...structuredClone(graph), executors: [], executor_snapshot: { hashes: { 'res://executor.gd': hash }, directories: {} } };
	provider.setGraph(uri(project), browsing);
	const browseAmount = provider.getChildren(provider.getChildren(provider.getChildren()[0]).at(-1))[0];
	onPrompt = () => { assert.equal(editInspections.length, 1); assert.equal(calls.length, beforeCancel); };
	picks.push('int'); inputs.push('43'); await run(browseAmount, 'set'); onPrompt = undefined;
	check('Editing a browsing row prepares full source validation before prompting', calls.at(-1).request.executor_snapshot === editGraph.executor_snapshot
		&& calls.at(-1).request.catalog_paths.length > 0 && editInspections[0][3] === names.interaction);
	const editedCount = calls.length;
	editGraph = structuredClone(editGraph); editGraph.nodes[names.interaction].id = 'external_change';
	await run(browseAmount, 'set');
	check('Changed metadata between browsing and editing prevents prompts and writes', calls.length === editedCount && errors.at(-1).includes('changed since'));

	const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
	for (const name of ['addEntry', 'renameEntry', 'removeEntry', 'editValue', 'addEffect', 'removeReference', 'clearRequirements', 'newResource', 'createAndLinkResource', 'assignExistingResource', 'replaceReference', 'renameResourceFile', 'deleteResourceFile', 'openOwningResource']) {
		assert.ok(pkg.contributes.commands.some(command => command.command === 'customTreeView.' + name));
		assert.ok(pkg.contributes.menus['customTreeView.resourceMenu'].some(command => command.command === 'customTreeView.' + name));
	}
	check('All structural commands have curated menu contributions', true);
	const published = [], statuses = [];
	const selection = new ResourceSelection({ clear() {}, setGraph: (_project, graphArg) => published.push(graphArg) }, report, message => statuses.push(message));
	const tick = () => new Promise(resolve => setImmediate(resolve));
	selection.follow({ document: { uri: uri(path.join(project, names.action.slice(6))) } });
	await tick();
	selection.follow({ document: { uri: uri(path.join(project, names.interaction.slice(6))) } });
	await tick();
	loads[1].resolve(graph); await tick(); loads[0].resolve({ ...graph, roots: [names.action] }); await tick();
	check('Slower earlier selections cannot replace the current resource', published.length === 1 && published[0].roots[0] === names.interaction);
	api.workspace.textDocuments = [{ isDirty: true, uri: uri(path.join(project, names.action.slice(6))) }];
	selection.updateStatus();
	check('Unsaved related edits are identified as saved-data views', statuses.at(-1).includes('Showing saved data'));
	api.workspace.textDocuments = [];
	let finishOperation;
	const pending = new Promise(resolve => { finishOperation = resolve; });
	selection.changed(uri(path.join(project, names.action.slice(6))), pending);
	await new Promise(resolve => setTimeout(resolve, 180));
	check('Saved-file refresh waits for an active editing operation', loads.length === 2);
	finishOperation(); await tick();
	assert.equal(loads.length, 3); loads[2].resolve(graph); await tick();
	check('Saved dependency changes refresh the resource tree', published.length === 2);
	const attribute = 'res://Framework/Content/Gameplay/Authored/Entity/Attributes/Abilities/reflex.tres';
	const unsupported = { version: 2, supported: false, source_path: attribute, roots: [], nodes: {},
		dependency_hashes: { [attribute]: hash }, catalog_paths: [] };
	const { validateGraph } = load(path.join(out, 'bridges/resource_bridge.js'));
	validateGraph(unsupported);
	assert.throws(() => validateGraph({ ...unsupported, roots: [attribute] }), /unsupported Resource/);
	const errorsBeforeUnsupported = errors.length;
	selection.follow({ document: { uri: uri(path.join(project, attribute.slice(6))) } }); await tick();
	loads[3].resolve(unsupported); await tick();
	check('Attribute schemas clear the behavior view without an error popup', published.length === 2
		&& errors.length === errorsBeforeUnsupported && statuses.at(-1).includes('Open a Behavior'));
	selection.updateStatus();
	check('Unsupported selections retain their explanatory view message', statuses.at(-1).includes('Open a Behavior'));
	selection.follow({ document: { uri: uri(path.join(project, names.interaction.slice(6))) } }); await tick();
	check('Returning to an unchanged resource uses the cached graph', loads.length === 4);
	check('Returning to a behavior Resource restores its graph', published.length === 3 && statuses.at(-1) === undefined);
	selection.follow({ document: { uri: uri(path.join(project, names.action.slice(6))) } }); await tick();
	loads[4].reject(new Error('Behavior Resource has an empty authored ID.')); await tick();
	check('Malformed behavior Resources still report errors', errors.length === errorsBeforeUnsupported + 1
		&& errors.at(-1).includes('empty authored ID'));
	selection.follow({ document: { uri: uri(path.join(project, names.interaction.slice(6))) } }); await tick();
	const reload = selection.refresh(); await tick();
	selection.removed(uri(path.join(project, names.interaction.slice(6))));
	loads[5].resolve(graph); await reload; await tick(); await selection.refresh();
	check('Deleting the selected Resource clears details and discards pending loads', published.length === 4
		&& loads.length === 6 && statuses.at(-1).includes('Open a framework'));
	selection.dispose();
	await executorChecks();
	await startingPresetChecks();
	configurationChecks();
	provider.dispose();
	console.log('[behavior-extension] Checks passed: true');
}

function configurationChecks() {
	const { validateGraph } = load(path.join(out, 'bridges/resource_bridge.js'));
	const configuration = source => ({
		version: 2, mode: 'browse', roots: [source], catalog_paths: [],
		dependency_hashes: { [source]: hash },
		nodes: { [source]: {
			...resource(source, 'configuration', [], [
				node('Bindings', 'Array', [part('Bindings')], { mutable: false })
			]),
			configuration_type: 'input',
			physical_keys: [{ label: 'W', code: '87' }, { label: 'Up Arrow', code: '4194320' }]
		} }
	});
	const controls = configuration('res://Framework/Content/Configuration/Input/controls.tres');
	validateGraph(controls);
	provider.setGraph(uri(project), controls);
	const root = provider.getChildren()[0];
	const bindings = provider.getTreeItem(provider.getChildren(root)[0]);
	check('Configuration offers typed binding and creation commands',
		bindings.label === 'Bindings' && bindings.contextValue === 'behavior_data|open_owner|input_bindings'
		&& provider.getTreeItem(root).contextValue === 'configuration|new_configuration');
	assert.throws(() => validateGraph(configuration(names.action)), /Content\/Configuration/);
	const profilePath = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres';
	const profile = configuration(profilePath);
	profile.nodes[profilePath].configuration_type = 'movement';
	delete profile.nodes[profilePath].physical_keys;
	validateGraph(profile);
	provider.setGraph(uri(project), profile);
	assert.match(provider.getTreeItem(provider.getChildren()[0]).contextValue, /movement_configuration/);
	assert.throws(() => validateGraph(configuration(profilePath)), /Content\/Configuration/);
	check('Profiles accepts Movement while Input stays under Configuration', true);
}

async function startingPresetChecks() {
	const source = 'res://Framework/Content/Gameplay/Presentation/Entity/Player/starting_attributes.tres';
	const health = 'res://Framework/Content/Gameplay/Authored/Entity/Attributes/Statistics/health.tres';
	const speed = 'res://Framework/Content/Gameplay/Authored/Entity/Attributes/Statistics/speed.tres';
	const fragments = node('Fragments', 'Array', [part('Fragments')], {}, [
		node('[0]', 'String', [part('Fragments'), part('0', 'index')]),
		node('[1]', 'String', [part('Fragments'), part('1', 'index')])
	]);
	const id = node('Definition ID', 'StringName', [part('Definition ID')]);
	const attr = node('current', 'int', [part('Effective Attributes'), part('health', 'StringName'), part('current')], { editable: true });
	const effective = node('Effective Attributes', 'Dictionary', [part('Effective Attributes')], {}, [
		node('health', 'Dictionary', [part('Effective Attributes'), part('health', 'StringName')], {}, [attr])
	]);
	const preset = { version: 2, roots: [source], catalog_paths: [],
		dependency_hashes: { [source]: hash, [health]: hash, [speed]: hash },
		nodes: { [source]: { ...resource(source, 'starting_attributes', [], [id, fragments, effective]), fragment_paths: [health, speed] } } };
	provider.setGraph(uri(project), { ...preset, mode: 'browse' });
	editGraph = preset;
	const root = provider.getChildren()[0];
	const [idRow, fragmentRow, effectiveRow] = provider.getChildren(root);
	check('Starting preset menus offer fragment editing and keep the definition ID protected',
		provider.getTreeItem(root).contextValue.includes('|choose_fragments')
		&& !provider.getTreeItem(idRow).contextValue.includes('|edit')
		&& provider.getTreeItem(provider.getChildren(fragmentRow)[0]).contextValue.includes('|fragment_down'));
	const valueRow = provider.getChildren(provider.getChildren(effectiveRow)[0])[0];
	picks.push('int'); inputs.push('75');
	await run(valueRow, 'set');
	check('Preset values use the guarded presentation edit route',
		calls.at(-1).request.presentation_preset === true
		&& calls.at(-1).request.path[0].text === 'Effective Attributes'
		&& calls.at(-1).request.value_text === '75');
	await run(provider.getChildren(fragmentRow)[0], 'fragment_down');
	check('Moving a fragment submits the edited composition order',
		JSON.stringify(calls.at(-1).request.fragment_paths) === JSON.stringify([speed, health]));
	const before = calls.length;
	await run(fragmentRow, 'set_fragments');
	check('Cancelling fragment selection leaves the preset untouched', calls.length === before);
	fragmentSelection = { paths: [speed], hashes: { [speed]: hash } };
	await run(fragmentRow, 'set_fragments');
	check('Fragment selection forwards the selected paths and inspected hashes',
		calls.at(-1).request.fragment_paths[0] === speed && calls.at(-1).request.expected_hashes[speed] === hash);
	fragmentSelection = undefined;
}
main().catch(error => { console.error(error); process.exitCode = 1; });

async function executorChecks() {
	const descriptor = { id: 'direct_health', label: 'Direct Health', description: 'Sets health.', supports_effects: false,
		arguments: [{ name: 'amount', allowed_types: ['int', 'float'], required: true, numeric: true }] };
	graph.executors = [descriptor];
	graph.executor_snapshot = { hashes: { 'res://executor.gd': hash }, directories: {} };
	const action = graph.nodes[names.action];
	action.behavior_id = 'direct_health'; action.supports_effects = false; action.argument_specs = descriptor.arguments;
	action.data.children.push(node('behavior_id', 'StringName', [part('behavior_id')], { editable: true }));
	const r = rows();
	check('Custom action displays behavior without Add Effect', provider.getTreeItem(r.action).description === '[direct_health]'
		&& !provider.getTreeItem(r.action).contextValue.includes('|add_effect'));
	check('Actions without script metadata hide executor navigation', !provider.getTreeItem(r.action).contextValue.includes('|open_executor'));
	descriptor.script_path = 'res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_2d_executor.gd';
	const navigationRows = rows();
	const navigationItem = provider.getTreeItem(navigationRows.action);
	check('Registered script paths enable navigation and appear in the tooltip', navigationItem.contextValue.includes('|open_executor')
		&& navigationItem.tooltip.includes(descriptor.script_path));
	check('Nested data and non-Action rows hide executor navigation', !provider.getTreeItem(navigationRows.amount).contextValue.includes('|open_executor')
		&& !provider.getTreeItem(navigationRows.group).contextValue.includes('|open_executor'));
	delete descriptor.script_path;
	const currentRows = rows();
	Object.assign(r, currentRows);
	const count = calls.length;
	await run(r.action, 'add_effect');
	check('Unsupported field commands perform no write', calls.length === count);
	picks.push({ id: 'direct_health' }); await run(r.action, 'set_behavior');
	check('Behavior selection submits the metadata snapshot', calls.at(-1).request.operation === 'set_behavior'
		&& calls.at(-1).request.behavior_id === 'direct_health' && calls.at(-1).request.executor_snapshot.hashes['res://executor.gd'] === hash);
	picks.push({ id: 'direct_health' }); await run(provider.getChildren(r.action).at(-1), 'set');
	check('Editing behavior_id uses the behavior picker', calls.at(-1).request.operation === 'set_behavior');
	const before = calls.length;
	picks.push(undefined); await run(r.action, 'set_behavior');
	check('Cancelling behavior selection performs no write', calls.length === before);
	api.workspace.textDocuments.push({ isDirty: true, uri: uri(path.join(project, 'executor.gd')) });
	await run(r.action, 'set_behavior');
	check('Dirty executor code blocks authoring', calls.length === before && /Save or revert/.test(errors.at(-1)));
	api.workspace.textDocuments.length = 0;
	const { validateGraph } = load(path.join(out, 'bridges/resource_bridge.js'));
	const invalid = structuredClone(graph); invalid.executors[0].arguments[0].allowed_types = ['Node'];
	assert.throws(() => validateGraph(invalid), /metadata/);
	check('Malformed executor metadata is rejected at the bridge boundary', true);
	const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json')));
	check('Behavior command has a curated action menu entry', pkg.contributes.commands.some(c => c.command === 'customTreeView.setActionBehavior')
		&& pkg.contributes.menus['customTreeView.resourceMenu'].some(c => c.command === 'customTreeView.setActionBehavior'));
	check('Executor navigation has a conditional curated menu entry', pkg.contributes.commands.some(c => c.command === 'customTreeView.openExecutorScript')
		&& pkg.contributes.menus['customTreeView.resourceMenu'].some(c => c.command === 'customTreeView.openExecutorScript' && c.when.includes('open_executor'))
		&& pkg.contributes.menus.commandPalette.some(c => c.command === 'customTreeView.openExecutorScript' && c.when === 'false'));
	const { editSequence } = load(path.join(out, 'commands/sequence_editing_command.js'));
	const sequencePath = base + 'Sequence/probe.tres';
	const sequenceGraph = structuredClone(graph);
	const configuration = node('Configuration', 'Behavior', [], {sequence: {role: 'configuration', step_id: ''}});
	const step = node('Damage [ACTION]', 'Behavior', [], {sequence: {role: 'step', step_id: 'damage', step_kind: 'action', label: 'Damage'}});
	const steps = node('Steps [SEQUENCE]', 'Behavior', [], {sequence: {role: 'steps', step_id: ''}}, [step]);
	sequenceGraph.roots = [sequencePath];
	sequenceGraph.dependency_hashes[sequencePath] = hash;
	sequenceGraph.nodes[sequencePath] = {id: 'probe', kind: 'behavior', source_path: sequencePath, content_hash: hash, links: [], data: node('data', 'Dictionary', [], {}, [configuration, steps])};
	provider.setGraph(uri(project), sequenceGraph);
	const sequenceRoot = provider.getChildren()[0];
	const [configurationRow, stepsRow] = provider.getChildren(sequenceRoot);
	const stepRow = provider.getChildren(stepsRow)[0];
	check('Unified tree exposes owned Configuration and Steps roles', provider.getTreeItem(stepsRow).contextValue.includes('sequence_add') && provider.getTreeItem(stepRow).tooltip.includes('Step ID: damage'));
	inputs.push('Renamed Damage');
	await editSequence(provider, stepRow, 'rename', report, async () => {refreshes++;});
	check('Step rename addresses its owning file and stable ID', calls.at(-1).source === sequencePath && calls.at(-1).request.step_id === 'damage' && calls.at(-1).request.label === 'Renamed Damage');
	await editSequence(provider, stepRow, 'move_up', report, async () => {});
	check('Reordering submits the sibling direction', calls.at(-1).request.operation === 'sequence_move' && calls.at(-1).request.direction === -1);
	const beforeCancel = calls.length;
	inputs.push(undefined);
	await editSequence(provider, stepRow, 'rename', report, async () => {});
	check('Cancelling a sequence prompt performs no write', calls.length === beforeCancel);
	api.workspace.isTrusted = false;
	await editSequence(provider, stepRow, 'rename', report, async () => {});
	check('Untrusted sequence edits are blocked', calls.length === beforeCancel);
	api.workspace.isTrusted = true;
	check('Sequence commands belong to the expanded curated menu', pkg.contributes.menus['customTreeView.resourceMenu'].filter(item => item.command?.startsWith('customTreeView.sequence.')).length === 11);

}
