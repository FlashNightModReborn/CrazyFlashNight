export interface ParsedArgs {
  /** Positional arguments. */
  _: string[];
  /** `--key value` or boolean `--key` flags. */
  flags: Record<string, string | boolean>;
}

/** Minimal argv parser: positionals + `--flag [value]`. */
export function parseArgs(argv: string[]): ParsedArgs {
  const positionals: string[] = [];
  const flags: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === undefined) continue;
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) {
        flags[key] = next;
        i++;
      } else {
        flags[key] = true;
      }
    } else {
      positionals.push(a);
    }
  }
  return { _: positionals, flags };
}

export function printJson(v: unknown): void {
  process.stdout.write(`${JSON.stringify(v, null, 2)}\n`);
}

export function printLine(s = ''): void {
  process.stdout.write(`${s}\n`);
}

export function fail(msg: string): never {
  process.stderr.write(`error: ${msg}\n`);
  process.exit(1);
}
