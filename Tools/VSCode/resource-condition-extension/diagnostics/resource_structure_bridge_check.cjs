const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {randomBytes,createHash} = require('node:crypto');
const {execFileSync} = require('node:child_process');
const {LibraryService} = require('../out/library/library_service.js');
const {loadResourceGraph} = require('../out/bridges/resource_bridge.js');
const {editBehavior} = require('../out/bridges/behavior_editing_bridge.js');
const project = path.resolve(process.argv[2] ?? '');
const executable = process.argv[3];
const renameOnly = process.argv[4] === 'rename-only';
const root = 'res://Framework/Content/Gameplay/Profiles/Movement/Behavior';
const name = 'DiagnosticStructure_' + randomBytes(8).toString('hex');
const folder = root + '/' + name;
const local = source => path.join(project,source.slice(6));
const resource = file => folder+'/'+file;
const report = message => {if(/^(SCRIPT ERROR|ERROR):/m.test(message))throw Error(message);};
const service = new LibraryService({projectDirectory:project,workspaceDirectory:path.dirname(project)},executable,report);
const check = label => console.log(`[resource-structure-bridge] ${label}: true`);
const write = (file,text) => fs.writeFile(local(resource(file)),text.replace(/\r?\n/g,'\r\n'));
const schemaFolders = {action: "Actions", automation: "Automation", behavior: "Behavior", condition: "Conditions", condition_group: "Conditions", interaction: "Interactions"};
const schema = kind => {
	if (!Object.hasOwn(schemaFolders, kind)) { throw new Error("Unknown fixture schema: " + kind); }
	return `res://Framework/Infrastructure/API/Gameplay/Resources/${schemaFolders[kind]}/${kind}_resource.gd`;
};
const ownedFiles = new Set(['action.tres','other.tres','condition.tres','other_condition.tres','group.tres','interaction.tres','automation.tres','consumer.gd','config.godot','consumer.tscn','binary_probe.gd','binary.res','uid_only.gd','renamed.tres']);
async function main(){
	assert.ok(executable && project);
	const initial = await service.catalogue();
	const production = new Map(await Promise.all(initial.entries.filter(entry=>entry.kind==='resource').map(async entry=>[entry.source_path,await fs.readFile(local(entry.source_path))])));
	let created=false;
	try{
		await service.createCategory(initial.entries.find(entry=>entry.source_path===root),name);created=true;
		const catalog=await service.catalogue();
		const parent=catalog.entries.find(entry=>entry.source_path===folder);
		const action=await service.createResource(parent,'action.tres',{resource_kind:'action',id:name+'_action',behavior_id:'attribute_effects'},catalog);
		const uid=(await fs.readFile(local(action),'utf8')).match(/uid="([^"]+)"/)[1];
		await write('other.tres',`[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="${schema('action')}" id="schema"]\n[resource]\nscript = ExtResource("schema")\nid = &"${name}_other"\nbehavior_id = &"attribute_effects"\n`);
		for(const file of ['condition','other_condition'])await write(file+'.tres',`[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="${schema('condition')}" id="schema"]\n[resource]\nscript = ExtResource("schema")\nid = &"${name}_${file}"\nrequirement = {"entity": &"actor", "container": &"strength", "path": ["current"], "operator": ">=", "value": 20}\n`);
		await write('group.tres',`[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="${schema('condition_group')}" id="schema"]\n[resource]\nscript = ExtResource("schema")\nid = &"${name}_group"\n`);
		await write('interaction.tres',`[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="${schema('interaction')}" id="schema"]\n[ext_resource type="Resource" path="${action}" uid="${uid}" id="action"]\n[resource]\nscript = ExtResource("schema")\nid = &"${name}_interaction"\naction = ExtResource("action")\narguments = {&"amount": -7}\n`);
		await write('automation.tres',`[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="${schema('automation')}" id="schema"]\n[ext_resource type="Resource" path="${resource('interaction.tres')}" id="interaction"]\n[resource]\nscript = ExtResource("schema")\nid = &"${name}_automation"\ninteraction = ExtResource("interaction")\n`);
		if(!renameOnly){
		const edit=async(source,request)=>{const graph=await loadResourceGraph(project,executable,report,source);return editBehavior(project,executable,source,{expected_hashes:graph.dependency_hashes,catalog_paths:graph.catalog_paths,catalog_seed:source,executor_snapshot:graph.executor_snapshot,...request},report);};
		await edit(resource('group.tres'),{operation:'set_reference',role:'condition',target_path:resource('condition.tres')});
		await edit(resource('group.tres'),{operation:'set_reference',role:'condition',target_path:resource('other_condition.tres'),condition_index:0,condition_path:resource('condition.tres')});
		const groupBytes=await fs.readFile(local(resource('group.tres')));
		await assert.rejects(edit(resource('group.tres'),{operation:'set_reference',role:'condition',target_path:resource('other_condition.tres')}),/already assigned/);
		assert.deepEqual(await fs.readFile(local(resource('group.tres'))),groupBytes);
		await edit(resource('interaction.tres'),{operation:'set_reference',role:'requirements',target_path:resource('group.tres')});
		await edit(resource('interaction.tres'),{operation:'set_reference',role:'action',target_path:resource('other.tres')});
		await edit(resource('interaction.tres'),{operation:'set_reference',role:'action',target_path:action});
		await assert.rejects(edit(resource('automation.tres'),{operation:'set_reference',role:'interaction',target_path:resource('condition.tres')}),/incompatible/);
		check('Typed relationship assignment, condition replacement and duplicate/type rejection');
		await edit(resource('interaction.tres'),{operation:'clear_requirements'});
		assert.deepEqual(await fs.readFile(local(resource('group.tres'))),groupBytes);
		await assert.rejects(edit(resource('interaction.tres'),{operation:'clear_action'}),/Unsupported/);
		check('Optional unlink preserves referenced files and required references cannot be cleared');
		}
		await write('consumer.gd',`extends RefCounted\nconst Saved = preload("${action}")\nconst Relative = preload("action.tres")\nconst FilenameLabel = "action.tres"\n# Leave this comment alone: ${action}\n`);
		await write('config.godot',`[behavior]\nresource="${action}"\n`);
		await write('consumer.tscn',`[gd_scene format=3]\n[ext_resource type="Resource" path="${action}" uid="${uid}" id="behavior"]\n[node name="Consumer" type="Node"]\nmetadata/behavior = ExtResource("behavior")\n`);
		const entry=async()=> (await service.catalogue()).entries.find(entry=>entry.source_path===action);
		await assert.rejects(service.previewRename(await entry(),'../escape.tres'),/valid/);
		await assert.rejects(service.previewRename(await entry(),'other.tres'),/already exists/);
		let preview=await service.previewRename(await entry(),'renamed.tres');
		await fs.appendFile(local(resource('consumer.gd')),'# newer inspection required\r\n');
		await assert.rejects(service.renameResource(await entry(),preview),/changed/);
		assert.ok(await fs.stat(local(action)));
		check('Traversal, sibling collisions and stale project snapshots reject renames');
		await write('uid_only.gd',`extends RefCounted\nconst SavedPath = "${uid}"\n`);
		await assert.rejects(service.previewRename(await entry(),'renamed.tres'),/UID-only/);
		await fs.unlink(local(resource('uid_only.gd')));
		await write('binary_probe.gd',`extends SceneTree\nfunc _initialize() -> void:\n\tvar wrapper := Resource.new()\n\twrapper.set_meta("behavior", load("${action}"))\n\tvar error := ResourceSaver.save(wrapper, "${resource('binary.res')}")\n\tquit(0 if error == OK else 1)\n`);
		execFileSync(executable,['--headless','--path',project,'--script',resource('binary_probe.gd')],{encoding:'utf8',windowsHide:true,timeout:30000});
		await assert.rejects(service.previewRename(await entry(),'renamed.tres'),/binary consumer/);
		await fs.unlink(local(resource('binary.res')));await fs.unlink(local(resource('binary_probe.gd')));
		check('Unsupported UID-only and binary consumers are rejected before any write');
		const validCode=await fs.readFile(local(resource('consumer.gd')));
		await fs.appendFile(local(resource('consumer.gd')),'this is invalid syntax\r\n');
		const invalidCode=await fs.readFile(local(resource('consumer.gd')));
		const selectedFailure=await entry();const failedPreview=await service.previewRename(selectedFailure,'renamed.tres');
		await assert.rejects(service.renameResource(selectedFailure,failedPreview),/failed verification|Parse Error|parse error/i);
		assert.ok(await fs.stat(local(action)));await assert.rejects(fs.stat(local(resource('renamed.tres'))),{code:'ENOENT'});
		assert.deepEqual(await fs.readFile(local(resource('consumer.gd'))),invalidCode);
		assert.ok((await fs.readFile(local(resource('interaction.tres')),'utf8')).includes(action));
		await fs.writeFile(local(resource('consumer.gd')),validCode);
		check('Failed consumer verification rolls back file locations and all owned reference updates');
		const selected=await entry();preview=await service.previewRename(selected,'renamed.tres');
		assert.ok(preview.changes.length>=4);
		const destination=await service.renameResource(selected,preview);
		await assert.rejects(fs.stat(local(action)),{code:'ENOENT'});
		assert.ok((await fs.readFile(local(destination),'utf8')).includes(`uid="${uid}"`));
		const graph=await loadResourceGraph(project,executable,report,resource('interaction.tres'));
		assert.equal(graph.nodes[destination].id,name+'_action');
		assert.equal(graph.nodes[resource('interaction.tres')].links[0].target,destination);
		const code=await fs.readFile(local(resource('consumer.gd')),'utf8');
		assert.equal(code.split(`preload("${destination}")`).length-1,2);
		assert.ok(code.includes('# Leave this comment alone: '+action));
		assert.ok(code.includes('const FilenameLabel = "action.tres"'));
		for(const file of ['config.godot','consumer.tscn'])assert.ok((await fs.readFile(local(resource(file)),'utf8')).includes(destination));
		check('Rename preserves UID/authored ID and updates resource, scene, script and relative/configuration references');
		const renamedEntry=(await service.catalogue()).entries.find(entry=>entry.source_path===destination);
		const deletion=await service.previewDeletion(renamedEntry);
		assert.ok(deletion.consumers.some(entry=>entry.source_path===resource('consumer.tscn')));
		let deleted=false;await assert.rejects(service.deleteResource(renamedEntry,deletion,async()=>{deleted=true;}),/still referenced/);assert.equal(deleted,false);
		for(const [file,bytes]of production)assert.deepEqual(await fs.readFile(local(file)),bytes);
		check('Referenced deletion is blocked and production Resources remain unchanged');
	}finally{
		if(created){const directory=local(folder);assert.equal(path.dirname(path.resolve(directory)),path.resolve(local(root)));
			assert.equal(await fs.realpath(directory),directory);
			for(const name of await fs.readdir(directory)){assert.ok(ownedFiles.has(name),name);await fs.unlink(path.join(directory,name));}
			await fs.rmdir(directory);check('Owned fixtures removed');}
	}
	check('Checks passed');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
