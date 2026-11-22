const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const { pathToFileURL } = require('node:url');
const { createHash } = require('node:crypto');

function load(relative, mocks = {}) {
	const file = path.resolve(__dirname, '../out', relative);
	const loaded = { exports: {} };
	const original = createRequire(file);
	vm.runInNewContext(fs.readFileSync(file, 'utf8'), {
		module: loaded, exports: loaded.exports, Buffer, AbortController, setTimeout, clearTimeout,
		require: name => Object.hasOwn(mocks, name) ? mocks[name] : original(name)
	}, { filename: file });
	return loaded.exports;
}

function uri(file) {
	const url = pathToFileURL(file);
	return { scheme: 'file', fsPath: path.resolve(file), path: decodeURIComponent(url.pathname), toString: () => url.href };
}
class EventEmitter {
	event = () => ({ dispose() {} });
	fire() {}
	dispose() {}
}
class TreeItem { constructor(label, collapsibleState) { Object.assign(this, { label, collapsibleState }); } }
class ThemeIcon { constructor(id) { this.id = id; } }
const errors = [];
let answers = [];
let writes = [];
let afterPrompt = () => {};
let dirty = false;
const bytes = Buffer.from('attribute fixture');
const source = 'res://Framework/Content/Gameplay/Authored/Entity/test.tres';
const project = path.resolve(__dirname, '../../../../framework-project');
const context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
const resourceUri = uri(path.join(project, source.slice(6)));
const api = {
	EventEmitter, TreeItem, ThemeIcon,
	TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
	Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
	workspace: {
		isTrusted: true,
		workspaceFolders: [{ uri: uri(context.workspaceDirectory) }],
		get textDocuments() { return dirty ? [{ isDirty: true, uri: resourceUri }] : []; },
		fs: { async readFile() { return bytes; } },
		getConfiguration: () => ({ get: () => 'configured-godot.exe' })
	},
	window: {
		async showQuickPick() { const result = answers.shift(); afterPrompt(); return result; },
		async showInputBox() { const result = answers.shift(); afterPrompt(); return result; },
		async showWarningMessage() { const result = answers.shift(); afterPrompt(); return result; },
		showErrorMessage: async message => { errors.push(message); },
		showInformationMessage: async () => {}
	}
};
const { AttributeTreeProvider } = load('tree/attribute_tree_provider.js', { vscode: api });
const provider = new AttributeTreeProvider();
const hash = createHash('sha256').update(bytes).digest('hex');
const key = (kind, text) => ({ kind, text });
const rootKey = key('StringName', 'needs');
const collection = (label, parts, children) => ({
	label, path: parts, kind: 'Dictionary', value_text: `${children.length} entries`, children,
	editable: false, mutable: parts.length > 0, can_add: true
});
const leaf = (label, parts, kind = 'int', text = '1') => ({
	label, path: parts, kind, value_text: text, children: [], editable: true, mutable: true, can_add: false
});
function graph(file = source) {
	const scalar = leaf('current', [rootKey, key('String', 'current')]);
	const arrayPath = [rootKey, key('String', 'items')];
	const array = { ...collection('items', arrayPath, [leaf('[0]', [...arrayPath, key('index', '0')])]), kind: 'Array' };
	return { version: 1, source_path: file, content_hash: hash, supported: true,
		root: collection(file.split('/').pop(), [], [collection('needs', [rootKey], [scalar, array])]) };
}
const output = { appendLine() {} };
const workspaceMock = {
	async attributePathInProject() { return source; },
	async resolveProjectContext() { return context; },
	isInside: (directory, candidate) => candidate.startsWith(directory)
};
const selectionHelpers = load('resources/attribute_selection.js', {
	vscode: api, '../workspace/project_context': workspaceMock,
	'../bridges/attribute_bridge': {}
});
const { AttributeCommands, numberError } = load('commands/attribute_commands.js', {
	vscode: api,
	'../tree/attribute_tree_provider': { projectUri: () => resourceUri },
	'../workspace/project_context': workspaceMock,
	'../resources/attribute_selection': selectionHelpers,
	'../bridges/attribute_bridge': { async editAttributes(...args) { writes.push(args[3]); return graph(); } }
});
let refreshed = 0;
const commands = new AttributeCommands(provider, output, async () => { refreshed++; });
function select() {
	provider.setGraph(context, graph());
	const root = provider.getChildren()[0];
	const container = provider.getChildren(root)[0];
	const [value, array] = provider.getChildren(container);
	return { root, container, value, array, item: provider.getChildren(array)[0] };
}
function check(label, action) { action(); console.log(`[attribute-extension] ${label}: true`); }
async function test(label, action) { await action(); console.log(`[attribute-extension] ${label}: true`); }

