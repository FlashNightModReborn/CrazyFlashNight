/*
 * Minimal CSInterface shim for cf7-animate-kit.
 * ============================================
 *
 * Adobe ships a ~2000-line CSInterface.js with the CEP SDK. We only need a
 * sliver of it (evalScript + a couple of host/env accessors), and we refuse to
 * pull a vendored copy over the network at build time. So this file implements
 * just the surface our panel touches, against the same `window.__adobe_cep__`
 * global that Adobe's CEP runtime injects into every panel.
 *
 * If you ever need the full API (color themes, extension lifecycle events,
 * persistence, etc.), drop Adobe's official CSInterface.js in this same folder
 * and update src/lib/cep.d.ts + the import in bridge.ts — the rest of the panel
 * only depends on `evalScript`, `getHostEnvironment`, and `getOSInformation`.
 *
 * Plain ES5/global script on purpose: it is loaded as a classic module by the
 * bundler and mirrors Adobe's distribution form (no build step of its own).
 */

/** @constructor */
function CSInterface() {}

/**
 * Evaluate a JSFL/ExtendScript expression in the host (Animate) VM.
 * @param {string} script  expression to run in the host scripting engine
 * @param {(result: string) => void} [callback]  receives the string result
 *   (or the literal "EvalScript error." sentinel when the host throws).
 */
CSInterface.prototype.evalScript = function (script, callback) {
  if (typeof callback !== 'function') {
    callback = function () {};
  }
  if (
    typeof window === 'undefined' ||
    !window.__adobe_cep__ ||
    typeof window.__adobe_cep__.evalScript !== 'function'
  ) {
    // Outside a CEP host (e.g. plain browser dev preview). Surface Adobe's
    // own error sentinel so the bridge's guard path is exercised in dev too.
    callback('EvalScript error.');
    return;
  }
  window.__adobe_cep__.evalScript(script, callback);
};

/**
 * Host environment info (appName, appVersion, appLocale, ...).
 * Returns null when not running inside CEP.
 * @returns {import('./cep.js').AdobeCepHostEnvironment | null}
 */
CSInterface.prototype.getHostEnvironment = function () {
  if (typeof window === 'undefined' || !window.__adobe_cep__) return null;
  try {
    return JSON.parse(window.__adobe_cep__.getHostEnvironment());
  } catch (e) {
    return null;
  }
};

/**
 * OS string ("Windows ..." / "Mac OS ...").
 * @returns {string}
 */
CSInterface.prototype.getOSInformation = function () {
  if (typeof window === 'undefined' || !window.__adobe_cep__) return 'unknown';
  try {
    return window.__adobe_cep__.getOSInformation();
  } catch (e) {
    return 'unknown';
  }
};

/**
 * True when running inside a real CEP host with the evalScript bridge wired.
 * (Not part of Adobe's API — a convenience for our dev/host detection.)
 * @returns {boolean}
 */
CSInterface.prototype.hasHostBridge = function () {
  return (
    typeof window !== 'undefined' &&
    !!window.__adobe_cep__ &&
    typeof window.__adobe_cep__.evalScript === 'function'
  );
};

export { CSInterface };
export default CSInterface;
