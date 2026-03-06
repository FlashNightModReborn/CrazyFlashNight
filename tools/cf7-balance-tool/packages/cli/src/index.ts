#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

import {
  applyXmlBatchUpdates,
  discoverXmlFiles,
  loadProjectContext,
  loadXmlDocument,
  previewXmlBatchUpdates,
  runXmlRoundtripCheck,
  scanProjectFields
} from "@cf7-balance-tool/xml-io";
import type { XmlBatchOptions, XmlBatchUpdate } from "@cf7-balance-tool/xml-io";

interface CliOptions {
  attribute?: string;
  file?: string;
  inPlace: boolean;
  input?: string;
  output?: string;
  outputDir?: string;
  path?: string;
  project?: string;
  value?: string;
}

interface BatchCommandContext {
  inputPath: string;
  projectConfigPath: string;
  projectRoot: string;
  updates: XmlBatchUpdate[];
  batchOptions: XmlBatchOptions;
}

function main(): void {
  const args = process.argv.slice(2);
  const [group, action] = args;

  if (group === "project" && action === "scan") {
    runProjectScan(args.slice(2));
    return;
  }

  if (group === "project" && action === "fields") {
    runFieldScan(args.slice(2));
    return;
  }

  if (group === "project" && action === "roundtrip-check") {
    runProjectRoundtripCheck(args.slice(2));
    return;
  }

  if (group === "project" && action === "batch-preview") {
    runProjectBatchPreview(args.slice(2));
    return;
  }

  if (group === "project" && action === "batch-set") {
    runProjectBatchSet(args.slice(2));
    return;
  }

  if (group === "xml" && action === "get") {
    runXmlGet(args.slice(2));
    return;
  }

  if (group === "xml" && action === "set") {
    runXmlSet(args.slice(2));
    return;
  }

  printHelp();
  process.exitCode = 1;
}

function runProjectScan(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const files = discoverXmlFiles(projectConfigPath);

  emitJson(
    {
      projectConfigPath,
      totals: {
        files: files.length
      },
      files
    },
    options.output
  );
}

function runFieldScan(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const report = scanProjectFields(projectConfigPath);

  emitJson(report, options.output);
}

function runProjectRoundtripCheck(args: string[]): void {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const files = discoverXmlFiles(projectConfigPath);
  const report = runXmlRoundtripCheck(files.map((file) => file.absolutePath));

  emitJson(
    {
      projectConfigPath,
      ...report
    },
    options.output
  );
}

function runProjectBatchPreview(args: string[]): void {
  const context = resolveBatchCommandContext(args);
  const result = previewXmlBatchUpdates(context.updates, context.batchOptions);

  emitJson(
    {
      projectConfigPath: context.projectConfigPath,
      inputPath: context.inputPath,
      ...result
    },
    parseOptions(args).output
  );
}

function runProjectBatchSet(args: string[]): void {
  const context = resolveBatchCommandContext(args);
  const result = applyXmlBatchUpdates(context.updates, context.batchOptions);

  emitJson(
    {
      projectConfigPath: context.projectConfigPath,
      inputPath: context.inputPath,
      ...result
    },
    parseOptions(args).output
  );
}

function runXmlGet(args: string[]): void {
  const options = parseOptions(args);
  const filePath = resolveRequiredFilePath(options.file);
  const xmlPath = requireOption(options.path, "--path");
  const document = loadXmlDocument(filePath);
  const value = options.attribute
    ? document.getAttribute(xmlPath, options.attribute)
    : document.getNodeText(xmlPath);

  if (value === undefined) {
    throw new Error(`XML value not found: ${xmlPath}`);
  }

  emitJson(
    {
      file: filePath,
      xmlPath,
      attribute: options.attribute ?? null,
      value
    },
    options.output
  );
}

function runXmlSet(args: string[]): void {
  const options = parseOptions(args);
  const filePath = resolveRequiredFilePath(options.file);
  const xmlPath = requireOption(options.path, "--path");
  const nextValue = requireOption(options.value, "--value");
  const document = loadXmlDocument(filePath);

  if (options.attribute) {
    document.setAttribute(xmlPath, options.attribute, nextValue);
  } else {
    document.setNodeText(xmlPath, nextValue);
  }

  const serialized = document.serialize();

  if (options.inPlace) {
    document.save(filePath);
    process.stdout.write(`${filePath}\n`);
    return;
  }

  if (options.output) {
    const outputPath = path.resolve(process.cwd(), options.output);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, serialized, "utf8");
    process.stdout.write(`${outputPath}\n`);
    return;
  }

  process.stdout.write(serialized);
}

