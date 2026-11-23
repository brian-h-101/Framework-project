const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const { draftConfiguration } = require('../out/bridges/behavior_editing_bridge.js');
const { loadResourceGraph, MOVEMENT_CONTROLLER_ROOT } = require('../out/bridges/resource_bridge.js');
const { directoryFingerprint, sha256 } = require('../out/library/library_paths.js');

const project = path.resolve(process.argv[2] ?? path.join(__dirname, '../../../../framework-project'));
const executable = process.argv[3] ?? 'Godot_v4.7.1-stable_win64_console.exe';
const controls = 'res://Framework/Content/Configuration/Input/controls.tres';
const player = 'res://Framework/Content/Gameplay/Presentation/Entity/Player/player_2d.tscn';
const enemy = 'res://Framework/Content/Gameplay/Presentation/Entity/Enemy/enemy_2d.tscn';
const controllerNames = { keyboard: 'controller_check_keyboard.tres', ai: 'controller_check_ai.tres' };
const source = kind => `${MOVEMENT_CONTROLLER_ROOT}/${controllerNames[kind]}`;
const say = message => console.log('[controller-authoring] ' + message);

async function main() {
	const temp = fs.realpathSync(os.tmpdir());
	const scratch = fs.mkdtempSync(path.join(temp, 'framework-controller-'));
	const disk = resource => path.join(scratch, resource.slice(6));
	const uri = fsPath => ({ scheme: 'file', fsPath });
	const directions = ['left', 'right', 'up', 'down'];
	const actions = Object.fromEntries(directions.map(direction => [direction, 'move_' + direction]));
	const opened = [];
	const errors = [];
	let kind = 'keyboard';
	let cancel = true;
	let refreshes = 0;
	const vscode = {
		Uri: { file: uri, joinPath: (root, ...parts) => uri(path.join(root.fsPath, ...parts)) },
		workspace: {
			isTrusted: true, workspaceFolders: [{ uri: uri(scratch) }], textDocuments: [],
			findFiles: async () => [uri(path.join(scratch, 'project.godot'))],
			getConfiguration: () => ({ get: () => executable }),
		},
		window: {
			async showQuickPick(items, { title }) {
				if (title.endsWith('— Type')) { return items.find(item => item.controller === kind); }
				if (title.startsWith('Keyboard Movement')) {
					if (cancel) { return; }
					const direction = directions.find(value => title.includes(` ${value} `));
					assert.equal(items[0], actions[direction]);
					assert.ok(directions.slice(0, directions.indexOf(direction)).every(used => !items.includes(actions[used])));
					return items[0];
				}
				assert.ok(['AI Movement — Targeting', 'AI Movement — Distance Unit'].includes(title));
				return items[0];
			},
			async showInputBox({ title, value, validateInput }) {
				if (title.endsWith('— Filename')) {
					assert.ok(validateInput('../bad.tres'));
					assert.equal(validateInput(controllerNames[kind]), undefined);
					return controllerNames[kind];
				}
				assert.equal(title, 'AI Movement — Stopping Distance');
				assert.equal(value, '4.8');
				assert.ok(validateInput('') && validateInput('-1') && validateInput('Infinity'));
				return value;
			},
			showErrorMessage: async error => errors.push(error),
			showTextDocument: async document => opened.push(document.fsPath),
		}
	};
	try {
		for (const name of ['Framework', 'Games', 'project.godot', 'icon.svg', 'icon.svg.import', '.godot/imported']) {
			const from = path.join(project, name);
			if (fs.existsSync(from)) { fs.cpSync(from, path.join(scratch, name), { recursive: true }); }
		}
		const projectFile = path.join(scratch, 'project.godot');
		fs.appendFileSync(projectFile, '\n[debug]\nfile_logging/enable_file_logging=false\n');
		const originals = [controls, player, enemy].map(file => fs.readFileSync(disk(file)));
		let ConfigurationCommands;
		const originalLoad = Module._load;
		try {
			Module._load = function (id, ...args) {
				return id === 'vscode' ? vscode : originalLoad.call(this, id, ...args);
			};
			({ ConfigurationCommands } = require('../out/commands/configuration_editing_command.js'));
		} finally { Module._load = originalLoad; }
		const commands = new ConfigurationCommands(undefined, { appendLine() {} }, async () => { refreshes++; });
		await commands.execute('new_movement_controller');
		assert.ok(!fs.existsSync(disk(source('keyboard'))));
		assert.deepEqual(errors, []);
		cancel = false;
		await commands.execute('new_movement_controller');
		kind = 'ai';
		await commands.execute('new_movement_controller');
		assert.deepEqual(errors, []);
		assert.deepEqual(opened, [disk(source('keyboard')), disk(source('ai'))]);
		assert.equal(refreshes, 2);
		say('Keyboard and AI controllers saved through the extension command');

		const saved = fs.readFileSync(disk(source('ai')));
		await commands.execute('new_movement_controller');
		assert.match(errors.pop(), /already exists/i);
		assert.deepEqual(fs.readFileSync(disk(source('ai'))), saved);
		assert.equal(refreshes, 2);
		const invalid = MOVEMENT_CONTROLLER_ROOT + '/controller_check_invalid.tres';
		const request = {
			operation: 'draft_movement_controller', controller_kind: 'keyboard',
			expected_parent: await directoryFingerprint(disk(MOVEMENT_CONTROLLER_ROOT)),
			expected_hashes: { [controls]: sha256(originals[0]) },
		};
		for (const [input_actions, error] of [
			[{ ...actions, up: 'missing_action' }, /bound key for up/],
			[{ ...actions, up: actions.left }, /distinct directional actions/],
		]) {
			await assert.rejects(draftConfiguration(scratch, executable, invalid, { ...request, input_actions }, say), error);
		}
		await assert.rejects(draftConfiguration(scratch, executable, invalid, {
			...request, controller_kind: 'ai', targeting: 'nearest', distance_unit: 'pixels', stopping_distance: -1
		}, say), /nonnegative/);
		await assert.rejects(draftConfiguration(scratch, executable, invalid, {
			...request, input_actions: actions, expected_hashes: { [controls]: '0'.repeat(64) }
		}, say), /dependency changed/);
		assert.ok(!fs.existsSync(disk(invalid)));
		say('Invalid settings and duplicate names leave the destination files intact');

		for (const controller of ['keyboard', 'ai']) {
			const file = source(controller);
			const graph = await loadResourceGraph(scratch, executable, say, file, { mode: 'browse' });
			const node = graph.nodes[file];
			assert.equal(node.configuration_type, 'movement_controller');
			const values = Object.fromEntries(node.data.children.map(row => [row.label, row]));
			assert.equal(values.kind.value_text, controller);
			if (controller === 'ai') {
				assert.equal(values.targeting.value_text, 'nearest');
				assert.equal(values.distance_unit.value_text, 'gameplay_units');
				assert.equal(Number(values.stopping_distance.value_text), 4.8);
			} else {
				assert.deepEqual(Object.fromEntries(values.actions.children.map(row => [row.label, row.value_text])), actions);
			}
		}
		const result = spawnSync(executable, ['--headless', '--path', scratch, '--script',
			'res://Framework/Env/Authoring/Scenes/Editing/scene_editing_cli.gd', '--', 'inspect-movement', player, '.'],
		{ cwd: scratch, encoding: 'utf8', timeout: 30000, windowsHide: true });
		if (result.error) { throw result.error; }
		const output = result.stdout + '\n' + result.stderr;
		assert.equal(result.status, 0, output);
		assert.doesNotMatch(output, /^(SCRIPT ERROR|ERROR):/m);
		const prefix = '[scene-editing] ';
		const line = output.split(/\r?\n/).find(value => value.startsWith(prefix));
		assert.ok(line, output);
		const inspection = JSON.parse(line.slice(prefix.length));
		assert.ok(inspection.ok, inspection.error);
		for (const controller of ['keyboard', 'ai']) {
			assert.ok(inspection.value.controllers.some(entry => entry.kind === controller && entry.source_path === source(controller)));
		}
		assert.deepEqual([controls, player, enemy].map(file => fs.readFileSync(disk(file))), originals);
		say('Framework Resources displays both controllers and Framework Scenes discovers both');
	} finally {
		assert.equal(path.dirname(scratch), temp);
		assert.ok(path.basename(scratch).startsWith('framework-controller-'));
		fs.rmSync(scratch, { recursive: true });
	}
}

main().catch(error => { console.error(error); process.exitCode = 1; });
