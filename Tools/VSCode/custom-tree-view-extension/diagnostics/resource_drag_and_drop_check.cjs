const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { URL, pathToFileURL } = require('node:url');

const calls = [];
const errors = [];
const logs = [];

function makeUri(value) {
	const url = new URL(value);

	return {
		scheme: url.protocol.slice(0, -1),
		path: decodeURIComponent(url.pathname),
		toString() {
			return url.href;
		},
		with({ query, fragment }) {
			const copy = new URL(url.href);

			if (query !== undefined) {
				copy.search = query;
			}

			if (fragment !== undefined) {
				copy.hash = fragment;
			}

			return makeUri(copy.href);
		}
	};
}

class DataTransferItem {
	constructor(value) {
		this.value = value;
	}

	async asString() {
		return String(this.value);
	}
}

const testApi = {
	Uri: {
		parse: value => makeUri(value)
	},
	DataTransferItem,
	window: {
		async showErrorMessage(message) {
			errors.push(message);
		}
	}
};

const compiledPath = path.resolve(
	__dirname,
	'../out/resource_drag_and_drop.js'
);

const loaded = { exports: {} };

vm.runInNewContext(
	fs.readFileSync(compiledPath, 'utf8'),
	{
		module: loaded,
		exports: loaded.exports,
		Error,
		require(name) {
			assert.equal(name, 'vscode');
			return testApi;
		}
	},
	{ filename: compiledPath }
);

const {
	ResourceDragAndDropController
} = loaded.exports;

const projectDirectory = path.resolve(
	__dirname,
	'../../../../framework-project'
);

const groupPath = 'res://Framework/Content/Condition/can_strike.tres';
const conditionPath = 'res://Framework/Content/Condition/actor_strength.tres';

function uriFor(resourcePath) {
	const filePath = path.join(
		projectDirectory,
		resourcePath.slice('res://'.length)
	);

	return makeUri(pathToFileURL(filePath).href);
}

function treeElement(sourcePath) {
	return {
		sourcePath,
		route: [sourcePath],
		ancestry: [sourcePath],
		cycle: false
	};
}

const groupUri = uriFor(groupPath);
const conditionUri = uriFor(conditionPath);

const items = new Map([
	[
		groupPath,
		{
			contextValue: 'condition_group',
			resourceUri: groupUri
		}
	],
	[
		conditionPath,
		{
			contextValue: 'condition',
			resourceUri: conditionUri
		}
	]
]);

const provider = {
	getTreeItem(element) {
		return items.get(element.sourcePath) ?? {};
	}
};

const controller = new ResourceDragAndDropController(
	provider,
	async files => {
		calls.push(files);
	},
	{
		appendLine(message) {
			logs.push(message);
		}
	}
);

const group = treeElement(groupPath);
const condition = treeElement(conditionPath);

const interactionPath =
	'res://Framework/Content/Interaction/strike.tres';

const interactionUri = uriFor(interactionPath);
const interaction = treeElement(interactionPath);

items.set(interactionPath, {
	contextValue: 'interaction',
	resourceUri: interactionUri
});

const actionPath =
	'res://Framework/Content/Action/change_health.tres';

const actionUri = uriFor(actionPath);
const action = treeElement(actionPath);

items.set(actionPath, {
	contextValue: 'action',
	resourceUri: actionUri
});

const activeToken = { isCancellationRequested: false };

function transferFor(...entries) {
	return new Map([
		[
			'text/uri-list',
			new DataTransferItem(entries.map(String).join('\r\n'))
		]
	]);
}

function check(label, passed) {
	assert.ok(passed, label);
	console.log(`[drop-check] ${label}: true`);
}

async function expectRejected(label, target, transfer, message) {
	const callsBefore = calls.length;
	const errorsBefore = errors.length;

	await controller.handleDrop(target, transfer, activeToken);

	check(label, (
		calls.length === callsBefore
		&& errors.length === errorsBefore + 1
		&& errors.at(-1) === message
		&& logs.at(-1) === `[drop] Error: ${message}`
	));
}

