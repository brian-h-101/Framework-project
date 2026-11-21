const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { pathToFileURL } = require('node:url');
const { createHash } = require('node:crypto');
const { SCENE_ROOTS, validateCatalogue } = require('../out/library/scene_library_bridge');
const project = path.resolve(__dirname, 'mock-project'), other = path.resolve(__dirname, 'other-project');
const uri = file => ({ scheme: 'file', fsPath: file, path: file.replaceAll('\\', '/'), toString: () => pathToFileURL(file).href });
const hash = createHash('sha256').update('[]').digest('hex');
const entry = (source, kind, extra = {}) => ({ source_path: source, parent_path: SCENE_ROOTS.includes(source) ? '' : source.slice(0, source.lastIndexOf('/')),
	name: source.split('/').at(-1), kind, fingerprint: hash, supported: kind === 'resource', ...extra });
const catalogue = { version: 1, root_paths: [...SCENE_ROOTS], entries: SCENE_ROOTS.flatMap(root => [entry(root, 'root'),
	entry(root + '/Empty', 'folder'), entry(root + '/Used', 'folder', { fingerprint: 'a'.repeat(64) }),
	entry(root + '/Link', 'blocked', { fingerprint: '' }), entry(root + '/scene.tscn', 'resource')]) };
const calls = [], picks = [], inputs = [], messages = [], trash = [], opened = [], changes = [];
let onPrompt, consumers = [], discoveries = 0;
const api = {
	Uri: { file: uri },
	workspace: { isTrusted: true, workspaceFolders: [{ uri: uri(path.dirname(project)) }], textDocuments: [],
		findFiles: async () => { discoveries++; return [uri(path.join(project, 'project.godot')), uri(path.join(other, 'project.godot'))]; },
		getConfiguration: () => ({ get: () => 'engine.exe' }), fs: { delete: async (...args) => trash.push(args) } },
	window: { activeTextEditor: undefined,
		showQuickPick: async (items, options) => { onPrompt?.(options); const next = picks.shift(); return typeof next === 'function' ? next(items, options) : next; },
		showInputBox: async options => { onPrompt?.(options); const next = inputs.shift(); if (next !== undefined && options.validateInput) assert.equal(options.validateInput(next), undefined); return next; },
		showWarningMessage: async (...args) => { messages.push(args); return picks.shift(); },
		showErrorMessage: async message => messages.push(message), showInformationMessage: async message => messages.push(message),
		showTextDocument: async target => opened.push(target) }
};
class Service {
	constructor(context, executable, report, ready) { Object.assign(this, { context, executable, ready }); }
	async catalogue() { return catalogue; }
	async createCategory(entry, name) { await this.ready(); calls.push(['category', this.context, entry, name]); return entry.source_path + '/' + name; }
	async createScene(entry, name, request, snapshot) { await this.ready(); calls.push(['scene', this.context, entry, name, request, snapshot]); return entry.source_path + '/' + name; }
	async previewDeletion(entry) { await this.ready(true); calls.push(['preview']); return { consumers }; }
	async deleteScene(entry, preview, callback) { await this.ready(true); calls.push(['delete-scene']); await callback(path.join(this.context.projectDirectory, entry.source_path.slice(6))); }
	async deleteEmptyCategory(entry, callback) { await this.ready(true); calls.push(['delete-category']); await callback(path.join(this.context.projectDirectory, entry.source_path.slice(6))); }
}
const cache = new Map();
function load(file) {
	file = path.resolve(file); if (cache.has(file)) return cache.get(file).exports;
	const module = { exports: {} }; cache.set(file, module);
	const local = name => {
		if (name === 'vscode') return api;
		if (name === './library_service') return { LibraryService: Service };
		if (name === '../scene_editing_bridge') return { nodeTypes: async () => ['Node', 'Node2D', 'Node3D', 'CharacterBody2D'] };
		if (name === '../project_context') return { ...require('../out/project_context'), resolveProjectContext: async file => ({ projectDirectory: path.dirname(file), workspaceDirectory: path.dirname(project) }) };
		return name.startsWith('.') ? load(path.resolve(path.dirname(file), name + '.js')) : require(name);
	};
	vm.runInThisContext('(function(require,module,exports){' + fs.readFileSync(file, 'utf8') + '\n})', { filename: file })(local, module, module.exports);
	return module.exports;
}
const { LibraryManager } = load(path.join(__dirname, '../out/library/library_manager.js'));
const manager = new LibraryManager({ appendLine() {} }, async (...args) => changes.push(args));
const op = prefix => items => items.find(item => item.label.startsWith(prefix));
const destination = source => items => { assert.ok(items.some(item => item.detail === other)); return items.find(item => item.entry.source_path === source && item.library.context.projectDirectory === project); };
const check = label => console.log(`[scene-library-ui] ${label}: true`);

