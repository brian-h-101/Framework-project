// This lookup only positions the editor. Godot supplies the hierarchy itself.
export function declarationLine(text: string, nodePath: string): number | undefined {
	const lines = text.split(/\r?\n/);
	for (let index = 0; index < lines.length; index++) {
		const line = lines[index];
		if (!/^\[node(?:\s|\])/.test(line)) {
			continue;
		}
		const name = field(line, 'name');
		const parent = field(line, 'parent');
		if (name === undefined) {
			continue;
		}
		const path = parent === undefined ? '.' : parent === '.' ? name : `${parent}/${name}`;
		if (path === nodePath) {
			return index;
		}
	}
	return undefined;
}

function field(header: string, name: string): string | undefined {
	const match = header.match(new RegExp(`(?:\\s)${name}=("(?:\\\\.|[^"\\\\])*")`));
	if (!match) {
		return undefined;
	}
	try {
		return JSON.parse(match[1]) as string;
	} catch {
		return undefined;
	}
}
