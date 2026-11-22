import * as vscode from 'vscode';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { isAuthoredFragment } from '../bridges/resource_bridge';

interface FragmentItem extends vscode.QuickPickItem {
	path: string;
	hash: string;
}

export async function pickPresetFragments(project: string, executable: string, current: string[],
	report: (message: string) => void): Promise<{ paths: string[]; hashes: Record<string, string> } | undefined> {
	const { stdout, stderr } = await promisify(execFile)(executable, ['--headless', '--path', project, '--script',
		'res://Framework/Env/Authoring/Attributes/attribute_library_cli.gd', '--', 'catalogue'],
	{ cwd: project, encoding: 'utf8', windowsHide: true, timeout: 30_000, maxBuffer: 16 * 1024 * 1024 });
	if (stderr.trim()) { report(stderr.trim()); }
	const prefix = '[attribute-library] ';
	const lines = stdout.split(/\r?\n/).filter(line => line.startsWith(prefix));
	if (lines.length !== 1 || /^(SCRIPT ERROR|ERROR):/m.test(stdout + '\n' + stderr)) {
		throw new Error('Godot could not inspect the Authored attribute library.');
	}
	const packet = JSON.parse(lines[0].slice(prefix.length));
	if (packet?.ok !== true || packet.value?.version !== 1 || !Array.isArray(packet.value.entries)) {
		throw new Error('Godot returned an invalid Authored attribute catalogue.');
	}
	const choices: FragmentItem[] = [];
	const seen = new Set<string>();
	for (const entry of packet.value.entries) {
		if (entry?.kind !== 'resource' || entry.supported !== true) { continue; }
		const path: unknown = entry.source_path;
		if (!isAuthoredFragment(path) || seen.has(path) || typeof entry.fingerprint !== 'string'
			|| !/^[a-f0-9]{64}$/.test(entry.fingerprint)) {
			throw new Error('Godot returned an invalid attribute fragment.');
		}
		seen.add(path);
		choices.push({ label: path.split('/').at(-1)!, description: path.slice(6),
			path, hash: entry.fingerprint, picked: current.includes(path) });
	}
	const selected = await vscode.window.showQuickPick(choices, {
		title: 'Choose Attribute Fragments', canPickMany: true, matchOnDescription: true, ignoreFocusOut: true
	});
	if (selected === undefined) { return; }
	const hashes = Object.fromEntries(selected.map(item => [item.path, item.hash]));
	// Keep the composition order of retained fragments and append new selections.
	const paths = [...new Set([...current.filter(path => Object.hasOwn(hashes, path)), ...selected.map(item => item.path)])];
	return { paths, hashes };
}
