"use strict";

// Historical filename retained only so old callers fail into the new narrow contract.
// No browser/page/evaluate/input primitive is exported.
const { attachPassiveObserver } = require("./cdp-passive-observer");
const { TRANSCRIPT_SCHEMA } = require("./common");

module.exports = Object.freeze({
  TRANSCRIPT_SCHEMA,
  attachPassiveObserver,
});
