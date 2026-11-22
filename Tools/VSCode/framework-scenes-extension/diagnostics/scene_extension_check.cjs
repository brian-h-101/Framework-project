const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const { readFileSync } = require('node:fs');
const { createRequire } = require('node:module');
const { basename, dirname, isAbsolute, join, resolve } = require('node:path');
const { tmpdir } = require('node:os');
const { pathToFileURL } = require('node:url');
const { setImmediate: nextTurn } = require('node:timers/promises');
const { validateSceneGraph } = require('../out/scene_bridge');
const { resolveProjectContext, scenePathInProject } = require('../out/project_context');
const { declarationLine } = require('../out/scene_navigation');
const { validateMovementConfigurations } = require('../out/movement_configuration_bridge');

function check(label, operation) {
	operation();
	console.log(`[scene-extension] ${label}: true`);
}

function graph(sourcePath = 'res://scene.tscn') {
	const node = (path, children, extra = {}) => ({
		path, name: path === '.' ? 'Scene' : path.split('/').pop(), type: 'Node2D',
		source_path: sourcePath, source_node_path: path,
		instance_path: '', base_scene_path: '', script_path: '', children,
		structural_scene: sourcePath, structural_node_path: path, instance_boundary: '',
		can_add: true, can_rename: path !== '.', can_remove: path !== '.', references: {},
		is_entity: false,
		interaction_resource_path: '',
		interaction_id: '',
		movement_configuration_path: '', can_assign_movement: false,
		has_script: false, script_source_path: '', can_attach_script: true, can_remove_script: false,
		...extra
	});
	return {
		version: 2, source_path: sourcePath, root: '.', dependencies: [sourcePath],
		dependency_hashes: { [sourcePath]: '0'.repeat(64) },
		nodes: {
			'.': node('.', ['Left', 'Right']),
			Left: node('Left', ['Left/Body']),
			'Left/Body': node('Left/Body', []),
			Right: node('Right', ['Right/Body']),
			'Right/Body': node('Right/Body', [])
		}
	};
}

function loadMock(relativePath, replacements) {
	const filename = resolve(__dirname, '..', relativePath);
	const originalRequire = createRequire(filename);
	const module = { exports: {} };
	new Function('require', 'module', 'exports', readFileSync(filename, 'utf8'))(
		name => Object.hasOwn(replacements, name) ? replacements[name] : originalRequire(name),
		module, module.exports
	);
	return module.exports;
}

function uri(filePath) {
	const absolute = resolve(filePath);
	const url = pathToFileURL(absolute);
	return { scheme: 'file', fsPath: absolute, path: url.pathname, toString: () => url.href };
}

const vscode = {
	__esModule: true,
	Uri: { file: uri, joinPath: (root, ...parts) => uri(join(root.fsPath, ...parts)) },
	TreeItem: class { constructor(label, collapsibleState) { Object.assign(this, { label, collapsibleState }); } },
	TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
	ThemeIcon: class { constructor(id) { this.id = id; } },
	EventEmitter: class {
		event = () => ({ dispose() {} });
		fire() {}
		dispose() {}
	},
	workspace: {
		isTrusted: true,
		workspaceFolders: [],
		textDocuments: [],
		getConfiguration: name => ({ get: () => name === 'frameworkScenes' ? 'godot-console.exe' : undefined })
	},
	window: { showErrorMessage: message => { throw new Error(message); } }
};

async function until(predicate) {
	const deadline = Date.now() + 3000;
	while (!predicate()) {
		if (Date.now() > deadline) { throw new Error('Timed out waiting for the diagnostic.'); }
		await nextTurn();
	}
}

