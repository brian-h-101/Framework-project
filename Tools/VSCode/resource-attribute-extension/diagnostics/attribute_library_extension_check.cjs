const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const { AUTHORED_ROOT, validateCatalogue } = require('../out/bridges/attribute_library_bridge.js');

function load(relative, mocks = {}) {
	const file = path.resolve(__dirname, '../out', relative), mod = { exports: {} }, original = createRequire(file);
	vm.runInNewContext(fs.readFileSync(file, 'utf8'), { module: mod, exports: mod.exports, Buffer, AbortController,
		setTimeout, clearTimeout, require: name => Object.hasOwn(mocks, name) ? mocks[name] : original(name) }, { filename: file });
	return mod.exports;
}
function uri(file) {
	const url = pathToFileURL(path.resolve(file));
	return { scheme: 'file', fsPath: path.resolve(file), path: decodeURIComponent(url.pathname), toString: () => url.href };
}
const project = path.resolve(__dirname, 'mock-project'), context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
let answers = [], afterPrompt = () => {}, consumers = [], deleted = [], requests = [], refreshes = 0, cleared = [], shown = 0;
const errors = [], folders = [{ uri: uri(context.workspaceDirectory) }];
const api = {
	EventEmitter: class { event = () => ({ dispose() {} }); fire() {} dispose() {} },
	TreeItem: class { constructor(label, collapsibleState) { Object.assign(this, { label, collapsibleState }); } },
	ThemeIcon: class { constructor(id) { this.id = id; } }, TreeItemCollapsibleState: { None: 0, Expanded: 2, Collapsed: 1 },
	Uri: { file: uri, joinPath: (base, ...parts) => uri(path.join(base.fsPath, ...parts)) },
	workspace: { isTrusted: true, workspaceFolders: folders, textDocuments: [],
		fs: { async delete(file, options) { deleted.push({ file, options }); } } },
	window: { async showInputBox(options) { const answer = answers.shift(); afterPrompt(); if (answer !== undefined && options.validateInput) { assert.equal(options.validateInput(answer), undefined); } return answer; },
		async showWarningMessage() { const answer = answers.shift(); afterPrompt(); return answer; },
		async showTextDocument(file) { shown++; return file; }, async showErrorMessage(message) { errors.push(message); } }
};
const output = { appendLine() {}, show() { shown++; } };
const helpers = {
	ensureWorkspace() { if (!api.workspace.isTrusted || !api.workspace.workspaceFolders.length) { throw new Error('Workspace changed.'); } },
	godotExecutable: () => 'configured-godot.exe', workspaceDirectories: () => api.workspace.workspaceFolders.map(folder => folder.uri.fsPath)
};
const treeModule = load('library/library_tree_provider.js', { vscode: api });
const provider = new treeModule.LibraryTreeProvider();
const hash = 'a'.repeat(64);
const entry = (source, parent, kind, supported = false) => ({ source_path: source, parent_path: parent, kind, supported,
	name: source.split('/').at(-1), fingerprint: kind === 'blocked' ? '' : hash });
const catalogue = { version: 1, root_path: AUTHORED_ROOT, entries: [entry(AUTHORED_ROOT, '', 'root'),
	entry(AUTHORED_ROOT + '/Entity', AUTHORED_ROOT, 'folder'),
	entry(AUTHORED_ROOT + '/Entity/test.tres', AUTHORED_ROOT + '/Entity', 'resource', true),
	entry(AUTHORED_ROOT + '/Linked', AUTHORED_ROOT, 'blocked')] };
function select() {
	provider.setProjects([{ context, catalogue: structuredClone(catalogue) }]);
	const root = provider.getChildren()[0], folder = provider.getChildren(root).find(row => row.source.endsWith('/Entity'));
	return { root, folder, file: provider.getChildren(folder)[0] };
}
class Service {
	constructor(_context, _exe, _report, ready) { this.ready = ready; }
	async createCategory(entry, name) { await this.ready(); requests.push({ operation: 'category', entry, name }); return entry.source_path + '/' + name; }
	async createResource(entry, name, container) { await this.ready(); requests.push({ operation: 'resource', entry, name, container }); return entry.source_path + '/' + name; }
	async previewDeletion(entry) { await this.ready(true); return { source_path: entry.source_path, consumers }; }
	async deleteResource(entry, preview, trash) { await this.ready(true); assert.equal(preview.consumers.length, 0); await trash(path.join(project, entry.source_path.slice(6))); }
	async deleteEmptyCategory(entry, trash) { await this.ready(true); await trash(path.join(project, entry.source_path.slice(6))); }
}
const { LibraryCommands } = load('library/library_commands.js', { vscode: api,
	'../resources/attribute_selection': helpers, './library_service': { LibraryService: Service },
	'./library_paths': { ...require('../out/library/library_paths.js'), checkedAuthoredPath: async () => 'checked' },
	'./library_tree_provider': treeModule });
const commands = new LibraryCommands(provider, output, async () => { refreshes++; }, { resourceRemoved: file => cleared.push(file) });
const check = label => console.log(`[library-extension] ${label}: true`);

