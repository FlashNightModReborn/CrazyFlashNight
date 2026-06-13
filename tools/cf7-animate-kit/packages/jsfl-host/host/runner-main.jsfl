// runner-main.jsfl — headless cf7ak job runner
// =============================================
// Mirrors the repo's proven CS6 automation pattern (scripts/compile_action.jsfl):
// config/job file in -> do work -> result file + done/error MARKER out, so a
// terminal (PowerShell/Node) can trigger Animate headlessly and read JSON back.
//
// This file ASSUMES the cf7ak host functions are already defined. The build
// step (scripts/build-runner.mjs) concatenates host/index.jsfl + this file into
// host/cf7ak-runner.jsfl, which is the single self-contained script you pass to
// Animate (Animate.exe cf7ak-runner.jsfl) or run from a scheduled task loader.
//
// Job/result files live in <Animate Configuration>/Commands/cf7ak/ so both the
// CLI (an-host resolves it from the discovered Commands dir) and JSFL
// (fl.configURI + "Commands/cf7ak/") agree on the path with no extra config.

function cf7akRunnerMain() {
  var base = fl.configURI + "Commands/cf7ak/";
  var jobURI = base + "cf7ak-job.json";
  var resultURI = base + "cf7ak-result.json";
  var doneURI = base + "cf7ak-done.marker";
  var errURI = base + "cf7ak-error.marker";

  if (!FLfile.exists(base)) FLfile.createFolder(base);
  // Clear stale markers first so freshness on the reader side is unambiguous.
  if (FLfile.exists(doneURI)) FLfile.remove(doneURI);
  if (FLfile.exists(errURI)) FLfile.remove(errURI);
  if (FLfile.exists(resultURI)) FLfile.remove(resultURI);

  try {
    if (!FLfile.exists(jobURI)) {
      FLfile.write(errURI, "no job file: " + jobURI);
      return;
    }
    var raw = FLfile.read(jobURI);
    var job = (typeof JSON !== "undefined" && JSON.parse) ? JSON.parse(raw) : eval("(" + raw + ")");
    var fn = job.fn;
    var argJson = "";
    if (job.args !== null && job.args !== undefined) {
      argJson = (typeof JSON !== "undefined") ? JSON.stringify(job.args) : "";
    }
    if (typeof cf7ak === "undefined") {
      FLfile.write(errURI, "cf7ak host not loaded (run cf7ak-runner.jsfl, not runner-main.jsfl)");
      return;
    }
    var resultStr = cf7ak(fn, argJson); // returns a JSON string { ok, data|error }
    FLfile.write(resultURI, resultStr);
    FLfile.write(doneURI, "ok");
  } catch (e) {
    FLfile.write(errURI, String(e));
  }
}

cf7akRunnerMain();