async function main() {
	check('Movement catalogue validates typed descriptions and dependency hashes', () => {
		const resource = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres';
		const entry = { source_path: resource, action_id: 'calculate_velocity', behavior_id: 'move', dependency_hashes: { [resource]: 'a'.repeat(64) } };
		const catalog = () => ({ version: 1, configurations: [structuredClone(entry)] });
		assert.equal(validateMovementConfigurations(catalog())[0].source_path, resource);
		for (const mutate of [
			value => value.version = 2,
			value => value.configurations.push(structuredClone(entry)),
			value => value.configurations[0].source_path = 'res://../outside.tres',
			value => value.configurations[0].source_path = 'res://Framework/Content/Behavior/Action/move.tres',
			value => value.configurations[0].action_id = '',
			value => value.configurations[0].behavior_id = '',
			value => value.configurations[0].dependency_hashes = {},
			value => value.configurations[0].dependency_hashes[resource] = 'invalid',
			value => value.configurations[0].dependency_hashes['res://../outside.gd'] = 'a'.repeat(64)
		]) { const value = catalog(); mutate(value); assert.throws(() => validateMovementConfigurations(value)); }
	});
	check('Repeated child names in distinct branches remain valid', () => {
		assert.equal(validateSceneGraph(graph(), 'res://scene.tscn').nodes['Right/Body'].name, 'Body');
	});
	check('Entity and Interaction metadata survive validation', () => {
		const value = graph();
		value.nodes.Left.is_entity = true;
		Object.assign(value.nodes['Left/Body'], {
			interaction_resource_path: 'res://Framework/Content/Behavior/Interaction/strike.tres',
			interaction_id: 'strike'
		});
		const nodes = validateSceneGraph(value, 'res://scene.tscn').nodes;
		assert.equal(nodes.Left.is_entity, true);
		assert.equal(nodes['Left/Body'].interaction_id, 'strike');
		assert.equal(nodes['Left/Body'].interaction_resource_path,
			'res://Framework/Content/Behavior/Interaction/strike.tres');
	});
	for (const [label, mutate] of [
		['Incorrect parent is rejected', value => value.nodes.Left.children.push('Right')],
		['Duplicate children are rejected', value => value.nodes['.'].children.push('Left')],
		['Missing child is rejected', value => value.nodes.Left.children.push('Left/Missing')],
		['Disconnected node is rejected', value => value.nodes['.'].children.pop()],
		['Cycle is rejected', value => value.nodes.Left.children.push('.')],
		['External file path is rejected', value => value.nodes.Left.source_path = 'file:///outside.tscn'],
		['Resource traversal is rejected', value => value.nodes.Left.script_path = 'res://../outside.gd'],
		['Entity marker must be boolean', value => value.nodes.Left.is_entity = 'player'],
		['Interaction ID must be text', value => value.nodes.Left.interaction_id = 42],
		['Interaction resource path must be text', value => value.nodes.Left.interaction_resource_path = null],
		['Movement capability cannot be forged', value => value.nodes.Left.can_assign_movement = true],
		['Movement resource path must be text', value => value.nodes.Left.movement_configuration_path = null],
		['Script capability cannot be forged', value => value.nodes.Left.can_remove_script = true],
		['Script ownership cannot escape the scene graph', value => value.nodes.Left.script_source_path = 'res://missing.tscn'],
		['Wrong selected scene is rejected', value => value.source_path = 'res://other.tscn']
	]) {
		check(label, () => { const value = graph(); mutate(value); assert.throws(() => validateSceneGraph(value, 'res://scene.tscn')); });
	}
	check('Node navigation distinguishes identical names by parent', () => {
		const text = '[node name="Root" type="Node2D"]\n[node name="Body" parent="Left"]\n[node name="Body" parent="Right"]';
		assert.equal(declarationLine(text, '.'), 0);
		assert.equal(declarationLine(text, 'Right/Body'), 2);
		assert.equal(declarationLine(text, 'Missing'), undefined);
	});

	const directory = await fs.mkdtemp(join(tmpdir(), 'framework-scenes-check-'));
	try {
		const project = join(directory, 'Project');
		const first = join(project, 'Scenes/first.tscn');
		const second = join(project, 'Scenes/second.tscn');
		const camera = join(project, 'Scenes/camera.tscn');
		const write = async (path, text = '') => { await fs.mkdir(dirname(path), { recursive: true }); await fs.writeFile(path, text); };
		for (const path of [join(project, 'project.godot'),
			join(project, 'Framework/Env/Authoring/Scenes/Inspection/scene_graph_export.gd'), first, second, camera]) {
			await write(path);
		}
		for (const [label, roots] of [
			['Direct project folder resolves', [project]],
			['Parent workspace folder resolves', [directory]],
			['Multiple workspace folders resolve', [join(directory, 'Unrelated'), directory]],
			['Overlapping folders resolve', [directory, project]]
		]) {
			const actual = await resolveProjectContext(first, roots);
			assert.equal(actual.projectDirectory, project);
			assert.equal(await scenePathInProject(actual, first), 'res://Scenes/first.tscn');
			console.log(`[scene-extension] ${label}: true`);
		}
		await assert.rejects(resolveProjectContext(first, [join(directory, 'Unrelated')]));
		await write(join(project, 'Nested/project.godot'));
		const nested = join(project, 'Nested/scene.tscn');
		await write(nested);
		await assert.rejects(resolveProjectContext(nested, [directory]), /nearest Godot project/);
		console.log('[scene-extension] Nested unsupported project cannot fall back to parent: true');

		const context = await resolveProjectContext(first, [directory]);
		const { SceneTreeProvider } = loadMock('out/scene_tree_provider.js', { vscode });
		const provider = new SceneTreeProvider();
		const treeGraph = graph();
		treeGraph.dependencies.push('res://linked.tscn');
		treeGraph.dependency_hashes['res://linked.tscn'] = '0'.repeat(64);
		treeGraph.nodes.Left.instance_path = 'res://linked.tscn';
		treeGraph.nodes.Left.script_path = 'res://movement.gd';
		treeGraph.nodes['Left/Body'].properties = [
			{ name: 'color', type: 'Color', value: 'Color(0.2, 0.6, 1, 1)', source_path: 'res://linked.tscn' }
		];
		treeGraph.nodes.Left.properties = [
			{ name: 'position', type: 'Vector2', value: 'Vector2(320, 360)', source_path: 'res://scene.tscn' }
		];
		Object.assign(treeGraph.nodes.Left, { has_script: true, script_source_path: 'res://scene.tscn', can_attach_script: false, can_remove_script: true });
		provider.setGraph(context, validateSceneGraph(treeGraph, 'res://scene.tscn'));
		const root = provider.getChildren()[0];
		const left = provider.getChildren(root)[0];
		check('Tree exposes nested children and contextual navigation', () => {
			assert.equal(provider.getTreeItem(left).contextValue, 'scene_node_instance_scripted_add_rename_remove_detach_script_set_property');
			assert.equal(provider.getChildren(left)[0].path, 'Left/Body');
			assert.equal(provider.getParent(left).path, '.');
			assert.equal(provider.getTreeItem(left).command.command, 'frameworkScenes.openDeclaration');
		});
		check('Saved properties appear in an expandable group without changing scene child order', () => {
			const [body, placement] = provider.getChildren(left);
			assert.equal(body.path, 'Left/Body');
			assert.equal(provider.getTreeItem(placement).label, 'Properties');
			assert.equal(provider.getTreeItem(placement).collapsibleState, vscode.TreeItemCollapsibleState.Collapsed);
			const [position] = provider.getChildren(placement);
			assert.equal(provider.getTreeItem(position).description, 'Vector2(320, 360)');
			assert.deepEqual(provider.getParent(placement), left);
			assert.deepEqual(provider.getParent(position), placement);
			assert.equal(provider.getChildren(position).length, 0);
			assert.throws(() => provider.resolve(position), /current node/);
			const [inherited] = provider.getChildren(provider.getChildren(body)[0]);
			const item = provider.getTreeItem(inherited);
			assert.equal(item.label, 'color');
			assert.match(item.description, /inherited/);
			assert.match(item.tooltip, /Saved in: res:\/\/linked\.tscn/);
		});
		check('Property previews must name a dependency and have unique keys per node', () => {
			const invalid = structuredClone(treeGraph);
			invalid.nodes.Left.properties[0].source_path = 'res://unrelated.tscn';
			assert.throws(() => validateSceneGraph(invalid, 'res://scene.tscn'), /Invalid property preview/);
			invalid.nodes.Left.properties = [treeGraph.nodes.Left.properties[0], treeGraph.nodes.Left.properties[0]];
			assert.throws(() => validateSceneGraph(invalid, 'res://scene.tscn'), /Invalid property preview/);
		});
		provider.clear();
		check('Old context-menu items are rejected after refresh', () => assert.throws(() => provider.resolve(left)));

		const loads = [];
		const publications = [];
		let displayed;
		let status;
		const { SceneSelection } = loadMock('out/scene_selection.js', {
			vscode,
			'./scene_bridge': {
				loadSceneGraph: (...args) => new Promise((resolve, reject) => loads.push({ args, resolve, reject }))
			},
			'./scene_tree_provider': { projectUri: (projectContext, path) => uri(join(projectContext.projectDirectory, path.slice(6))) }
		});
		const selection = new SceneSelection({
			clear: () => { displayed = undefined; },
			setGraph: (_, value) => { publications.push(value); displayed = value; }
		}, { appendLine() {} }, message => { status = message; });
		try {
			vscode.workspace.workspaceFolders = [{ uri: uri(directory) }];
			selection.follow({ document: { uri: uri(first) } });
			await until(() => loads.length === 1);
			selection.follow({ document: { uri: uri(second) } });
			await until(() => loads.length === 2);
			assert.equal(loads[0].args[4].aborted, true);
			assert.equal(loads[1].args[0], project);
			assert.equal(loads[1].args[1], 'godot-console.exe');
			const currentGraph = graph('res://Scenes/second.tscn');
			currentGraph.dependencies.push('res://Scenes/camera.tscn');
			currentGraph.dependency_hashes['res://Scenes/camera.tscn'] = '0'.repeat(64);
			loads[1].resolve(currentGraph);
			await until(() => publications.length === 1);
			loads[0].resolve(graph('res://Scenes/first.tscn'));
			await nextTurn();
			assert.equal(displayed.source_path, 'res://Scenes/second.tscn');
			assert.equal(publications.length, 1);
			console.log('[scene-extension] Latest selection wins and obsolete process is aborted: true');
			selection.follow({ document: { uri: uri(join(project, 'notes.txt')) } });
			assert.equal(loads.length, 2);
			assert.equal(displayed, currentGraph);
			console.log('[scene-extension] Non-scene editor retains the last scene: true');
			vscode.workspace.textDocuments = [{ uri: uri(camera), isDirty: true }];
			selection.updateStatus();
			assert.match(status, /saved scene data/);
			console.log('[scene-extension] Unsaved dependency is clearly identified: true');
			selection.scheduleRefresh(uri(camera));
			await until(() => loads.length === 3);
			assert.equal(loads[2].args[2], 'res://Scenes/second.tscn');
			console.log('[scene-extension] Saving a nested dependency reloads the selected scene: true');
			vscode.workspace.workspaceFolders = [];
			selection.workspaceChanged();
			loads[2].resolve(currentGraph);
			await nextTurn();
			assert.equal(displayed, undefined);
			assert.equal(publications.length, 1);
			console.log('[scene-extension] Removed workspace cannot publish a late response: true');
			vscode.workspace.workspaceFolders = [{ uri: uri(directory) }];
			let finish;
			const pending = new Promise(resolve => { finish = resolve; });
			selection.follow({ document: { uri: uri(first) } }, pending);
			await nextTurn(); assert.equal(loads.length, 3);
			finish(); await until(() => loads.length === 4);
			selection.removed(uri(first)); loads[3].resolve(graph('res://Scenes/first.tscn')); await nextTurn();
			assert.equal(displayed, undefined); await selection.refresh(); assert.equal(loads.length, 4);
			console.log('[scene-extension] Selection waits for mutations and deleted scenes discard late results: true');
		} finally {
			selection.dispose();
			provider.dispose();
		}
	} finally {
		if (!isAbsolute(directory) || dirname(directory) !== resolve(tmpdir())
			|| !basename(directory).startsWith('framework-scenes-check-')) {
			throw new Error('Unexpected diagnostic cleanup path.');
		}
		await fs.rm(directory, { recursive: true });
	}
	console.log('[scene-extension] Checks passed: true');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