async function main() {
	const externalTransfer = transferFor(
		'# Diagnostic URI list',
		conditionUri.toString() + '?preview=1#L3,5',
		''
	);

	await controller.handleDrop(group, externalTransfer, activeToken);

	check('External drop routes the correct files', (
		calls.length === 1
		&& calls[0].group.toString() === groupUri.toString()
		&& calls[0].condition.toString() === conditionUri.toString()
		&& errors.length === 0
	));

	const internalTransfer = new Map();

	controller.handleDrag(
		[condition],
		internalTransfer,
		activeToken
	);

	check('Tree drag supplies the condition URI', (
		await internalTransfer.get('text/uri-list')?.asString()
	) === conditionUri.toString());

	await controller.handleDrop(group, internalTransfer, activeToken);

	check('Tree drag and drop reaches assignment', (
		calls.length === 2
		&& calls[1].group.toString() === groupUri.toString()
		&& calls[1].condition.toString() === conditionUri.toString()
	));

	const groupDrag = new Map();

	controller.handleDrag([group], groupDrag, activeToken);

	check('Tree drag supplies the group URI', (
		await groupDrag.get('text/uri-list')?.asString()
	) === groupUri.toString());

	const callsBeforeRequirements = calls.length;

	await controller.handleDrop(
		interaction,
		groupDrag,
		activeToken
	);

	check('Tree group drop supplies neutral resource files', (
		calls.length === callsBeforeRequirements + 1
		&& calls.at(-1)?.interaction?.toString()
			=== interactionUri.toString()
		&& calls.at(-1)?.resource?.toString()
			=== groupUri.toString()
		&& errors.length === 0
	));

	await controller.handleDrop(
		interaction,
		transferFor(groupUri),
		activeToken
	);

	check('External group drop supplies neutral resource files', (
		calls.length === callsBeforeRequirements + 2
		&& calls.at(-1)?.interaction?.toString()
			=== interactionUri.toString()
		&& calls.at(-1)?.resource?.toString()
			=== groupUri.toString()
		&& errors.length === 0
	));

	const actionDrag = new Map();

	controller.handleDrag(
		[action],
		actionDrag,
		activeToken
	);

	check('Tree drag supplies the action URI', (
		await actionDrag.get('text/uri-list')?.asString()
	) === actionUri.toString());

	const callsBeforeActions = calls.length;

	await controller.handleDrop(
		interaction,
		actionDrag,
		activeToken
	);

	check('Tree action drop supplies neutral resource files', (
		calls.length === callsBeforeActions + 1
		&& calls.at(-1)?.interaction?.toString()
			=== interactionUri.toString()
		&& calls.at(-1)?.resource?.toString()
			=== actionUri.toString()
		&& errors.length === 0
	));

	await controller.handleDrop(
		interaction,
		transferFor(actionUri.toString() + '?preview=1#L2'),
		activeToken
	);

	check('External action drop supplies neutral resource files', (
		calls.length === callsBeforeActions + 2
		&& calls.at(-1)?.interaction?.toString()
			=== interactionUri.toString()
		&& calls.at(-1)?.resource?.toString()
			=== actionUri.toString()
		&& errors.length === 0
	));

	const interactionDrag = new Map();

	controller.handleDrag(
		[interaction],
		interactionDrag,
		activeToken
	);

	check(
		'Interaction drag does not supply an assignment URI',
		!interactionDrag.has('text/uri-list')
	);

	await expectRejected(
		'Drop onto empty tree space is rejected',
		undefined,
		transferFor(conditionUri),
		'Drop onto a condition group or interaction.'
	);

	await expectRejected(
		'Drop onto a condition is rejected',
		condition,
		transferFor(conditionUri),
		'Drop onto a condition group or interaction.'
	);

	await expectRejected(
		'Drop onto a cycle marker is rejected',
		{ ...group, cycle: true },
		transferFor(conditionUri),
		'Drop onto a condition group or interaction.'
	);

	await expectRejected(
		'Missing file data is rejected',
		group,
		new Map(),
		'The drop does not contain a resource file.'
	);

	await expectRejected(
		'Multiple files are rejected together',
		group,
		transferFor(conditionUri, groupUri),
		'Drag exactly one .tres resource at a time.'
	);

	await expectRejected(
		'Non-resource file is rejected',
		group,
		transferFor(uriFor(
			'res://Framework/Env/Authoring/condition_assignment.gd'
		)),
		'Drop a local .tres resource file.'
	);

	await expectRejected(
		'Non-local URI is rejected',
		group,
		transferFor('https://example.invalid/actor_strength.tres'),
		'Drop a local .tres resource file.'
	);

	const callsBeforeCancellation = calls.length;
	const errorsBeforeCancellation = errors.length;

	await controller.handleDrop(
		group,
		transferFor(conditionUri),
		{ isCancellationRequested: true }
	);

	check('Already cancelled drop is ignored', (
		calls.length === callsBeforeCancellation
		&& errors.length === errorsBeforeCancellation
	));

	const lateToken = { isCancellationRequested: false };

	const lateTransfer = new Map([
		[
			'text/uri-list',
			{
				async asString() {
					lateToken.isCancellationRequested = true;
					return conditionUri.toString();
				}
			}
		]
	]);

	await controller.handleDrop(group, lateTransfer, lateToken);

	check('Cancellation while reading prevents assignment', (
		calls.length === callsBeforeCancellation
		&& errors.length === errorsBeforeCancellation
	));

	console.log('[drop-check] Checks passed: true');
}

main().catch(error => {
	console.error('[drop-check]', error);
	console.log('[drop-check] Checks passed: false');
	process.exitCode = 1;
});
