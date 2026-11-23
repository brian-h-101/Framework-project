const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { inspectAttributes, editAttributes } = require('../out/bridges/attribute_bridge.js');

const project = path.resolve(process.argv[2] ?? '');
const executable = process.argv[3];
assert.ok(executable && fs.existsSync(path.join(project, 'project.godot')),
	'Expected <Godot project directory> <Godot executable>.');
const production = 'res://Framework/Content/Gameplay/Authored/Entity/Attributes/Needs/needs.tres';
const sourcePath = resource => path.join(project, resource.slice(6));
const original = fs.readFileSync(sourcePath(production));
const parent = path.join(project, '.godot', 'diagnostics');
fs.mkdirSync(parent, { recursive: true });
const temporary = fs.mkdtempSync(path.join(parent, 'attribute_bridge_'));
const fixture = path.join(temporary, 'attributes.tres');
const resource = `res://${path.relative(project, fixture).split(path.sep).join('/')}`;
const schema = 'res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd';
fs.writeFileSync(fixture, `[gd_resource type="Resource" format=3]\n\n[ext_resource type="Script" path="${schema}" id="1"]\n\n[resource]\nscript = ExtResource("1")\ncontainers = {&"test": {"value": 1, "items": [], "sibling": {"kept": 7}}}\n`);
const key = (kind, text) => ({ kind, text });
const root = [key('StringName', 'test')];
function leaf(graph, parts) {
	let current = graph.root;
	for (const part of parts) { current = current.children.find(child => JSON.stringify(child.path.at(-1)) === JSON.stringify(part)); }
	return current;
}
const check = label => console.log(`[attribute-bridge] ${label}: true`);
const report = message => { if (/^(SCRIPT ERROR|ERROR|WARNING):/m.test(message)) { throw new Error(message); } };

(async () => {
	try {
		const needs = await inspectAttributes(project, executable, production, report);
		assert.equal(leaf(needs, [key('StringName', 'needs'), key('String', 'hunger'), key('String', 'current')]).kind, 'int');
		check('Production Resource exports a typed nested tree');
		let graph = await inspectAttributes(project, executable, resource, report);
		const initialHash = graph.content_hash;
		const edit = async (operation, parts, extra = {}) => {
			graph = await editAttributes(project, executable, resource,
				{ expected_hash: graph.content_hash, operation, path: parts, ...extra }, report);
			assert.equal(graph.content_hash, createHash('sha256').update(fs.readFileSync(fixture)).digest('hex'));
		};
		await edit('set', [...root, key('String', 'value')], { value_type: 'int', value_text: '9223372036854775807' });
		assert.equal(leaf(graph, [...root, key('String', 'value')]).value_text, '9223372036854775807');
		assert.equal(leaf(graph, [...root, key('String', 'sibling'), key('String', 'kept')]).value_text, '7');
		check('Exact 64-bit values reach Godot and siblings remain intact');
		const unicode = `Quotes " slash \\ newline\n雪 ${'long '.repeat(700)}`;
		await edit('add', root, { key: key('StringName', 'text'), value_type: 'String', value_text: unicode });
		assert.equal(leaf(graph, [...root, key('StringName', 'text')]).value_text, unicode);
		check('UTF-8 strings larger than 1024 bytes survive stdin and saving');
		await edit('add', [...root, key('String', 'items')], { value_type: 'bool', value_text: 'true' });
		assert.equal(leaf(graph, [...root, key('String', 'items'), key('index', '0')]).value_text, 'true');
		await edit('rename', [...root, key('StringName', 'text')], { key: key('String', 'renamed') });
		assert.equal(leaf(graph, [...root, key('String', 'renamed')]).value_text, unicode);
		await edit('remove', [...root, key('String', 'items'), key('index', '0')]);
		assert.equal(leaf(graph, [...root, key('String', 'items')]).children.length, 0);
		check('Array additions, key renames and removals persist');
		const saved = fs.readFileSync(fixture);
		await assert.rejects(editAttributes(project, executable, resource,
			{ expected_hash: graph.content_hash, operation: 'add', path: root, key: key('String', 'renamed'), value_type: 'int', value_text: '2' }, report), /already contains/i);
		await assert.rejects(editAttributes(project, executable, resource,
			{ expected_hash: initialHash, operation: 'remove', path: root }, report), /file changed/i);
		await assert.rejects(editAttributes(project, executable, resource,
			{ expected_hash: graph.content_hash, operation: 'set', path: [...root, key('String', 'value')], value_type: 'int', value_text: '20.0' }, report), /valid integer/i);
		assert.deepEqual(fs.readFileSync(fixture), saved);
		check('Duplicate, stale and invalid edits preserve saved bytes');
		const config = await inspectAttributes(project, executable,
			'res://Framework/Content/Configuration/Lighting/shadows.tres', report);
		assert.equal(config.supported, false);
		check('Other Resource schemas are distinguished');
		const invalid = spawnSync(executable, ['--headless', '--path', project, '--script',
			'res://Framework/Env/Authoring/Attributes/attribute_cli.gd', '--', 'edit', resource],
			{ input: '{broken json', encoding: 'utf8', windowsHide: true, timeout: 30000 });
		assert.equal(invalid.status, 1);
		assert.match(invalid.stdout, /Expected an attribute edit JSON object/);
		assert.deepEqual(fs.readFileSync(fixture), saved);
		check('Malformed stdin is rejected without changing the Resource');
		const controller = new AbortController(); controller.abort();
		await assert.rejects(inspectAttributes(project, executable, resource, report, controller.signal), /abort/i);
		check('Cancelled inspection terminates without changing the Resource');
		assert.deepEqual(fs.readFileSync(sourcePath(production)), original);
		check('Production Resource remains byte-for-byte unchanged');
		assert.deepEqual(fs.readdirSync(temporary), ['attributes.tres']);
		check('No staging files remain');
	} finally {
		assert.equal(path.dirname(path.resolve(temporary)), path.resolve(parent));
		assert.ok(path.basename(temporary).startsWith('attribute_bridge_'));
		assert.equal(fs.realpathSync(temporary), temporary);
		if (fs.existsSync(fixture)) { fs.unlinkSync(fixture); }
		fs.rmdirSync(temporary);
		check('Temporary fixture and folder removed');
	}
	check('Checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
