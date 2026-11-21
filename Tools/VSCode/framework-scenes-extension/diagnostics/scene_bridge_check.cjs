const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFile } = require('node:fs/promises');
const { resolve, join } = require('node:path');
const { loadSceneGraph } = require('../out/scene_bridge');

async function main() {
	const project = process.argv[2];
	const godot = process.argv[3];
	if (!project || !godot) {
		throw new Error('Usage: node diagnostics/scene_bridge_check.cjs <project-directory> <godot-console-executable>');
	}
	const projectDirectory = resolve(project);
	const sources = [
		'Framework/Content/Maps/city_recreated.tscn',
		'Framework/Content/Presentation/Entity/Player/player_2d.tscn',
		'Framework/Content/Presentation/Entity/Enemy/enemy_2d.tscn',
		'Framework/Content/Camera/player_camera_2d.tscn',
		'Framework/Content/UI/HUD/ui_root.tscn',
		'Diagnostics/Fixtures/SceneGraph/inherited.tscn',
		'Diagnostics/Fixtures/SceneGraph/composed.tscn'
	];
	const hash = async path => createHash('sha256').update(await readFile(join(projectDirectory, path))).digest('hex');
	const hashes = await Promise.all(sources.map(hash));
	for (const source of sources) {
		const scenePath = `res://${source}`;
		const graph = await loadSceneGraph(projectDirectory, godot, scenePath, message => console.error(message));
		assert.equal(graph.source_path, scenePath);
		assert.ok(graph.nodes['.'].name);
		if (source.endsWith('city_recreated.tscn')) {
			assert.equal(graph.nodes['Player/View2D/FollowCamera'].type, 'Camera2D');
			assert.equal(graph.nodes['Enemy/View2D/Body'].source_path, 'res://Framework/Content/Presentation/Entity/Enemy/enemy_2d.tscn');
		}
		console.log(`[scene-bridge-check] Loaded ${Object.keys(graph.nodes).length} node(s): ${source}`);
	}
	assert.throws(() => loadSceneGraph(projectDirectory, godot,
		'res://Framework/Content/Behavior/Action/change_health.tres', () => {}));
	await assert.rejects(loadSceneGraph(projectDirectory, godot,
		'res://Diagnostics/Fixtures/SceneGraph/missing.tscn', () => {}), /does not exist/);
	for (let index = 0; index < sources.length; index++) {
		assert.equal(await hash(sources[index]), hashes[index]);
	}
	console.log('[scene-bridge-check] Source scene bytes remain unchanged: true');
	console.log('[scene-bridge-check] Checks passed: true');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
