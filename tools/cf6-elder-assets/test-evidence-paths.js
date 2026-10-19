"use strict";
const assert = require("assert"), path = require("path"), vm = require("vm"), fs = require("fs"), crypto = require("crypto");
const {validateOutput} = require("./evidence-paths");
const root = path.resolve("/r"), prefix = "tools/cf6-elder-assets/e/x/";
validateOutput(path.join(root, prefix + "a".repeat(179-prefix.length)), root);
assert.throws(() => validateOutput(path.join(root, prefix + "a".repeat(180-prefix.length)), root));
validateOutput(path.join(root, prefix + "a".repeat(177-prefix.length) + "😀"), root);
assert.throws(() => validateOutput(path.join(root, prefix + "a".repeat(178-prefix.length) + "😀"), root));
for (const name of ["20261017-calibration", "20261018-loader-size-followup"])
  assert.throws(() => validateOutput(path.join(root, "tools/cf6-elder-assets/evidence", name, "new.json"), root));
const anchor = path.parse(root).root;
const deepRoot = anchor + "r".repeat(60-anchor.length);
validateOutput(path.join(deepRoot,prefix+"a".repeat(179-prefix.length)),deepRoot);
assert.throws(() => validateOutput(path.join(deepRoot+"r",prefix+"a".repeat(179-prefix.length)),deepRoot+"r"));
// Exercise the real current planner with read-only dependencies stubbed.
let writes=0;
const moduleObject={exports:{}};
const code=fs.readFileSync(path.join(__dirname,"arena-plan.js"),"utf8");
const stubFs={readFileSync:()=>Buffer.from("source"),mkdirSync:()=>{writes++;},writeFileSync:()=>{writes++;}};
const stubCp={execFileSync:(_,args)=>args[0]==="ls-files"?Buffer.from(""):"a".repeat(40)};
const context={module:moduleObject,exports:moduleObject.exports,__dirname,process:{env:{APPDATA:"/appdata"}},Buffer,console,
 require:(name)=>name==="fs"?stubFs:name==="path"?path:name==="child_process"?stubCp:name==="crypto"?crypto:
 name==="./evidence-paths"?{validateOutput}:name.includes("arena-calibration-core")?{normalizeManifest:x=>x}:
 name.includes("runtime-process-identity")?{resolveExpectedRuntimeIdentity:()=>({runtimeMode:"isolated_candidate",coreSha256:"x",buildIdentity:"x",payloadClosure:"x"})}:(()=>{throw Error(name);})()};
vm.runInNewContext(code,context,{filename:"arena-plan.js"});
const repo=path.resolve(__dirname,"../..");
assert.throws(()=>moduleObject.exports.createPlan({experimentId:"short",variant:"two-phase",outputDirectory:path.join(repo,"tmp","x".repeat(180)),projectRoot:"/worker",candidateRoot:"/worker/tmp/runtime-candidates/v2/x",seedPath:"/seed"}),/budget/);
assert.strictEqual(writes,0,"over-budget output must fail before any mkdir or write");
console.log("Evidence path JavaScript checks PASS: boundaries, Unicode, retired roots, real planner no-write rejection.");