function resolveBatchCommandContext(args: string[]): BatchCommandContext {
  const options = parseOptions(args);
  const projectConfigPath = resolveProjectConfigPath(options.project);
  const projectContext = loadProjectContext(projectConfigPath);
  const inputPath = path.resolve(process.cwd(), requireOption(options.input, "--input"));
  const updates = loadBatchUpdates(inputPath).map((update) => ({
    ...update,
    filePath: resolveBatchFilePath(update.filePath, inputPath, projectContext.projectRoot)
  }));
  const baseDir = resolveCommonBaseDir([
    projectContext.projectRoot,
    projectContext.resolvedDirs.items,
    projectContext.resolvedDirs.mods,
    projectContext.resolvedDirs.enemies
  ]);
  const batchOptions = createBatchOptions(options, baseDir);

  return {
    inputPath,
    projectConfigPath,
    projectRoot: projectContext.projectRoot,
    updates,
    batchOptions
  };
}

function createBatchOptions(options: CliOptions, baseDir?: string): XmlBatchOptions {
  return {
    ...(baseDir ? { baseDir } : {}),
    ...(options.inPlace ? { inPlace: true } : {}),
    ...(options.outputDir ? { outputDir: options.outputDir } : {})
  };
}

function emitJson(payload: unknown, output?: string): void {
  const serialized = JSON.stringify(payload, null, 2);

  if (output) {
    const absoluteOutputPath = path.resolve(process.cwd(), output);
    fs.mkdirSync(path.dirname(absoluteOutputPath), { recursive: true });
    fs.writeFileSync(absoluteOutputPath, serialized, "utf8");
    process.stdout.write(`${absoluteOutputPath}\n`);
    return;
  }

  process.stdout.write(`${serialized}\n`);
}

function loadBatchUpdates(inputPath: string): XmlBatchUpdate[] {
  const rawInput = fs.readFileSync(inputPath, "utf8");
  const parsed = JSON.parse(rawInput) as unknown;
  const rawUpdates = Array.isArray(parsed)
    ? parsed
    : isRecord(parsed) && Array.isArray(parsed.updates)
      ? parsed.updates
      : undefined;

  if (!rawUpdates) {
    throw new Error("Batch input must be an array or an object with an updates array.");
  }

  return rawUpdates.map((entry, index) => parseBatchUpdate(entry, index));
}

function parseBatchUpdate(entry: unknown, index: number): XmlBatchUpdate {
  if (!isRecord(entry)) {
    throw new Error(`Batch update at index ${index} must be an object.`);
  }

  const filePath = requireStringOption(entry.filePath, `updates[${index}].filePath`);
  const xmlPath = requireStringOption(entry.xmlPath, `updates[${index}].xmlPath`);
  const value = requireStringOption(entry.value, `updates[${index}].value`);
  const attribute = entry.attribute;
  const update: XmlBatchUpdate = {
    filePath,
    xmlPath,
    value
  };

  if (attribute !== undefined) {
    if (typeof attribute !== "string") {
      throw new Error(`updates[${index}].attribute must be a string when provided.`);
    }

    update.attribute = attribute;
  }

  return update;
}

function parseOptions(args: string[]): CliOptions {
  const options: CliOptions = {
    inPlace: false
  };

  for (let index = 0; index < args.length; index += 1) {
    const current = args[index];
    const next = args[index + 1];

    if ((current === "--attribute" || current === "--attr") && next) {
      options.attribute = next;
      index += 1;
      continue;
    }

    if (current === "--file" && next) {
      options.file = next;
      index += 1;
      continue;
    }

    if (current === "--input" && next) {
      options.input = next;
      index += 1;
      continue;
    }

    if (current === "--output" && next) {
      options.output = next;
      index += 1;
      continue;
    }

    if (current === "--output-dir" && next) {
      options.outputDir = next;
      index += 1;
      continue;
    }

    if (current === "--path" && next) {
      options.path = next;
      index += 1;
      continue;
    }

    if (current === "--project" && next) {
      options.project = next;
      index += 1;
      continue;
    }

    if (current === "--value" && next) {
      options.value = next;
      index += 1;
      continue;
    }

    if (current === "--in-place") {
      options.inPlace = true;
    }
  }

  return options;
}

