import * as vscode from 'vscode';
import { lstat, open, readFile, unlink } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';
import { generatedLayoutScenePath, isLayoutCategory, LAYOUT_PRESET_FOLDER, LAYOUT_SUFFIX, runLayout } from '../bridges/layout_bridge';
import { ensureWorkspace } from '../library/library_manager';
import { checkedProjectPath, directoryFingerprint, nameError, sha256, verifyLibrarySnapshot, type DependencySnapshot } from '../library/library_paths';
import { scalarError } from '../resources/value_prompts';
import { ResourceTreeProvider, resourceUri, type ResourceTreeElement } from '../tree/resource_tree_provider';
import { isInside, validateResourcePath, type ProjectContext } from '../workspace/project_context';
import { projectFor } from './configuration_editing_command';

export type LayoutOperation = 'create' | 'create_category' | 'delete_category' | 'build' | 'add' | 'rename' | 'remove' | 'attach_script' | 'set_property' | 'assign_resource';
interface Property { name: string; kind: string; value: string }
interface LayoutInspection { name: string; type: string; dependency_hashes: Record<string, string>; properties: Property[] }
interface LayoutCategory { source_path: string; fingerprint: string }
interface CategoryDeletionPreview extends DependencySnapshot {
	source_path: string;
	consumers: { source_path: string }[];
	file_count: number;
}
type LayoutRequest = (args: string[], body?: object) => Promise<unknown>;

export class LayoutCommands {
	constructor(private readonly provider: ResourceTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly refresh: () => Promise<void>, private readonly removed: (uri: vscode.Uri) => void) {}

