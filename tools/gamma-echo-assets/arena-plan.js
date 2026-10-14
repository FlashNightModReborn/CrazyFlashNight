"use strict";

// Plan authoring only. Execution remains with the existing bounded two-Worker runner.
const fs = require("fs");
const path = require("path");
const child = require("child_process");
const { normalizeManifest } = require("../arena-calibration/lib/arena-calibration-core");

function writeNew(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", { flag: "wx" });
}

function main() {
  const configFile = process.argv[2];
  if (!configFile) throw Error("Usage: node arena-plan.js <plan-input.json>");
  const config = JSON.parse(fs.readFileSync(configFile, "utf8"));
  const candidateMode = config.candidateMode || "enhanced";
  if (!["enhanced", "default"].includes(candidateMode)) throw Error("Unsupported candidate mode");
  if (config.compareLifeSteal && (config.compareToNoah || candidateMode !== "default")) throw Error("Life-steal comparison requires identical default AI and same Tyrant unit");
  const comparison = config.compareLifeSteal ? "gamma-echo-lifesteal-ab" : config.compareToNoah ? "gamma-echo-vs-noah"
    : candidateMode === "default" ? "gamma-echo-default-parity" : "gamma-echo-ai-ab";
  const root = path.resolve(__dirname, "../..");
  const native = JSON.parse(fs.readFileSync(path.join(__dirname, "native-manifest.json"), "utf8"));
  const balance = JSON.parse(fs.readFileSync(path.join(__dirname, "balance-inputs.json"), "utf8"));
  const buildCommit = child.execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", windowsHide: true }).trim();
  if (!Array.isArray(config.workers) || config.workers.length !== 2) throw Error("Two explicit owned Workers required");
  const casesPerJob = [];
  const groups = (config.levels || [30]).map(level => {
  const jobs = config.workers.map((worker, index) => {
    const variantIndex = config.compareLifeSteal ? 1 : index;
    const variant = native.variants[variantIndex], row = balance.rows[variantIndex];
    const type = "兵种" + balance.unitIds[variantIndex];
    const entry = (mode, level, isCandidate) => {
      const parameters = mode === "default" ? {} : { 克隆兽AI模式: mode };
      if (config.compareLifeSteal && !isCandidate) parameters.克隆兽吸血模式 = "off";
      return { type, level, sourceId: `unit-${balance.unitIds[variantIndex]}-${mode}${config.compareLifeSteal ? (isCandidate ? "-ls5" : "-ls0") : ""}`,
        ...(Object.keys(parameters).length ? { parameters } : {}) };
    };
    const cases = [];
      for (const enhancedSide of ["blue", "red"]) {
        const baseline = { type: "兵种372", level, sourceId: "unit-372-noah" };
        cases.push({
          caseId: `unit-${balance.unitIds[variantIndex]}-lv${level}-${candidateMode}-${enhancedSide}`,
          blueRoster: [config.compareToNoah && enhancedSide !== "blue" ? baseline : entry(config.compareLifeSteal || enhancedSide === "blue" ? candidateMode : "baseline", level, enhancedSide === "blue")],
          redRoster: [config.compareToNoah && enhancedSide !== "red" ? baseline : entry(config.compareLifeSteal || enhancedSide === "red" ? candidateMode : "baseline", level, enhancedSide === "red")],
          repeat: config.repeat || 2, timeoutFrames: config.timeoutFrames || 2400,
          tags: ["gamma-echo", comparison, variant.variant, `${candidateMode}-${enhancedSide}`, `level-${level}`],
          plannerReason: config.compareLifeSteal ? "两侧均为同等级暴君克隆兽、相同默认 AI 与面板，只对基准侧关闭固有 5% 吸血；交换红蓝，实际 startMaxHp 须相等。" : config.compareToNoah ? "与原诺亚克隆兽同等级、交换红蓝；包含阶段面板差异，单列为整体验证，不用于估计纯 AI 收益。" : "同一兵种、等级和 XML 面板，仅切换私有 AI；交换红蓝；普通怪物模板不套用人形单位的蓝方生命修正，结果须核对双方实际 startMaxHp 相等。",
          authorityContext: { experiment: comparison, candidateMode, enhancedSide, variant: variant.variant,
            sourceStage: variant.stage, sourceSwf: "flashswf/arts/new/Codex专用素材.swf", aiRevision: config.aiRevision || 1,
            panelPolicy: config.compareToNoah ? "native XML panels; candidate stage 8/9 versus Noah stage 6" : "unchanged XML panel on both sides; require equal actual startMaxHp",
            combatPolicy: "Noah attack frames, damage multiplier and segment counts unchanged" },
        });
      }
    const manifest = normalizeManifest({ batchId: `${config.experimentId}-${worker.workerId}-l${level}`, buildCommit,
      planner: { name: "gamma-echo-mirror-ai-ab", version: config.aiRevision || 1 },
      repeat: config.repeat || 2, timeoutFrames: config.timeoutFrames || 2400, cases });
    const runs = manifest.cases.reduce((n, c) => n + c.repeat, 0);
    if (runs > 25) throw Error("Split the bounded shard at 25 runs");
    const maximumCombatMs = manifest.cases.reduce((n, c) => n + c.repeat * c.timeoutFrames * 1000 / 30, 0);
    if (maximumCombatMs > 780000) throw Error("Split the shard: worst-case combat must leave two minutes within the fifteen-minute Worker limit");
    const manifestPath = path.join(root, "tmp/monster-reskin/gamma-echo-integration-20261014", config.experimentId, `${worker.workerId}-lv${level}-manifest.json`);
    writeNew(manifestPath, manifest);
    casesPerJob.push(runs);
    return { jobId: `${worker.workerId}-lv${level}`, workerId: worker.workerId, manifestPath, batchTimeoutMs: 900000 };
  });
  return { groupId: `level-${level}`, condition: comparison, mode: "parallel", visibility: "unknown", jobs };
  });
  const tracked = child.execFileSync("git", ["ls-files", "-z", "--", "flashswf", "sound", "sounds", "music", "font", "fonts"],
    { cwd: root, windowsHide: true, maxBuffer: 32 * 1024 * 1024 }).toString("utf8").split("\0");
  const resources = tracked.filter(p => /^flashswf\//.test(p) && /\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(p));
  for (const p of tracked) if (/^(sounds?|music|fonts?)\//i.test(p)) resources.push(p);
  const plan = { schema: "arena-worker.experiment-plan.v1", experimentId: config.experimentId,
    workers: config.workers.map(worker => ({ workerId: worker.workerId, projectRoot: worker.projectRoot,
      candidateRoot: worker.candidateRoot || config.candidateRoot, seedPath: config.seedPath, resourcePaths: [...new Set(resources)] })),
    sharedObjectsRoot: path.join(process.env.APPDATA, "Macromedia", "Flash Player", "#SharedObjects"),
    saveRoots: [path.join(root, "saves"), ...config.workers.map(worker => path.join(worker.projectRoot, "saves"))],
    groups, comparisons: [] };
  const planPath = path.join(root, "tmp/monster-reskin/gamma-echo-integration-20261014", config.experimentId, "experiment-plan.json");
  writeNew(planPath, plan);
  console.log(JSON.stringify({ planPath, runsPerWorker: casesPerJob, resourcePaths: resources.length }));
}

if (require.main === module) main();
