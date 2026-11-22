const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const { ResourceBrowsePool } = require('../out/bridges/resource_browse_bridge');
const { loadResourceGraph } = require('../out/bridges/resource_bridge');
const { editBehavior } = require('../out/bridges/behavior_editing_bridge');
const { prepareEditGraph } = require('../out/resources/edit_context');

async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected project and Godot executable.');
	const project = path.resolve(projectArg);
	const nonce = randomBytes(5).toString('hex');
	const relative = 'Framework/Content/Gameplay/Presentation/Entity/preset_probe_' + nonce;
	const folder = path.join(project, relative);
	const filename = path.join(folder, 'starting_attributes.tres');
	const source = 'res://' + relative + '/starting_attributes.tres';
	const uid = 'uid://c' + nonce;
	const authored = 'res://Framework/Content/Gameplay/Authored/Entity/Attributes/';
	const health = authored + 'Statistics/health.tres';
	const speed = authored + 'Statistics/speed.tres';
	const schema = 'res://Framework/Infrastructure/API/Entity/Resources/';
	const absolute = file => path.join(project, file.slice(6));
	const hash = bytes => createHash('sha256').update(bytes).digest('hex');
	const healthBefore = await fs.readFile(absolute(health));
	const speedBefore = await fs.readFile(absolute(speed));
	const report = message => console.error(message);
	const browser = new ResourceBrowsePool();
	const full = () => loadResourceGraph(project, executable, report, source);
	const part = (text, kind = 'String') => ({ kind, text });
	const field = (graph, ...labels) => labels.reduce((node, label) => {
		const found = node.children.find(child => child.label === label);
		assert.ok(found, label);
		return found;
	}, graph.nodes[source].data);
	const write = (graph, request) => editBehavior(project, executable, source, {
		presentation_preset: true, catalog_paths: [], catalog_seed: source,
		expected_hashes: graph.dependency_hashes, ...request
	}, report);
	await fs.mkdir(folder);
	let created = false;
	try {
		await fs.writeFile(filename, [
			`[gd_resource type="Resource" format=3 uid="${uid}"]`, '',
			`[ext_resource type="Script" path="${schema}starting_attributes_resource.gd" id="1"]`,
			`[ext_resource type="Script" path="${schema}container_fragment_resource.gd" id="2"]`,
			`[ext_resource type="Resource" path="${health}" id="3"]`, '',
			'[resource]', 'script = ExtResource("1")', 'id = &"preset_probe_' + nonce + '"',
			'fragments = Array[ExtResource("2")]([ExtResource("3")])',
			'overrides = {&"identity": {"name": "Probe"}}', ''
		].join('\r\n'), { flag: 'wx' });
		created = true;
		const browsed = await browser.load(project, executable, source, report);
		assert.equal(browsed.nodes[source].kind, 'starting_attributes');
		assert.deepEqual(browsed.nodes[source].fragment_paths, [health]);
		assert.equal(field(browsed, 'Definition ID').editable, false);
		const current = field(browsed, 'Effective Attributes', 'health', 'current');
		assert.equal(current.value_text, '100');
		assert.equal(current.editable, true);
		const snapshot = await prepareEditGraph(browsed, project, executable, report);
		const patch = { operation: 'set', path: current.path, value_type: 'int', value_text: '75' };
		await write(snapshot, patch);
		await assert.rejects(write(snapshot, patch), /changed or was not inspected/);
		const updated = await full();
		assert.equal(field(updated, 'Overrides', 'health', 'current').value_text, '75');
		assert.equal(field(updated, 'Effective Attributes', 'health', 'maximum').value_text, '100');
		assert.equal(field(updated, 'Effective Attributes', 'health', 'current').value_text, '75');
		console.log('[starting-preset] Editing an inherited value saves a local override and rejects stale writes.');

		const fragments = { operation: 'set_fragments', fragment_paths: [speed, health],
			expected_hashes: { ...updated.dependency_hashes, [speed]: hash(speedBefore) } };
		await write(updated, fragments);
		const withSpeed = await full();
		assert.deepEqual(withSpeed.nodes[source].fragment_paths, [speed, health]);
		assert.equal(field(withSpeed, 'Effective Attributes', 'speed', 'current').value_text, '20');
		const saved = await fs.readFile(filename, 'utf8');
		await assert.rejects(write(withSpeed, { operation: 'set_fragments',
			fragment_paths: ['res://Diagnostics/Fixtures/StartingPresetDiscovery/Probe/starting_attributes.tres'] }), /inside/);
		await assert.rejects(write(withSpeed, { operation: 'set', path: [part('Definition ID')],
			value_type: 'StringName', value_text: 'different_id' }), /authored overrides/);
		assert.equal(await fs.readFile(filename, 'utf8'), saved);
		assert.ok(saved.split('\r\n')[0].includes(`uid="${uid}"`));
		assert.ok(!/(?<!\r)\n/.test(saved));
		assert.equal(withSpeed.nodes[source].id, 'preset_probe_' + nonce);
		assert.deepEqual(await fs.readFile(absolute(health)), healthBefore);
		assert.deepEqual(await fs.readFile(absolute(speed)), speedBefore);
		console.log('[starting-preset] Fragment edits retain order, IDs, UIDs, line endings, and shared fragment bytes.');

		const override = field(withSpeed, 'Overrides', 'health', 'current');
		await write(withSpeed, { operation: 'remove', path: override.path });
		const removed = await full();
		assert.equal(field(removed, 'Effective Attributes', 'health', 'current').value_text, '100');
		await write(removed, { operation: 'add', path: [part('Overrides')], key: part('strength', 'StringName'),
			value_type: 'Dictionary', value_text: '{}' });
		const added = await full();
		await write(added, { operation: 'add', path: field(added, 'Overrides', 'strength').path,
			key: part('current'), value_type: 'int', value_text: '80' });
		assert.equal(field(await full(), 'Effective Attributes', 'strength', 'current').value_text, '80');
		console.log('[starting-preset] Overrides can be removed to inherit again or added for a new container.');
	} finally {
		browser.dispose();
		if (created) { await fs.unlink(filename); }
		await fs.rmdir(folder);
	}
	console.log('[starting-preset] Checks passed.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
