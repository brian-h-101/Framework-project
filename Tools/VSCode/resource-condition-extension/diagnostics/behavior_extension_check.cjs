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
		if (name.endsWith('/resource_bridge') && file.endsWith('resource_selection.js')) {
			return { loadResourceGraph: (...args) => new Promise((resolve, reject) => loads.push({ args, resolve, reject })) };
		}
		if (name.endsWith('/behavior_editing_bridge')) {
			return { editBehavior: async (projectArg, executable, source, request) => {
				calls.push({ projectArg, executable, source, request }); return { source_path: source, content_hash: hash };
			} };
		}
		if (name.endsWith('/project_context')) {
			return { resolveProjectContext: async () => ({ projectDirectory: project, workspaceDirectory: project }) };
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
const base = 'res://Framework/Content/Behavior/';
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
	const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
	for (const name of ['addEntry', 'renameEntry', 'removeEntry', 'editValue', 'addEffect', 'removeConditionFromGroup', 'clearRequirements']) {
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
	const attribute = 'res://Framework/Content/Authored/Entity/Attributes/Abilities/reflex.tres';
	const unsupported = { version: 2, supported: false, source_path: attribute, roots: [], nodes: {},
		dependency_hashes: { [attribute]: hash }, catalog_paths: [] };
	const { validateGraph } = load(path.join(out, 'bridges/resource_bridge.js'));
	validateGraph(unsupported);
	assert.throws(() => validateGraph({ ...unsupported, roots: [attribute] }), /unsupported Resource/);
	const errorsBeforeUnsupported = errors.length;
	selection.follow({ document: { uri: uri(path.join(project, attribute.slice(6))) } }); await tick();
	loads[3].resolve(unsupported); await tick();
	check('Attribute schemas clear the behavior view without an error popup', published.length === 2
		&& errors.length === errorsBeforeUnsupported && statuses.at(-1).includes('Open an action'));
	selection.updateStatus();
	check('Unsupported selections retain their explanatory view message', statuses.at(-1).includes('Open an action'));
	selection.follow({ document: { uri: uri(path.join(project, names.interaction.slice(6))) } }); await tick();
	loads[4].resolve(graph); await tick();
	check('Returning to a behavior Resource restores its graph', published.length === 3 && statuses.at(-1) === undefined);
	selection.follow({ document: { uri: uri(path.join(project, names.action.slice(6))) } }); await tick();
	loads[5].reject(new Error('Behavior Resource has an empty authored ID.')); await tick();
	check('Malformed behavior Resources still report errors', errors.length === errorsBeforeUnsupported + 1
		&& errors.at(-1).includes('empty authored ID'));
	selection.follow({ document: { uri: uri(path.join(project, names.interaction.slice(6))) } }); await tick();
	selection.removed(uri(path.join(project, names.interaction.slice(6))));
	loads[6].resolve(graph); await tick(); await selection.refresh();
	check('Deleting the selected Resource clears details and discards pending loads', published.length === 3
		&& loads.length === 7 && statuses.at(-1).includes('Open a framework'));
	selection.dispose();
	await executorChecks();
	provider.dispose();
	console.log('[behavior-extension] Checks passed: true');
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
	descriptor.script_path = 'res://Framework/Content/Executor/direct_health_executor.gd';
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
}
