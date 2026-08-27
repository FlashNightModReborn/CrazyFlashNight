"use strict";

const {
  sha256OfValue,
} = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function logistic(value) {
  if (value >= 0) {
    const inverse = Math.exp(-value);
    return 1 / (1 + inverse);
  }
  const exponent = Math.exp(value);
  return exponent / (1 + exponent);
}

function rosterIdentity(testCase, side) {
  const roster = side === "blue" ? testCase.blueRoster : testCase.redRoster;
  const formation = side === "blue" ? testCase.blueFormation : testCase.redFormation;
  const semantic = { roster, formation, formationSpacing: testCase.formationSpacing };
  return `roster-${sha256OfValue(semantic).slice(7, 23)}`;
}

function rosterLabel(testCase, side) {
  const roster = side === "blue" ? testCase.blueRoster : testCase.redRoster;
  const counts = new Map();
  roster.forEach((entry) => {
    const key = `${entry.type}@${entry.level}${entry.parameters ? "+payload" : ""}`;
    counts.set(key, (counts.get(key) || 0) + 1);
  });
  return Array.from(counts.entries()).map(([key, count]) => `${key}x${count}`).join(" + ").slice(0, 240);
}

function connectedComponents(nodeCount, observations) {
  const adjacency = Array.from({ length: nodeCount }, () => new Set());
  observations.forEach((entry) => {
    adjacency[entry.blue].add(entry.red);
    adjacency[entry.red].add(entry.blue);
  });
  const components = Array(nodeCount).fill(-1);
  let componentCount = 0;
  for (let start = 0; start < nodeCount; start += 1) {
    if (components[start] !== -1) continue;
    const queue = [start];
    components[start] = componentCount;
    for (let cursor = 0; cursor < queue.length; cursor += 1) {
      const node = queue[cursor];
      adjacency[node].forEach((next) => {
        if (components[next] === -1) {
          components[next] = componentCount;
          queue.push(next);
        }
      });
    }
    componentCount += 1;
  }
  return { components, componentCount };
}

function fitBradleyTerry(nodeCount, observations, options) {
  options = options || {};
  const strength = Array(nodeCount).fill(0);
  let sideBias = 0;
  const lambda = options.regularization || 0.1;
  const iterations = options.iterations || 600;
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const gradient = Array(nodeCount).fill(0);
    const curvature = Array(nodeCount).fill(lambda);
    let sideGradient = 0;
    let sideCurvature = lambda;
    observations.forEach((entry) => {
      const probability = logistic(strength[entry.blue] - strength[entry.red] + sideBias);
      const residual = entry.outcome - probability;
      const weight = Math.max(1e-6, probability * (1 - probability));
      gradient[entry.blue] += residual;
      gradient[entry.red] -= residual;
      curvature[entry.blue] += weight;
      curvature[entry.red] += weight;
      sideGradient += residual;
      sideCurvature += weight;
    });
    let maximumStep = 0;
    for (let index = 0; index < nodeCount; index += 1) {
      gradient[index] -= lambda * strength[index];
      const step = Math.max(-0.5, Math.min(0.5, gradient[index] / curvature[index])) * 0.5;
      strength[index] += step;
      maximumStep = Math.max(maximumStep, Math.abs(step));
    }
    sideGradient -= lambda * sideBias;
    const sideStep = Math.max(-0.5, Math.min(0.5, sideGradient / sideCurvature)) * 0.5;
    sideBias += sideStep;
    maximumStep = Math.max(maximumStep, Math.abs(sideStep));
    const mean = strength.reduce((sum, value) => sum + value, 0) / Math.max(1, strength.length);
    for (let index = 0; index < nodeCount; index += 1) strength[index] -= mean;
    if (maximumStep < 1e-8) break;
  }
  const information = Array(nodeCount).fill(lambda);
  observations.forEach((entry) => {
    const probability = logistic(strength[entry.blue] - strength[entry.red] + sideBias);
    const weight = Math.max(1e-6, probability * (1 - probability));
    information[entry.blue] += weight;
    information[entry.red] += weight;
  });
  return {
    strength,
    sideBias,
    standardErrors: information.map((value) => Math.sqrt(1 / value)),
  };
}

