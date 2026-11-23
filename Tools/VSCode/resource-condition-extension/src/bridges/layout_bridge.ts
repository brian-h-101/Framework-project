import { execFile } from 'node:child_process';

export const LAYOUT_PRESET_FOLDER = 'res://Framework/Content/Gameplay/Presets';
const LAYOUT_SCENE_FOLDER = 'res://Framework/Content/Gameplay/Presentation/Layouts';
export const LAYOUT_SUFFIX = '.layout.tres';

export function isLayoutCategory(source: string): boolean {
	return source === LAYOUT_PRESET_FOLDER || (source.startsWith(LAYOUT_PRESET_FOLDER + '/')
		&& source.slice(LAYOUT_PRESET_FOLDER.length + 1).split('/').every(part => part && !part.startsWith('.') && !/[\\:\0]/.test(part)));
}

export function generatedLayoutScenePath(preset: string): string {
	const relative = preset.slice(LAYOUT_PRESET_FOLDER.length + 1, -LAYOUT_SUFFIX.length);
	return LAYOUT_SCENE_FOLDER + '/' + relative + '.tscn';
}

export function runLayout(project: string, executable: string, args: string[],
	report: (message: string) => void, request?: object): Promise<unknown> {
	const input = request === undefined ? '' : JSON.stringify(request);
	if (Buffer.byteLength(input) > 1024 * 1024) { throw new Error('Layout requests cannot exceed 1 MiB.'); }
	return new Promise((resolve, reject) => {
		const child = execFile(executable, ['--headless', '--path', project,
			'--script', 'res://Framework/Env/Authoring/Scenes/Editing/scene_editing_cli.gd', '--', ...args],
		{ cwd: project, encoding: 'utf8', windowsHide: true, timeout: 30_000, maxBuffer: 16 * 1024 * 1024 },
		(error, stdout, stderr) => {
			try {
				if (stderr.trim()) { report(stderr.trim()); }
				const prefix = '[scene-editing] ';
				const packets = stdout.split(/\r?\n/).filter(line => line.startsWith(prefix));
				if (packets.length !== 1) { throw error ?? new Error('Godot returned no unique layout result.'); }
				const result = JSON.parse(packets[0].slice(prefix.length));
				if (result?.ok !== true) { throw new Error(result?.error || 'Layout authoring failed.'); }
				if (error) { throw error; }
				if (/^(SCRIPT ERROR|ERROR):/m.test(stderr + '\n' + stdout)) { throw new Error('Godot reported an error while authoring the layout.'); }
				resolve(result.value);
			} catch (failure) { reject(failure); }
		});
		child.stdin?.on('error', () => undefined);
		child.stdin?.end(input);
	});
}