async function main() {
	let rows = select();
	assert.equal(provider.getTreeItem(rows.root).contextValue, 'library_root');
	assert.equal(provider.getTreeItem(rows.folder).contextValue, 'library_folder');
	assert.equal(provider.getTreeItem(rows.file).contextValue, 'library_resource_supported');
	assert.equal(provider.getParent(rows.file).source, rows.folder.source);
	check('Library folders, files, and protected roots have distinct roles');
	provider.setProjects([{ context, catalogue }, { context: { ...context, projectDirectory: project + '-two' }, catalogue }]);
	assert.equal(provider.getChildren().length, 2);
	assert.throws(() => provider.resolve(rows.file), /current category/);
	assert.equal(provider.getChildren(rows.folder).length, 0);
	assert.equal(provider.getParent(rows.file), undefined);
	check('Multiple project roots stay independent and stale rows are rejected');
	assert.throws(() => validateCatalogue({ ...catalogue, entries: [...catalogue.entries, catalogue.entries[1]] }), /repeated/);
	assert.throws(() => validateCatalogue({ ...catalogue, entries: [{ ...catalogue.entries[0], source_path: 'res://Outside' }] }), /path|root/);
	check('Catalogue validation rejects duplicate and escaping paths');
	rows = select(); answers = ['Vehicles']; await commands.execute('category', rows.root);
	assert.equal(requests.at(-1).entry.source_path, AUTHORED_ROOT); assert.equal(requests.at(-1).name, 'Vehicles');
	answers = ['Statistics']; await commands.execute('category', rows.folder);
	assert.equal(requests.at(-1).entry.source_path, AUTHORED_ROOT + '/Entity');
	check('Category prompts route to the selected root or nested folder');
	answers = ['durability.tres', 'durability']; await commands.execute('resource', rows.folder);
	assert.equal(requests.at(-1).container, 'durability'); assert.equal(shown, 1);
	check('New resources collect a native container name and open the published file');
	const before = requests.length; answers = []; await commands.execute('category', rows.root);
	assert.equal(requests.length, before);
	check('Prompt cancellation creates no directory or file');
	consumers = [{ source_path: 'res://profile.tres', kind: 'resource' }]; answers = ['Show References'];
	await commands.execute('delete-resource', rows.file); assert.equal(deleted.length, 0); assert.equal(shown, 2);
	check('Referenced files display their consumers without offering forced deletion');
	consumers = []; answers = []; await commands.execute('delete-resource', rows.file); assert.equal(deleted.length, 0);
	check('Cancelling deletion leaves the selected file untouched');
	answers = ['Delete Resource']; await commands.execute('delete-resource', rows.file);
	assert.equal(deleted.length, 1); assert.equal(deleted[0].options.useTrash, true); assert.equal(deleted[0].options.recursive, false);
	assert.equal(cleared.length, 1);
	check('Confirmed resource deletion uses the Recycle Bin and clears selected details');
	answers = ['Delete Category']; await commands.execute('delete-category', rows.folder);
	assert.equal(deleted.length, 2); assert.equal(deleted[1].options.recursive, false);
	check('Category deletion requests are nonrecursive');
	api.workspace.textDocuments = [{ isDirty: true, uri: uri(path.join(project, 'unsaved.gd')) }];
	await commands.execute('delete-resource', rows.file); assert.equal(deleted.length, 2); assert.match(errors.at(-1), /Save or revert/);
	api.workspace.textDocuments = [];
	check('Unsaved project references prevent deletion checks');
	answers = ['Late']; afterPrompt = () => { provider.clear(); afterPrompt = () => {}; };
	await commands.execute('category', rows.root); assert.equal(requests.length, before); assert.match(errors.at(-1), /current category/);
	check('A changed library selection during prompts prevents creation');
	rows = select(); api.workspace.isTrusted = false; await commands.execute('category', rows.root);
	assert.equal(requests.length, before); api.workspace.isTrusted = true;
	check('Untrusted workspaces cannot author library entries');
	const pending = [], published = [], statuses = [];
	api.workspace.findFiles = async () => [uri(path.join(project, 'project.godot'))];
	const { LibraryController } = load('library/library_controller.js', { vscode: api,
		'../workspace/project_context': { resolveProjectContext: async () => context },
		'../resources/attribute_selection': helpers,
		'./library_service': { LibraryService: class { catalogue(signal) { return new Promise(resolve => pending.push({ resolve, signal })); } } }
	});
	const controller = new LibraryController({ clear() {}, setProjects: projects => published.push(projects) }, output, message => statuses.push(message));
	const tick = () => new Promise(resolve => setImmediate(resolve));
	const first = controller.refresh(); await tick(); const second = controller.refresh(); await tick();
	assert.equal(pending[0].signal.aborted, true); pending[1].resolve(catalogue); await second;
	pending[0].resolve(catalogue); await first;
	assert.equal(published.length, 1); assert.equal(published[0][0].context.projectDirectory, project);
	check('Library discovery works without an active file and rejects late responses');
	controller.dispose(); provider.dispose();
	const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
	assert.ok(manifest.contributes.views.frameworkAttributes.some(view => view.id === 'resourceAttribute.library'));
	assert.ok(manifest.contributes.views.frameworkAttributes.some(view => view.id === 'resourceAttribute.attributes'));
	for (const name of ['newCategory', 'newSubcategory', 'newAttributeResource', 'deleteResource', 'deleteCategory']) {
		assert.ok(manifest.contributes.menus['resourceAttribute.libraryMenu'].some(item => item.command === 'resourceAttribute.' + name));
	}
	check('The container exposes library and detail views with curated authoring menus');
	assert.ok(refreshes >= 5);
	console.log('[library-extension] Checks passed: true');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
