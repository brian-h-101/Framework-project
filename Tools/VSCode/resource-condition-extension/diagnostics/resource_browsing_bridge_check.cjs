const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { performance } = require('node:perf_hooks');
const { ResourceBrowsePool } = require('../out/bridges/resource_browse_bridge');
const { loadResourceGraph } = require('../out/bridges/resource_bridge');
const { prepareEditGraph } = require('../out/resources/edit_context');
const { editBehavior } = require('../out/bridges/behavior_editing_bridge');

const [project, godot] = process.argv.slice(2);
if (!project || !godot) { throw new Error('Supply the Godot project directory and executable.'); }
const sources = ['Interaction/drag_check', 'Automation/auto_strike', 'Interaction/strike']
	.map(name => 'res://Framework/Content/Behavior/' + name + '.tres');
sources.push('res://Diagnostics/Fixtures/BehaviorSequence/nested_strike.tres');
const originalAction = 'res://Framework/Content/Behavior/Action/change_health.tres';
const relative = 'Diagnostics/Fixtures/BrowsePerformance_' + randomUUID().replaceAll('-', '');
const folder = path.join(project, relative);
const source = 'res://' + relative + '/action.tres';
const resourceFile = path.join(folder, 'action.tres');
const scriptFile = path.join(folder, 'probe.gd');
const report = message => console.error(message);
const check = (label, valid = true) => { assert.ok(valid, label); console.log('[browsing-bridge] ' + label + ': true'); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const owned = [];
const pool = new ResourceBrowsePool();

async function main() {
	const production = new Map();
	for (const file of [...sources, originalAction]) { production.set(file, hash(await fs.readFile(path.join(project, file.slice(6))))); }
	await fs.mkdir(folder, { recursive: false });
	try {
		const action = (await fs.readFile(path.join(project, originalAction.slice(6)), 'utf8'))
			.replace('id = &"change_health"', 'id = &"browsing_performance_probe"');
		await fs.writeFile(resourceFile, action, { flag: 'wx' }); owned.push(resourceFile);
		await fs.writeFile(scriptFile, 'extends RefCounted\r\n', { flag: 'wx' }); owned.push(scriptFile);
		const timings = [];
		for (const file of sources) {
			let start = performance.now();
			const browse = await pool.load(project, godot, file, report);
			const workerMs = Math.round(performance.now() - start);
			start = performance.now();
			const full = await loadResourceGraph(project, godot, report, file);
			const fullMs = Math.round(performance.now() - start);
			assert.deepEqual(browse.nodes, full.nodes);
			assert.deepEqual(browse.executors, full.executors);
			assert.equal(browse.executor_snapshot, undefined);
			assert.equal(browse.catalog_paths.length, 0);
			timings.push({ file: file.split('/').at(-1), worker_ms: workerMs, full_ms: fullMs,
				browse_hashes: Object.keys(browse.dependency_hashes).length, full_source_hashes: Object.keys(full.executor_snapshot.hashes).length });
		}
		console.table(timings);
		check('Lightweight trees and executor metadata match full inspection for legacy and nested Behaviors');
		const unsupported = await pool.load(project, godot,
			'res://Framework/Content/Gameplay/Authored/Entity/Attributes/Abilities/reflex.tres', report);
		check('Unrelated attribute Resources remain an empty supported-schema view', unsupported.supported === false && !unsupported.roots.length);
		const browse = await pool.load(project, godot, source, report);
		const edit = await prepareEditGraph(browse, project, godot, report);
		check('A real browsing tree upgrades to full guarded editing', !!edit.executor_snapshot && edit.catalog_paths.length > 0);
		const request = graph => ({ operation: 'set_behavior', behavior_id: 'attribute_effects',
			expected_hashes: graph.dependency_hashes, catalog_paths: graph.catalog_paths,
			catalog_seed: source, executor_snapshot: graph.executor_snapshot });
		const before = await fs.readFile(resourceFile);
		await assert.rejects(editBehavior(project, godot, source, request(browse), report), /catalogue|snapshot|inspected|changed/i);
		check('Lightweight metadata cannot authorize a backend write', before.equals(await fs.readFile(resourceFile)));
		await editBehavior(project, godot, source, request(edit), report);
		const savedBrowse = await pool.load(project, godot, source, report);
		check('Fresh full inspection permits the intended edit', savedBrowse.nodes[source].behavior_id === 'attribute_effects');
		await assert.rejects(prepareEditGraph(browse, project, godot, report), /changed since/);
		check('Old displayed Resource data is rejected before another edit');
		pool.invalidate(resourceFile);
		const updated = await pool.load(project, godot, source, report);
		check('Invalidation reloads saved Resource changes', updated.nodes[source].behavior_id === 'attribute_effects');
		const guarded = await prepareEditGraph(updated, project, godot, report);
		await fs.appendFile(scriptFile, '# External source edit after the edit dialog opened.\r\n');
		const saved = await fs.readFile(resourceFile);
		await assert.rejects(editBehavior(project, godot, source, { ...request(guarded), behavior_id: 'change_health' }, report), /executor|snapshot|changed/i);
		check('Source edits after preparation still prevent saving', saved.equals(await fs.readFile(resourceFile)));
		pool.invalidate(scriptFile);
		await fs.writeFile(resourceFile, (await fs.readFile(resourceFile, 'utf8')).replace('browsing_performance_probe', 'externally_renamed_probe'));
		const renamed = await pool.load(project, godot, source, report);
		check('A restarted worker discovers external edits', renamed.nodes[source].id === 'externally_renamed_probe');
		const cancelled = new AbortController(); cancelled.abort();
		await assert.rejects(loadResourceGraph(project, godot, report, source, { mode: 'browse', signal: cancelled.signal }), { name: 'AbortError' });
		check('Already cancelled one-shot inspections do not launch');
	} finally {
		pool.dispose();
		for (const file of owned.reverse()) { await fs.unlink(file); }
		await fs.rmdir(folder);
		check('Owned diagnostic files and folder removed');
		for (const [file, expected] of production) { assert.equal(hash(await fs.readFile(path.join(project, file.slice(6)))), expected, file); }
		check('Production Resources remain unchanged');
	}
	check('Checks passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