function aggregateDirectedPairs(observations) {
  const pairs = new Map();
  observations.forEach((entry) => {
    const key = `${entry.blue}|${entry.red}`;
    if (!pairs.has(key)) pairs.set(key, { wins: 0, samples: 0 });
    const pair = pairs.get(key);
    pair.wins += entry.outcome;
    pair.samples += 1;
  });
  return pairs;
}

function detectNonTransitiveCycles(nodeCount, observations, nodeIds) {
  const directed = aggregateDirectedPairs(observations);
  function rate(left, right) {
    const forward = directed.get(`${left}|${right}`) || { wins: 0, samples: 0 };
    const reverse = directed.get(`${right}|${left}`) || { wins: 0, samples: 0 };
    const samples = forward.samples + reverse.samples;
    if (samples < 3) return null;
    const wins = forward.wins + (reverse.samples - reverse.wins);
    return wins / samples;
  }
  const cycles = [];
  for (let a = 0; a < nodeCount; a += 1) {
    for (let b = a + 1; b < nodeCount; b += 1) {
      for (let c = b + 1; c < nodeCount; c += 1) {
        const ab = rate(a, b);
        const bc = rate(b, c);
        const ca = rate(c, a);
        if (ab !== null && bc !== null && ca !== null && ab > 0.6 && bc > 0.6 && ca > 0.6) {
          cycles.push({ nodes: [nodeIds[a], nodeIds[b], nodeIds[c]], rates: [ab, bc, ca], disposition: "context_dependent" });
        }
        const ac = rate(a, c);
        const cb = rate(c, b);
        const ba = rate(b, a);
        if (ac !== null && cb !== null && ba !== null && ac > 0.6 && cb > 0.6 && ba > 0.6) {
          cycles.push({ nodes: [nodeIds[a], nodeIds[c], nodeIds[b]], rates: [ac, cb, ba], disposition: "context_dependent" });
        }
      }
    }
  }
  return cycles;
}

