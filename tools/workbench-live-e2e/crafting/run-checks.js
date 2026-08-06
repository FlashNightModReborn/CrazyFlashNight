#!/usr/bin/env node
"use strict";

// Historical filename retained only as a loadable tombstone. The bootstrap owns
// the sole module-journal admission path for the offline gate.
module.exports = Object.freeze({ status: "SUPERSEDED / NOT_ADMITTED" });

if (require.main === module) {
  console.error("SUPERSEDED / NOT_ADMITTED: use crafting/bootstrap.js --check");
  process.exitCode = 2;
}
