const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const { pathToFileURL } = require('node:url');

const out = path.resolve(__dirname, '../out');
const project = path.resolve(__dirname, 'mock-project');
const hash = 'a'.repeat(64);
const source = 'res://Framework/Content/Behavior/Action/a.tres';
const second = source.replace('a.tres', 'b.tres');
const graph = file => ({ version: 2, mode: 'browse', roots: [file], catalog_paths: [], executors: [],
	dependency_hashes: { [file]: hash }, nodes: { [file]: { id: 'probe', kind: 'action', source_path: file,
		content_hash: hash, links: [], data: { label: 'data', kind: 'Dictionary', value_text: '', path: [], children: [],
			editable: false, mutable: false, can_add: false, can_remove: false, can_rename: false,
			can_add_effect: false, allowed_types: [], choices: [] } } } });
function loader(overrides) {
	const modules = new Map();
	return function load(file) {
		file = path.resolve(file);
		if (modules.has(file)) { return modules.get(file).exports; }
		const mod = { exports: {} }; modules.set(file, mod);
		const local = name => overrides(name, file) ?? (name.startsWith('.')
			? load(path.resolve(path.dirname(file), name + '.js')) : require(name));
		vm.runInThisContext('(function(require,module,exports){' + fs.readFileSync(file, 'utf8') + '\n})', { filename: file })(local, mod, mod.exports);
		return mod.exports;
	};
}
function check(label, value = true) { assert.ok(value, label); console.log('[resource-performance] ' + label + ': true'); }
const tick = () => new Promise(resolve => setImmediate(resolve));
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

async function workerChecks() {
	const children = [];
	const load = loader(name => name === 'node:child_process' ? { spawn(exe, args, options) {
		const child = new EventEmitter();
		child.exe = exe; child.args = args; child.options = options; child.killed = false; child.writes = [];
		child.stdout = new EventEmitter(); child.stdout.setEncoding = () => undefined;
		child.stderr = new EventEmitter(); child.stderr.setEncoding = () => undefined;
		child.stdin = new EventEmitter(); child.stdin.destroy = () => undefined;
		child.stdin.write = buffer => {
			assert.equal(buffer.readUInt32LE(0), buffer.length - 4);
			child.writes.push(JSON.parse(buffer.subarray(4).toString('utf8')));
		};
		child.kill = () => { child.killed = true; };
		child.packet = packet => child.stdout.emit('data', '[resource-browse] ' + JSON.stringify(packet) + '\r\n');
		child.ready = () => child.packet({ protocol: 1, ready: true });
		child.reply = (value = graph(child.writes.at(-1).source)) => child.packet({ protocol: 1,
			id: child.writes.at(-1).id, result: { ok: true, value } });
		children.push(child); return child;
	} } : undefined);
	const { ResourceBrowsePool } = load(path.join(out, 'bridges/resource_browse_bridge.js'));
	const pool = new ResourceBrowsePool(500, 10_000);
	try {
		const first = pool.load(project, 'godot.exe', source, () => undefined);
		const child = children.at(-1);
		assert.equal(child.writes.length, 0); child.ready(); child.reply(); await first;
		const unicode = second.replace('b.tres', 'caf\u00e9.tres');
		const next = pool.load(project, 'godot.exe', unicode, () => undefined);
		assert.equal(child.writes.at(-1).source, unicode); child.reply(); await next;
		check('Completed requests reuse one hidden worker and preserve UTF-8 framing', children.length === 1 && child.options.windowsHide);
		const active = pool.load(project, 'godot.exe', source, () => undefined);
		const queuedAbort = new AbortController();
		const queued = pool.load(project, 'godot.exe', second, () => undefined, queuedAbort.signal);
		const queuedRejected = assert.rejects(queued, { name: 'AbortError' }); queuedAbort.abort(); await queuedRejected;
		child.reply(); await active;
		check('Cancelling a queued request leaves the active worker usable', !child.killed && child.writes.length === 3);
		const abort = new AbortController();
		const cancelled = pool.load(project, 'godot.exe', source, () => undefined, abort.signal);
		const rejected = assert.rejects(cancelled, { name: 'AbortError' }); abort.abort(); await rejected;
		check('Cancelling an active request terminates its process', child.killed);
		const restarted = pool.load(project, 'godot.exe', source, () => undefined);
		const replacement = children.at(-1); replacement.ready(); replacement.reply(); await restarted;
		check('The next request restarts a cancelled worker', replacement !== child);
		pool.invalidate(path.join(project + '-other', 'executor.gd'));
		assert.equal(replacement.killed, false);
		pool.invalidate(path.join(project, 'executor.gd'));
		check('Source invalidation is scoped to the owning project', replacement.killed);
		const failed = pool.load(project, 'godot.exe', source, () => undefined);
		const failedCheck = assert.rejects(failed, /worker exited/); children.at(-1).emit('exit', 3, null); await failedCheck;
		check('Worker crashes reject pending inspection instead of hanging');
		const malformed = pool.load(project, 'godot.exe', source, () => undefined);
		const malformedCheck = assert.rejects(malformed, /does not match/);
		children.at(-1).ready(); children.at(-1).reply(graph(second)); await malformedCheck;
		check('Responses for a different Resource are rejected');
		const engineError = pool.load(project, 'godot.exe', source, () => undefined);
		const engineCheck = assert.rejects(engineError, /Godot browsing failed/);
		children.at(-1).stderr.emit('data', 'SCRIPT ERROR: Parse error\n'); await engineCheck;
		check('Godot script errors reject inspection even without an exit code');
		const disposal = pool.load(project, 'godot.exe', source, () => undefined);
		const disposalCheck = assert.rejects(disposal, { name: 'AbortError' }); pool.dispose(); await disposalCheck;
		await assert.rejects(pool.load(project, 'godot.exe', source, () => undefined), { name: 'AbortError' });
		check('Disposal closes owned workers and prevents further process launches', children.every(item => item.killed));
	} finally { pool.dispose(); }
	const timed = new ResourceBrowsePool(15, 10_000);
	try { await assert.rejects(timed.load(project, 'godot.exe', source, () => undefined), /timed out/); }
	finally { timed.dispose(); }
	check('Unresponsive workers time out and release the process');
	const idle = new ResourceBrowsePool(500, 15);
	try {
		const request = idle.load(project, 'godot.exe', source, () => undefined);
		const child = children.at(-1); child.ready(); child.reply(); await request; await wait(25);
		check('Idle workers release background processes', child.killed);
	} finally { idle.dispose(); }
}

