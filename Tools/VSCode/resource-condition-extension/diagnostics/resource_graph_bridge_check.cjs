const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
	loadResourceGraph
} = require('../out/bridges/resource_bridge.js');

const cases = [
	{
		path: 'res://Framework/Content/Behavior/Interaction/strike.tres',
		kind: 'interaction',
		nodes: 4
	},
	{
		path: 'res://Framework/Content/Behavior/Condition/can_strike.tres',
		kind: 'condition_group',
		nodes: 2
	},
	{
		path: 'res://Framework/Content/Behavior/Condition/actor_strength.tres',
		kind: 'condition',
		nodes: 1
	},
	{
		path: 'res://Framework/Content/Behavior/Action/change_health.tres',
		kind: 'action',
		nodes: 1
	}
];

async function main() {
	const [projectDirectory, godotExecutable] = process.argv.slice(2);

	if (!projectDirectory || !godotExecutable) {
		throw new Error(
			'Expected the Godot project directory and executable path.'
		);
	}

	const diagnostics = [];

	const report = message => {
		diagnostics.push(message);
		console.error(message);
	};

	for (const testCase of cases) {
		const graph = await loadResourceGraph(
			projectDirectory,
			godotExecutable,
			report,
			testCase.path
		);

		assert.equal(graph.version, 2);
		assert.ok(graph.catalog_paths.length >= 7);
		assert.match(graph.nodes[testCase.path].content_hash, /^[a-f0-9]{64}$/);
		assert.ok(graph.nodes[testCase.path].data.children);
		assert.deepEqual(graph.roots, [testCase.path]);
		assert.equal(graph.nodes[testCase.path].kind, testCase.kind);
		assert.equal(
			graph.nodes[testCase.path].source_path,
			testCase.path
		);
		assert.equal(Object.keys(graph.nodes).length, testCase.nodes);

		console.log(
			`[graph-bridge] ${testCase.kind} selection returns `
			+ `one root and ${testCase.nodes} node(s): true`
		);
	}

	const catalogue = await loadResourceGraph(
		projectDirectory,
		godotExecutable,
		report
	);

	assert.ok(
		catalogue.roots.includes(
			'res://Framework/Content/Behavior/Interaction/strike.tres'
		)
	);

	console.log('[graph-bridge] Existing catalogue call works: true');
	for (const source of [
		'res://Framework/Content/Authored/Entity/Attributes/Abilities/reflex.tres',
		'res://Framework/Content/Authored/Entity/Attributes/Identity/identity.tres',
		'res://Framework/Content/Configuration/Lighting/city_lighting.tres',
		'res://Framework/Content/Presentation/Entity/Player/starting_attributes.tres'
	]) {
		const file = path.join(projectDirectory, source.slice(6));
		const before = fs.readFileSync(file);
		const other = await loadResourceGraph(projectDirectory, godotExecutable, report, source);
		assert.equal(other.supported, false);
		assert.equal(other.source_path, source);
		assert.deepEqual(other.roots, []); assert.deepEqual(other.nodes, {});
		assert.deepEqual(other.catalog_paths, []);
		assert.deepEqual(Object.keys(other.dependency_hashes), [source]);
		assert.deepEqual(fs.readFileSync(file), before);
	}
	console.log('[graph-bridge] Attribute, configuration, and presentation schemas are ignored without altering their files: true');
	const diagnosticsDirectory = path.join(projectDirectory, '.godot', 'diagnostics');
	fs.mkdirSync(diagnosticsDirectory, { recursive: true });
	const fixtureDirectory = fs.mkdtempSync(path.join(diagnosticsDirectory, 'behavior_schema_check_'));
	const fixtureFile = path.join(fixtureDirectory, 'empty_id.tres');
	const fixtureSource = 'res://' + path.relative(projectDirectory, fixtureFile).split(path.sep).join('/');
	try {
		fs.writeFileSync(fixtureFile, '[gd_resource type="Resource" format=3]\n\n'
			+ '[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd" id="1"]\n\n'
			+ '[resource]\nscript = ExtResource("1")\n', { flag: 'wx' });
		await assert.rejects(() => loadResourceGraph(projectDirectory, godotExecutable, report, fixtureSource), /empty authored ID/);
		console.log('[graph-bridge] A behavior Resource with no authored ID remains an error: true');
	} finally { fs.unlinkSync(fixtureFile); fs.rmdirSync(fixtureDirectory); }

	const missingPath =
		'res://Framework/Content/Behavior/Condition/__resource_graph_missing_check__.tres';

	await assert.rejects(
		() => loadResourceGraph(
			projectDirectory,
			godotExecutable,
			report,
			missingPath
		),
		{ message: 'Resource file does not exist: ' + missingPath }
	);

	console.log(
		'[graph-bridge] Missing-resource error reaches TypeScript: true'
	);

	assert.doesNotMatch(
		diagnostics.join('\n'),
		/^(?:SCRIPT ERROR|ERROR):/m
	);

	console.log('[graph-bridge] Checks passed: true');
}

main().catch(error => {
	console.error('[graph-bridge]', error);
	console.log('[graph-bridge] Checks passed: false');
	process.exitCode = 1;
});
