#!/usr/bin/env tsx
import { existsSync, readFileSync, writeFileSync, renameSync, mkdirSync } from "node:fs";
import { dirname, join, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";
import {
  parseItemsDir,
  parseModsDir,
  parseEnemiesDir,
  parseHairstyleFile,
} from "./xml-parsers.js";
import { extractAs2DictConstant } from "./as2-constants.js";
import type { BuildOptions, BuildResult, SaveRepairDict } from "./types.js";

const TOOL_VERSION = "0.1.0";
const SCHEMA_VERSION = 1;

export function build(opts: BuildOptions): BuildResult {
  const root = resolve(opts.projectRoot);
  const outputPath = opts.outputPath ?? join(root, "launcher", "data", "save_repair_dict.json");

  const itemsRes = parseItemsDir(join(root, "data", "items"));
  const modsRes = parseModsDir(join(root, "data", "items", "equipment_mods"));
  const enemiesRes = parseEnemiesDir(join(root, "data", "enemy_properties"));
  const hairFile = join(root, "data", "items", "hairstyle.xml");
  const hairstyles = parseHairstyleFile(hairFile);

  const saveManagerPath = join(
    root,
    "scripts",
    "类定义",
    "org",
    "flashNight",
    "neur",
    "Server",
    "SaveManager.as",
  );
  const skills = extractAs2DictConstant(saveManagerPath, "REPAIR_DICT_SKILLS");
  const taskChains = extractAs2DictConstant(saveManagerPath, "REPAIR_DICT_TASK_CHAINS");
  const stages = extractAs2DictConstant(saveManagerPath, "REPAIR_DICT_STAGES");

  const sourceFiles = [
    ...itemsRes.sourceFiles,
    ...modsRes.sourceFiles,
    ...enemiesRes.sourceFiles,
    hairFile,
    saveManagerPath,
  ]
    .map((f) => relative(root, f).replace(/\\/g, "/"))
    .sort();

  const dict: SaveRepairDict = {
    schemaVersion: SCHEMA_VERSION,
    generated: {
      // Use stable timestamp when verify mode is on so verification doesn't churn on time alone.
      // Real builds get a real timestamp; verify mode replaces it before comparison (see verify path).
      at: new Date().toISOString(),
      tool: TOOL_VERSION,
      sourceFiles,
    },
    items: itemsRes.names,
    mods: modsRes.names,
    enemies: enemiesRes.names,
    hairstyles,
    skills: dedupeSorted(skills),
    taskChains: dedupeSorted(taskChains),
    stages: dedupeSorted(stages),
  };

  if (opts.verify) {
    if (!existsSync(outputPath)) {
      return {
        dict,
        verified: false,
        diff: `output file does not exist: ${outputPath}`,
      };
    }
    const existing = JSON.parse(readFileSync(outputPath, "utf-8")) as SaveRepairDict;
    // Ignore generated.at when comparing — only structural content matters.
    const a = stripVolatile(existing);
    const b = stripVolatile(dict);
    const aJson = JSON.stringify(a);
    const bJson = JSON.stringify(b);
    if (aJson === bJson) {
      return { dict, verified: true };
    }
    return {
      dict,
      verified: false,
      diff: summarizeDiff(a, b),
    };
  }

  // Atomic write: tmp + rename
  mkdirSync(dirname(outputPath), { recursive: true });
  const tmp = outputPath + ".tmp";
  const json = JSON.stringify(dict, null, 2) + "\n";
  writeFileSync(tmp, json, { encoding: "utf8" });
  renameSync(tmp, outputPath);
  return { dict };
}

function dedupeSorted(arr: string[]): string[] {
  return [...new Set(arr.filter((s) => s && !s.includes("�")))].sort((a, b) => a.localeCompare(b, "zh"));
}

function stripVolatile(d: SaveRepairDict): Omit<SaveRepairDict, "generated"> & { generated: { tool: string; sourceFiles: string[] } } {
  return {
    ...d,
    generated: {
      tool: d.generated.tool,
      sourceFiles: d.generated.sourceFiles,
    },
  };
}

function summarizeDiff(a: ReturnType<typeof stripVolatile>, b: ReturnType<typeof stripVolatile>): string {
  const lines: string[] = [];
  for (const key of ["items", "mods", "enemies", "hairstyles", "skills", "taskChains", "stages"] as const) {
    const setA = new Set(a[key]);
    const setB = new Set(b[key]);
    const added = [...setB].filter((x) => !setA.has(x));
    const removed = [...setA].filter((x) => !setB.has(x));
    if (added.length || removed.length) {
      lines.push(`  ${key}: +${added.length} -${removed.length}`);
      for (const x of added.slice(0, 5)) lines.push(`    +"${x}"`);
      for (const x of removed.slice(0, 5)) lines.push(`    -"${x}"`);
      if (added.length + removed.length > 10) lines.push(`    ... (truncated)`);
    }
  }
  return lines.length > 0 ? lines.join("\n") : "(no field-level diff; check sourceFiles)";
}

// CLI entry
function main(): void {
  const args = process.argv.slice(2);
  const verify = args.includes("--verify");
  const projectRootIdx = args.indexOf("--project-root");
  let projectRoot: string;
  if (projectRootIdx >= 0 && args[projectRootIdx + 1]) {
    projectRoot = args[projectRootIdx + 1];
  } else {
    // Default: walk up from this script to find the project root (containing data/ + scripts/ + launcher/).
    const here = dirname(fileURLToPath(import.meta.url));
    // src/ → tools/cf7-save-repair-dict-build/ → tools/ → projectRoot
    projectRoot = resolve(here, "..", "..", "..");
  }

  const result = build({ projectRoot, verify });
  if (verify) {
    if (result.verified) {
      console.log("[dict-build] verified: save_repair_dict.json is up-to-date");
      process.exit(0);
    } else {
      console.error("[dict-build] VERIFY FAILED: regenerate save_repair_dict.json");
      console.error(result.diff ?? "(no diff available)");
      process.exit(1);
    }
  }
  console.log(`[dict-build] wrote ${join(projectRoot, "launcher", "data", "save_repair_dict.json")}`);
  console.log(
    `  items=${result.dict.items.length}`
    + `, mods=${result.dict.mods.length}`
    + `, enemies=${result.dict.enemies.length}`
    + `, hairstyles=${result.dict.hairstyles.length}`
    + `, skills=${result.dict.skills.length}`
    + `, taskChains=${result.dict.taskChains.length}`
    + `, stages=${result.dict.stages.length}`,
  );
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, "/")}` || process.argv[1].endsWith("build.ts")) {
  main();
}