	async execute(operation: LayoutOperation, element?: ResourceTreeElement): Promise<void> {
		try {
			const selected = element ? this.provider.resolve(element) : undefined;
			const libraryOperation = operation === 'create' || operation === 'create_category' || operation === 'delete_category';
			if (!libraryOperation && selected?.resource.kind !== 'layout') { throw new Error('Choose a Layout Preset.'); }
			const context = await projectFor(selected?.uri);
			if (!context) { return; }
			const project = vscode.Uri.file(context.projectDirectory);
			const executableFor = () => vscode.workspace.getConfiguration('godotTools', project).get<string>('editorPath.godot4')?.trim();
			const executable = executableFor();
			if (!executable) { throw new Error('Configure godotTools.editorPath.godot4 for this workspace.'); }
			const request = (args: string[], body?: object) => runLayout(context.projectDirectory, executable, args, text => this.output.appendLine(text), body);
			const hashes: Record<string, string> = {};
			const ready = async (): Promise<void> => {
				ensureWorkspace(context);
				if (element) { this.provider.resolve(element); }
				if (executableFor() !== executable) { throw new Error('The configured Godot executable changed. Retry the operation.'); }
				if (vscode.workspace.textDocuments.some(doc => doc.isDirty && doc.uri.scheme === 'file' && isInside(context.projectDirectory, doc.uri.fsPath))) {
					throw new Error('Save or revert project edits before authoring a layout.');
				}
				for (const [source, hash] of Object.entries(hashes)) {
					if (sha256(await readFile(await checkedProjectPath(context, source))) !== hash) {
						throw new Error('Layout dependency changed. Refresh and retry: ' + source);
					}
				}
			};
			const pickType = async (): Promise<string | undefined> => {
				const types = await request(['node-types']);
				if (!Array.isArray(types) || !types.every(type => typeof type === 'string')) { throw new Error('Malformed Godot node type list.'); }
				return vscode.window.showQuickPick(types.filter(type => type !== 'InstancePlaceholder'), { title: 'Layout Node Type', ignoreFocusOut: true });
			};
			await ready();
			if (operation === 'create_category' || operation === 'delete_category') {
				await this.manageCategory(operation, context, request, ready);
				return;
			}
			if (operation === 'create') {
				const categories = await layoutCategories(request);
				const category = categories.length === 1 ? categories[0] : await pickCategory(categories, 'New Layout Preset — Category');
				if (!category) { return; }
				const presetName = await vscode.window.showInputBox({ title: 'New Layout Preset — File Name',
					prompt: 'The extension adds .layout.tres', ignoreFocusOut: true, validateInput: nameError });
				if (presetName === undefined) { return; }
				const type = await pickType();
				if (!type) { return; }
				const name = await promptName('Layout Root Name', type);
				if (name === undefined) { return; }
				const source = `${category.source_path}/${presetName}${LAYOUT_SUFFIX}`;
				await ready();
				const draft = await request(['create-layout', source], { name, node_type: type, expected_parent: category.fingerprint });
				await ready();
				await publishPreset(context, source, draft);
				await vscode.window.showTextDocument(resourceUri(project, source));
				return;
			}
			const source = selected!.resource.source_path;
			const nodePath = operation === 'build' ? '.' : selected!.data?.layout_path;
			if (nodePath === undefined) { throw new Error('Choose a node row in the Layout Preset.'); }
			const current = inspection(await request(['inspect-layout', source, nodePath]), source);
			if (current.dependency_hashes[source] !== selected!.resource.content_hash) { throw new Error('The selected layout changed. Refresh and retry.'); }
			Object.assign(hashes, current.dependency_hashes);
			await ready();
			if (operation === 'build') {
				const result = await request(['build-layout', source], hashes) as { scene_path: string };
				const expected = generatedLayoutScenePath(source);
				if (result?.scene_path !== expected) { throw new Error('Godot returned an invalid generated scene path.'); }
				await vscode.window.showTextDocument(vscode.Uri.joinPath(project, ...expected.slice(6).split('/')));
				this.output.appendLine('[layout] Built ' + expected);
				return;
			}
			const body: Record<string, unknown> = { operation, node_path: nodePath, expected_hashes: hashes };
			if (operation === 'add' || operation === 'rename') {
				const type = operation === 'add' ? await pickType() : current.type;
				if (!type) { return; }
				const name = await promptName(operation === 'add' ? 'New Child Name' : 'Rename Layout Node', operation === 'add' ? type : current.name);
				if (name === undefined) { return; }
				Object.assign(body, { name, node_type: type });
			} else if (operation === 'remove') {
				if (await vscode.window.showWarningMessage(`Remove ${current.name} and its children?`, { modal: true }, 'Remove Node') !== 'Remove Node') { return; }
			} else if (operation === 'attach_script') {
				body.asset_path = await pickAsset(context, 'gd', 'Attach Layout Script');
				if (!body.asset_path) { return; }
			} else {
				const options = current.properties.filter(property => (property.kind === 'Resource') === (operation === 'assign_resource'))
					.map(property => ({ property, label: property.name, description: property.kind, detail: property.value }));
				if (!options.length) { void vscode.window.showInformationMessage('This node has no compatible properties.'); return; }
				const choice = await vscode.window.showQuickPick(options, { title: 'Layout Node Property', matchOnDescription: true, ignoreFocusOut: true });
				if (!choice) { return; }
				const field = choice.property;
				body.property_name = field.name;
				if (operation === 'assign_resource') {
					body.asset_path = await pickAsset(context, 'tres', `Assign Resource — ${field.name}`);
					if (!body.asset_path) { return; }
				} else {
					const value = field.kind === 'bool'
						? await vscode.window.showQuickPick(['true', 'false'], { title: field.name, ignoreFocusOut: true })
						: await vscode.window.showInputBox({ title: field.name, value: field.value, ignoreFocusOut: true,
							validateInput: text => scalarError(field.kind, text) });
					if (value === undefined) { return; }
					Object.assign(body, { property_type: field.kind, property_value: value });
				}
			}
			if (typeof body.asset_path === 'string') {
				hashes[body.asset_path] = sha256(await readFile(await checkedProjectPath(context, body.asset_path)));
			}
			await ready();
			await request(['edit-layout', source], body);
			await this.refresh();
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine('[layout] Error: ' + message);
			void vscode.window.showErrorMessage(message);
		}
	}