async function selectionChecks() {
	const jobs = [], published = [], statuses = [], errors = [], invalidations = [];
	const uri = file => ({ scheme: 'file', fsPath: file, path: file.replaceAll('\\', '/'), toString: () => pathToFileURL(file).href });
	const inside = (base, file) => { const part = path.relative(base, file); return !path.isAbsolute(part) && part !== '..' && !part.startsWith('..' + path.sep); };
	let executable = 'godot.exe', disposed = false;
	const api = { Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
		workspace: { isTrusted: true, workspaceFolders: [{ uri: uri(project) }], textDocuments: [], getConfiguration: () => ({ get: () => executable }) },
		window: { showErrorMessage: message => errors.push(message) } };
	const browser = { load: (...args) => new Promise((resolve, reject) => jobs.push({ args, resolve, reject })),
		invalidate: file => invalidations.push(file), dispose: () => { disposed = true; } };
	const load = loader(name => name === 'vscode' ? api : name.endsWith('/project_context')
		? { resolveProjectContext: async () => ({ projectDirectory: project, workspaceDirectory: project }), isInside: inside } : undefined);
	const { ResourceSelection } = load(path.join(out, 'resources/resource_selection.js'));
	const selection = new ResourceSelection({ clear() {}, setGraph: (_project, value) => published.push(value) }, { appendLine() {} }, message => statuses.push(message), browser);
	const follow = async file => { selection.follow({ document: { uri: uri(path.join(project, file.slice(6))) } }); await tick(); };
	try {
		await follow(source); await follow(source);
		check('Repeated notifications for an in-flight file launch one request', jobs.length === 1);
		await follow(second);
		check('Rapid file changes abort the obsolete request', jobs[0].args[4].aborted);
		jobs[1].resolve(graph(second)); await tick(); jobs[0].resolve(graph(source)); await tick();
		check('Late results cannot replace the current file', published.length === 1 && published[0].roots[0] === second);
		await follow(source); jobs[2].resolve(graph(source)); await tick();
		await follow(second); await follow(source);
		check('Revisiting both saved files uses their cached trees without Godot', jobs.length === 3 && published.length === 4);
		api.workspace.textDocuments = [{ isDirty: true, uri: uri(path.join(project, 'executor.gd')) }]; selection.updateStatus();
		check('Unsaved project scripts remain visibly marked as saved data', statuses.at(-1).includes('Showing saved data'));
		api.workspace.textDocuments = [];
		selection.changed(uri(path.join(project + '-other', 'unrelated.gd'))); await wait(175);
		check('Changes in another project preserve cached trees', jobs.length === 3);
		let finish; const after = new Promise(resolve => { finish = resolve; });
		selection.changed(uri(path.join(project, 'executor.gd')), after); await wait(175);
		check('File refresh waits for an active editing operation', jobs.length === 3);
		finish(); await tick(); jobs[3].resolve(graph(source)); await tick();
		await follow(second); jobs[4].resolve(graph(second)); await tick();
		check('Executor changes invalidate active and inactive Resource caches', jobs.length === 5);
		executable = 'other-godot.exe'; await follow(second); jobs[5].resolve(graph(second)); await tick();
		check('Executable configuration changes cannot reuse a previous cache', jobs[5].args[1] === executable);
		api.workspace.isTrusted = false; selection.updateStatus();
		check('Losing trust clears browsing authority', statuses.at(-1).includes('trusted'));
		api.workspace.isTrusted = true; await follow(source);
		selection.removed(uri(path.join(project, source.slice(6)))); jobs[6].resolve(graph(source)); await tick();
		check('Deleting a selected file discards its late response', statuses.at(-1).includes('Open a framework') && published.length === 7);
		await follow(second); jobs[7].resolve(graph(second)); await tick();
		selection.workspaceChanged(); await tick();
		check('Workspace changes rebuild the selected Resource', jobs.length === 9);
		jobs[8].resolve(graph(second)); await tick();
		check('Expected cancellation and invalidation produce no error popup', errors.length === 0 && invalidations.length > 0);
	} finally { selection.dispose(); }
	check('Selection disposal aborts requests and disposes its worker pool', disposed);
}

