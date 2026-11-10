"use strict";
// Keep this list equal to Contracts/GameQualificationInput.cs. These are test
// gestures, not arbitrary native key chords. The Host separately admits only
// the candidate-bound qualification slots and the Launcher surface.
const GESTURES = Object.freeze(["w","a","s","d","j","k","r","1","2","3","4","5","space",
  "shift+a","shift+d","a+j","d+j","w+j","s+j","shift+a+j","shift+d+j","a+r","d+r"]);
function isGesture(token) {
  return typeof token === "string" && token.startsWith("q205:")
    && GESTURES.includes(token.slice(5));
}
module.exports = {GESTURES, isGesture};
