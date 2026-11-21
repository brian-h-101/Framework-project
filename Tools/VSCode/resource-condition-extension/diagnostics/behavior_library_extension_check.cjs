const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { pathToFileURL } = require('node:url');
const { createHash } = require('node:crypto');
const root = 'res://Framework/Content/Behavior';
const project = path.resolve(__dirname, 'mock-project');
const other = path.resolve(__dirname, 'other-project');
const uri = file => ({ scheme: 'file', fsPath: file, path: file.replaceAll('\\', '/'), toString: () => pathToFileURL(file).href });
const hash = createHash('sha256').update('[]').digest('hex');
const entry = (source, kind, extra = {}) => ({ source_path: source, parent_path: source === root ? '' : source.slice(0, source.lastIndexOf('/')),
	name: source.split('/').at(-1), kind, fingerprint: hash, supported: false, ...extra });
const catalog = { version: 1, root_path: root, executors: [{id:'attribute_effects', label:'Attribute Effects', description:'', supports_effects:true, arguments:[]}], entries: [entry(root, 'root'), entry(root + '/Magic', 'folder'),
	entry(root + '/used', 'folder', { fingerprint: 'a'.repeat(64) }), entry(root + '/link', 'blocked', { fingerprint: '' }),
	entry(root + '/action.tres', 'resource', { supported: true, valid: true, resource_kind: 'action', id: 'action', argument_specs: [{ name: 'amount', numeric: true, required: true, allowed_types: ['int', 'float'] }] }),
	entry(root + '/group.tres', 'resource', { supported: true, valid: true, resource_kind: 'condition_group', id: 'group', argument_specs: [] }),
	entry(root + '/foreign.tres', 'resource', { supported: false, valid: false, resource_kind: '', id: '', argument_specs: [] })] };