	private async manageCategory(operation: 'create_category' | 'delete_category', context: ProjectContext,
		request: LayoutRequest, ready: () => Promise<void>): Promise<void> {
		const creating = operation === 'create_category';
		const categories = (await layoutCategories(request)).filter(item => creating || item.source_path !== LAYOUT_PRESET_FOLDER);
		if (!categories.length) {
			void vscode.window.showInformationMessage('There are no Preset subcategories to delete.');
			return;
		}
		const choice = await pickCategory(categories, creating ? 'New Preset Subcategory — Parent' : 'Delete Preset Subcategory');
		if (!choice) { return; }
		const source = choice.source_path;
		if (creating) {
			const name = await vscode.window.showInputBox({ title: 'New Preset Subcategory — Name', ignoreFocusOut: true, validateInput: nameError });
			if (name === undefined) { return; }
			if (nameError(name)) { throw new Error('Choose a valid folder name.'); }
			const target = source + '/' + name;
			await ready();
			const created = await request(['create-layout-category', target], { expected_parent: choice.fingerprint }) as { source_path?: string };
			if (created?.source_path !== target) { throw new Error('Godot returned an invalid preset category path.'); }
			void vscode.window.showInformationMessage('Created ' + target.slice(6));
			return;
		}
		await ready();
		const preview = await request(['preview-layout-category-deletion', source],
			{ expected_directory: choice.fingerprint }) as CategoryDeletionPreview;
		if (!preview || preview.source_path !== source || preview.directories?.[source] !== choice.fingerprint
			|| !preview.hashes || !Array.isArray(preview.consumers) || !Number.isSafeInteger(preview.file_count) || preview.file_count < 0) {
			throw new Error('Invalid preset category deletion preview.');
		}
		if (preview.consumers.length) {
			const detail = preview.consumers.map(item => item.source_path).join('\n');
			this.output.appendLine('[layout] Category is referenced by:\n' + detail);
			void vscode.window.showWarningMessage('This preset subcategory is still referenced.', { modal: true, detail });
			return;
		}
		const detail = `${source.slice(6)}\n\nThis moves the folder, its subfolders, and ${preview.file_count} file(s).`;
		if (await vscode.window.showWarningMessage('Move this preset subcategory to the Recycle Bin?',
			{ modal: true, detail }, 'Move to Recycle Bin') !== 'Move to Recycle Bin') { return; }
		await ready();
		await verifyLibrarySnapshot(context, preview, 'Delete Preset Subcategory');
		await ready();
		const root = await checkedProjectPath(context, LAYOUT_PRESET_FOLDER);
		const folder = await checkedProjectPath(context, source);
		if (relative(root, folder) === '' || !isInside(root, folder) || await directoryFingerprint(folder) !== choice.fingerprint) {
			throw new Error('The selected subcategory changed. Refresh and retry.');
		}
		const uri = vscode.Uri.file(folder);
		await vscode.workspace.fs.delete(uri, { useTrash: true, recursive: true });
		this.removed(uri);
	}
}

async function layoutCategories(request: LayoutRequest): Promise<LayoutCategory[]> {
	const categories = await request(['layout-categories']) as LayoutCategory[];
	if (!Array.isArray(categories) || categories.length === 0 || categories[0]?.source_path !== LAYOUT_PRESET_FOLDER
		|| categories.some(item => !item || typeof item.source_path !== 'string' || !isLayoutCategory(item.source_path)
			|| typeof item.fingerprint !== 'string' || (!/^[a-f0-9]{64}$/.test(item.fingerprint)
				&& (item.source_path !== LAYOUT_PRESET_FOLDER || item.fingerprint !== '')))
		|| new Set(categories.map(item => item.source_path)).size !== categories.length) {
		throw new Error('Malformed Presets category catalogue.');
	}
	return categories;
}

