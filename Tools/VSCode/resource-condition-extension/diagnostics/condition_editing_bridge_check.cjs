const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');

const {
	getConditionComparison,
	setConditionComparison
} = require('../out/bridges/condition_editing_bridge.js');

const execute = promisify(execFile);
const READ_PREFIX = '[editing-readback] ';

function check(label, condition) {
	assert.ok(condition, label);
	console.log(`[editing-bridge] ${label}: true`);
}

async function main() {
	const [projectArgument, godotExecutable] = process.argv.slice(2);

	if (!projectArgument || !godotExecutable) {
		throw new Error(
			'Expected the Godot project directory and executable path.'
		);
	}

	const projectDirectory = path.resolve(projectArgument);

	await fs.access(path.join(projectDirectory, 'project.godot'));

	const sourceFiles = [
		'Framework/Content/Behavior/Condition/actor_strength.tres',
		'Framework/Content/Behavior/Condition/can_strike.tres'
	].map(relativePath => path.join(projectDirectory, relativePath));

	const sourceBytes = await Promise.all(
		sourceFiles.map(file => fs.readFile(file))
	);

	const diagnosticsDirectory = path.join(
		projectDirectory,
		'.godot',
		'diagnostics'
	);

	await fs.mkdir(diagnosticsDirectory, { recursive: true });

	const testDirectory = await fs.mkdtemp(
		path.join(diagnosticsDirectory, 'condition_editing_bridge_')
	);

	const resourceDirectory =
		`res://.godot/diagnostics/${path.basename(testDirectory)}`;

	const conditionPath = `${resourceDirectory}/condition.tres`;
	const readerPath = `${resourceDirectory}/read_saved.gd`;

	const ownedFiles = [
		'condition.tres',
		'read_saved.gd',
		'read_saved.gd.uid'
	];

	const conditionText = `[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd" id="1_condition"]

[resource]
script = ExtResource("1_condition")
id = &"editing_bridge_check"
requirement = {
	"entity": &"actor",
	"container": &"strength",
	"path": ["current"],
	"operator": ">=",
	"value": 10,
	"message": "Original message.",
	"metadata": {
		"tags": ["bridge-preserved"],
		"enabled": true
	}
}
`;

	const readerText = `extends SceneTree

const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd"
)


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()

	if arguments.size() != 5:
		push_error("Expected path, operator, numeric type, value, and message.")
		quit(2)
		return

	var condition: ConditionResource = ResourceLoader.load(
		arguments[0],
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as ConditionResource

	if condition == null:
		push_error("Saved condition could not be loaded.")
		quit(2)
		return

	var expected_value: Variant

	if arguments[2] == "int":
		expected_value = arguments[3].to_int()
	else:
		expected_value = arguments[3].to_float()

	var expected_requirement: Dictionary = {
		"entity": &"actor",
		"container": &"strength",
		"path": ["current"],
		"operator": arguments[1],
		"value": expected_value,
		"message": arguments[4],
		"metadata": {
			"tags": ["bridge-preserved"],
			"enabled": true,
		},
	}

	var checks: Dictionary = {
		"id_preserved": condition.id == &"editing_bridge_check",
		"requirement_preserved": (
			condition.requirement == expected_requirement
		),
		"numeric_type_preserved": (
			typeof(condition.requirement.get("value"))
			== typeof(expected_value)
		),
	}

	print("[editing-readback] ", JSON.stringify(checks))

	var passed: bool = (
		checks["id_preserved"]
		and checks["requirement_preserved"]
		and checks["numeric_type_preserved"]
	)

	quit(0 if passed else 1)
`;

	const cases = [
		{
			label: 'Integer',
			operator: '>=',
			value_type: 'int',
			value_text: '20',
			message: 'Requires at least 20 strength.'
		},
		{
			label: 'Integral float',
			operator: '<',
			value_type: 'float',
			value_text: '20',
			message: 'Requires less than 20 strength.'
		},
		{
			label: 'Maximum integer',
			operator: '<=',
			value_type: 'int',
			value_text: '9223372036854775807',
			message: 'Maximum integer bridge check.'
		}
	];

	const report = message => {
		console.error(`[editing-bridge] Godot diagnostics:\n${message}`);
	};

	try {
		await fs.writeFile(
			path.join(testDirectory, 'condition.tres'),
			conditionText.replace(/\r?\n/g, '\r\n'),
			{ encoding: 'utf8', flag: 'wx' }
		);

		await fs.writeFile(
			path.join(testDirectory, 'read_saved.gd'),
			readerText.replace(/\r?\n/g, '\r\n'),
			{ encoding: 'utf8', flag: 'wx' }
		);

		for (const [index, testCase] of cases.entries()) {
			const { label, ...edit } = testCase;

			const result = await setConditionComparison(
				projectDirectory,
				godotExecutable,
				conditionPath,
				edit,
				report
			);

			assert.deepEqual(result, {
				condition_path: conditionPath,
				...edit
			});

			check(`${label} reply preserves typed numeric text`, true);

			const conditionFile = path.join(
				testDirectory,
				'condition.tres'
			);

			const bytesBeforeRead = await fs.readFile(conditionFile);

			const current = await getConditionComparison(
				projectDirectory,
				godotExecutable,
				conditionPath,
				report
			);

			assert.equal(current.condition_path, conditionPath);
			assert.equal(current.operator, edit.operator);
			assert.equal(current.value_type, edit.value_type);
			assert.equal(current.message, edit.message);

			if (edit.value_type === 'int') {
				assert.equal(current.value_text, edit.value_text);
			} else {
				assert.equal(
					Number(current.value_text),
					Number(edit.value_text)
				);
			}

			check(`${label} read returns the saved comparison`, true);

			check(
				`${label} read preserves resource bytes`,
				(await fs.readFile(conditionFile)).equals(bytesBeforeRead)
			);

			const logName = `readback_${index}.log`;
			ownedFiles.push(logName);

			const { stdout, stderr } = await execute(
				godotExecutable,
				[
					'--headless',
					'--path',
					projectDirectory,
					'--log-file',
					path.join(testDirectory, logName),
					'--script',
					readerPath,
					'--',
					conditionPath,
					edit.operator,
					edit.value_type,
					edit.value_text,
					edit.message
				],
				{
					cwd: projectDirectory,
					encoding: 'utf8',
					windowsHide: true,
					timeout: 30_000,
					maxBuffer: 4 * 1024 * 1024
				}
			);

			assert.doesNotMatch(
				stdout + '\n' + stderr,
				/^(?:SCRIPT ERROR|ERROR):/m
			);

			const lines = stdout
				.split(/\r?\n/)
				.filter(line => line.startsWith(READ_PREFIX));

			assert.equal(lines.length, 1);

			assert.deepEqual(
				JSON.parse(lines[0].slice(READ_PREFIX.length)),
				{
					id_preserved: true,
					requirement_preserved: true,
					numeric_type_preserved: true
				}
			);

			check(`${label} saved data and numeric type are correct`, true);
		}

		const groupPath =
			'res://Framework/Content/Behavior/Condition/can_strike.tres';

		await assert.rejects(
			() => getConditionComparison(
				projectDirectory,
				godotExecutable,
				groupPath,
				report
			),
			{ message: 'Expected a condition: ' + groupPath }
		);

		check('Read rejection reaches TypeScript', true);

		for (const [index, sourceFile] of sourceFiles.entries()) {
			check(
				`Production resource unchanged: ${path.basename(sourceFile)}`,
				(await fs.readFile(sourceFile)).equals(sourceBytes[index])
			);
		}
	} finally {
		for (const fileName of ownedFiles) {
			await fs.unlink(path.join(testDirectory, fileName)).catch(error => {
				if (error.code !== 'ENOENT') {
					throw error;
				}
			});
		}

		await fs.rmdir(testDirectory);
		console.log('[editing-bridge] Temporary files and folder removed: true');
	}

	console.log('[editing-bridge] Checks passed: true');
}

main().catch(error => {
	console.error('[editing-bridge]', error);
	console.log('[editing-bridge] Checks passed: false');
	process.exitCode = 1;
});
