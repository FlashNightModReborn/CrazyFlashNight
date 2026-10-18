"use strict";
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert/strict');
const {parseSwf}=require('../../tools/swf-metadata');
const root=process.cwd(),out=__dirname;
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const repair=read(path.join(out,'r20-native-fixture-repair.json'));
const allowed=new Set(repair.changes.map(r=>r.path));
const forbiddenClasses=['org.flashNight.arki.unit.Action.Melee.Cf6ElderAssetTest','org.flashNight.arki.unit.Action.Melee.Cf6ElderCombatEffectsTest'];
const suites=[];
for(const name of ['audio','player-aim','elder-render']){
 const base=path.join(out,'native-r20-range-support',name);
 const result=read(path.join(base,'result.json'));assert.equal(result.exitCode,0);assert(result.bindingsUnchanged);
 const bindings=read(path.join(base,'bindings-after.json'));
 const differences=bindings.filter(b=>hash(path.join(root,b.path))!==b.sha256.toLowerCase());
 assert.deepEqual(new Set(differences.map(b=>b.path)),allowed);
 const swf=parseSwf(fs.readFileSync(path.join(base,'TestLoader.swf')));
 assert(!swf.classes.some(c=>forbiddenClasses.includes(c.fqn)));
 suites.push({name,testSwfSha256:swf.sha256,compiledClasses:swf.classes.length,
  unchangedCurrentBindings:bindings.length-differences.length,
  changedBindingsAbsentFromCompiledTest: differences.map(b=>b.path),
  forbiddenClassesAbsent:forbiddenClasses,qualified:true});
}
fs.writeFileSync(path.join(out,'r20-unaffected-native-suites.json'),JSON.stringify({qualified:true,suites,
 boundary:'The first-cohort audio, player and rendering executions retain their actual frozen identities. Only two unrelated test fixture files changed afterwards; neither class is embedded in these test SWFs, and all their other bound inputs match current bytes.'},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({qualified:true,suites:suites.map(s=>({name:s.name,compiledClasses:s.compiledClasses,unchangedCurrentBindings:s.unchangedCurrentBindings}))}));
