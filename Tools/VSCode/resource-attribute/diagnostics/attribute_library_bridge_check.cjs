const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { LibraryService } = require('../out/library/library_service.js');
const { AUTHORED_ROOT } = require('../out/bridges/attribute_library_bridge.js');
const { checkedAuthoredPath, nameError } = require('../out/library/library_paths.js');
const { inspectAttributes } = require('../out/bridges/attribute_bridge.js');

const check = label => console.log(`[library-bridge] ${label}: true`);
async function main() {
	const [projectArg, executable] = process.argv.slice(2);
	assert.ok(projectArg && executable, 'Expected <Godot project> <Godot executable>.');
	const project = path.resolve(projectArg);
	const context = { projectDirectory: project, workspaceDirectory: path.dirname(project) };
	const report = message => { if (/^(SCRIPT ERROR|ERROR|WARNING):/m.test(message)) { throw new Error(message); } };
	const service = new LibraryService(context, executable, report);
	const before = await service.catalogue();
	const production = new Map();
	for (const entry of before.entries.filter(entry => entry.kind === 'resource')) {
		production.set(entry.source_path, await fs.readFile(path.join(project, entry.source_path.slice(6))));
	}
	const name = 'DiagnosticLibrary_' + randomBytes(8).toString('hex');
	const sourceRoot = AUTHORED_ROOT + '/' + name;
	const ownedRoot = path.join(project, sourceRoot.slice(6));
	const get = async source => {
		const entry = (await service.catalogue()).entries.find(entry => entry.source_path === source);
		assert.ok(entry, source); return entry;
	};
	let created = false;
	try {
		assert.equal(await service.createCategory(before.entries[0], name), sourceRoot); created = true;
		const folder = await get(sourceRoot);
		assert.equal(folder.kind, 'folder');
		check('An empty top-level category is created and discovered');
		await assert.rejects(service.createCategory(await get(AUTHORED_ROOT), name.toUpperCase()), /already exists/);
		await assert.rejects(service.createCategory(folder, '../escape'), /leading dot|Names cannot/);
		assert.ok(nameError('CON.tres')); assert.ok(nameError('COM¹')); assert.ok(nameError('bad.'));
		check('Duplicate sibling names and invalid Windows names are rejected');
		await service.createCategory(folder, 'Statistics');
		await assert.rejects(service.createCategory(folder, 'Stale'), /changed/);
		check('A stale parent directory snapshot cannot create entries');
		const nestedSource = sourceRoot + '/Statistics';
		const nested = await get(nestedSource);
		const resourceSource = await service.createResource(nested, 'durability.tres', 'durability');
		const resourceFile = path.join(project, resourceSource.slice(6));
		const bytes = await fs.readFile(resourceFile);
		assert.match(bytes.toString(), /^\[gd_resource.*uid="uid:\/\/[a-z0-9]+"/);
		assert.ok(!/(?<!\r)\n/.test(bytes.toString()));
		assert.ok(!/^ +\S/m.test(bytes.toString()));
		const graph = await inspectAttributes(project, executable, resourceSource, report);
		assert.equal(graph.root.children[0].path[0].kind, 'StringName');
		assert.equal(graph.root.children[0].path[0].text, 'durability');
		assert.equal(graph.root.children[0].children.length, 0);
		check('A new typed container file has a UID, tabs, CRLF, and an editable native tree');
		await assert.rejects(service.createResource(await get(nestedSource), 'DURABILITY.tres', 'other'), /already exists/);
		assert.deepEqual(await fs.readFile(resourceFile), bytes);
		check('Duplicate creation cannot overwrite an existing resource');
		const runtimeOutput = execFileSync(executable, ['--headless', '--path', project, '--script',
			'res://Diagnostics/Content/authored_library_check.gd', '--', resourceSource], { encoding: 'utf8', windowsHide: true, timeout: 30000 });
		assert.match(runtimeOutput, /New category fragment composes through starting attributes: true/);
		assert.match(runtimeOutput, /Checks passed: true/);
		check('New categories work through runtime starting-attribute composition');
		const consumerFile = path.join(ownedRoot, 'consumer.tscn');
		const consumerText = `[gd_scene format=3]\n[ext_resource type="Resource" path="${resourceSource}" id="1"]\n[node name="Consumer" type="Node"]\nmetadata/fragment = ExtResource("1")\n`;
		await fs.writeFile(consumerFile, consumerText, { flag: 'wx' });
		let entry = await get(resourceSource);
		let preview = await service.previewDeletion(entry);
		assert.ok(preview.consumers.some(consumer => consumer.source_path === sourceRoot + '/consumer.tscn'));
		let trashed = 0;
		const trash = async file => { trashed++; await fs.unlink(file); };
		await assert.rejects(service.deleteResource(entry, preview, trash), /still referenced/);
		assert.equal(trashed, 0); assert.deepEqual(await fs.readFile(resourceFile), bytes);
		check('Scene dependencies block deletion and identify the consumer');
		await fs.unlink(consumerFile);
		const script = path.join(ownedRoot, 'consumer.gd');
		await fs.writeFile(script, `extends RefCounted\nconst SOURCE = "${resourceSource}"\n`, { flag: 'wx' });
		preview = await service.previewDeletion(await get(resourceSource));
		assert.ok(preview.consumers.some(consumer => consumer.source_path.endsWith('/consumer.gd')));
		check('Literal Godot script references also block deletion');
		await fs.writeFile(script, 'extends RefCounted\nconst SOURCE = "Statistics/durability.tres"\n');
		preview = await service.previewDeletion(await get(resourceSource));
		assert.ok(preview.consumers.some(consumer => consumer.source_path.endsWith('/consumer.gd')));
		check('Relative literal script references block deletion');
		await fs.unlink(script);
		const uid = bytes.toString().match(/uid="([^"]+)"/)[1];
		await fs.writeFile(consumerFile, consumerText.replace('type="Resource" path=', `type="Resource" uid="${uid}" path=`));
		preview = await service.previewDeletion(entry);
		assert.ok(preview.consumers.some(consumer => consumer.source_path.endsWith('/consumer.tscn')));
		check('UID-bearing resource dependencies are detected');
		await fs.unlink(consumerFile);
		preview = await service.previewDeletion(entry);
		assert.equal(preview.consumers.length, 0);
		await fs.writeFile(consumerFile, consumerText, { flag: 'wx' });
		await assert.rejects(service.deleteResource(entry, preview, trash), /directories changed/);
		assert.equal(trashed, 0); await fs.unlink(consumerFile);
		check('A consumer added after inspection prevents stale deletion');
		await fs.writeFile(consumerFile, '[gd_scene format=3]\n[node name="Unlinked" type="Node"]\n');
		preview = await service.previewDeletion(entry);
		await fs.writeFile(consumerFile, consumerText);
		await assert.rejects(service.deleteResource(entry, preview, trash), /references changed/);
		assert.equal(trashed, 0); await fs.unlink(consumerFile);
		check('References added to an existing scene invalidate its checked hash');
		await fs.appendFile(resourceFile, '\n# changed by another author\n');
		await assert.rejects(service.previewDeletion(entry), /changed/);
		await fs.writeFile(resourceFile, bytes);
		check('Changed resource bytes reject deletion');
		const guarded = new LibraryService(context, executable, report, async deleting => { if (deleting) { throw new Error('dirty editor'); } });
		await assert.rejects(guarded.previewDeletion(entry), /dirty editor/);
		check('Deletion readiness guards run before dependency inspection');
		await assert.rejects(service.deleteEmptyCategory(await get(nestedSource), trash), /empty category/);
		await assert.rejects(service.deleteEmptyCategory(await get(AUTHORED_ROOT), trash), /root cannot/);
		check('Nonempty categories and the authored root are protected');
		await assert.rejects(checkedAuthoredPath(context, AUTHORED_ROOT + 'Extra', 'directory'), /inside/);
		await assert.rejects(checkedAuthoredPath(context, AUTHORED_ROOT + '/../Behavior', 'directory'), /Invalid/);
		check('Sibling prefixes and traversal cannot escape the authored library');
		const linked = path.join(ownedRoot, 'Linked');
		await fs.symlink(path.join(project, 'Diagnostics'), linked, process.platform === 'win32' ? 'junction' : 'dir');
		try {
			assert.equal((await get(sourceRoot + '/Linked')).kind, 'blocked');
			await assert.rejects(checkedAuthoredPath(context, sourceRoot + '/Linked', 'directory'), /links|junctions/);
			check('Linked categories are read-only and cannot escape the library');
		} finally { await fs.unlink(linked); }
		preview = await service.previewDeletion(entry);
		await service.deleteResource(entry, preview, trash);
		assert.equal(trashed, 1); await assert.rejects(fs.access(resourceFile));
		check('An unreferenced unchanged resource reaches the deletion callback');
		await service.deleteEmptyCategory(await get(nestedSource), async folder => { await fs.rmdir(folder); });
		const hidden = path.join(ownedRoot, '.not_empty');
		await fs.writeFile(hidden, 'synthetic hidden content');
		await assert.rejects(service.deleteEmptyCategory(await get(sourceRoot), trash), /empty category/);
		await fs.unlink(hidden);
		check('Hidden files also prevent empty-category deletion');
		await service.deleteEmptyCategory(await get(sourceRoot), async folder => { await fs.rmdir(folder); }); created = false;
		check('Empty subcategories and categories can be deleted');
		for (const [source, original] of production) { assert.deepEqual(await fs.readFile(path.join(project, source.slice(6))), original); }
		check('All existing authored resource bytes remain unchanged');
	} finally {
		if (created) {
			const root = await fs.realpath(ownedRoot);
			assert.equal(root, ownedRoot);
			assert.ok(path.basename(root).startsWith('DiagnosticLibrary_'));
			assert.equal(path.dirname(root), path.join(project, AUTHORED_ROOT.slice(6)));
			async function cleanup(directory) {
				assert.ok(directory === root || directory.startsWith(root + path.sep));
				assert.equal(await fs.realpath(directory), directory);
				for (const name of await fs.readdir(directory)) {
					const full = path.join(directory, name); const info = await fs.lstat(full);
					if (info.isDirectory() && !info.isSymbolicLink()) { await cleanup(full); } else { await fs.unlink(full); }
				}
				await fs.rmdir(directory);
			}
			await cleanup(root);
		}
		check('Temporary library fixtures are cleaned');
	}
	console.log('[library-bridge] Checks passed: true');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
