const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const { createHash } = require('node:crypto');
const { isInside } = require('../out/workspace/project_context.js');
const { AUTHORED_ROOT } = require('../out/bridges/attribute_library_bridge.js');

function load(relative, mocks) {
	const file = path.resolve(__dirname, '../out', relative), mod = { exports: {} }, original = createRequire(file);
	vm.runInNewContext(fs.readFileSync(file, 'utf8'), { module: mod, exports: mod.exports, Buffer,
		require: name => Object.hasOwn(mocks, name) ? mocks[name] : original(name) }, { filename: file });
	return mod.exports;
}
function uri(file) {
	const url = pathToFileURL(file);
	return { scheme: 'file', fsPath: file, path: decodeURIComponent(url.pathname), toString: () => url.href };
}
const project = path.resolve(__dirname, 'mock-project');
const secondProject = path.join(project, 'nested-project');
const context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
const secondContext = { projectDirectory: secondProject, workspaceDirectory: context.workspaceDirectory };
const calls = [], errors = [], information = [], prompts = [];
let answers = [], afterPick = () => {}, refreshes = 0;
const api = {
	EventEmitter: class { event = () => ({ dispose() {} }); fire() {} dispose() {} },
	Uri: { file: uri, joinPath: (base, ...parts) => uri(path.join(base.fsPath, ...parts)) },
	workspace: { isTrusted: true, workspaceFolders: [{ uri: uri(context.workspaceDirectory) }] },
	window: {
		activeTextEditor: undefined,
		async showQuickPick(items, options) {
			prompts.push({ items, options });
			const next = answers.shift(); const answer = typeof next === 'function' ? next(items) : next;
			afterPick(items, answer); return answer;
		},
		async showInformationMessage(message) { information.push(message); },
		async showErrorMessage(message) { errors.push(message); }
	}
};
const helpers = { ensureWorkspace(selected) {
	if (!api.workspace.isTrusted || !api.workspace.workspaceFolders.some(folder => path.relative(folder.uri.fsPath, selected.workspaceDirectory) === '')) {
		throw new Error('The trusted workspace changed.');
	}
} };
const tree = load('library/library_tree_provider.js', { vscode: api });
const { LibraryManageCommand } = load('library/library_manage_command.js', {
	vscode: api, './library_tree_provider': tree, '../resources/attribute_selection': helpers
});
const provider = new tree.LibraryTreeProvider();
const fingerprint = 'a'.repeat(64), empty = createHash('sha256').update('[]').digest('hex');
const entry = (source, parent, kind, supported = false, hash = fingerprint) => ({
	source_path: source, parent_path: parent, kind, supported, name: source.split('/').at(-1), fingerprint: hash
});
const folder = AUTHORED_ROOT + '/Entity', file = folder + '/health.tres', emptyFolder = AUTHORED_ROOT + '/Empty';
const catalogue = { version: 1, root_path: AUTHORED_ROOT, entries: [
	entry(AUTHORED_ROOT, '', 'root'), entry(folder, AUTHORED_ROOT, 'folder'),
	entry(file, folder, 'resource', true), entry(folder + '/other.tres', folder, 'resource', false),
	entry(emptyFolder, AUTHORED_ROOT, 'folder', false, empty),
	entry(AUTHORED_ROOT + '/HiddenFiles', AUTHORED_ROOT, 'folder'),
	entry(AUTHORED_ROOT + '/Linked', AUTHORED_ROOT, 'blocked', false, '')
] };
let projects = [{ context, catalogue }, { context: secondContext, catalogue }];
const delegate = { async execute(operation, element) { const resolved = provider.resolve(element); calls.push({ operation, element, ...resolved }); } };
const manager = new LibraryManageCommand(provider, delegate, async () => {
	refreshes++; provider.setProjects(structuredClone(projects));
}, { appendLine() {} });
const operation = label => items => { const found = items.find(item => item.label.startsWith(label)); assert.ok(found, label); return found; };
const target = (source, projectRoot = project) => items => {
	const found = items.find(item => item.choice.entry.source_path === source && item.choice.context.projectDirectory === projectRoot);
	assert.ok(found, source); return found;
};
const check = label => console.log(`[manage-library] ${label}: true`);
function reset() { answers = []; afterPick = () => {}; prompts.length = 0; }

