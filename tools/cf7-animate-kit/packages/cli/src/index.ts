#!/usr/bin/env node
import { runSol } from './commands/sol.js';
import { runAn } from './commands/an.js';
import { runArt } from './commands/art.js';
import { printLine, fail } from './lib/args.js';

const USAGE = `cf7-animate-kit — clean, offline Animate productivity CLI

Usage: cf7-animate-kit <domain> <subcommand> [args]

Domains:
  sol    Flash SharedObject (.sol / AMF0) read / info / diff / from-json
  an     Adobe Animate maintenance (paths, jvm.ini, sidebar, cache, install)   [P1]
  art    Authoring helpers over XFL (lint / linkage-scan / dup-scan)            [P3]

Run 'cf7-animate-kit sol help' for sol subcommands.

This tool is fully offline. It performs no network access, no license / activation
logic, and never edits the hosts file. See CF7-AnimateKit-DevSpec-v1.md.`;

function main(): void {
  const [, , domain, ...rest] = process.argv;
  switch (domain) {
    case 'sol':
      return runSol(rest);
    case 'an':
      return runAn(rest);
    case 'art':
      return runArt(rest);
    case undefined:
    case 'help':
    case '--help':
    case '-h':
      return printLine(USAGE);
    default:
      fail(`unknown domain: ${domain}. Run 'cf7-animate-kit help'.`);
  }
}

main();
