const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const project = path.resolve(process.argv[2] ?? path.join(__dirname, '../../../../framework-project'));
const godot = process.argv[3] ?? 'Godot_v4.7.1-stable_win64_console.exe';
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'framework-movement-'));
const source = 'Framework/Content/Gameplay/Presentation/Entity/Player/player_2d.tscn';
const city = 'Framework/Content/Gameplay/Maps/city.tscn';
const input = 'Framework/Content/Configuration/Input/controls.tres';
const profile = 'Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres';
const grid = 'Framework/Content/Gameplay/Profiles/Movement/Shared/movement_grid.tres';
const nativeProfile = 'Framework/Content/Gameplay/Profiles/Movement/Shared/movement_3d.tres';
const nativeMap = 'Diagnostics/Fixtures/Movement/Physics3D/physics_3d_map.tscn';
const keyboard = 'Framework/Content/Gameplay/Controller/player_keyboard.tres';
const ai = 'Framework/Content/Gameplay/Controller/enemy_ai.tres';
const enemy = 'Framework/Content/Gameplay/Presentation/Entity/Enemy/enemy_2d.tscn';
const runtimeCheck = 'Diagnostics/Gameplay/world_bridge_movement_check.gd';
const behavior = 'Framework/Content/Gameplay/Profiles/Movement/Behavior/move.tres';
const calculator = 'Framework/Content/Universal/Movement/based/Execution/velocity_calculator.gd';
const runner = 'Framework/Content/Universal/Movement/based/Execution/movement_component.gd';
const script = 'Framework/Env/Authoring/Scenes/Editing/scene_editing_cli.gd';
const resource = file => 'res://' + file;
const read = file => fs.readFileSync(path.join(scratch, file), 'utf8');
const write = (file, value) => fs.writeFileSync(path.join(scratch, file), value);
const hash = file => createHash('sha256').update(fs.readFileSync(path.join(scratch, file))).digest('hex');
const say = message => console.log('[movement-capability] ' + message);
const check = (value, message) => { assert.ok(value, message); say(message + ': true'); };

function run(scriptPath, args = [], request, expected = 0) {
	const result = spawnSync(godot, ['--headless', '--path', scratch, '--log-file', path.join(scratch, 'check.log'),
		'--script', resource(scriptPath), '--', ...args], {
		cwd: scratch, encoding: 'utf8', input: request === undefined ? '' : JSON.stringify(request),
		timeout: 30000, windowsHide: true
	});
	if (result.error) { throw result.error; }
	const output = result.stdout + '\n' + result.stderr;
	assert.equal(result.status, expected, output);
	// The test runner can deny access to Windows' certificate store.
	assert.doesNotMatch(output, /^(SCRIPT ERROR|ERROR)(?!: Failed to read the root certificate store\.)\s*:/m);
	return result.stdout;
}

function capability(command, request, expected = 0, scene = city, node = 'Player') {
	const prefix = '[scene-editing] ';
	const lines = run(script, [command, resource(scene), node], request, expected)
		.split(/\r?\n/).filter(line => line.startsWith(prefix));
	assert.equal(lines.length, 1);
	const result = JSON.parse(lines[0].slice(prefix.length));
	assert.equal(result.ok, expected === 0, result.error);
	return result.ok ? result.value : result.error;
}

