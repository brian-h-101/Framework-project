const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createHash } = require('node:crypto');
const { pathToFileURL } = require('node:url');
const project = path.resolve(__dirname, 'mock-project');
const profiles = 'res://Framework/Content/Gameplay/Profiles';
const category = profiles + '/Movement';
const root = category + '/Behavior';
const source = root + '/Interaction/test.tres', action = root + '/Action/action.tres';
const group = root + '/Condition/group.tres', condition = root + '/Condition/condition.tres';
const created = root + '/Action/new.tres';
const bytes = Buffer.from('saved');
const hash = createHash('sha256').update(bytes).digest('hex');
const uri = file => ({ scheme: 'file', fsPath: file, path: file.split(path.sep).join('/'), toString: () => pathToFileURL(file).href });
const data = { label: 'data', kind: 'Dictionary', path: [], value_text: '', children: [], editable: false, mutable: false,
	can_add: false, can_rename: false, can_remove: false, can_add_effect: false, allowed_types: [], choices: [] };
const node = (source_path, kind, links = []) => ({source_path, id: kind, kind, content_hash: hash, data, links,
	...(kind === 'condition_group' ? { operator: 'all' } : kind === 'condition' ? {operator:'>=',value_text:'20'} : {})});
const graph = {version:2, roots:[source], nodes:{[source]:node(source,'interaction',[{role:'action',target:action,index:-1},{role:'requirements',target:group,index:-1}]),
	[action]:node(action,'action'),[group]:node(group,'condition_group',[{role:'condition',target:condition,index:0}]),[condition]:node(condition,'condition')},
	dependency_hashes:Object.fromEntries([source,action,group,condition].map(path=>[path,hash])),catalog_paths:[source,action,group,condition]};
const picks=[], inputs=[], confirms=[], calls=[], errors=[], opens=[], deletes=[], removed=[];
let onPrompt, creation = {filename:'new.tres',request:{resource_kind:'action',id:'new'}}, failLink=false, consumers=[];
const entry = (source_path, kind, resource_kind) => ({source_path,kind,resource_kind,name:source_path.split('/').at(-1),
	parent_path:source_path.slice(0,source_path.lastIndexOf('/')),fingerprint:hash,supported:kind==='resource',valid:true,id:resource_kind});
const catalogue = {entries:[entry(profiles,'root'),entry(category,'folder'),entry(root,'folder'),entry(root+'/Action','folder'),entry(root+'/Interaction','folder'),
	entry(source,'resource','interaction'),entry(action,'resource','action'),entry(group,'resource','condition_group'),entry(condition,'resource','condition')]};
