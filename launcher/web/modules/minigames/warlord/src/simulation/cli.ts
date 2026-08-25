import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { runBatchSimulation } from './run.js';

const countArg = process.argv.find((arg) => arg.startsWith('--games='));
const gameCount = countArg ? Number.parseInt(countArg.split('=')[1] ?? '32', 10) : 32;
if (!Number.isInteger(gameCount) || gameCount <= 0) throw new Error(`Invalid --games value: ${gameCount}`);

const result = runBatchSimulation(gameCount);
const artifacts = resolve(process.cwd(), 'artifacts');
mkdirSync(artifacts, { recursive: true });
writeFileSync(resolve(artifacts, 'simulation-summary.json'), `${JSON.stringify(result.summary, null, 2)}\n`, 'utf8');
writeFileSync(resolve(artifacts, 'sample-replay.json'), `${JSON.stringify(result.sampleReplay, null, 2)}\n`, 'utf8');
process.stdout.write(`${JSON.stringify(result.summary)}\n`);
