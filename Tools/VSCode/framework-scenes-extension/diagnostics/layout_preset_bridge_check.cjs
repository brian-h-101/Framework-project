const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const { resolveLayout, editScene, runSceneEditing } = require('../out/scene_editing_bridge.js');
const { loadSceneGraph } = require('../out/scene_bridge.js');
const { loadResourceGraph } = require('../../resource-condition-extension/out/bridges/resource_bridge.js');

async function main() {
	const [directory, executable] = process.argv.slice(2);
	assert.ok(directory && executable, 'Expected a Godot project and executable.');
	const project = path.resolve(directory);
	const presetFolder = 'res://Framework/Content/Gameplay/Presets';
	const sceneFolder = 'res://Framework/Content/Gameplay/Presentation/Layouts';
	const name = 'DiagnosticLayout_' + randomBytes(8).toString('hex');
	const parentCategory = presetFolder + '/' + name;
	const category = parentCategory + '/Outdoor';
	const generatedCategory = sceneFolder + '/' + name + '/Outdoor';
	const preset = category + '/ground.layout.tres';
	const generated = generatedCategory + '/ground.tscn';
	const target = sceneFolder + '/' + name + '_target.tscn';
	const script = 'res://Framework/Content/Universal/Map/based/Rendering2D/tile_map_layer_2d.gd';
	const ground = 'res://Framework/Content/Configuration/Map/city_ground.tres';
	const file = source => path.join(project, source.slice(6));
	const exists = source => fs.stat(file(source)).then(() => true, error => {
		if (error.code === 'ENOENT') { return false; }
		throw error;
	});
	const existingFolders = new Map(await Promise.all([presetFolder, sceneFolder].map(async folder => [folder, await exists(folder)])));
	const report = message => console.error(message);
	const request = (action, source, payload, extra = []) => runSceneEditing(project, executable,
		[action, source, ...extra].filter(item => item !== undefined), payload, report);
	const hash = async source => createHash('sha256').update(await fs.readFile(file(source))).digest('hex');
	const layout = node => request('inspect-layout', preset, undefined, [node]);
	const change = async (node, operation, fields = {}) => {
		const inspected = await layout(node);
		const expected = { ...inspected.dependency_hashes };
		if (fields.asset_path) { expected[fields.asset_path] = await hash(fields.asset_path); }
		return request('edit-layout', preset, { operation, node_path: node, expected_hashes: expected, ...fields });
	};
	const scene = source => loadSceneGraph(project, executable, source, report);
	const placement = async (name, source = target) => {
		const inspected = await scene(source);
		const layoutResult = await resolveLayout(project, executable, preset, report);
		return editScene(project, executable, source, { operation: 'add_instance', path: '.', name,
			instance_scene: layoutResult.scene_path, layout_path: preset, layout_hashes: layoutResult.dependency_hashes,
			expected_hashes: { ...inspected.dependency_hashes, [generated]: layoutResult.dependency_hashes[generated] } }, report);
	};
	const setPosition = async (node, value) => editScene(project, executable, target, {
		operation: 'set_property', path: node, property_name: 'position', property_type: 'Vector2', property_value: value,
		expected_hashes: (await scene(target)).dependency_hashes
	}, report);
	const build = async () => request('build-layout', preset, (await layout('.')).dependency_hashes);
	const categoryHash = async source => {
		const listed = await request('layout-categories');
		const entry = listed.find(item => item.source_path === source);
		assert.ok(entry, source);
		return entry.fingerprint;
	};
	const createCategory = async (source, parent) => request('create-layout-category', source, { expected_parent: await categoryHash(parent) });
	const previewCategory = async source => request('preview-layout-category-deletion', source, { expected_directory: await categoryHash(source) });
	try {
		assert.equal((await createCategory(parentCategory, presetFolder)).source_path, parentCategory);
		assert.equal((await createCategory(category, parentCategory)).source_path, category);
		await assert.rejects(createCategory(parentCategory + '/OUTDOOR', parentCategory), /already exists/);
		await assert.rejects(previewCategory(presetFolder), /Choose a subcategory/);
		const emptyCategory = await previewCategory(category);
		assert.equal(emptyCategory.file_count, 0);
		assert.deepEqual(emptyCategory.consumers, []);
		const draft = await request('create-layout', preset, {
			name: 'GroundLayout', node_type: 'Node2D', expected_parent: await categoryHash(category),
		});
		await fs.writeFile(file(preset), draft.source_text, { flag: 'wx' });
		const populatedCategory = await previewCategory(parentCategory);
		assert.equal(populatedCategory.file_count, 1);
		assert.deepEqual(populatedCategory.consumers, []);
		console.log('[layout] Nested categories are discoverable and scoped for deletion');
		await assert.rejects(resolveLayout(project, executable, preset, report), /Build the selected Layout Preset/);
		const untouched = await hash(preset);
		await assert.rejects(change('.', 'add', { name: 'Bad', node_type: 'Resource' }), /instantiable native Node/);
		await assert.rejects(change('.', 'attach_script', { asset_path: script }), /cannot attach/);
		assert.equal(await hash(preset), untouched);
		await change('.', 'add', { name: 'Temporary', node_type: 'Node2D' });
		await change('Temporary', 'remove');
		await change('.', 'add', { name: 'Tiles', node_type: 'TileMapLayer' });
		await change('Tiles', 'rename', { name: 'Ground' });
		await change('Ground', 'attach_script', { asset_path: script });
		const properties = (await layout('Ground')).properties;
		assert.ok(properties.some(property => property.name === 'content' && property.kind === 'Resource'));
		await change('Ground', 'assign_resource', { property_name: 'content', asset_path: ground });
		await change('Ground', 'set_property', { property_name: 'z_index', property_type: 'int', property_value: '-1' });
		await change('Ground', 'set_property', { property_name: 'metadata/receives_shadow', property_type: 'bool', property_value: 'true' });
		await assert.rejects(change('Ground', 'set_property', { property_name: 'missing_property', property_type: 'int', property_value: '4' }), /no supported property/);
		const graph = await loadResourceGraph(project, executable, report, preset, { mode: 'browse' });
		const root = graph.nodes[preset].data.children.find(child => child.layout_path === '.');
		assert.equal(graph.nodes[preset].kind, 'layout');
		assert.equal(root.children.find(child => child.label === 'Children').children[0].layout_path, 'Ground');
		console.log('[layout] Preset validates node structure, script compatibility, properties, and assigned resources');

		const first = await build();
		assert.equal(first.scene_path, generated);
		assert.equal(await exists(category + '/ground.tscn'), false);
		const referencedCategory = await previewCategory(parentCategory);
		assert.ok(referencedCategory.consumers.some(item => item.source_path === generated));
		const generatedText = await fs.readFile(file(generated), 'utf8');
		assert.match(generatedText, /z_index = -1/);
		assert.ok(generatedText.includes(script) && generatedText.includes(ground));
		await fs.writeFile(file(target), '[gd_scene format=3]\n\n[node name="LayoutTest" type="Node2D"]\n', { flag: 'wx' });
		await placement('GroundOne');
		await placement('GroundTwo');
		await setPosition('GroundOne', '20, 30');
		await setPosition('GroundTwo', '80, 90');
		await assert.rejects(placement('Cyclic', generated), /dependency cycle/);
		assert.equal(await fs.readFile(file(generated), 'utf8'), generatedText);
		const placed = await hash(target);
		await change('Ground', 'set_property', { property_name: 'z_index', property_type: 'int', property_value: '-3' });
		await assert.rejects(placement('Stale'), /Rebuild the selected Layout Preset/);
		assert.equal(await hash(target), placed);
		const rebuilt = await build();
		assert.equal(rebuilt.uid, first.uid);
		assert.match(await fs.readFile(file(generated), 'utf8'), /z_index = -3/);
		assert.equal(await hash(target), placed);
		const after = await scene(target);
		assert.equal(after.nodes['GroundOne/Ground'].type, 'TileMapLayer');
		assert.equal(after.nodes['GroundTwo/Ground'].type, 'TileMapLayer');
		for (const node of ['GroundOne/Ground', 'GroundTwo/Ground']) {
			assert.equal(after.nodes[node].properties.find(property => property.name === 'z_index').value, '-3');
		}
		const destination = await fs.readFile(file(target), 'utf8');
		assert.match(destination, /position = Vector2\(20, 30\)/);
		assert.match(destination, /position = Vector2\(80, 90\)/);
		console.log('[layout] Both placements share rebuilt layout content and preserve local positions');
		console.log('[layout] Checks passed');
	} finally {
		for (const source of [target, generated, preset]) {
			await fs.unlink(file(source)).catch(error => { if (error.code !== 'ENOENT') { throw error; } });
		}
		for (const folder of [generatedCategory, sceneFolder + '/' + name, category, parentCategory]) {
			if (await exists(folder) && !(await fs.readdir(file(folder))).length) { await fs.rmdir(file(folder)); }
		}
		for (const [folder, existed] of existingFolders) {
			if (!existed && await exists(folder) && !(await fs.readdir(file(folder))).length) { await fs.rmdir(file(folder)); }
		}
	}
}

main().catch(error => { console.error(error); process.exitCode = 1; });