async function pickCategory(categories: LayoutCategory[], title: string): Promise<LayoutCategory | undefined> {
	const items = categories.map(category => ({
		label: category.source_path === LAYOUT_PRESET_FOLDER ? 'Presets' : category.source_path.slice(LAYOUT_PRESET_FOLDER.length + 1),
		description: category.source_path.slice(6),
		category,
	}));
	return (await vscode.window.showQuickPick(items, { title, matchOnDescription: true, ignoreFocusOut: true }))?.category;
}

function inspection(value: unknown, source: string): LayoutInspection {
	const result = value as LayoutInspection;
	if (!result || typeof result.name !== 'string' || typeof result.type !== 'string' || !Array.isArray(result.properties)
		|| result.properties.some(entry => !entry || typeof entry.name !== 'string' || typeof entry.kind !== 'string' || typeof entry.value !== 'string')
		|| !result.dependency_hashes || !Object.hasOwn(result.dependency_hashes, source)) {
		throw new Error('Malformed Layout Preset inspection.');
	}
	for (const [path, hash] of Object.entries(result.dependency_hashes)) {
		validateResourcePath(path);
		if (!/^[a-f0-9]{64}$/.test(hash)) { throw new Error('Malformed layout dependency hash.'); }
	}
	return result;
}

async function promptName(title: string, value: string): Promise<string | undefined> {
	return vscode.window.showInputBox({ title, value, ignoreFocusOut: true,
		validateInput: name => !name.trim() || name === '.' || name === '..' || /[:@/"%\\\r\n]/.test(name)
			? 'Enter a valid Godot node name.' : undefined });
}

async function pickAsset(context: ProjectContext, extension: 'gd' | 'tres', title: string): Promise<string | undefined> {
	const files = await vscode.workspace.findFiles(new vscode.RelativePattern(context.projectDirectory, `**/*.${extension}`),
		'**/{.git,.godot,node_modules,out}/**');
	const options = files.filter(file => file.scheme === 'file' && isInside(context.projectDirectory, file.fsPath))
		.map(file => {
			const path = relative(context.projectDirectory, file.fsPath).split(sep).join('/');
			return { label: path.split('/').at(-1)!, description: path };
		}).filter(item => !item.label.startsWith('.') && !item.label.endsWith(LAYOUT_SUFFIX))
		.sort((a, b) => a.description.localeCompare(b.description));
	const chosen = await vscode.window.showQuickPick(options, { title, matchOnDescription: true, ignoreFocusOut: true });
	return chosen ? 'res://' + chosen.description : undefined;
}

async function publishPreset(context: ProjectContext, source: string, value: unknown): Promise<void> {
	const draft = value as { source_path: string; source_text: string; content_hash: string; expected_parent: string; uid: string };
	if (!draft || draft.source_path !== source || typeof draft.source_text !== 'string' || Buffer.byteLength(draft.source_text) > 1024 * 1024
		|| sha256(Buffer.from(draft.source_text)) !== draft.content_hash
		|| !/^uid:\/\/[a-z0-9]+$/.test(draft.uid) || !draft.source_text.split(/\r?\n/, 1)[0].includes(`uid="${draft.uid}"`)) {
		throw new Error('Godot returned an invalid Layout Preset draft.');
	}
	const category = source.slice(0, source.lastIndexOf('/'));
	if (!isLayoutCategory(category)) { throw new Error('Choose a category under Presets.'); }
	const folder = await checkedProjectPath(context, category);
	if (await directoryFingerprint(folder) !== draft.expected_parent) { throw new Error('The Presets folder changed. Retry creation.'); }
	const path = join(folder, source.split('/').at(-1)!);
	const handle = await open(path, 'wx');
	const owned = await handle.stat();
	try {
		await handle.writeFile(draft.source_text, 'utf8');
		await handle.sync();
	} catch (error) {
		await handle.close();
		const current = await lstat(path);
		if (!current.isSymbolicLink() && current.ino === owned.ino && current.dev === owned.dev) { await unlink(path); }
		throw error;
	}
	await handle.close();
}
