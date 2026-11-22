import * as vscode from 'vscode';
import { basename, dirname, join, relative, sep } from 'node:path';
import { isInside, type ProjectContext } from './project_context';

const EXCLUDED = '**/{.git,.godot,node_modules,out}/**';

interface SceneFile {
	uri: vscode.Uri;
	path: string;
}

type Choice = vscode.QuickPickItem & (
	| { action: 'scene'; file: SceneFile }
	| { action: 'folder'; name: string }
	| { action: 'parent' | 'search' | 'folders' }
);

export async function pickSceneInstance(context: ProjectContext, currentScene: string): Promise<vscode.Uri | undefined> {
	const project = context.projectDirectory;
	const currentFile = join(project, currentScene.slice('res://'.length));
	const [uris, projectFiles] = await Promise.all([
		vscode.workspace.findFiles(new vscode.RelativePattern(project, '**/*.tscn'), EXCLUDED),
		vscode.workspace.findFiles(new vscode.RelativePattern(project, '**/project.godot'), EXCLUDED)
	]);
	const nestedProjects = projectFiles
		.filter(uri => uri.scheme === 'file' && isInside(project, uri.fsPath))
		.map(uri => dirname(uri.fsPath))
		.filter(folder => relative(project, folder) !== '');
	const files: SceneFile[] = uris
		.filter(uri => uri.scheme === 'file' && isInside(project, uri.fsPath)
			&& relative(currentFile, uri.fsPath) !== ''
			&& !nestedProjects.some(folder => isInside(folder, uri.fsPath)))
		.map(uri => ({ uri, path: relative(project, uri.fsPath).split(sep).join('/') }))
		.filter(file => file.path.endsWith('.tscn'))
		.sort((left, right) => left.path.localeCompare(right.path));
	if (!files.length) {
		void vscode.window.showInformationMessage('No other .tscn scenes were found in this Godot project.');
		return;
	}
	const folderPath: string[] = [];
	let searching = false;
	while (true) {
		const prefix = folderPath.length ? folderPath.join('/') + '/' : '';
		const items: Choice[] = searching
			? [{ action: 'folders', label: 'Back to Folders', iconPath: new vscode.ThemeIcon('arrow-left') },
				...files.map(sceneChoice)]
			: folderChoices(files, prefix);
		const chosen = await vscode.window.showQuickPick(items, {
			title: 'Add Scene Instance — ' + (searching ? 'All Scenes' : prefix || basename(project)),
			placeHolder: searching ? 'Search full scene paths' : 'Choose a folder or scene',
			matchOnDescription: true,
			ignoreFocusOut: true
		});
		if (!chosen) { return; }
		switch (chosen.action) {
			case 'scene': return chosen.file.uri;
			case 'folder': folderPath.push(chosen.name); break;
			case 'parent': folderPath.pop(); break;
			case 'search': searching = true; break;
			case 'folders': searching = false; break;
		}
	}
}

function folderChoices(files: SceneFile[], prefix: string): Choice[] {
	const folders = new Set<string>();
	const scenes: Choice[] = [];
	for (const file of files) {
		if (!file.path.startsWith(prefix)) { continue; }
		const local = file.path.slice(prefix.length);
		const separator = local.indexOf('/');
		if (separator === -1) {
			scenes.push(sceneChoice(file));
		} else {
			folders.add(local.slice(0, separator));
		}
	}
	const navigation: Choice = prefix
		? { action: 'parent', label: 'Parent Folder', iconPath: new vscode.ThemeIcon('arrow-up') }
		: { action: 'search', label: 'Search All Scenes…', iconPath: new vscode.ThemeIcon('search') };
	const contents = [
		...[...folders].sort((a, b) => a.localeCompare(b)).map((name): Choice => ({
			action: 'folder', name, label: name + '/', iconPath: new vscode.ThemeIcon('folder')
		})),
		...scenes
	];
	return prefix ? [navigation, ...contents] : [...contents, navigation];
}

function sceneChoice(file: SceneFile): Choice {
	return {
		action: 'scene', file, label: file.path.split('/').at(-1)!,
		description: file.path, iconPath: vscode.ThemeIcon.File
	};
}