(async () => {
	const validation = load('bridges/attribute_bridge.js');
	check('Typed graph validation and exact integer text', () => {
		const fixture = graph();
		fixture.root.children[0].children[0].value_text = '9223372036854775807';
		assert.equal(validation.validateGraph(fixture, source).root.children[0].children[0].value_text, '9223372036854775807');
		const broken = structuredClone(fixture);
		broken.root.children[0].children[0].path[0] = key('StringName', 'wrong');
		assert.throws(() => validation.validateGraph(broken, source), /path|tree/i);
		assert.throws(() => validation.validateGraph({ ...fixture, content_hash: 'bad' }, source), /graph/i);
	});
	check('Context commands match node roles and stale rows are rejected', () => {
		const elements = select();
		assert.match(provider.getTreeItem(elements.root).contextValue, /_root_add/);
		assert.doesNotMatch(provider.getTreeItem(elements.root).contextValue, /_remove/);
		assert.match(provider.getTreeItem(elements.value).contextValue, /_edit/);
		assert.doesNotMatch(provider.getTreeItem(elements.item).contextValue, /_rename/);
		provider.clear();
		assert.throws(() => provider.resolve(elements.value), /current entry/);
	});
	check('Numeric input preserves the 64-bit range', () => {
		assert.equal(numberError('int', '9223372036854775807'), undefined);
		assert.equal(numberError('int', '-9223372036854775808'), undefined);
		for (const text of ['9223372036854775808', '-9223372036854775809', '20.0', '']) {
			assert.ok(numberError('int', text));
		}
		assert.equal(numberError('float', '1.25e2'), undefined);
		assert.ok(numberError('float', '1e999'));
	});
	await test('Edit sends typed paths and exact value text', async () => {
		answers = ['int', '9223372036854775807'];
		await commands.execute('set', select().value);
		assert.equal(writes.at(-1).value_text, '9223372036854775807');
		assert.equal(writes.at(-1).path[0].kind, 'StringName');
		assert.equal(writes.at(-1).expected_hash, hash);
		assert.equal(refreshed, 1);
	});
	await test('Container, dictionary and array additions route correctly', async () => {
		answers = ['StringName', 'new_container'];
		await commands.execute('add', select().root);
		assert.equal(writes.at(-1).value_type, 'Dictionary');
		assert.equal(writes.at(-1).key.text, 'new_container');
		answers = ['String', 'new_attribute', 'Array'];
		await commands.execute('add', select().container);
		assert.equal(writes.at(-1).value_text, '[]');
		answers = ['bool', 'true'];
		await commands.execute('add', select().array);
		assert.equal(writes.at(-1).key, undefined);
		assert.equal(writes.at(-1).value_type, 'bool');
	});
	await test('Rename and removal use the selected entry', async () => {
		answers = ['String', 'renamed'];
		await commands.execute('rename', select().value);
		assert.equal(writes.at(-1).key.text, 'renamed');
		answers = ['Remove Entry'];
		await commands.execute('remove', select().item);
		assert.equal(writes.at(-1).operation, 'remove');
		assert.equal(writes.at(-1).path.at(-1).kind, 'index');
	});
	await test('Cancellation at each prompt writes nothing', async () => {
		const before = writes.length;
		for (const input of [[], ['int']]) {
			answers = input.slice(); await commands.execute('set', select().value);
		}
		for (const input of [[], ['String'], ['String', 'name'], ['String', 'name', 'String']]) {
			answers = input.slice(); await commands.execute('add', select().container);
		}
		answers = []; await commands.execute('remove', select().value);
		answers = ['bool']; await commands.execute('set', select().value);
		assert.equal(writes.length, before);
	});
	await test('Dirty, changed and untrusted files cannot write', async () => {
		const before = writes.length;
		dirty = true; await commands.execute('set', select().value); dirty = false;
		api.workspace.isTrusted = false; await commands.execute('set', select().value); api.workspace.isTrusted = true;
		const original = api.workspace.fs.readFile;
		api.workspace.fs.readFile = async () => Buffer.from('changed');
		await commands.execute('set', select().value);
		api.workspace.fs.readFile = original;
		assert.equal(writes.length, before);
		assert.ok(errors.some(message => /resource file changed/i.test(message)));
	});
	await test('Changes during prompts reject the pending edit', async () => {
		const before = writes.length;
		answers = ['int', '3']; afterPrompt = () => { dirty = true; };
		await commands.execute('set', select().value);
		dirty = false;
		answers = ['int', '3']; afterPrompt = () => { provider.clear(); };
		await commands.execute('set', select().value);
		afterPrompt = () => {};
		assert.equal(writes.length, before);
	});
	await test('Only one edit dialog runs at a time', async () => {
		const before = writes.length;
		answers = [];
		const element = select().value;
		await Promise.all([commands.execute('set', element), commands.execute('remove', element)]);
		assert.equal(writes.length, before);
	});
	await test('File following uses latest results and clears on workspace removal', async () => {
		const pending = [];
		const { AttributeSelection: Selection } = load('resources/attribute_selection.js', {
			vscode: api, '../workspace/project_context': workspaceMock,
			'../bridges/attribute_bridge': { inspectAttributes: async (...args) => new Promise(resolve => pending.push({ args, resolve })) }
		});
		const statuses = [];
		const selection = new Selection(provider, output, text => statuses.push(text));
		selection.follow({ document: { uri: resourceUri } });
		await new Promise(resolve => setImmediate(resolve));
		const secondUri = uri(path.join(project, 'Framework/Content/Gameplay/Authored/Entity/other.tres'));
		workspaceMock.attributePathInProject = async (_context, file) => file.endsWith('other.tres') ? source.replace('test.tres', 'other.tres') : source;
		selection.follow({ document: { uri: secondUri } });
		await new Promise(resolve => setImmediate(resolve));
		pending[1].resolve(graph(source.replace('test.tres', 'other.tres')));
		await new Promise(resolve => setImmediate(resolve));
		pending[0].resolve(graph());
		await new Promise(resolve => setImmediate(resolve));
		assert.equal(provider.resolve(provider.getChildren()[0]).graph.source_path, source.replace('test.tres', 'other.tres'));
		const folders = api.workspace.workspaceFolders;
		api.workspace.workspaceFolders = [];
		selection.workspaceChanged();
		assert.equal(provider.getChildren().length, 0);
		api.workspace.workspaceFolders = folders;
		selection.dispose();
	});
	await test('Real project resolution supports parent, multi-root and nested workspaces', async () => {
		const resolver = require('../out/workspace/project_context.js');
		const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'resource-attribute-check-'));
		const makeProject = directory => {
			fs.mkdirSync(path.join(directory, 'Framework/Env/Authoring/Attributes'), { recursive: true });
			fs.writeFileSync(path.join(directory, 'project.godot'), 'config_version=5\n');
			fs.writeFileSync(path.join(directory, 'Framework/Env/Authoring/Attributes/attribute_cli.gd'), 'extends SceneTree\n');
			const file = path.join(directory, 'attributes.tres'); fs.writeFileSync(file, 'fixture'); return file;
		};
		try {
			const one = path.join(temporary, 'one'); const two = path.join(temporary, 'two');
			const oneFile = makeProject(one); const twoFile = makeProject(two);
			assert.equal((await resolver.resolveProjectContext(oneFile, [one])).projectDirectory, one);
			assert.equal((await resolver.resolveProjectContext(oneFile, [temporary])).projectDirectory, one);
			assert.equal((await resolver.resolveProjectContext(twoFile, [one, two])).projectDirectory, two);
			const nested = path.join(one, 'nested'); const nestedFile = makeProject(nested);
			assert.equal((await resolver.resolveProjectContext(nestedFile, [temporary])).projectDirectory, nested);
			const oneContext = await resolver.resolveProjectContext(oneFile, [temporary]);
			await assert.rejects(resolver.attributePathInProject(oneContext, twoFile), /same Godot project/i);
			await assert.rejects(resolver.resolveProjectContext(oneFile, [two]), /workspace/i);
			const unsupported = path.join(one, 'unsupported'); fs.mkdirSync(unsupported);
			fs.writeFileSync(path.join(unsupported, 'project.godot'), 'config_version=5');
			const unsupportedFile = path.join(unsupported, 'x.tres'); fs.writeFileSync(unsupportedFile, 'fixture');
			await assert.rejects(resolver.resolveProjectContext(unsupportedFile, [temporary]), /helper/i);
		} finally {
			assert.equal(path.dirname(path.resolve(temporary)), path.resolve(os.tmpdir()));
			assert.ok(path.basename(temporary).startsWith('resource-attribute-check-'));
			assert.equal(fs.realpathSync(temporary), temporary);
			fs.rmSync(temporary, { recursive: true });
		}
	});
	check('Activation registers every declared command and the dedicated view', () => {
		const registered = new Map();
		const disposable = () => ({ dispose() {} });
		let viewId;
		api.commands = { registerCommand(id, action) { registered.set(id, action); return disposable(); } };
		api.window.createOutputChannel = () => ({ ...output, dispose() {} });
		api.window.createTreeView = id => { viewId = id; return disposable(); };
		for (const name of ['onDidChangeActiveTextEditor']) { api.window[name] = disposable; }
		for (const name of ['onDidSaveTextDocument', 'onDidChangeTextDocument', 'onDidChangeWorkspaceFolders', 'onDidChangeConfiguration']) {
			api.workspace[name] = disposable;
		}
		api.workspace.createFileSystemWatcher = () => ({
			dispose() {}, onDidChange: disposable, onDidCreate: disposable, onDidDelete: disposable
		});
		class Selection { follow() {} dispose() {} }
		const extension = load('extension.js', {
			vscode: api,
			'./library/library_tree_provider': { LibraryTreeProvider: class {} },
			'./library/library_controller': { LibraryController: class { async refresh() {} } },
			'./library/library_commands': { LibraryCommands: class {} },
			'./library/library_manage_command': { LibraryManageCommand: class {} },
			'./tree/attribute_tree_provider': { AttributeTreeProvider, projectUri: () => resourceUri },
			'./resources/attribute_selection': { AttributeSelection: Selection },
			'./commands/attribute_commands': { AttributeCommands },
			'./workspace/project_context': workspaceMock
		});
		const subscriptions = [];
		extension.activate({ subscriptions });
		const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
		assert.equal(viewId, 'resourceAttribute.attributes');
		for (const command of manifest.contributes.commands) { assert.ok(registered.has(command.command), command.command); }
		assert.equal(manifest.name, 'resource-attribute');
		assert.ok(subscriptions.length > registered.size);
	});
	provider.dispose();
	console.log('[attribute-extension] Checks passed: true');
})().catch(error => { console.error(error); process.exitCode = 1; });
