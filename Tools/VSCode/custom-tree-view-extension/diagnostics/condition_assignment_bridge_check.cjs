const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');

const {
	addConditionToGroup
} = require('../out/condition_assignment_bridge.js');

const CONDITION_PATH =
	'res://Framework/Content/Condition/actor_strength.tres';

function check(label, condition) {
	assert.ok(condition, label);
	console.log(`[assignment-bridge] ${label}: true`);
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

	const productionFiles = [
		{
			label: 'Production condition unchanged',
			file: path.join(
				projectDirectory,
				'Framework/Content/Condition/actor_strength.tres'
			)
		},
		{
			label: 'Production group unchanged',
			file: path.join(
				projectDirectory,
				'Framework/Content/Condition/can_strike.tres'
			)
		}
	];

	const productionBefore = await Promise.all(
		productionFiles.map(source => fs.readFile(source.file))
	);

	const diagnosticsDirectory = path.join(
		projectDirectory,
		'.godot',
		'diagnostics'
	);

	await fs.mkdir(diagnosticsDirectory, { recursive: true });

	const testDirectory = await fs.mkdtemp(
		path.join(diagnosticsDirectory, 'condition_assignment_bridge_')
	);

	const groupFile = path.join(testDirectory, 'group.tres');

	const groupPath =
		`res://.godot/diagnostics/${path.basename(testDirectory)}/group.tres`;

	const groupText = `[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/condition_group_resource.gd" id="1_group"]

[resource]
script = ExtResource("1_group")
id = &"bridge_assignment_check"
`;

	let groupCreated = false;

	const report = message => {
		console.log(`[assignment-bridge] Godot diagnostics:\n${message}`);
	};

	try {
		await fs.writeFile(groupFile, groupText, {
			encoding: 'utf8',
			flag: 'wx'
		});

		groupCreated = true;

		const result = await addConditionToGroup(
			projectDirectory,
			godotExecutable,
			groupPath,
			CONDITION_PATH,
			report
		);

		assert.deepEqual(result, {
			group_path: groupPath,
			condition_path: CONDITION_PATH,
			condition_count: 1
		});

		console.log('[assignment-bridge] Correct assignment result: true');

		const savedBytes = await fs.readFile(groupFile);
		const savedText = savedBytes.toString('utf8');

		check(
			'Saved file references the condition',
			savedText.includes(CONDITION_PATH)
			&& savedText.includes('conditions = ')
		);

		await assert.rejects(
			() => addConditionToGroup(
				projectDirectory,
				godotExecutable,
				groupPath,
				CONDITION_PATH,
				report
			),
			{
				message: (
					"Condition 'actor_strength' is already assigned "
					+ "to group 'bridge_assignment_check'."
				)
			}
		);

		console.log(
			'[assignment-bridge] Duplicate error reaches TypeScript: true'
		);

		const afterRejection = await fs.readFile(groupFile);

		check(
			'Rejected assignment preserves saved bytes',
			afterRejection.equals(savedBytes)
		);

		for (const [index, source] of productionFiles.entries()) {
			const currentBytes = await fs.readFile(source.file);

			check(
				source.label,
				currentBytes.equals(productionBefore[index])
			);
		}
	} finally {
		if (groupCreated) {
			await fs.unlink(groupFile);
			console.log('[assignment-bridge] Temporary group removed: true');
		}

		await fs.rmdir(testDirectory);
		console.log('[assignment-bridge] Temporary folder removed: true');
	}

	console.log('[assignment-bridge] Checks passed: true');
}

main().catch(error => {
	console.error('[assignment-bridge]', error);
	console.log('[assignment-bridge] Checks passed: false');
	process.exitCode = 1;
});
