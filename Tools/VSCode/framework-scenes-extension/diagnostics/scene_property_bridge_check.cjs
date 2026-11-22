const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { editScene, inspectNodeProperties } = require('../out/scene_editing_bridge');
const { loadSceneGraph } = require('../out/scene_bridge');

async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected the project and Godot executable.');
	const project = path.resolve(projectArg);
	const id = randomBytes(6).toString('hex');
	const relative = '.godot/diagnostics/scene_properties_' + id;
	const directory = path.join(project, relative);
	const file = path.join(directory, 'entity.tscn');
	const scene = 'res://' + relative + '/entity.tscn';
	const instancedFile = path.join(directory, 'instance.tscn');
	const instance = 'res://' + relative + '/instance.tscn';
	const report = message => console.error(message);
	const body = 'View2D/Body';
	const uid = 'uid://b' + id;
	const original = [
		`[gd_scene format=3 uid="${uid}"]`, '',
		'[node name="Probe" type="Node2D" unique_id=100]',
		'position = Vector2(5, 6)',
		'metadata/large_text = "' + 'x'.repeat(1024) + '"',
		'metadata/payload = PackedByteArray(0, 1, 2, 3)',
		'metadata/entity_definition = &"player"', '',
		'[node name="View2D" type="CharacterBody2D" parent="." unique_id=200]', '',
		'[node name="Body" type="Polygon2D" parent="View2D" unique_id=300] ; body comment',
		'color = Color(1, 1, 1, 1) ; preserve this comment', '',
		'[node name="StatusAnchor" type="Marker2D" parent="View2D" unique_id=400]', '',
		'[node name="TargetPoint" type="Marker2D" parent="View2D" unique_id=500]', ''
	].join('\r\n');
	const properties = async (nodePath, source = scene) => Object.fromEntries(
		(await inspectNodeProperties(project, executable, source, nodePath, report)).map(property => [property.name, property])
	);
	const request = (nodePath, name, type, value, hashes) => ({
		operation: 'set_property', path: nodePath, property_name: name, property_type: type,
		property_value: value, expected_hashes: hashes
	});
	const write = async (nodePath, name, type, value, source = scene, hashes) => {
		const expected = hashes ?? (await loadSceneGraph(project, executable, source, report)).dependency_hashes;
		return editScene(project, executable, source, request(nodePath, name, type, value, expected), report);
	};
	await fs.mkdir(directory, { recursive: true });
	const owned = [];
	try {
		await fs.writeFile(file, original, { flag: 'wx' }); owned.push(file);
		await fs.writeFile(instancedFile, [
			'[gd_scene format=3]', '',
			`[ext_resource type="PackedScene" path="${scene}" id="1"]`, '',
			'[node name="Map" type="Node2D"]', '',
			'[node name="Placed" parent="." instance=ExtResource("1")]', ''
		].join('\r\n'), { flag: 'wx' }); owned.push(instancedFile);
		const bodyBefore = await properties(body);
		assert.equal(bodyBefore.color.type, 'Color');
		assert.equal(bodyBefore.color.saved, true);
		assert.equal(bodyBefore.polygon.type, 'PackedVector2Array');
		assert.equal(bodyBefore['metadata/casts_shadow'].value, 'true');
		const inspected = (await loadSceneGraph(project, executable, scene, report)).dependency_hashes;
		const points = '-16, -16, 16, -16, 16, 16, -16, 16';
		await write(body, 'polygon', 'PackedVector2Array', points);
		await assert.rejects(write(body, 'color', 'Color', '0.1, 0.2, 0.3', scene, inspected), /dependency changed/);
		await write(body, 'color', 'Color', '0.2, 0.6, 1, 1');
		await write(body, 'metadata/casts_shadow', 'bool', 'true');
		await write('View2D', 'metadata/entity_spatial_root', 'bool', 'true');
		await write('View2D/StatusAnchor', 'metadata/ui_anchor_role', 'StringName', 'status');
		await write('View2D/TargetPoint', 'metadata/interaction_target', 'bool', 'true');
		await write('View2D/TargetPoint', 'metadata/note', 'String', 'a note with an embedded "quote"');
		const after = await properties(body);
		assert.equal(after.polygon.value.split(',').map(Number).join(','), points.split(',').map(Number).join(','));
		assert.equal(after.color.saved, true);
		assert.equal(after['metadata/casts_shadow'].saved, true);
		assert.equal((await properties('View2D/TargetPoint'))['metadata/note'].value, 'a note with an embedded "quote"');
		const tree = await loadSceneGraph(project, executable, scene, report);
		const bodyProperties = Object.fromEntries(tree.nodes[body].properties.map(property => [property.name, property]));
		assert.equal(bodyProperties.color.value, 'Color(0.2, 0.6, 1, 1)');
		assert.equal(bodyProperties['metadata/casts_shadow'].value, 'true');
		assert.equal(bodyProperties.polygon.type, 'PackedVector2Array');
		const rootProperties = Object.fromEntries(tree.nodes['.'].properties.map(property => [property.name, property]));
		assert.equal(rootProperties['metadata/payload'].value, '4 bytes');
		assert.ok(rootProperties['metadata/large_text'].value.length <= 240);
		console.log('[scene-property] The hierarchy includes typed saved values and bounded previews for large values.');
		const saved = await fs.readFile(file, 'utf8');
		assert.ok(saved.includes(`uid="${uid}"`) && saved.includes('unique_id=300] ; body comment'));
		assert.ok(saved.includes(' ; preserve this comment') && !/(?<!\r)\n/.test(saved));
		assert.match(saved, /metadata\/ui_anchor_role = &"status"/);
		assert.equal((saved.match(/^color = /gm) ?? []).length, 1);
		console.log('[scene-property] Native and metadata writes preserve values, comments, scene UID, node IDs, and CRLF.');

		await assert.rejects(write(body, 'polygon', 'PackedVector2Array', '1, 2, 3'), /X,Y pairs/);
		await assert.rejects(write(body, 'color', 'String', 'red'), /declared type/);
		await assert.rejects(write(body, 'unknown_property', 'int', '10'), /declared type/);
		await assert.rejects(write('View2D/StatusAnchor', 'metadata/ui_anchor_role', 'bool', 'true'), /requires StringName/);
		assert.equal(await fs.readFile(file, 'utf8'), saved);
		console.log('[scene-property] Stale, invalid, and mistyped requests leave scene bytes unchanged.');

		const inherited = (await loadSceneGraph(project, executable, instance, report)).nodes.Placed.properties;
		assert.deepEqual(inherited.find(property => property.name === 'position'), {
			name: 'position', type: 'Vector2', value: 'Vector2(5, 6)', source_path: scene
		});
		await write('Placed', 'position', 'Vector2', '320, 360', instance);
		assert.equal((await properties('Placed', instance)).position.value, '320, 360');
		const placed = (await loadSceneGraph(project, executable, instance, report)).nodes.Placed.properties;
		assert.deepEqual(placed.filter(property => property.name === 'position'), [
			{ name: 'position', type: 'Vector2', value: 'Vector2(320, 360)', source_path: instance }
		]);
		assert.equal(placed.find(property => property.name === 'metadata/entity_definition').source_path, scene);
		await assert.rejects(write('Placed/View2D/Body', 'color', 'Color', '1, 0, 0', instance), /locally declared/);
		assert.equal(await fs.readFile(file, 'utf8'), saved);
		console.log('[scene-property] Local instance placement edits leave its shared source and borrowed children intact.');
	} finally {
		for (const ownedFile of owned) { await fs.unlink(ownedFile); }
		await fs.rmdir(directory);
	}
	console.log('[scene-property] Checks passed.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