async function main() {
	validateCatalogue(catalogue);
	assert.throws(() => validateCatalogue({ ...catalogue, entries: [...catalogue.entries, entry('res://Framework/Content/Camera', 'root')] }), /path/);
	assert.throws(() => validateCatalogue({ ...catalogue, entries: [...catalogue.entries, catalogue.entries[0]] }), /repeated/);
	check('Catalogue validation requires exactly the three scoped roots');
	await manager.execute(); assert.equal(discoveries, 0);
	check('Cancelling management performs no discovery');
	for (const root of SCENE_ROOTS) {
		picks.push(op('New Category'), destination(root)); inputs.push('Category'); await manager.execute();
		picks.push(op('New Subcategory'), destination(root + '/Empty')); inputs.push('Nested'); await manager.execute();
	}
	assert.equal(calls.filter(call => call[0] === 'category').length, 6);
	check('Category and subcategory creation routes to each selected project and library');
	for (const [root, template, native] of [
		[SCENE_ROOTS[0], '2D Map', undefined], [SCENE_ROOTS[0], 'Empty 3D', undefined],
		[SCENE_ROOTS[1], 'Presentation', 'CharacterBody2D'], [SCENE_ROOTS[2], 'Control Widget', undefined], [SCENE_ROOTS[2], 'HUD Parent', undefined]
	]) {
		picks.push(op('New Scene'), destination(root + '/Empty'), items => {
			assert.ok(items.every(item => item.root === root)); return items.find(item => item.label.startsWith(template));
		});
		if (native) picks.push(native);
		inputs.push('new_scene.tscn', 'NewScene'); await manager.execute();
	}
	const scenes = calls.filter(call => call[0] === 'scene');
	assert.deepEqual(scenes.map(call => call[4].template), ['map_2d', 'empty_3d', 'presentation', 'control', 'hud']);
	assert.equal(scenes[2][4].root_type, 'CharacterBody2D'); assert.equal(opened.length, 5);
	check('Scene prompts expose only appropriate templates and open the created file');
	const writes = calls.length;
	for (const sequence of [[], [destination(SCENE_ROOTS[0])], [destination(SCENE_ROOTS[0]), op('Empty 2D')]]) {
		picks.push(op('New Scene'), ...sequence); await manager.execute(); picks.length = 0;
	}
	assert.equal(calls.length, writes);
	check('Cancelled destination, template, and filename prompts perform no write');
	consumers = [{ source_path: 'res://consumer.tscn', kind: 'resource' }];
	picks.push(op('Delete Scene'), destination(SCENE_ROOTS[0] + '/scene.tscn')); await manager.execute();
	assert.equal(trash.length, 0); assert.ok(JSON.stringify(messages).includes('consumer.tscn'));
	consumers = []; picks.push(op('Delete Scene'), destination(SCENE_ROOTS[0] + '/scene.tscn'), undefined); await manager.execute(); assert.equal(trash.length, 0);
	picks.push(op('Delete Scene'), destination(SCENE_ROOTS[0] + '/scene.tscn'), 'Move to Recycle Bin'); await manager.execute();
	assert.equal(trash.length, 1); assert.deepEqual(trash[0][1], { useTrash: true, recursive: false }); assert.equal(changes.at(-1)[1], true);
	picks.push(op('Delete Empty Category'), items => { assert.ok(items.every(item => item.entry.name === 'Empty')); return items[0]; }, 'Move to Recycle Bin'); await manager.execute();
	assert.equal(trash.length, 2);
	check('References and cancellation block deletion; confirmed deletes use nonrecursive Trash');
	const before = calls.length;
	onPrompt = options => { if (options.title === 'New Category — Name') api.workspace.isTrusted = false; };
	picks.push(op('New Category'), destination(SCENE_ROOTS[0])); inputs.push('Blocked'); await manager.execute();
	assert.equal(calls.length, before); api.workspace.isTrusted = true; onPrompt = undefined;
	api.workspace.textDocuments.push({ isDirty: true, uri: uri(path.join(project, 'references.gd')), fileName: 'references.gd' });
	picks.push(op('New Category'), destination(SCENE_ROOTS[0])); inputs.push('Blocked'); await manager.execute(); assert.equal(calls.length, before);
	api.workspace.textDocuments.length = 0;
	check('Workspace trust and unsaved project references are checked again after prompts');
	api.window.activeTextEditor = { document: { uri: uri(path.join(other, 'scene.tscn')) } };
	picks.push(op('New Category'), items => { assert.equal(items[0].library.context.projectDirectory, other); return undefined; }); await manager.execute();
	check('Multiple projects remain distinct and the active project is offered first');
	const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json')));
	assert.equal(pkg.contributes.commands.find(item => item.command === 'frameworkScenes.manageAuthoredLibrary').icon, '$(folder-opened)');
	assert.ok(pkg.contributes.menus['view/title'].some(item => item.command === 'frameworkScenes.manageAuthoredLibrary' && item.group === 'navigation@2'));
	check('The folder icon is between Find a Scene and Refresh'); check('Checks passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
