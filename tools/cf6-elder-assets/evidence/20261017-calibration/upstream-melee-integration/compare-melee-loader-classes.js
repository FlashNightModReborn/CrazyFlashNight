"use strict";
const fs = require("fs"), path = require("path"), cp = require("child_process"), crypto = require("crypto");
const { parseSwf } = require("../../tools/swf-metadata");
const root = path.resolve(__dirname, "../.."), out = __dirname;
const oldPath = path.join(out, "upstream-melee-integration/local-asLoader.swf");
const newPath = path.join(out, "build-integrated-melee-loader/asLoader.swf");
const before = parseSwf(fs.readFileSync(oldPath)), after = parseSwf(fs.readFileSync(newPath));
const oldClasses = new Map(before.classes.map(row => [row.fqn, row]));
const newClasses = new Map(after.classes.map(row => [row.fqn, row]));
const changed = [...new Set([...oldClasses.keys(), ...newClasses.keys()])].sort().filter(name => {
    const a = oldClasses.get(name), b = newClasses.get(name);
    return !a || !b || a.actionSha256 !== b.actionSha256;
});
const sharedPath = "scripts/逻辑/单位函数/单位函数_雾人_兵器搓招指令.as";
const sourceBefore = cp.execFileSync("git", ["show", "68473abd27f1d20b13c04f655770745fb42633ba:" + sharedPath], { cwd: root, windowsHide: true }).toString("utf8").replace(/\r\n/g, "\n");
const sourceAfter = fs.readFileSync(path.join(root, sharedPath), "utf8").replace(/\r\n/g, "\n");
const begin = sourceAfter.indexOf("_root.技能函数.冷兵器攻击搓招 = function():Number {");
if (begin < 0) throw Error("Expected added skill function missing");
const end = sourceAfter.indexOf("\n};", begin) + 4;
const addition = sourceAfter.slice(begin, end);
const existingRootSourceUnchanged = sourceAfter.slice(0, begin) + sourceAfter.slice(end) === sourceBefore;
const report = {
    beforeSha256: before.sha256, afterSha256: after.sha256,
    beforeClasses: before.classes.length, afterClasses: after.classes.length,
    changedClasses: changed, allClassActionsByteIdentical: changed.length === 0,
    existingRootSourceUnchanged, addedFunction: "_root.技能函数.冷兵器攻击搓招",
    addedFunctionSha256: crypto.createHash("sha256").update(addition).digest("hex"),
    classes: after.classes.map(row => ({ name: row.fqn, actionSha256: row.actionSha256, actionBytes: row.actionBytes })),
    boundary: "This is compiled-class identity and narrow source-delta evidence. The C3-bound Headbot fights retain their original loader identity; this comparison is not a claim that those fights ran again on C4. Upstream player assets and input data are separate changes."
};
fs.writeFileSync(path.join(out, "melee-loader-class-equivalence.json"), JSON.stringify(report, null, 2) + "\n", { flag: "wx" });
console.log(JSON.stringify({ beforeClasses: before.classes.length, afterClasses: after.classes.length, changedClasses: changed, existingRootSourceUnchanged }));
if (changed.length || !existingRootSourceUnchanged) process.exitCode = 1;
