const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');

const {
	setInteractionRequirements
} = require('../out/bridges/condition_assignment_bridge.js');

const ACTION_PATH =
	'res://Framework/Content/Behavior/Action/change_health.tres';

const FIRST_GROUP_PATH =
	'res://Framework/Content/Behavior/Condition/can_strike.tres';

function check(label, condition) {
	assert.ok(condition, label);
	console.log('[requirements-bridge] ' + label + ': true');
}

function checkSavedFields(text, label) {
	check(
		label,
		text.includes('id = &"requirements_bridge_check"')
		&& text.includes('path="' + ACTION_PATH + '"')
		&& /^action = ExtResource\("[^"]+"\)$/m.test(text)
		&& /arguments = \{\s*&"amount":\s*-10\s*\}/m.test(text)
	);
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

	const productionPaths = [
		ACTION_PATH,
		FIRST_GROUP_PATH,
		'res://Framework/Content/Behavior/Condition/actor_strength.tres',
		'res://Framework/Content/Behavior/Interaction/strike.tres'
	];

	const productionFiles = productionPaths.map(resourcePath => ({
		resourcePath,
		file: path.join(projectDirectory, resourcePath.slice(6))
	}));

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
		path.join(diagnosticsDirectory, 'requirements_bridge_')
	);

	const resourceDirectory =
		'res://.godot/diagnostics/' + path.basename(testDirectory);

	const interactionPath = resourceDirectory + '/interaction.tres';
	const replacementPath = resourceDirectory + '/replacement_group.tres';

	const interactionFile = path.join(testDirectory, 'interaction.tres');
	const replacementFile = path.join(testDirectory, 'replacement_group.tres');

	const interactionText = [
		'[gd_resource type="Resource" format=3]',
		'',
		'[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd" id="1_interaction"]',
		'[ext_resource type="Resource" path="' + ACTION_PATH + '" id="2_action"]',
		'',
		'[resource]',
		'script = ExtResource("1_interaction")',
		'id = &"requirements_bridge_check"',
		'action = ExtResource("2_action")',
		'arguments = {',
		'\t&"amount": -10',
		'}',
		''
	].join('\r\n');

	const replacementText = [
		'[gd_resource type="Resource" format=3]',
		'',
		'[ext_resource type="Script" path="res://Framework/Infrastructure/API/Gameplay/Resources/condition_group_resource.gd" id="1_group"]',
		'',
		'[resource]',
		'script = ExtResource("1_group")',
		'id = &"bridge_replacement_requirements"',
		''
	].join('\r\n');

	const report = message => {
		console.log('[requirements-bridge] Godot diagnostics:\n' + message);
	};

	try {
		await fs.writeFile(interactionFile, interactionText, {
			encoding: 'utf8',
			flag: 'wx'
		});

		await fs.writeFile(replacementFile, replacementText, {
			encoding: 'utf8',
			flag: 'wx'
		});

		const replacementBefore = await fs.readFile(replacementFile);

		const initialResult = await setInteractionRequirements(
			projectDirectory,
			godotExecutable,
			interactionPath,
			FIRST_GROUP_PATH,
			report
		);

		assert.deepEqual(initialResult, {
			interaction_path: interactionPath,
			group_path: FIRST_GROUP_PATH
		});

		console.log(
			'[requirements-bridge] Initial assignment result is correct: true'
		);

		const initiallySaved = await fs.readFile(interactionFile, 'utf8');

		check(
			'Initial group reference is saved',
			initiallySaved.includes('path="' + FIRST_GROUP_PATH + '"')
			&& /^requirements = ExtResource\("[^"]+"\)$/m.test(initiallySaved)
		);

		checkSavedFields(
			initiallySaved,
			'Initial assignment preserves ID, action and amount'
		);

		const replacementResult = await setInteractionRequirements(
			projectDirectory,
			godotExecutable,
			interactionPath,
			replacementPath,
			report
		);

		assert.deepEqual(replacementResult, {
			interaction_path: interactionPath,
			group_path: replacementPath
		});

		console.log(
			'[requirements-bridge] Replacement result is correct: true'
		);

		const replacedBytes = await fs.readFile(interactionFile);
		const replacedText = replacedBytes.toString('utf8');

		check(
			'Replacement replaces the previous group reference',
			replacedText.includes('path="' + replacementPath + '"')
			&& !replacedText.includes(FIRST_GROUP_PATH)
			&& /^requirements = ExtResource\("[^"]+"\)$/m.test(replacedText)
		);

		checkSavedFields(
			replacedText,
			'Replacement preserves ID, action and amount'
		);

		await assert.rejects(
			() => setInteractionRequirements(
				projectDirectory,
				godotExecutable,
				interactionPath,
				replacementPath,
				report
			),
			{
				message: (
					"Condition group 'bridge_replacement_requirements' "
					+ "is already assigned to interaction "
					+ "'requirements_bridge_check'."
				)
			}
		);

		console.log(
			'[requirements-bridge] Duplicate error reaches TypeScript: true'
		);

		check(
			'Duplicate rejection preserves saved bytes',
			(await fs.readFile(interactionFile)).equals(replacedBytes)
		);

		check(
			'Assigned replacement group remains unchanged',
			(await fs.readFile(replacementFile)).equals(replacementBefore)
		);

		for (const [index, source] of productionFiles.entries()) {
			check(
				'Production resource unchanged: ' + source.resourcePath,
				(await fs.readFile(source.file)).equals(productionBefore[index])
			);
		}
	} finally {
		for (const file of [interactionFile, replacementFile]) {
			try {
				await fs.unlink(file);
			} catch (error) {
				if (error.code !== 'ENOENT') {
					throw error;
				}
			}
		}

		await fs.rmdir(testDirectory);

		console.log(
			'[requirements-bridge] Temporary files and folder removed: true'
		);
	}

	console.log('[requirements-bridge] Checks passed: true');
}

main().catch(error => {
	console.error('[requirements-bridge]', error);
	console.log('[requirements-bridge] Checks passed: false');
	process.exitCode = 1;
});
