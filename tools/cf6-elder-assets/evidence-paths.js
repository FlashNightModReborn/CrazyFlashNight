"use strict";
const path = require("path");
const OLD_PREFIXES = [
  "tools/cf6-elder-assets/evidence/20261017-calibration",
  "tools/cf6-elder-assets/evidence/20261018-loader-size-followup"
];
function validateOutput(target, root) {
  const absolute = path.resolve(target), base = path.resolve(root);
  const local = path.relative(base, absolute);
  const relative = local.split(path.sep).join("/");
  if (local !== ".." && !local.startsWith(".." + path.sep) && !path.isAbsolute(local)) {
    if (OLD_PREFIXES.some(p => relative.toLowerCase() === p || relative.toLowerCase().startsWith(p + "/")))
      throw Error("Archived evidence root is retired; use e/<short-campaign>");
    if (relative.length > 179) throw Error("Evidence output exceeds supported relative budget 179 UTF-16");
  }
  if (absolute.length > 240) throw Error("Evidence output exceeds full visible budget 240 UTF-16");
  if (absolute.split(path.sep).some(p => p.length > 255)) throw Error("Evidence output component exceeds 255 UTF-16");
  return absolute;
}
module.exports = {validateOutput};