function analyzePairedStrength(shards, options) {
  options = options || {};
  const nodeMap = new Map();
  const nodes = [];
  const observations = [];
  const excluded = [];
  const matchupAudit = new Map();
  const inputRefs = [];
  let draws = 0;

  function nodeIndex(testCase, side) {
    const nodeId = rosterIdentity(testCase, side);
    if (!nodeMap.has(nodeId)) {
      nodeMap.set(nodeId, nodes.length);
      nodes.push({ nodeId, label: rosterLabel(testCase, side), samples: 0 });
    }
    return nodeMap.get(nodeId);
  }

  shards.forEach((shard) => {
    assertSchemaInstance("arena-calibration.case-manifest.v1", shard.manifest, "paired strength manifest");
    if (shard.inputRef) inputRefs.push(shard.inputRef);
    const cases = new Map(shard.manifest.cases.map((entry) => [entry.caseId, entry]));
    (shard.rows || []).forEach((row) => {
      assertSchemaInstance("arena-calibration.result.v1", row, "paired strength result");
      const testCase = cases.get(row.caseId);
      if (!testCase || row.caseHash !== testCase.caseHash) throw new Error(`result does not bind to manifest: ${row.runId}`);
      const blue = nodeIndex(testCase, "blue");
      const red = nodeIndex(testCase, "red");
      const unordered = [nodes[blue].nodeId, nodes[red].nodeId].sort().join("|");
      if (!matchupAudit.has(unordered)) matchupAudit.set(unordered, { matchupId: unordered, orientations: new Set(), rows: 0, timeouts: 0, errors: 0 });
      const audit = matchupAudit.get(unordered);
      audit.orientations.add(nodes[blue].nodeId);
      audit.rows += 1;
      if (row.status === "timeout") audit.timeouts += 1;
      if (!["finished", "timeout"].includes(row.status)) audit.errors += 1;
      if (row.status !== "finished") {
        excluded.push({ runId: row.runId, status: row.status, matchupId: unordered });
        return;
      }
      let outcome;
      if (row.winner === "blue") outcome = 1;
      else if (row.winner === "red") outcome = 0;
      else {
        outcome = 0.5;
        draws += 1;
      }
      observations.push({ blue, red, outcome, runId: row.runId });
      nodes[blue].samples += 1;
      nodes[red].samples += 1;
    });
  });

  const fit = fitBradleyTerry(nodes.length, observations, options);
  const connectivity = connectedComponents(nodes.length, observations);
  const reportNodes = nodes.map((node, index) => ({
    nodeId: node.nodeId,
    label: node.label,
    strength: fit.strength[index],
    lower95: fit.strength[index] - 1.96 * fit.standardErrors[index],
    upper95: fit.strength[index] + 1.96 * fit.standardErrors[index],
    samples: node.samples,
    component: connectivity.components[index],
  }));

  const bridgeSuggestions = [];
  if (connectivity.componentCount > 1) {
    const byComponent = new Map();
    reportNodes.forEach((node) => {
      if (!byComponent.has(node.component)) byComponent.set(node.component, []);
      byComponent.get(node.component).push(node);
    });
    const rootComponent = byComponent.get(0);
    for (let component = 1; component < connectivity.componentCount; component += 1) {
      const candidates = [];
      rootComponent.forEach((left) => byComponent.get(component).forEach((right) => {
        candidates.push({ left, right, distance: Math.abs(left.strength - right.strength) });
      }));
      candidates.sort((left, right) => left.distance - right.distance || left.left.nodeId.localeCompare(right.left.nodeId));
      const best = candidates[0];
      bridgeSuggestions.push({
        leftNodeId: best.left.nodeId,
        rightNodeId: best.right.nodeId,
        reason: "disconnected_component_bridge",
        expectedInformationGain: 1 / (1 + best.distance),
      });
    }
  }

  const nodeIds = nodes.map((entry) => entry.nodeId);
  const report = {
    schema: "arena-calibration.paired-strength-report.v1",
    reportId: options.reportId || "paired-strength-report",
    model: "regularized-bradley-terry-draw-half-v1",
    cohortId: options.cohortId,
    inputRefs: Array.from(new Set(inputRefs)).sort(),
    eligibleResults: observations.length,
    excludedResults: excluded.length,
    draws,
    sideBias: fit.sideBias,
    nodes: reportNodes,
    componentCount: connectivity.componentCount,
    bridgeSuggestions,
    nonTransitiveCycles: detectNonTransitiveCycles(nodes.length, observations, nodeIds),
    createdAt: options.createdAt || new Date().toISOString(),
    reportHash: "",
  };
  report.reportHash = sha256OfValue(withoutHash(report, "reportHash"));
  assertSchemaInstance(report.schema, report, "paired strength report");

  const sideSwapReview = Array.from(matchupAudit.values()).map((entry) => ({
    matchupId: entry.matchupId,
    samples: entry.rows,
    orientations: entry.orientations.size,
    sideSwapReviewed: entry.orientations.size >= 2,
    timeoutRate: entry.rows > 0 ? entry.timeouts / entry.rows : 0,
    errorCount: entry.errors,
  }));
  const actions = bridgeSuggestions.map((entry, index) => ({
    action: "create_bridge",
    actionId: `bridge-${index + 1}`,
    leftNodeId: entry.leftNodeId,
    rightNodeId: entry.rightNodeId,
    reason: entry.reason,
  }));
  sideSwapReview.filter((entry) => !entry.sideSwapReviewed).forEach((entry, index) => {
    actions.push({ action: "create_side_swap", actionId: `side-swap-${index + 1}`, matchupId: entry.matchupId, reason: "missing_orientation" });
  });
  const anomalyDisposition = sideSwapReview
    .filter((entry) => entry.timeoutRate > 0.05 || entry.errorCount > 0)
    .map((entry) => ({
      matchupId: entry.matchupId,
      disposition: entry.errorCount > 0 ? "quarantined" : "stability_investigate",
      timeoutRate: entry.timeoutRate,
      errorCount: entry.errorCount,
    }));
  report.nonTransitiveCycles.forEach((cycle) => anomalyDisposition.push({
    matchupId: cycle.nodes.join("|"),
    disposition: "context_dependent",
    timeoutRate: 0,
    errorCount: 0,
  }));
  const plan = {
    schema: "arena-calibration.active-sampling-plan.v1",
    planId: options.planId || "active-sampling-plan",
    strengthReportHash: report.reportHash,
    actions,
    sideSwapReview,
    anomalyDisposition,
    createdAt: options.createdAt || new Date().toISOString(),
    planHash: "",
  };
  plan.planHash = sha256OfValue(withoutHash(plan, "planHash"));
  assertSchemaInstance(plan.schema, plan, "active sampling plan");
  return { report, plan, excluded };
}

module.exports = {
  analyzePairedStrength,
  connectedComponents,
  fitBradleyTerry,
  rosterIdentity,
};