const calls = [], picks = [], inputs = [], messages = [], trash = [], opened = [], changed = [];
let onPrompt, consumers = [], discoveries = 0;
const api = {
	Uri: { file: uri },
	workspace: { isTrusted: true, workspaceFolders: [{ uri: uri(path.dirname(project)) }], textDocuments: [],
		findFiles: async () => { discoveries++; return [uri(path.join(project, 'project.godot')), uri(path.join(other, 'project.godot'))]; },
		getConfiguration: () => ({ get: () => 'engine.exe' }), fs: { delete: async (...args) => trash.push(args) } },
	window: { activeTextEditor: undefined,
		showQuickPick: async (items, options) => { onPrompt?.(options); const next = picks.shift(); return typeof next === 'function' ? next(items, options) : next; },
		showInputBox: async options => { onPrompt?.(options); const value = inputs.shift(); if (value !== undefined && options.validateInput) { assert.equal(options.validateInput(value), undefined); } return value; },
		showWarningMessage: async (...args) => { messages.push(args); return picks.shift(); },
		showInformationMessage: async message => messages.push(message), showErrorMessage: async message => messages.push(message),
		showTextDocument: async value => opened.push(value), setStatusBarMessage() {} }
};
const contexts = directory => ({ projectDirectory: directory, workspaceDirectory: path.dirname(project) });
class Service {
	constructor(context, executable, report, ready) { this.context = context; this.ready = ready; }
	async catalogue() { return catalog; }
	async createCategory(entry, name) { await this.ready(); calls.push(['category', this.context, entry, name]); return entry.source_path + '/' + name; }
	async createResource(entry, name, request, snapshot) { await this.ready(); calls.push(['resource', this.context, entry, name, request, snapshot]); return entry.source_path + '/' + name; }
	async previewDeletion(entry) { await this.ready(true); calls.push(['preview', this.context, entry]); return { consumers }; }
	async deleteResource(entry, preview, callback) { await this.ready(true); calls.push(['delete-resource']); await callback(path.join(this.context.projectDirectory, entry.source_path.slice(6))); }
	async deleteEmptyCategory(entry, callback) { await this.ready(true); calls.push(['delete-category']); await callback(path.join(this.context.projectDirectory, entry.source_path.slice(6))); }
}
const cache = new Map();
function load(file) {
	file = path.resolve(file); if (cache.has(file)) { return cache.get(file).exports; }
	const module = { exports: {} }; cache.set(file, module);
	const localRequire = name => {
		if (name === 'vscode') { return api; }
		if (name === './library_service') { return { LibraryService: Service }; }
		if (name.endsWith('/project_context')) { return { ...require('../out/workspace/project_context.js'), resolveProjectContext: async file => contexts(path.dirname(file)) }; }
		return name.startsWith('.') ? load(path.resolve(path.dirname(file), name + '.js')) : require(name);
	};
	vm.runInThisContext('(function(require,module,exports){' + fs.readFileSync(file, 'utf8') + '\n})', { filename: file })(localRequire, module, module.exports);
	return module.exports;
}
const { LibraryManager } = load(path.join(__dirname, '../out/library/library_manager.js'));
const manager = new LibraryManager({ appendLine() {} }, async (...args) => changed.push(args));
const check = label => console.log(`[behavior-library-ui] ${label}: true`);
const op = label => items => items.find(item => item.label.startsWith(label));
const destination = source => items => { assert.ok(items.some(item => item.detail === other)); return items.find(item => item.entry.source_path === source && item.library.context.projectDirectory === project); };
async function main() {
	await manager.execute(); assert.equal(discoveries, 0);
	check('Cancelling management performs no discovery or write');
	picks.push(op('New Category'), destination(root)); inputs.push('Magic2'); await manager.execute();
	picks.push(op('New Subcategory'), destination(root + '/Magic')); inputs.push('Healing'); await manager.execute();
	assert.deepEqual(calls.slice(0, 2).map(call => [call[0], call[2].source_path, call[3]]), [['category', root, 'Magic2'], ['category', root + '/Magic', 'Healing']]);
	check('Category and subcategory routes keep project identity and parent paths');
	for (const type of ['Action', 'Condition Group', 'Condition', 'Interaction']) {
		picks.push(op('New Behavior'), destination(root + '/Magic'), items => items.find(item => item.label === type));
		inputs.push(type.toLowerCase().replaceAll(' ', '_') + '.tres', 'new_' + type.toLowerCase().replaceAll(' ', '_'));
		if (type === 'Action') { picks.push(items => items[0]); }
		if (type === 'Condition') { picks.push('actor', '>=', 'int'); inputs.push('strength', '["current"]', '9223372036854775807', 'Requires strength.'); }
		if (type === 'Interaction') { picks.push(items => items.find(item => item.path.endsWith('/action.tres')), 'int', items => items.find(item => item.path.endsWith('/group.tres'))); inputs.push('-7'); }
		await manager.execute();
	}
	const resources = calls.filter(call => call[0] === 'resource');
	assert.deepEqual(resources.map(call => call[4].resource_kind), ['action', 'condition_group', 'condition', 'interaction']);
	assert.equal(resources[2][4].requirement.value_text, '9223372036854775807');
	assert.deepEqual(resources[3][4].arguments, [{ name: 'amount', value_type: 'int', value_text: '-7' }]);
	assert.equal(resources[3][4].requirements_path, root + '/group.tres'); assert.equal(opened.length, 4);
	check('All four native Resource types collect complete creation data, preserving int64 text');
	assert.equal(resources[0][4].behavior_id, 'attribute_effects');
	const specs = catalog.entries.find(entry => entry.id === 'action').argument_specs;
	specs.push({ name: 'note', allowed_types: ['String'], required: false, numeric: false });
	for (const optional of ['Skip', 'Set value']) {
		picks.push(op('New Behavior'), destination(root + '/Magic'), op('Interaction'),
			items => items.find(item => item.path.endsWith('/action.tres')), 'int', optional);
		inputs.push('optional_' + optional.replaceAll(' ', '_') + '.tres', 'optional_' + optional.replaceAll(' ', '_'), '4');
		if (optional === 'Set value') {
			picks.push(items => { assert.deepEqual(items, ['String']); return 'String'; }); inputs.push('optional note');
		}
		picks.push(items => items.find(item => item.path === ''));
		await manager.execute();
		const args = calls.filter(call => call[0] === 'resource').at(-1)[4].arguments;
		assert.equal(args.length, optional === 'Skip' ? 1 : 2);
	}
	specs.pop();
	check('Action creation selects behavior; Interaction creation honors optional typed arguments');
	catalog.entries.push(entry(root + '/interaction.tres', 'resource', { supported: true, valid: true, resource_kind: 'interaction', id: 'strike', argument_specs: [] }));
	picks.push(op('New Behavior'), destination(root + '/Magic'), op('Automation'), items => items.find(item => item.path.endsWith('/interaction.tres')));
	inputs.push('automatic.tres', 'automatic', '0.25', '1');
	await manager.execute();
	const automatic = calls.filter(call => call[0] === 'resource').at(-1)[4];
	assert.deepEqual(automatic, { resource_kind: 'automation', id: 'automatic', interaction_path: root + '/interaction.tres', interval_seconds: 0.25, cooldown_seconds: 1 });
	check('Automation creation selects an Interaction and finite session-second durations');
	catalog.entries.pop();
	const writes = calls.filter(call => call[0] !== 'preview').length;
	for (let stage = 0; stage < 3; stage++) {
		picks.push(op('New Behavior'), stage === 0 ? undefined : destination(root), stage === 1 ? undefined : op('Action'));
		if (stage === 0) { picks.pop(); }
		await manager.execute(); picks.length = 0;
	}
	assert.equal(calls.filter(call => call[0] !== 'preview').length, writes);
	check('Cancelling destination, type, or filename performs no write');
	consumers = [{ source_path: 'res://consumer.tres', kind: 'authored_id' }];
	picks.push(op('Delete Resource'), items => { assert.ok(!items.some(item => item.entry.name === 'foreign.tres')); return destination(root + '/action.tres')(items); });
	await manager.execute(); assert.equal(trash.length, 0); assert.ok(JSON.stringify(messages).includes('consumer.tres'));
	consumers = []; picks.push(op('Delete Resource'), destination(root + '/action.tres'), 'Move to Recycle Bin'); await manager.execute();
	assert.equal(trash.length, 1); assert.deepEqual(trash[0][1], { useTrash: true, recursive: false }); assert.equal(changed.at(-1)[1], true);
	picks.push(op('Delete Empty Category'), items => { assert.ok(items.every(item => item.entry.source_path === root + '/Magic')); return items[0]; }, 'Move to Recycle Bin');
	await manager.execute(); assert.equal(trash.length, 2);
	check('Referenced resources are blocked; confirmed file and empty-folder deletions use nonrecursive Trash');
	onPrompt = options => { if (options.title === 'New Category — Name') { api.workspace.isTrusted = false; } };
	picks.push(op('New Category'), destination(root)); inputs.push('Blocked'); const count = calls.length; await manager.execute();
	assert.equal(calls.length, count); assert.match(messages.at(-1), /workspace changed/); onPrompt = undefined; api.workspace.isTrusted = true;
	api.workspace.textDocuments.push({ isDirty: true, uri: uri(path.join(project, 'consumer.gd')), fileName: 'consumer.gd' });
	picks.push(op('New Category'), destination(root)); inputs.push('Blocked'); await manager.execute(); assert.equal(calls.length, count); assert.match(messages.at(-1), /Save or revert/);
	api.workspace.textDocuments.length = 0;
	check('Workspace trust and dirty project consumers are rechecked after prompts');
	api.window.activeTextEditor = { document: { uri: uri(path.join(other, 'resource.tres')) } };
	picks.push(op('New Category'), items => { assert.equal(items[0].library.context.projectDirectory, other); return undefined; }); await manager.execute();
	check('Multi-root destinations prioritize the active Godot project');
	const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json')));
	const command = pkg.contributes.commands.find(item => item.command === 'customTreeView.manageBehaviorLibrary');
	assert.equal(command.icon, '$(folder-opened)');
	assert.ok(pkg.contributes.menus['view/title'].some(item => item.command === command.command && item.group === 'navigation@1'));
	check('Manage Behavior Library has a folder icon in the Resources toolbar');
	check('Checks passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
