const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { LibraryService } = require('../out/library/library_service');
const { SCENE_ROOTS, libraryRequest, validateCatalogue } = require('../out/library/scene_library_bridge');
const { checkedLibraryPath, nameError } = require('../out/library/library_paths');
const { loadSceneGraph } = require('../out/scene_bridge');

const check = label => console.log(`[scene-library] ${label}: true`);
async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected project and Godot executable.');
	const project = path.resolve(projectArg), context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
	const service = new LibraryService(context, executable, text => { if (/^(SCRIPT ERROR|ERROR):/m.test(text)) { throw new Error(text); } });
	const before = await service.catalogue();
	assert.deepEqual(before.root_paths, SCENE_ROOTS);
	assert.ok(before.entries.every(e => SCENE_ROOTS.some(root => e.source_path === root || e.source_path.startsWith(root + '/'))));
	assert.ok(!before.entries.some(e => e.source_path.endsWith('.tres')));
	const production = new Map();
	for (const e of before.entries.filter(e => e.kind === 'resource')) production.set(e.source_path, await fs.readFile(path.join(project, e.source_path.slice(6))));
	const name = 'DiagnosticScenes_' + randomBytes(8).toString('hex');
	const owned = [];
	const get = async source => { const entry = (await service.catalogue()).entries.find(e => e.source_path === source); assert.ok(entry, source); return entry; };
	const create = async (folder, filename, request) => {
		const catalogue = await service.catalogue();
		return service.createScene(catalogue.entries.find(e => e.source_path === folder), filename, request, catalogue);
	};
	const absolute = source => path.join(project, source.slice(6));
	const trashCalls = [];
	const trash = async file => { trashCalls.push(file); await fs.unlink(file); };
	try {
		for (const root of SCENE_ROOTS) {
			const folder = await service.createCategory(await get(root), name);
			owned.push(folder);
			await service.createCategory(await get(folder), 'Nested');
		}
		check('The three approved libraries support independent categories and subcategories');
		const mapFolder = owned[0] + '/Nested', presentation = owned[1] + '/Nested', hud = owned[2] + '/Nested';
		await assert.rejects(service.createCategory(await get(SCENE_ROOTS[0]), name.toUpperCase()), /already exists/);
		assert.ok(nameError('COM¹')); assert.ok(nameError('CON.tscn'));
		await assert.rejects(service.createCategory(await get(mapFolder), '../escape'), /leading dot|reserved/);
		check('Duplicate siblings and unsafe Windows names are rejected');
		for (const outside of ['res://Framework/Content/Camera', 'res://Framework/Content/UI', 'res://Framework/Content/MapsExtra']) {
			await assert.rejects(checkedLibraryPath(context, outside, 'directory'), /inside/);
			await assert.rejects(libraryRequest(project, executable, 'draft', outside + '/probe.tscn', { template: 'empty_2d', node_name: 'Probe' }, () => {}), /inside/);
		}
		await assert.rejects(checkedLibraryPath(context, SCENE_ROOTS[0] + '/../UI/HUD', 'directory'), /Invalid/);
		check('Both frontend and Godot reject paths outside the three roots');
		const cases = [
			[mapFolder, 'map.tscn', 'map_2d', 'Node2D', 3],
			[mapFolder, 'empty_2d.tscn', 'empty_2d', 'Node2D', 1],
			[mapFolder, 'empty_3d.tscn', 'empty_3d', 'Node3D', 1],
			[presentation, 'presentation.tscn', 'presentation', 'CharacterBody2D', 1],
			[presentation, 'plain.tscn', 'presentation', 'Node', 1],
			[hud, 'control.tscn', 'control', 'Control', 1],
			[hud, 'hud.tscn', 'hud', 'CanvasLayer', 2]
		];
		for (const [folder, filename, template, type, count] of cases) {
			const source = await create(folder, filename, { template, node_name: 'NewScene', root_type: type });
			const text = await fs.readFile(absolute(source), 'utf8');
			assert.match(text, /^\[gd_scene .*uid="uid:\/\/[a-z0-9]+"/); assert.ok(!/(?<!\r)\n/.test(text)); assert.ok(!/^ +\S/m.test(text));
			const graph = await loadSceneGraph(project, executable, source, () => {});
			assert.equal(graph.nodes['.'].name, 'NewScene'); assert.equal(graph.nodes['.'].type, type); assert.equal(Object.keys(graph.nodes).length, count);
			if (template === 'map_2d') { assert.ok(text.includes('ground.tres')); assert.equal(graph.nodes.Ground.type, 'TileMapLayer'); assert.ok(graph.nodes.Lighting.script_path.endsWith('/lighting_2d.gd')); }
			if (template === 'control' || template === 'hud') { assert.match(text, /light_mode = 1/); }
			if (template === 'hud') { assert.match(text, /layer = 10/); assert.equal(graph.nodes.Root.type, 'Control'); }
		}
		check('All six templates and native presentation roots save valid UIDs, hierarchies, tabs, and CRLF');
		await assert.rejects(create(mapFolder, 'MAP.tscn', { template: 'empty_2d', node_name: 'Duplicate' }), /already exists/);
		await assert.rejects(create(mapFolder, 'bad.tres', { template: 'empty_2d', node_name: 'Bad' }), /tscn/);
		await assert.rejects(create(mapFolder, 'wrong.tscn', { template: 'hud', node_name: 'Bad' }), /unavailable/);
		await assert.rejects(create(presentation, 'wrong.tscn', { template: 'presentation', node_name: 'Bad', root_type: 'Resource' }), /native Node/);
		check('Existing files cannot be overwritten and templates are scoped to their library');
		const target = mapFolder + '/empty_2d.tscn';
		const consumers = [
			['consumer.tscn', `[gd_scene format=3]\n[ext_resource type="PackedScene" path="${target}" id="1"]\n[node name="Consumer" type="Node2D"]\n[node name="Placed" parent="." instance=ExtResource("1")]\n`],
			['inherited.tscn', `[gd_scene format=3]\n[ext_resource type="PackedScene" path="${target}" id="1"]\n[node name="Inherited" instance=ExtResource("1")]\n`],
			['startup.tres', `[gd_resource type="Resource" format=3]\n[resource]\nmetadata/initial_map = "${target}"\n`],
			['redirects.tres', `[gd_resource type="Resource" format=3]\n[resource]\nmetadata/map_path_redirects = {"res://Old.tscn": "${target}"}\n`],
			['consumer.gd', 'extends RefCounted\nconst SCENE = "Nested/empty_2d.tscn"\n']
		];
		for (const [filename, text] of consumers) {
			const file = absolute(owned[0] + '/' + filename); await fs.writeFile(file, text, { flag: 'wx' });
			const entry = await get(target), preview = await service.previewDeletion(entry);
			assert.ok(preview.consumers.some(c => c.source_path === owned[0] + '/' + filename), filename);
			await assert.rejects(service.deleteScene(entry, preview, trash), /still referenced/);
			assert.equal(trashCalls.length, 0); await fs.unlink(file);
		}
		check('Instances, inheritance, configuration strings, redirects, and relative script references block deletion');
		for (const source of [SCENE_ROOTS[0] + '/city_recreated.tscn', SCENE_ROOTS[2] + '/ui_root.tscn']) {
			const preview = await service.previewDeletion(await get(source)); assert.ok(preview.consumers.length);
		}
		check('The configured starting map and persistent HUD remain protected');
		const entry = await get(target), preview = await service.previewDeletion(entry);
		assert.equal(preview.consumers.length, 0);
		const late = absolute(owned[0] + '/late.tres'); await fs.writeFile(late, `[gd_resource type="Resource" format=3]\n[resource]\nmetadata/map = "${target}"\n`);
		await assert.rejects(service.deleteScene(entry, preview, trash), /directories changed/); await fs.unlink(late);
		const changed = await service.previewDeletion(entry); await fs.appendFile(absolute(target), '\r\n# changed\r\n');
		await assert.rejects(service.deleteScene(entry, changed, trash), /references changed/);
		check('Changed scenes and new consumers invalidate deletion previews');
		const stale = await service.catalogue();
		await fs.appendFile(absolute(target), '# changed again\r\n');
		await assert.rejects(service.createScene(stale.entries.find(e => e.source_path === mapFolder), 'stale.tscn', { template: 'empty_2d', node_name: 'Stale' }, stale), /library changed/);
		check('Stale library snapshots cannot publish new scenes');
		for (const root of SCENE_ROOTS) await assert.rejects(service.deleteEmptyCategory(await get(root), trash), /roots cannot/);
		await assert.rejects(service.deleteEmptyCategory(await get(mapFolder), trash), /empty category/);
		const empty = owned[0] + '/Empty'; await service.createCategory(await get(owned[0]), 'Empty');
		await fs.writeFile(absolute(empty + '/.keep'), 'hidden'); await assert.rejects(service.deleteEmptyCategory(await get(empty), trash), /empty category/); await fs.unlink(absolute(empty + '/.keep'));
		const link = absolute(owned[0] + '/Link'); await fs.symlink(path.join(project, 'Diagnostics'), link, process.platform === 'win32' ? 'junction' : 'dir');
		try { await assert.rejects(checkedLibraryPath(context, owned[0] + '/Link', 'directory'), /link|junction/); }
		finally { if (process.platform === 'win32') await fs.rmdir(link); else await fs.unlink(link); }
		check('Roots, nonempty categories, hidden contents, and linked folders are protected');
		const removable = await get(target); await service.deleteScene(removable, await service.previewDeletion(removable), trash);
		assert.equal(trashCalls.length, 1); await service.deleteEmptyCategory(await get(empty), async file => { trashCalls.push(file); await fs.rmdir(file); });
		assert.equal(trashCalls.length, 2);
		check('Unreferenced scenes and empty categories reach the supplied deletion callback');
		assert.throws(() => validateCatalogue({ ...before, root_paths: [SCENE_ROOTS[0]] }), /Malformed/);
	} finally {
		for (const source of owned) {
			const folder = absolute(source); assert.equal(await fs.realpath(folder), folder);
			assert.ok(SCENE_ROOTS.some(root => path.dirname(folder) === absolute(root)));
			await fs.rm(folder, { recursive: true });
		}
		for (const [source, bytes] of production) assert.deepEqual(await fs.readFile(absolute(source)), bytes);
	}
	check('Temporary files cleaned and all production scenes preserved'); check('Checks passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