function resolveProjectConfigPath(value?: string): string {
  if (value) {
    const directPath = path.resolve(process.cwd(), value);

    if (fs.existsSync(directPath)) {
      return directPath;
    }

    const fallbackFromValue = findProjectConfig(
      path.dirname(directPath),
      path.basename(value)
    );
    if (fallbackFromValue) {
      return fallbackFromValue;
    }

    return directPath;
  }

  const fallback = findProjectConfig(process.cwd(), "project.json");
  return fallback ?? path.resolve(process.cwd(), "project.json");
}

function resolveRequiredFilePath(value?: string): string {
  return path.resolve(process.cwd(), requireOption(value, "--file"));
}

function requireOption(value: string | undefined, flagName: string): string {
  if (!value) {
    throw new Error(`Missing required option: ${flagName}`);
  }

  return value;
}

function requireStringOption(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty string.`);
  }

  return value;
}

function findProjectConfig(startDir: string, fileName: string): string | undefined {
  let currentDir = path.resolve(startDir);

  while (true) {
    const candidate = path.join(currentDir, fileName);
    if (fs.existsSync(candidate)) {
      return candidate;
    }

    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) {
      return undefined;
    }

    currentDir = parentDir;
  }
}

function resolveBatchFilePath(filePath: string, inputPath: string, projectRoot: string): string {
  if (path.isAbsolute(filePath)) {
    return filePath;
  }

  const inputRelativePath = path.resolve(path.dirname(inputPath), filePath);
  if (fs.existsSync(inputRelativePath)) {
    return inputRelativePath;
  }

  const projectRelativePath = path.resolve(projectRoot, filePath);
  if (fs.existsSync(projectRelativePath)) {
    return projectRelativePath;
  }

  return projectRelativePath;
}

function resolveCommonBaseDir(values: Array<string | undefined>): string | undefined {
  const normalizedValues = values
    .filter((value): value is string => Boolean(value))
    .map((value) => path.resolve(value));

  const [firstValue, ...restValues] = normalizedValues;

  if (!firstValue) {
    return undefined;
  }

  let currentBase = firstValue;

  for (const value of restValues) {
    currentBase = findCommonAncestor(currentBase, value);
  }

  return currentBase;
}

function findCommonAncestor(left: string, right: string): string {
  const leftPath = splitResolvedPath(left);
  const rightPath = splitResolvedPath(right);

  if (leftPath.root.toLowerCase() !== rightPath.root.toLowerCase()) {
    return leftPath.root;
  }

  const sharedSegments: string[] = [];
  const sharedLength = Math.min(leftPath.segments.length, rightPath.segments.length);

  for (let index = 0; index < sharedLength; index += 1) {
    const leftSegment = leftPath.segments[index];
    const rightSegment = rightPath.segments[index];

    if (!leftSegment || !rightSegment || leftSegment.toLowerCase() !== rightSegment.toLowerCase()) {
      break;
    }

    sharedSegments.push(leftSegment);
  }

  return sharedSegments.length > 0
    ? path.join(leftPath.root, ...sharedSegments)
    : leftPath.root;
}

function splitResolvedPath(value: string): { root: string; segments: string[] } {
  const absolutePath = path.resolve(value);
  const parsedPath = path.parse(absolutePath);

  return {
    root: parsedPath.root,
    segments: absolutePath.slice(parsedPath.root.length).split(path.sep).filter(Boolean)
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function printHelp(): void {
  process.stdout.write(
    [
      "CF7 Balance Tool CLI",
      "",
      "Commands:",
      "  project scan [--project <file>] [--output <file>]",
      "  project fields [--project <file>] [--output <file>]",
      "  project roundtrip-check [--project <file>] [--output <file>]",
      "  project batch-preview --input <file> [--project <file>] [--output <file>] [--output-dir <dir>] [--in-place]",
      "  project batch-set --input <file> [--project <file>] [--output <file>] (--output-dir <dir> | --in-place)",
      "  xml get --file <file> --path <xmlPath> [--attr <name>] [--output <file>]",
      "  xml set --file <file> --path <xmlPath> --value <value> [--attr <name>] [--output <file>] [--in-place]",
      "",
      "Examples:",
      "  npm run project-scan -- --project ./project.json",
      "  npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json",
      "  npm run roundtrip-check -- --project ./project.json --output ./reports/roundtrip-report.json",
      "  npm run batch-preview -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-preview-report.json",
      "  npm run batch-set -- --project ./project.json --input ./reports/batch-updates.sample.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output"
    ].join("\n")
  );
}

main();