const api={
	Uri:{file:uri,joinPath:(base,...parts)=>uri(path.join(base.fsPath,...parts))},
	EventEmitter:class{event=()=>({dispose(){}});fire(){}dispose(){}},TreeItem:class{constructor(label){this.label=label;}},
	TreeItemCollapsibleState:{None:0,Collapsed:1},ThemeIcon:class{static File='file';constructor(id){this.id=id;}},
	commands:{executeCommand:async(command,target)=>opens.push([command,target])},
	workspace:{isTrusted:true,workspaceFolders:[{uri:uri(project)}],textDocuments:[],getConfiguration:()=>({get:()=>'engine.exe'}),
		fs:{delete:async(...args)=>deletes.push(args)}},
	window:{showQuickPick:async(items,options)=>{onPrompt?.(options);const pick=picks.shift();return typeof pick==='function'?pick(items,options):pick;},
		showInputBox:async(options)=>{onPrompt?.(options);const input=inputs.shift();if(input!==undefined)assert.equal(options.validateInput?.(input),undefined);return input;},
		showWarningMessage:async()=>confirms.shift(),showErrorMessage:async message=>errors.push(message)}
};
class Service{
	constructor(context,executable,report,ready){this.ready=ready;}
	async catalogue(){return catalogue;}
	async createResource(parent,filename,request){await this.ready();calls.push({op:'create',parent,filename,request});return created;}
	async previewRename(selected,name){await this.ready();return{source_path:selected.source_path,destination_path:selected.parent_path+'/'+name,changes:[],id:selected.id,hashes:{[selected.source_path]:hash},directories:{},uid:'uid://test'};}
	async renameResource(selected,preview){await this.ready();calls.push({op:'rename',selected,preview});return preview.destination_path;}
	async previewDeletion(){await this.ready();return{consumers};}
	async deleteResource(selected,preview,trash){await this.ready();await trash(path.join(project,selected.source_path.slice(6)));}
}
const cache=new Map();
function load(file){
	file=path.resolve(file);if(cache.has(file))return cache.get(file).exports;
	const module={exports:{}};cache.set(file,module);
	const req=name=>{
		if(name==='vscode')return api;
		if(name==='node:fs/promises')return{readFile:async()=>bytes,lstat:async()=>({ino:1,dev:1,isSymbolicLink:()=>false}),unlink:async file=>removed.push(file)};
		if(name.endsWith('/library_service'))return{LibraryService:Service};
		if(name.endsWith('/library_manager'))return{ensureWorkspace:()=>{if(!api.workspace.isTrusted||!api.workspace.workspaceFolders.length)throw Error('workspace changed');}};
		if(name.endsWith('/resource_prompts'))return{creationDetails:async(_catalogue,kind)=>{calls.push({op:'details',kind});return creation;}};
		if(name.endsWith('/project_context'))return{resolveProjectContext:async()=>({projectDirectory:project,workspaceDirectory:project}),isInside:(root,file)=>!path.relative(root,file).startsWith('..')};
		if(name.endsWith('/behavior_editing_bridge'))return{editBehavior:async(_project,_exe,owner,request)=>{if(failLink)throw Error('incompatible arguments');calls.push({op:'edit',owner,request});}};
		if(name.endsWith('/resource_bridge')&&file.endsWith('resource_structure_command.js'))return{loadResourceGraph:async()=>({...graph,dependency_hashes:{...graph.dependency_hashes,[created]:hash}})};
		return name.startsWith('.')?load(path.resolve(path.dirname(file),name+'.js')):require(name);
	};
	vm.runInThisContext('(function(require,module,exports){'+fs.readFileSync(file,'utf8')+'\n})',{filename:file})(req,module,module.exports);
	return module.exports;
}
const {ResourceTreeProvider}=load(path.join(__dirname,'../out/tree/resource_tree_provider.js'));
const {ResourceStructureCommands}=load(path.join(__dirname,'../out/commands/resource_structure_command.js'));
const provider=new ResourceTreeProvider();
const changed=[];
const commands=new ResourceStructureCommands(provider,{appendLine(){}},async(...args)=>changed.push(args));
const rows=()=>{provider.setGraph(uri(project),structuredClone(graph));const owner=provider.getChildren()[0];const[actionRow,groupRow]=provider.getChildren(owner);return{owner,action:actionRow,group:groupRow,condition:provider.getChildren(groupRow)[0]};};
const pickRole=role=>items=>items.find(item=>item.role===role);
const check=label=>console.log(`[resource-structure-ui] ${label}: true`);
async function main(){
	let r=rows();
	assert.ok(provider.getTreeItem(r.owner).contextValue.includes('|link_resource'));
	assert.ok(provider.getTreeItem(r.action).contextValue.includes('|replace_reference'));
	assert.ok(!provider.getTreeItem(r.action).contextValue.includes('|remove_reference'));
	assert.ok(provider.getTreeItem(r.condition).contextValue.includes('|remove_reference'));
	await commands.execute('open_owner',r.condition);assert.equal(opens.at(-1)[1].fsPath,path.join(project,group.slice(6)));
	check('Menus distinguish file ownership, required links and optional links');
	picks.push(pickRole('action'),items=>{assert.ok(items.every(item=>item.entry.resource_kind==='action'));return items[0];});
	await commands.execute('assign_resource',r.owner);
	assert.equal(calls.at(-1).owner,source);assert.equal(calls.at(-1).request.target_path,action);
	picks.push(items=>items[0]);await commands.execute('replace_reference',r.action);
	assert.equal(calls.at(-1).owner,source);assert.equal(calls.at(-1).request.role,'action');
	check('Assignment and replacement write the relationship owner');
	const count=calls.length;await commands.execute('remove_reference',r.action);assert.equal(calls.length,count);
	confirms.push('Remove Reference');await commands.execute('remove_reference',r.group);assert.equal(calls.at(-1).request.operation,'clear_requirements');
	confirms.push('Remove Reference');await commands.execute('remove_reference',r.condition);assert.equal(calls.at(-1).request.condition_index,0);assert.equal(calls.at(-1).owner,group);
	check('Required links are protected and optional removals preserve resource files');
	picks.push(pickRole('action'),items=>{
		assert.ok(items.every(item=>item.entry.source_path.startsWith(root)));
		return items.find(item=>item.entry.source_path===root+'/Action');
	});
	await commands.execute('create_link',r.owner);
	assert.equal(calls.findLast(item=>item.op==='details').kind,'action');assert.equal(calls.at(-1).request.target_path,created);
	check('Creation selects a compatible schema and links the new file');
	failLink=true;picks.push(pickRole('action'),items=>items[0]);await commands.execute('create_link',r.owner);
	assert.equal(removed.at(-1),path.join(project,created.slice(6)));failLink=false;
	check('A failed link removes only the unchanged newly created file');
	const before=calls.length;await commands.execute('create_link',r.owner);assert.equal(calls.length,before);
	picks.push(pickRole('action'),undefined);await commands.execute('create_link',r.owner);assert.equal(calls.length,before);
	check('Cancellation performs no file or relationship write');
	inputs.push('renamed.tres');confirms.push('Rename Resource');await commands.execute('rename_file',r.action);
	assert.equal(calls.at(-1).op,'rename');assert.equal(calls.at(-1).preview.id,'action');assert.ok(opens.at(-1)[1].fsPath.endsWith('renamed.tres'));
	check('File rename preserves authored identity and opens the new path');
	consumers=[{source_path:source}];const trash=deletes.length;await commands.execute('delete_file',r.action);assert.equal(deletes.length,trash);
	consumers=[];confirms.push('Delete Resource');await commands.execute('delete_file',r.action);
	assert.deepEqual(deletes.at(-1)[1],{useTrash:true,recursive:false});
	check('Deletion blocks referenced files and uses nonrecursive Recycle Bin deletion');
	r=rows();onPrompt=()=>{api.workspace.isTrusted=false;};picks.push(pickRole('action'),items=>items[0]);const edits=calls.filter(c=>c.op==='edit').length;
	await commands.execute('assign_resource',r.owner);assert.equal(calls.filter(c=>c.op==='edit').length,edits);onPrompt=undefined;api.workspace.isTrusted=true;picks.length=0;
	api.workspace.textDocuments=[{isDirty:true,uri:uri(path.join(project,'dirty.gd'))}];await commands.execute('rename_file',r.action);assert.match(errors.at(-1),/Save or revert/);api.workspace.textDocuments=[];
	const stale=r.owner;provider.clear();await commands.execute('assign_resource',stale);assert.match(errors.at(-1),/stale/);
	check('Trust changes, dirty files and stale rows prevent mutations');
	const pkg=JSON.parse(fs.readFileSync(path.join(__dirname,'../package.json')));
	for(const name of ['newResource','createAndLinkResource','assignExistingResource','replaceReference','removeReference','renameResourceFile','deleteResourceFile','openOwningResource'])assert.ok(pkg.contributes.menus['customTreeView.resourceMenu'].some(item=>item.command==='customTreeView.'+name));
	check('Every new command is registered in the curated Resource menu');
	check('Checks passed');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