try {
	for (const name of ['Framework', 'Games', 'project.godot', 'icon.svg', 'icon.svg.import', '.godot/imported', runtimeCheck, nativeMap]) {
		const from = path.join(project, name);
		if (fs.existsSync(from)) { fs.cpSync(from, path.join(scratch, name), { recursive: true }); }
	}
	const originalScene = read(source);
	const originalEnemy = read(enemy);
	const initialMap = hash(city);
	const shared = [profile, grid, nativeProfile, behavior, input, keyboard, ai];
	const originalHashes = shared.map(hash);
	const folders = [...new Set(shared.map(file => path.dirname(file)))];
	const entries = folders.map(folder => fs.readdirSync(path.join(scratch, folder)));
	const playerOptions = { configuration_path: resource(profile), controller_path: resource(keyboard) };
	const enemyOptions = { configuration_path: resource(profile), controller_path: resource(ai) };
	const gridOptions = { configuration_path: resource(grid), controller_path: resource(keyboard), environment: 'grid' };
	const nativeOptions = { configuration_path: resource(nativeProfile), controller_path: resource(keyboard), environment: 'physics_3d' };

	const inspected = capability('inspect-movement');
	check(inspected.scene_path === resource(source) && inspected.body_path === 'View2D'
		&& inspected.configurations.filter(entry => entry.source_path === resource(profile)).length === 1
		&& inspected.configurations.some(entry => entry.source_path === resource(grid) && entry.environment === 'grid'
			&& entry.behavior_id === 'move')
		&& inspected.controllers.some(entry => entry.kind === 'keyboard')
		&& inspected.controllers.some(entry => entry.kind === 'ai'), 'City resolves the owned scene and discovers shared resources');
	for (const [node, options] of [['Player', playerOptions], ['Enemy', enemyOptions]]) {
		const plan = capability('plan-movement', options, 0, city, node);
		check(!plan.add_binding && !plan.attach_script && !plan.assign_configuration && !plan.assign_controller,
			node + ' already reuses the shared profile and its chosen controller');
		check(!capability('apply-movement', { ...options, token: plan.token }, 0, city, node).changed,
			node + ' reapply is a no-op');
	}
	check(read(source) === originalScene && read(enemy) === originalEnemy, 'Reapplying preserves both scene files');
	check(/different movement environment/i.test(capability('plan-movement', { ...gridOptions, environment: 'physics_2d' }, 1)),
		'A mismatched environment is rejected');
	const gridPlan = capability('plan-movement', gridOptions);
	check(gridPlan.environment === 'grid' && gridPlan.assign_configuration && !gridPlan.attach_script
		&& !gridPlan.assign_controller && !gridPlan.add_binding && gridPlan.behavior_path === resource(behavior),
		'The Grid plan changes the environment profile and reuses the same Behavior and controller');
	check(capability('apply-movement', { ...gridOptions, token: gridPlan.token }).changed
		&& capability('inspect-movement').current_configuration === resource(grid),
		'Applying Grid saves the profile on the owned scene');
	write(source, originalScene);

	const nativeInspection = capability('inspect-movement', undefined, 0, nativeMap);
	check(nativeInspection.configurations.length === 1 && nativeInspection.configurations[0].environment === 'physics_3d'
		&& nativeInspection.body_path === 'Player/Body3D', 'A 3D body offers the matching environment profile');
	check(/incompatible/i.test(capability('plan-movement', playerOptions, 1, nativeMap)),
		'A 3D body rejects assignment of a 2D profile');
	const nativeSource = read(nativeMap);
	const bare3D = nativeSource.replace(/\[node name="Body3D" type="CharacterBody3D" parent="Player"\][^\[]+/,
		block => block.replace(/^(?:script|content|controller) = ExtResource.+\r?\n/gm, ''));
	assert.notEqual(bare3D, nativeSource);
	write(nativeMap, bare3D);
	const plan3D = capability('plan-movement', nativeOptions, 0, nativeMap);
	check(plan3D.attach_script && plan3D.assign_configuration && plan3D.assign_controller && !plan3D.add_binding
		&& plan3D.dependency_hashes['res://Framework/Content/Universal/Movement/based/Physics3D/movement_body_3d.gd'],
		'The 3D specification chooses its mounting script while reusing the Behavior binding');
	check(capability('apply-movement', { ...nativeOptions, token: plan3D.token }, 0, nativeMap).changed
		&& capability('inspect-movement', undefined, 0, nativeMap).current_configuration === resource(nativeProfile),
		'The authoring plan installs the compatible 3D movement specification');

	// Rename both nodes to exercise discovery by spatial role and Behavior ID.
	const renamed = originalScene.replaceAll('View2D', 'MotionBody').replace('name="MoveBehavior"', 'name="MovementBinding"');
	const bare = renamed.replace(/^script = ExtResource\("attached_script"\)\r?\n/m, '')
		.replace(/^content = ExtResource\("movement_content"\)\r?\n/m, '')
		.replace(/^controller = ExtResource\("movement_controller"\)\r?\n/m, '');
	assert.notEqual(bare, renamed);
	write(source, bare);
	const review = capability('plan-movement', playerOptions);
	check(review.attach_script && review.assign_configuration && review.assign_controller && !review.add_binding
		&& review.binding_path === 'MovementBinding' && review.input_actions.length === 4,
		'Authoring plans a single scene edit and reuses an existing binding regardless of its node name');
	check(review.dependency_hashes[resource(calculator)] === hash(calculator)
		&& review.dependency_hashes[resource(runner)] === hash(runner),
		'The authoring review includes the extracted runner and calculator');
	const calculatorText = read(calculator);
	write(calculator, calculatorText + '\n');
	check(/changed since review/i.test(capability('apply-movement', { ...playerOptions, token: review.token }, 1))
		&& read(source) === bare, 'A changed Universal calculator invalidates the reviewed scene edit');
	write(calculator, calculatorText);
	const keyboardText = read(keyboard);
	write(keyboard, keyboardText + '\n');
	check(/changed since review/i.test(capability('apply-movement', { ...playerOptions, token: review.token }, 1))
		&& read(source) === bare, 'A stale controller rejects the whole scene edit');
	write(keyboard, keyboardText.replace('&"move_up"', '&"missing_move_up"'));
	check(/needs a binding/i.test(capability('plan-movement', playerOptions, 1)) && read(source) === bare,
		'A missing keyboard binding is reported without creating input or editing the scene');
	write(keyboard, keyboardText);

	const approved = capability('plan-movement', playerOptions);
	check(capability('apply-movement', { ...playerOptions, token: approved.token }).changed,
		'Applies the Movement adapter, profile, and keyboard controller');
	const editable = read(source);
	check(editable.includes('name="MovementBinding"') && !editable.includes('name="MoveBehavior"')
		&& editable.includes('name="FollowCamera"') && editable.includes('parent="MotionBody"')
		&& editable.startsWith(originalScene.split(/\r?\n/)[0]), 'Behavior binding, camera and scene UID survive');
	assert.deepEqual(shared.map(hash), originalHashes);
	assert.deepEqual(folders.map(folder => fs.readdirSync(path.join(scratch, folder))), entries);
	check(hash(city) === initialMap, 'Applying from City leaves the map and all shared resources unchanged');

	const swap = capability('plan-movement', enemyOptions);
	check(swap.assign_controller && !swap.assign_configuration && !swap.add_binding && !swap.input_actions.length,
		'Switching controller uses the same movement profile and Behavior');
	check(capability('apply-movement', { ...enemyOptions, token: swap.token }).changed
		&& capability('inspect-movement').current_controller === resource(ai), 'An existing controller reference can be replaced');
	write(source, originalScene);

	const runtime = run(runtimeCheck);
	check(runtime.includes('[bridge-movement] Checks passed: true'),
		'Both controllers run with shared movement in City, including AI stopping and keyboard release');
	say('Checks passed: true');
} finally {
	assert.equal(path.dirname(path.resolve(scratch)), path.resolve(os.tmpdir()));
	fs.rmSync(scratch, { recursive: true, force: true });
}
