const assert = require('node:assert/strict');

const {
	loadResourceGraph
} = require('../out/resource_bridge.js');

const cases = [
	{
		path: 'res://Framework/Content/Interaction/strike.tres',
		kind: 'interaction',
		nodes: 4
	},
	{
		path: 'res://Framework/Content/Condition/can_strike.tres',
		kind: 'condition_group',
		nodes: 2
	},
	{
		path: 'res://Framework/Content/Condition/actor_strength.tres',
		kind: 'condition',
		nodes: 1
	},
	{
		path: 'res://Framework/Content/Action/change_health.tres',
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

		assert.equal(graph.version, 1);
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
			'res://Framework/Content/Interaction/strike.tres'
		)
	);

	console.log('[graph-bridge] Existing catalogue call works: true');

	const missingPath =
		'res://Framework/Content/Condition/__resource_graph_missing_check__.tres';

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