async function main() {
	reset(); await manager.execute(); assert.equal(refreshes, 0); assert.equal(calls.length, 0);
	check('Cancelling the action menu performs no discovery or authoring');
	const cases = [
		['New Category', AUTHORED_ROOT, 'category'], ['New Subcategory', folder, 'category'],
		['New Attribute Resource', folder, 'resource'], ['Delete Resource', file, 'delete-resource'],
		['Delete Empty Category', emptyFolder, 'delete-category']
	];
	for (const [label, source, expected] of cases) {
		reset(); answers = [operation(label), target(source)]; await manager.execute();
		assert.equal(calls.at(-1).operation, expected); assert.equal(calls.at(-1).entry.source_path, source);
		assert.equal(prompts[1].options.matchOnDescription, true); assert.equal(prompts[1].options.matchOnDetail, true);
		assert.ok(prompts[1].items.every(item => item.description.includes(item.choice.entry.source_path.slice(6))
			&& item.detail === item.choice.context.projectDirectory));
	}
	check('All five operations route to existing library commands with visible project paths');
	reset(); answers = [operation('New Category'), target(AUTHORED_ROOT, secondProject)]; await manager.execute();
	assert.equal(calls.at(-1).context.projectDirectory, secondProject);
	check('Identical relative paths in different projects remain distinct');
	api.window.activeTextEditor = { document: { uri: uri(path.join(secondProject, file.slice(6))) } };
	reset(); answers = [operation('New Attribute Resource'), undefined]; const beforeCancel = calls.length;
	await manager.execute();
	assert.equal(prompts[1].items[0].choice.context.projectDirectory, secondProject);
	assert.equal(prompts[1].items[0].choice.entry.source_path, folder); assert.equal(calls.length, beforeCancel);
	check('The closest active project and its parent folder are offered first');
	reset(); answers = [operation('Delete Resource'), undefined]; await manager.execute();
	assert.equal(prompts[1].items[0].choice.entry.source_path, file);
	assert.ok(prompts[1].items.every(item => item.choice.entry.kind === 'resource' && item.choice.entry.supported));
	check('Resource deletion lists supported files and prioritizes the active file');
	reset(); answers = [operation('Delete Empty Category'), undefined]; await manager.execute();
	assert.ok(prompts[1].items.every(item => item.choice.entry.kind === 'folder' && item.choice.entry.fingerprint === empty));
	assert.ok(!prompts[1].items.some(item => item.choice.entry.source_path.endsWith('/HiddenFiles')));
	check('Empty-category deletion excludes roots, nonempty folders, hidden contents, and links');
	check('Cancelling a destination picker performs no authoring');
	reset(); answers = [operation('New Subcategory'), target(folder)];
	afterPick = items => { if (items[0]?.choice) { provider.clear(); } };
	await manager.execute(); assert.equal(calls.length, beforeCancel); assert.match(errors.at(-1), /current category/);
	check('Library revisions changing during the picker prevent stale dispatch');
	reset(); answers = [operation('New Subcategory'), target(folder)];
	afterPick = items => { if (items[0]?.choice) { api.workspace.isTrusted = false; } };
	await manager.execute(); assert.equal(calls.length, beforeCancel); assert.match(errors.at(-1), /workspace changed/);
	api.workspace.isTrusted = true;
	check('Workspace trust is checked again before invoking an operation');
	reset(); api.workspace.isTrusted = false; const beforePrompts = prompts.length; await manager.execute();
	assert.equal(prompts.length, beforePrompts); assert.equal(calls.length, beforeCancel); api.workspace.isTrusted = true;
	check('Untrusted workspaces cannot open the authoring workflow');
	projects = [{ context, catalogue: { ...catalogue, entries: catalogue.entries.filter(item => item.source_path !== emptyFolder) } }];
	reset(); answers = [operation('Delete Empty Category')]; await manager.execute();
	assert.equal(prompts.length, 1); assert.match(information.at(-1), /No empty categories/);
	check('No eligible deletion targets produces guidance without invoking a command');
	projects = []; reset(); answers = [operation('New Category')]; await manager.execute();
	assert.equal(prompts.length, 1); assert.match(information.at(-1), /No authored libraries/);
	check('A missing library gives project setup guidance');
	projects = [{ context, catalogue }]; provider.setProjects(projects);
	const copied = provider.getEntries().find(choice => choice.entry.source_path === file);
	copied.entry.name = 'changed'; copied.context.projectDirectory = 'changed';
	assert.equal(provider.resolve(copied.element).entry.name, 'health.tres');
	assert.equal(provider.resolve(copied.element).context.projectDirectory, project);
	check('Picker snapshots cannot mutate the library model');
	const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
	const manage = manifest.contributes.commands.find(item => item.command === 'resourceAttribute.manageLibrary');
	assert.equal(manage.icon, '$(folder-opened)');
	const navigation = manifest.contributes.menus['view/title'].filter(item => item.when === 'view == resourceAttribute.attributes')
		.sort((a, b) => a.group.localeCompare(b.group)).map(item => item.command);
	assert.deepEqual(navigation, ['resourceAttribute.findResource', 'resourceAttribute.manageLibrary', 'resourceAttribute.refresh']);
	check('The folder icon is ordered between Find Resource and Refresh');
	provider.dispose(); console.log('[manage-library] Checks passed: true');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
