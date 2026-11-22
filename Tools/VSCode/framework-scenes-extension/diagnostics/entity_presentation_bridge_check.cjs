const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { LibraryService } = require('../out/library/library_service');
const { libraryRequest } = require('../out/library/scene_library_bridge');

async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected project and Godot executable.');
	const project = path.resolve(projectArg);
	const context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
	const report = message => console.error(message);
	const service = new LibraryService(context, executable, report);
	const root = 'res://Framework/Content/Gameplay/Presentation/Entity';
	const id = 'paired_probe_' + randomBytes(6).toString('hex');
	const health = 'res://Framework/Content/Gameplay/Authored/Entity/Attributes/Statistics/health.tres';
	const files = [];
	const folders = [];
	const absolute = source => path.join(project, source.slice(6));
	const create = async (library, folder, name, request) => {
		const catalogue = await library.catalogue();
		const entry = catalogue.entries.find(item => item.source_path === folder);
		assert.ok(entry, folder);
		return library.createScene(entry, name, request, catalogue);
	};
	try {
		const fragments = await libraryRequest(project, executable, 'attribute-fragments', undefined, {}, report);
		assert.ok(fragments.includes(health));
		const healthBefore = await fs.readFile(absolute(health));
		for (const suffix of ['_one', '_two']) {
			const source = root + '/' + id + suffix;
			await fs.mkdir(absolute(source));
			folders.push(source);
		}
		const [first, second] = folders;
		const request = { template: 'entity_presentation', node_name: 'Probe', root_type: 'Node2D',
			definition_id: id, fragments: [health] };
		const scene = await create(service, first, 'probe.tscn', request);
		const preset = first + '/starting_attributes.tres';
		files.push(scene, preset);
		const sceneText = await fs.readFile(absolute(scene), 'utf8');
		const presetText = await fs.readFile(absolute(preset), 'utf8');
		assert.ok(sceneText.includes('metadata/entity_definition = &"' + id + '"'));
		assert.ok(presetText.includes('id = &"' + id + '"') && presetText.includes(health) && presetText.includes('"Probe"'));
		assert.match(presetText, /^\[gd_resource .*uid="uid:\/\/[a-z0-9]+"/);
		assert.ok(!/(?<!\r)\n/.test(presetText));
		assert.deepEqual(await fs.readFile(absolute(health)), healthBefore);
		assert.equal(await libraryRequest(project, executable, 'verify-entity', scene, { definition_id: id }, report), true);
		console.log('[entity-presentation] Scene and discoverable preset share the ID and retain the selected fragment.');

		await assert.rejects(create(service, first, 'another.tscn', { ...request, definition_id: id + '_another' }),
			/starting_attributes\.tres: .*already exists/);
		assert.equal(await fs.readFile(absolute(preset), 'utf8'), presetText);
		assert.deepEqual((await fs.readdir(absolute(first))).sort(), ['probe.tscn', 'starting_attributes.tres']);
		await assert.rejects(create(service, second, 'duplicate.tscn', request), /Definition ID.*already used/);
		await assert.rejects(create(service, second, 'outside.tscn', { ...request, definition_id: id + '_outside',
			fragments: ['res://Diagnostics/Fixtures/StartingPresetDiscovery/Probe/starting_attributes.tres'] }), /inside/);
		assert.deepEqual(await fs.readdir(absolute(second)), []);
		console.log('[entity-presentation] Existing presets, duplicate IDs, and out-of-library fragments are rejected.');

		const rollbackScene = second + '/rollback.tscn';
		const rollbackService = new LibraryService(context, executable, report, async () => {
			try { await fs.access(absolute(rollbackScene)); }
			catch (error) { if (error.code === 'ENOENT') { return; } throw error; }
			throw new Error('Diagnostic guard changed after publication.');
		});
		await assert.rejects(create(rollbackService, second, 'rollback.tscn', { ...request, definition_id: id + '_rollback' }),
			/Diagnostic guard changed/);
		assert.deepEqual(await fs.readdir(absolute(second)), []);
		console.log('[entity-presentation] A failed final guard rolls back both newly published files.');
	} finally {
		for (const source of files) { await fs.unlink(absolute(source)); }
		for (const source of folders) {
			// Remove only these diagnostic names in the uniquely created, verified folder.
			const folder = absolute(source);
			assert.equal(await fs.realpath(folder), folder);
			for (const name of ['rollback.tscn', 'starting_attributes.tres']) {
				try { await fs.unlink(path.join(folder, name)); }
				catch (error) { if (error.code !== 'ENOENT') { throw error; } }
			}
			await fs.rmdir(folder);
		}
	}
	console.log('[entity-presentation] Checks passed.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
