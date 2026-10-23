'use strict';
// Executes the finite arithmetic/state subset of the real AS2 source in Node.
// This is reference-model evidence, not AS2 compilation or AVM1 verification.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const here = __dirname;
const context = vm.createContext({trace: line => output.push(line)});
const output = [];
context.org = {flashNight: {arki: {scene: {}}}};
for (const name of ['Cf6TraversalRules', 'Cf6ElevatorRules', 'Cf6VehicleRules', 'Cf6SceneCompletionTest']) {
  let source = fs.readFileSync(path.join(here, name+'.as.txt'), 'utf8');
  const exports = [...source.matchAll(/public static function (\w+)/g)].map(m => m[1]);
  source = source.replace(/^import .*;\s*$/gm, '')
    .replace(/class org\.flashNight\.arki\.scene\.\w+\s*\{/, '(function(){')
    .replace(/\b(?:public|private) static function /g, 'function ')
    .replace(/\bprivate static var /g, 'var ')
    .replace(/:\s*(?:Number|String|Boolean|Object|Array|Void)\b/g, '');
  source = source.replace(/}\s*$/, 'return {'+exports.join(',')+'};})()');
  const value = vm.runInContext(source, context, {filename: name+'.reference.js'});
  context[name] = value;
  context.org.flashNight.arki.scene[name] = value;
}
vm.runInContext('Cf6SceneCompletionTest.runAllTests()', context);
assert(output.includes('Cf6SceneCompletionTest Tests Failed: 0'), output.join('\n'));
const count = Number(output.find(s => s.startsWith('Cf6SceneCompletionTest Tests Passed: ')).split(': ')[1]);
assert.equal(count, 51, 'unexpected native-suite/reference scenario count');
const plan = JSON.parse(fs.readFileSync(path.join(here,'completion-plan.json'),'utf8'));
context.planJSON = JSON.stringify(plan);
vm.runInContext(`
var p=JSON.parse(planJSON), owner={};
for(var i=0;i<p.traversals.length;i++) {
  var t=Cf6TraversalRules.create(p.traversals[i],owner);
  if(t==null) throw Error('actual generated path rejected');
  for(var f=0;f<p.traversals[i].durationFrames;f++) Cf6TraversalRules.advance(t,owner,false,true,true);
  if(!Cf6TraversalRules.takeCompletion(t,owner)) throw Error('actual path did not terminate');
}
`, context);
console.log(JSON.stringify({state:'reference_model_passed', scenarios:count,
  authoredTrajectories:plan.traversals.length, limitation:'Node arithmetic/source model only; CS6/AVM1 not run'}));
