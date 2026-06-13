import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

/**
 * Headless JSFL job runner — drives Animate's JSFL host (`cf7ak-runner.jsfl`)
 * from the terminal, mirroring the repo's proven CS6 automation chain
 * (scripts/compile_action.jsfl + compile_test.ps1): write a job file, trigger
 * Animate, poll for the done/error MARKER, and — crucially — verify the result
 * file is FRESH (not a stale leftover) before trusting it.
 *
 * This makes capability ③ (authoring) agent/CI-drivable against a real CS6 /
 * Animate, and is the native authoring path for CS6 (which cannot host a CEP
 * panel). All timing/IO is injectable so the orchestration is unit-tested with
 * a stub trigger (no real Animate needed).
 */
export type JsflTrigger =
  | { kind: 'exe'; exePath: string; scriptPath: string }
  | { kind: 'task'; taskName: string }
  | { kind: 'inline'; run: () => void | Promise<void> };

export interface RunJsflOptions {
  /** Directory both sides agree on (an-host: <Commands>/cf7ak; JSFL: fl.configURI+Commands/cf7ak). */
  jobDir: string;
  fn: string;
  args?: unknown;
  /** How to make Animate execute cf7ak-runner.jsfl. */
  trigger: JsflTrigger;
  timeoutSeconds?: number;
  pollIntervalMs?: number;
  /** Injectables (defaults: Date.now / setTimeout / child_process.spawn). */
  clock?: () => number;
  sleep?: (ms: number) => Promise<void>;
  spawnTrigger?: (cmd: string, args: string[]) => void;
}

export interface JsflRunResult {
  ok: boolean;
  data?: unknown;
  error?: string;
  timedOut?: boolean;
  jobPath: string;
  resultPath: string;
}

const FILES = {
  job: 'cf7ak-job.json',
  result: 'cf7ak-result.json',
  done: 'cf7ak-done.marker',
  error: 'cf7ak-error.marker',
} as const;

function rmIfExists(p: string): void {
  try {
    fs.rmSync(p, { force: true });
  } catch {
    /* ignore */
  }
}

async function fireTrigger(
  t: JsflTrigger,
  spawnTrigger: (cmd: string, args: string[]) => void,
): Promise<void> {
  switch (t.kind) {
    case 'exe':
      spawnTrigger(t.exePath, [t.scriptPath]);
      return;
    case 'task':
      spawnTrigger('powershell', ['-NoProfile', '-Command', `Start-ScheduledTask -TaskName '${t.taskName}'`]);
      return;
    case 'inline':
      await t.run();
      return;
  }
}

const defaultSpawn = (cmd: string, args: string[]): void => {
  const child = spawn(cmd, args, { detached: true, stdio: 'ignore' });
  child.unref();
};

/** Resolve the shared job directory from an Animate install's Commands dir. */
export function jobDirForCommands(commandsDir: string): string {
  return path.join(commandsDir, 'cf7ak');
}

export async function runJsflJob(opts: RunJsflOptions): Promise<JsflRunResult> {
  const clock = opts.clock ?? (() => Date.now());
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const spawnTrigger = opts.spawnTrigger ?? defaultSpawn;
  const timeoutSeconds = opts.timeoutSeconds ?? 30;
  const pollIntervalMs = opts.pollIntervalMs ?? 1000;

  const jobPath = path.join(opts.jobDir, FILES.job);
  const resultPath = path.join(opts.jobDir, FILES.result);
  const donePath = path.join(opts.jobDir, FILES.done);
  const errorPath = path.join(opts.jobDir, FILES.error);

  fs.mkdirSync(opts.jobDir, { recursive: true });
  // Clear stale artifacts so the marker + freshness check are unambiguous.
  rmIfExists(resultPath);
  rmIfExists(donePath);
  rmIfExists(errorPath);

  const startedAt = clock();
  fs.writeFileSync(jobPath, JSON.stringify({ fn: opts.fn, args: opts.args ?? null, ts: startedAt }), 'utf8');

  await fireTrigger(opts.trigger, spawnTrigger);

  const deadline = startedAt + timeoutSeconds * 1000;
  while (clock() < deadline) {
    if (fs.existsSync(errorPath)) {
      return { ok: false, error: fs.readFileSync(errorPath, 'utf8').trim(), jobPath, resultPath };
    }
    if (fs.existsSync(donePath) && fs.existsSync(resultPath)) {
      // Freshness: the result must have been written at/after we started
      // (defends against a leftover result file from a previous run).
      const mtime = fs.statSync(resultPath).mtimeMs;
      if (mtime >= startedAt - 1000) {
        try {
          const parsed = JSON.parse(fs.readFileSync(resultPath, 'utf8')) as {
            ok: boolean;
            data?: unknown;
            error?: string;
          };
          const out: JsflRunResult = { ok: parsed.ok, jobPath, resultPath };
          if (parsed.data !== undefined) out.data = parsed.data;
          if (parsed.error !== undefined) out.error = parsed.error;
          return out;
        } catch (e) {
          return { ok: false, error: `unparseable result: ${String(e)}`, jobPath, resultPath };
        }
      }
    }
    await sleep(pollIntervalMs);
  }
  return { ok: false, timedOut: true, error: `timed out after ${timeoutSeconds}s`, jobPath, resultPath };
}
