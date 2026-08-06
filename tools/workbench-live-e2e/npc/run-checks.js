#!/usr/bin/env node
"use strict";

// Historical filename retained only as a loadable tombstone. The bootstrap owns
// the sole module-journal admission path for the offline gate.
module.exports = Object.freeze({ status: "SUPERSEDED / NOT_ADMITTED" });

if (require.main === module) {
  process.stderr.write("run-checks.js is SUPERSEDED / NOT_ADMITTED; use npc/bootstrap.js --check\n");
  process.exitCode = 2;
}