async function editChecks() {
	let response, requested;
	const load = loader(name => name.endsWith('/resource_bridge') ? { loadResourceGraph: async (...args) => { requested = args; return response; } } : undefined);
	const { prepareEditGraph } = load(path.join(out, 'resources/edit_context.js'));
	const browse = graph(source);
	response = { ...structuredClone(browse), mode: 'edit', catalog_paths: [source], executor_snapshot: { hashes: { 'res://executor.gd': hash }, directories: {} } };
	assert.equal(await prepareEditGraph(browse, project, 'godot.exe', () => undefined), response);
	check('Editing upgrades the displayed browse graph to a fresh full source snapshot', requested[3] === source && response.executor_snapshot);
	for (const change of [
		value => { value.dependency_hashes[source] = 'b'.repeat(64); },
		value => { value.nodes[source].id = 'changed'; },
		value => { value.executors = [{ id: 'different' }]; },
		value => { delete value.executor_snapshot; },
		value => { value.mode = 'browse'; }
	]) {
		const original = structuredClone(response); change(response);
		await assert.rejects(prepareEditGraph(browse, project, 'godot.exe', () => undefined), /changed since/); response = original;
	}
	check('Stale dependencies, data, metadata and incomplete edit snapshots are rejected');
	const { validateGraph } = require('../out/bridges/resource_bridge');
	validateGraph(browse);
	assert.throws(() => validateGraph({ ...browse, executor_snapshot: response.executor_snapshot }), /write snapshot/);
	assert.throws(() => validateGraph({ ...browse, catalog_paths: [source] }), /catalogue edits/);
	check('Browsing packets cannot carry catalogue or write-snapshot authority');
}

(async () => { await workerChecks(); await selectionChecks(); await editChecks(); check('Checks passed'); })()
	.catch(error => { console.error(error); process.exitCode = 1; });
