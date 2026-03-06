import { app, BrowserWindow, dialog, ipcMain, shell, type OpenDialogOptions } from "electron";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  DEFAULT_OUTPUT_PATH_SETTINGS,
  OUTPUT_PATH_FIELDS,
  normalizeOutputPathSettings,
  type OutputPathSettingKey,
  type OutputPathSettings
} from "../shared/output-path-settings.js";

interface BatchUpdatePayload {
  filePath: string;
  xmlPath: string;
  value: string;
  attribute?: string;
}

interface ArtifactStateEntry {
  path: string;
  exists: boolean;
  kind: "file" | "directory";
  updatedAt?: string;
  size?: number;
  fileCount?: number;
}

interface ArtifactState {
  generatedInput: ArtifactStateEntry;
  previewReport: ArtifactStateEntry;
  batchSetReport: ArtifactStateEntry;
  batchOutputDir: ArtifactStateEntry;
}

interface ReportHistoryEntry {
  path: string;
  relativePath: string;
  category: "payload" | "preview-report" | "apply-report" | "mirrored-xml" | "json" | "other";
  updatedAt: string;
  size: number;
}

interface OutputPathState {
  settings: OutputPathSettings;
  resolved: OutputPathSettings;
  settingsFile: string;
}

interface CliBridgeResult {
  savedTo: string;
  reportPath?: string;
  report?: unknown;
  count: number;
  artifacts: ArtifactState;
}

interface OutputPathBridgeResult {
  outputSettings: OutputPathState;
  artifacts: ArtifactState;
  history: ReportHistoryEntry[];
  previewReport?: unknown;
}

interface ImportedPreviewReportResult {
  canceled: boolean;
  path?: string;
  report?: unknown;
}

interface ImportedBatchUpdatesResult {
  canceled: boolean;
  path?: string;
  updates?: BatchUpdatePayload[];
  count?: number;
}

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const rendererUrl = process.env.CF7_BALANCE_TOOL_RENDERER_URL;
const windowTitle = "CF7 \u6570\u503c\u5e73\u8861\u5de5\u5177";
const toolRoot = findToolRoot(currentDir);
const projectConfigPath = path.join(toolRoot, "project.json");
const settingsRoot = path.join(toolRoot, "settings");
const outputSettingsFilePath = path.join(settingsRoot, "output-paths.json");
const reportHistoryExtensions = new Set([".json", ".xml"]);
let outputPathSettings = loadOutputPathSettings();
ensureOutputSettingsFile();

function createMainWindow(): BrowserWindow {
  const mainWindow = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 1180,
    minHeight: 760,
    backgroundColor: "#120f0a",
    title: windowTitle,
    webPreferences: {
      preload: path.resolve(currentDir, "preload.js")
    }
  });

  if (rendererUrl) {
    void mainWindow.loadURL(rendererUrl);
  } else {
    void mainWindow.loadFile(path.resolve(currentDir, "../../dist/renderer/index.html"));
  }

  return mainWindow;
}

function registerIpcHandlers(): void {
  ipcMain.handle("cf7:get-artifact-state", () => getArtifactState());
  ipcMain.handle("cf7:get-report-history", () => getReportHistory());
  ipcMain.handle("cf7:get-output-settings", () => buildOutputPathBridgeResult());
  ipcMain.handle("cf7:save-output-settings", async (_event, nextSettings: OutputPathSettings) =>
    saveOutputPathSettings(nextSettings)
  );
  ipcMain.handle("cf7:reset-output-settings", () => resetOutputPathSettings());
  ipcMain.handle(
    "cf7:pick-output-path",
    async (event, key: OutputPathSettingKey, currentValue?: string) =>
      pickOutputPath(BrowserWindow.fromWebContents(event.sender) ?? undefined, key, currentValue)
  );
  ipcMain.handle(
    "cf7:pick-preview-report",
    async (event) => pickPreviewReport(BrowserWindow.fromWebContents(event.sender) ?? undefined)
  );
  ipcMain.handle(
    "cf7:pick-batch-updates",
    async (event) => pickBatchUpdates(BrowserWindow.fromWebContents(event.sender) ?? undefined)
  );
  ipcMain.handle("cf7:reveal-path", async (_event, targetPath: string) => revealPath(targetPath));
  ipcMain.handle("cf7:get-changelog", () => getChangelog());
  ipcMain.handle("cf7:run-validation", () => runValidation());
  ipcMain.handle("cf7:get-field-config", () => getFieldConfig());
  ipcMain.handle("cf7:save-field-config", (_event, config: FieldRegistryData) => saveFieldConfig(config));

  ipcMain.handle("cf7:save-batch-updates", async (_event, updates: BatchUpdatePayload[]) =>
    saveBatchUpdates(updates)
  );

  ipcMain.handle("cf7:run-batch-preview", async (_event, updates: BatchUpdatePayload[]) => {
    const saveResult = await saveBatchUpdates(updates);
    const outputPaths = getResolvedOutputPathSettings();

    await runCliCommand([
      "project",
      "batch-preview",
      "--project",
      projectConfigPath,
      "--input",
      outputPaths.generatedInputPath,
      "--output",
      outputPaths.previewReportPath,
      "--output-dir",
      outputPaths.batchOutputDir
    ]);

    return {
      ...saveResult,
      reportPath: outputPaths.previewReportPath,
      report: readJsonFile(outputPaths.previewReportPath),
      artifacts: getArtifactState()
    } satisfies CliBridgeResult;
  });

  ipcMain.handle("cf7:run-batch-set", async (_event, updates: BatchUpdatePayload[]) => {
    const saveResult = await saveBatchUpdates(updates);
    const outputPaths = getResolvedOutputPathSettings();

    await runCliCommand([
      "project",
      "batch-set",
      "--project",
      projectConfigPath,
      "--input",
      outputPaths.generatedInputPath,
      "--output",
      outputPaths.batchSetReportPath,
      "--output-dir",
      outputPaths.batchOutputDir
    ]);

    return {
      ...saveResult,
      reportPath: outputPaths.batchSetReportPath,
      report: readJsonFile(outputPaths.batchSetReportPath),
      artifacts: getArtifactState()
    } satisfies CliBridgeResult;
  });
}

async function saveBatchUpdates(updates: BatchUpdatePayload[]): Promise<CliBridgeResult> {
  const outputPaths = getResolvedOutputPathSettings();

  fs.mkdirSync(path.dirname(outputPaths.generatedInputPath), { recursive: true });
  fs.writeFileSync(outputPaths.generatedInputPath, JSON.stringify(updates, null, 2), "utf8");

  return {
    savedTo: outputPaths.generatedInputPath,
    count: updates.length,
    artifacts: getArtifactState()
  };
}

async function runCliCommand(args: string[]): Promise<void> {
  const cliEntry = resolveCliEntry();

  await new Promise<void>((resolve, reject) => {
    const child = spawn(cliEntry.command, [...cliEntry.args, ...args], {
      cwd: toolRoot,
      windowsHide: true
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(
        new Error(stderr.trim() || stdout.trim() || `CLI exited with code ${code ?? "unknown"}.`)
      );
    });
  });
}

function getArtifactState(): ArtifactState {
  const outputPaths = getResolvedOutputPathSettings();

  return {
    generatedInput: describeArtifactPath(outputPaths.generatedInputPath, "file"),
    previewReport: describeArtifactPath(outputPaths.previewReportPath, "file"),
    batchSetReport: describeArtifactPath(outputPaths.batchSetReportPath, "file"),
    batchOutputDir: describeArtifactPath(outputPaths.batchOutputDir, "directory")
  };
}

function getReportHistory(limit = 18): ReportHistoryEntry[] {
  const outputPaths = getResolvedOutputPathSettings();
  const result: ReportHistoryEntry[] = [];
  const seenFiles = new Set<string>();

  for (const filePath of collectHistoryFiles(outputPaths)) {
    const resolvedPath = path.resolve(filePath);
    const comparisonKey = getPathComparisonKey(resolvedPath);

    if (seenFiles.has(comparisonKey)) {
      continue;
    }

    seenFiles.add(comparisonKey);

    if (!reportHistoryExtensions.has(path.extname(resolvedPath).toLowerCase())) {
      continue;
    }

    result.push(describeReportHistoryEntry(resolvedPath, outputPaths));
  }

  return result
    .sort(
      (left, right) =>
        new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime() ||
        left.relativePath.localeCompare(right.relativePath)
    )
    .slice(0, limit);
}

function buildOutputPathBridgeResult(): OutputPathBridgeResult {
  const outputPaths = getResolvedOutputPathSettings();

  return {
    outputSettings: getOutputPathState(),
    artifacts: getArtifactState(),
    history: getReportHistory(),
    previewReport: readPreviewReport(outputPaths)
  };
}

function getOutputPathState(): OutputPathState {
  return {
    settings: { ...outputPathSettings },
    resolved: getResolvedOutputPathSettings(),
    settingsFile: outputSettingsFilePath
  };
}

function loadOutputPathSettings(): OutputPathSettings {
  if (!fs.existsSync(outputSettingsFilePath)) {
    return { ...DEFAULT_OUTPUT_PATH_SETTINGS };
  }

  try {
    const rawValue = JSON.parse(fs.readFileSync(outputSettingsFilePath, "utf8")) as
      | Partial<OutputPathSettings>
      | undefined;

    return normalizeOutputPathSettings(rawValue);
  } catch {
    return { ...DEFAULT_OUTPUT_PATH_SETTINGS };
  }
}

function saveOutputPathSettings(nextSettings: Partial<OutputPathSettings>): OutputPathBridgeResult {
  const normalizedSettings = normalizeOutputPathSettings(nextSettings);
  validateOutputPathSettings(normalizedSettings);
  outputPathSettings = normalizedSettings;
  ensureOutputSettingsFile();

  return buildOutputPathBridgeResult();
}

function resetOutputPathSettings(): OutputPathBridgeResult {
  outputPathSettings = { ...DEFAULT_OUTPUT_PATH_SETTINGS };
  ensureOutputSettingsFile();

  return buildOutputPathBridgeResult();
}

function ensureOutputSettingsFile(): void {
  fs.mkdirSync(settingsRoot, { recursive: true });
  fs.writeFileSync(outputSettingsFilePath, JSON.stringify(outputPathSettings, null, 2), "utf8");
}

function validateOutputPathSettings(nextSettings: OutputPathSettings): void {
  const resolvedSettings = getResolvedOutputPathSettings(nextSettings);
  const jsonPaths = [
    resolvedSettings.generatedInputPath,
    resolvedSettings.previewReportPath,
    resolvedSettings.batchSetReportPath
  ];
  const uniqueJsonPaths = new Set(jsonPaths.map((value) => getPathComparisonKey(value)));

  if (uniqueJsonPaths.size !== jsonPaths.length) {
    throw new Error("\u624b\u52a8 payload\u3001preview \u62a5\u544a\u548c batch-set \u62a5\u544a\u7684\u8def\u5f84\u4e0d\u80fd\u91cd\u590d\u3002");
  }

  for (const filePath of jsonPaths) {
    if (path.extname(filePath).toLowerCase() !== ".json") {
      throw new Error("JSON \u8f93\u51fa\u8def\u5f84\u5fc5\u987b\u4ee5 .json \u7ed3\u5c3e\u3002");
    }
  }

  if (jsonPaths.some((filePath) => samePath(filePath, resolvedSettings.batchOutputDir))) {
    throw new Error("\u955c\u50cf\u8f93\u51fa\u76ee\u5f55\u4e0d\u80fd\u4e0e JSON \u6587\u4ef6\u8def\u5f84\u76f8\u540c\u3002");
  }
}

function getResolvedOutputPathSettings(source = outputPathSettings): OutputPathSettings {
  const normalizedSettings = normalizeOutputPathSettings(source);

  return {
    generatedInputPath: resolveConfiguredPath(normalizedSettings.generatedInputPath),
    previewReportPath: resolveConfiguredPath(normalizedSettings.previewReportPath),
    batchSetReportPath: resolveConfiguredPath(normalizedSettings.batchSetReportPath),
    batchOutputDir: resolveConfiguredPath(normalizedSettings.batchOutputDir)
  };
}

function resolveConfiguredPath(targetPath: string): string {
  return path.normalize(path.isAbsolute(targetPath) ? targetPath : path.resolve(toolRoot, targetPath));
}

function collectHistoryFiles(outputPaths: OutputPathSettings): string[] {
  const roots = new Map<string, { path: string; recursive: boolean }>();

  addHistoryRoot(roots, path.dirname(outputPaths.generatedInputPath), false);
  addHistoryRoot(roots, path.dirname(outputPaths.previewReportPath), false);
  addHistoryRoot(roots, path.dirname(outputPaths.batchSetReportPath), false);
  addHistoryRoot(roots, outputPaths.batchOutputDir, true);

  return Array.from(roots.values()).flatMap((entry) =>
    collectDirectoryFiles(entry.path, entry.recursive)
  );
}

function addHistoryRoot(
  roots: Map<string, { path: string; recursive: boolean }>,
  directoryPath: string,
  recursive: boolean
): void {
  const resolvedPath = path.resolve(directoryPath);
  const key = getPathComparisonKey(resolvedPath);
  const currentValue = roots.get(key);

  if (currentValue) {
    currentValue.recursive = currentValue.recursive || recursive;
    return;
  }

  roots.set(key, {
    path: resolvedPath,
    recursive
  });
}

function collectDirectoryFiles(directoryPath: string, recursive: boolean): string[] {
  if (!fs.existsSync(directoryPath)) {
    return [];
  }

  const stats = fs.statSync(directoryPath);
  if (stats.isFile()) {
    return [directoryPath];
  }

  const result: string[] = [];

  for (const entry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
    const entryPath = path.join(directoryPath, entry.name);

    if (entry.isDirectory()) {
      if (recursive) {
        result.push(...collectDirectoryFiles(entryPath, true));
      }
      continue;
    }

    result.push(entryPath);
  }

  return result;
}

function describeReportHistoryEntry(filePath: string, outputPaths: OutputPathSettings): ReportHistoryEntry {
  const resolvedPath = path.resolve(filePath);
  const stats = fs.statSync(resolvedPath);

  return {
    path: resolvedPath,
    relativePath: toDisplayPath(resolvedPath),
    category: classifyReportHistoryEntry(resolvedPath, outputPaths),
    updatedAt: stats.mtime.toISOString(),
    size: stats.size
  };
}

function classifyReportHistoryEntry(
  filePath: string,
  outputPaths: OutputPathSettings
): ReportHistoryEntry["category"] {
  const resolvedPath = path.resolve(filePath);
  const extension = path.extname(resolvedPath).toLowerCase();

  if (samePath(resolvedPath, outputPaths.generatedInputPath)) {
    return "payload";
  }

  if (samePath(resolvedPath, outputPaths.previewReportPath)) {
    return "preview-report";
  }

  if (samePath(resolvedPath, outputPaths.batchSetReportPath)) {
    return "apply-report";
  }

  if (extension === ".xml" && isPathInsideDirectory(outputPaths.batchOutputDir, resolvedPath)) {
    return "mirrored-xml";
  }

  if (extension === ".json") {
    return "json";
  }

  return "other";
}

function describeArtifactPath(targetPath: string, fallbackKind: "file" | "directory"): ArtifactStateEntry {
  const resolvedPath = path.resolve(targetPath);

  if (!fs.existsSync(resolvedPath)) {
    return {
      path: resolvedPath,
      exists: false,
      kind: fallbackKind
    };
  }

  const stats = fs.statSync(resolvedPath);
  const kind = stats.isDirectory() ? "directory" : "file";

  const artifact: ArtifactStateEntry = {
    path: resolvedPath,
    exists: true,
    kind,
    updatedAt: stats.mtime.toISOString()
  };

  if (stats.isFile()) {
    artifact.size = stats.size;
  }

  if (stats.isDirectory()) {
    artifact.fileCount = countFilesInDirectory(resolvedPath);
  }

  return artifact;
}

function countFilesInDirectory(directoryPath: string): number {
  let fileCount = 0;

  for (const entry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
    const entryPath = path.join(directoryPath, entry.name);

    if (entry.isDirectory()) {
      fileCount += countFilesInDirectory(entryPath);
      continue;
    }

    fileCount += 1;
  }

  return fileCount;
}

function readPreviewReport(outputPaths: OutputPathSettings): unknown | undefined {
  if (!fs.existsSync(outputPaths.previewReportPath)) {
    return undefined;
  }

  return readJsonFile(outputPaths.previewReportPath);
}

async function pickPreviewReport(
  browserWindow: BrowserWindow | undefined
): Promise<ImportedPreviewReportResult> {
  const selectedPath = await pickJsonImportFile(
    browserWindow,
    "导入 preview 报告",
    getResolvedOutputPathSettings().previewReportPath
  );

  if (!selectedPath) {
    return { canceled: true };
  }

  return {
    canceled: false,
    path: selectedPath,
    report: parseBatchPreviewReport(readJsonFile(selectedPath))
  };
}

async function pickBatchUpdates(
  browserWindow: BrowserWindow | undefined
): Promise<ImportedBatchUpdatesResult> {
  const selectedPath = await pickJsonImportFile(
    browserWindow,
    "导入 payload JSON",
    getResolvedOutputPathSettings().generatedInputPath
  );

  if (!selectedPath) {
    return { canceled: true };
  }

  const updates = parseBatchUpdates(readJsonFile(selectedPath));

  return {
    canceled: false,
    path: selectedPath,
    updates,
    count: updates.length
  };
}

async function pickOutputPath(
  browserWindow: BrowserWindow | undefined,
  key: OutputPathSettingKey,
  currentValue?: string
): Promise<{ canceled: boolean; path?: string }> {
  const field = OUTPUT_PATH_FIELDS.find((item) => item.key === key);

  if (!field) {
    throw new Error(`Unknown output path key: ${key}`);
  }

  const outputPathState = getOutputPathState();
  const rawValue = currentValue ?? outputPathState.settings[key];
  const defaultPath = resolveConfiguredPath(rawValue);
  const baseOptions = {
    defaultPath,
    title: field.label
  };

  if (field.kind === "directory") {
    const openOptions: OpenDialogOptions = {
      ...baseOptions,
      properties: ["openDirectory", "createDirectory"]
    };
    const result = browserWindow
      ? await dialog.showOpenDialog(browserWindow, openOptions)
      : await dialog.showOpenDialog(openOptions);

    return result.filePaths[0]
      ? {
          canceled: result.canceled,
          path: result.filePaths[0]
        }
      : {
          canceled: result.canceled
        };
  }

  const saveOptions = {
    ...baseOptions,
    filters: [
      {
        name: "JSON Files",
        extensions: ["json"]
      },
      {
        name: "All Files",
        extensions: ["*"]
      }
    ]
  };
  const result = browserWindow
    ? await dialog.showSaveDialog(browserWindow, saveOptions)
    : await dialog.showSaveDialog(saveOptions);

  return result.filePath
    ? {
        canceled: result.canceled,
        path: result.filePath
      }
    : {
        canceled: result.canceled
      };
}

function readJsonFile(filePath: string): unknown {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

async function pickJsonImportFile(
  browserWindow: BrowserWindow | undefined,
  title: string,
  defaultPath: string
): Promise<string | undefined> {
  const options: OpenDialogOptions = {
    defaultPath,
    title,
    properties: ["openFile"],
    filters: [
      {
        name: "JSON Files",
        extensions: ["json"]
      },
      {
        name: "All Files",
        extensions: ["*"]
      }
    ]
  };
  const result = browserWindow
    ? await dialog.showOpenDialog(browserWindow, options)
    : await dialog.showOpenDialog(options);

  return result.canceled ? undefined : result.filePaths[0];
}

function parseBatchPreviewReport(value: unknown): unknown {
  if (!isRecord(value)) {
    throw new Error("preview 报告不是对象。");
  }

  if (typeof value.generatedAt !== "string" || !Array.isArray(value.files)) {
    throw new Error("preview 报告缺少 generatedAt 或 files。");
  }

  for (const file of value.files) {
    if (!isRecord(file)) {
      throw new Error("preview 报告包含非法文件节点。");
    }

    if (
      typeof file.sourceFile !== "string" ||
      typeof file.outputFile !== "string" ||
      typeof file.writeMode !== "string" ||
      !Array.isArray(file.changes)
    ) {
      throw new Error("preview 报告文件节点缺少必要字段。");
    }

    for (const change of file.changes) {
      if (!isRecord(change)) {
        throw new Error("preview 报告包含非法变更节点。");
      }

      if (
        typeof change.xmlPath !== "string" ||
        typeof change.beforeValue !== "string" ||
        typeof change.afterValue !== "string" ||
        typeof change.sourceLine !== "number"
      ) {
        throw new Error("preview 报告变更节点缺少必要字段。");
      }
    }
  }

  return value;
}

function parseBatchUpdates(value: unknown): BatchUpdatePayload[] {
  if (!Array.isArray(value)) {
    throw new Error("payload JSON 必须是数组。");
  }

  return value.map((item, index) => {
    if (!isRecord(item)) {
      throw new Error(`payload 第 ${index + 1} 项不是对象。`);
    }

    if (
      typeof item.filePath !== "string" ||
      typeof item.xmlPath !== "string" ||
      typeof item.value !== "string"
    ) {
      throw new Error(`payload 第 ${index + 1} 项缺少 filePath / xmlPath / value。`);
    }

    const payload: BatchUpdatePayload = {
      filePath: item.filePath,
      xmlPath: item.xmlPath,
      value: item.value
    };

    if (typeof item.attribute === "string") {
      payload.attribute = item.attribute;
    }

    return payload;
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

async function revealPath(targetPath: string): Promise<{ path: string }> {
  const resolvedPath = path.resolve(targetPath);

  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`Path does not exist: ${resolvedPath}`);
  }

  const stats = fs.statSync(resolvedPath);

  if (stats.isDirectory()) {
    const errorMessage = await shell.openPath(resolvedPath);
    if (errorMessage) {
      throw new Error(errorMessage);
    }
  } else {
    shell.showItemInFolder(resolvedPath);
  }

  return { path: resolvedPath };
}

function resolveCliEntry(): { command: string; args: string[] } {
  const cliDistEntry = path.join(toolRoot, "packages", "cli", "dist", "index.js");
  if (fs.existsSync(cliDistEntry)) {
    return {
      command: "node",
      args: [cliDistEntry]
    };
  }

  const tsxCliEntry = path.join(toolRoot, "node_modules", "tsx", "dist", "cli.mjs");
  const cliSourceEntry = path.join(toolRoot, "packages", "cli", "src", "index.ts");
  if (fs.existsSync(tsxCliEntry) && fs.existsSync(cliSourceEntry)) {
    return {
      command: "node",
      args: [tsxCliEntry, cliSourceEntry]
    };
  }

  throw new Error("CLI entry was not found. Run npm run typecheck once before using desktop actions.");
}

function samePath(leftPath: string, rightPath: string): boolean {
  return getPathComparisonKey(leftPath) === getPathComparisonKey(rightPath);
}

function isPathInsideDirectory(directoryPath: string, targetPath: string): boolean {
  const relativePath = path.relative(path.resolve(directoryPath), path.resolve(targetPath));
  return relativePath !== "" && !relativePath.startsWith("..") && !path.isAbsolute(relativePath);
}

function toDisplayPath(targetPath: string): string {
  const resolvedPath = path.resolve(targetPath);
  const relativePath = path.relative(toolRoot, resolvedPath);

  if (relativePath !== "" && !relativePath.startsWith("..") && !path.isAbsolute(relativePath)) {
    return relativePath.replaceAll("\\", "/");
  }

  return resolvedPath.replaceAll("\\", "/");
}

function getPathComparisonKey(targetPath: string): string {
  const resolvedPath = path.resolve(targetPath);
  return process.platform === "win32" ? resolvedPath.toLowerCase() : resolvedPath;
}

function findToolRoot(startDir: string): string {
  let currentPath = path.resolve(startDir);

  while (true) {
    const projectFile = path.join(currentPath, "project.json");
    const cliDirectory = path.join(currentPath, "packages", "cli");

    if (fs.existsSync(projectFile) && fs.existsSync(cliDirectory)) {
      return currentPath;
    }

    const parentPath = path.dirname(currentPath);
    if (parentPath === currentPath) {
      throw new Error("Unable to locate cf7-balance-tool workspace root.");
    }

    currentPath = parentPath;
  }
}

interface ChangelogEntry {
  timestamp: string;
  action: string;
  inputFile: string;
  summary: Record<string, unknown>;
  outputDir: string | null;
}

function getChangelog(limit = 50): ChangelogEntry[] {
  const changelogPath = path.join(toolRoot, "reports", "changelog.jsonl");

  if (!fs.existsSync(changelogPath)) {
    return [];
  }

  const lines = fs.readFileSync(changelogPath, "utf8").split("\n").filter(Boolean);
  const entries: ChangelogEntry[] = [];

  for (const line of lines) {
    try {
      entries.push(JSON.parse(line) as ChangelogEntry);
    } catch {
      // skip malformed lines
    }
  }

  return entries.reverse().slice(0, limit);
}

interface ValidationIssue {
  row: number;
  name: string;
  field: string;
  value: number;
  threshold: number;
  severity: "warning" | "error";
  message: string;
}

interface ValidationReport {
  summary: { total: number; errors: number; warnings: number };
  issues: ValidationIssue[];
}

async function runValidation(): Promise<ValidationReport> {
  const baselinePath = path.join(toolRoot, "baseline", "baseline-extracted.json");

  if (!fs.existsSync(baselinePath)) {
    return { summary: { total: 0, errors: 0, warnings: 0 }, issues: [] };
  }

  const outputPath = path.join(toolRoot, "reports", "validation-report.json");

  await runCliCommand([
    "validate",
    "--input",
    baselinePath,
    "--output",
    outputPath
  ]);

  return readJsonFile(outputPath) as ValidationReport;
}

interface FieldRegistryData {
  numericFields: string[];
  numericSuffixes: string[];
  stringFields: string[];
  booleanFields: string[];
  passthroughFields: string[];
  nestedNumericFields: string[];
  itemLevelFields: string[];
  attributeFields: string[];
  computedFields: string[];
}

function getFieldConfig(): FieldRegistryData {
  const configPath = path.join(toolRoot, "data", "field-config.json");
  if (!fs.existsSync(configPath)) {
    return {
      numericFields: [], numericSuffixes: [], stringFields: [],
      booleanFields: [], passthroughFields: [], nestedNumericFields: [],
      itemLevelFields: [], attributeFields: [], computedFields: [],
    };
  }
  return readJsonFile(configPath) as FieldRegistryData;
}

function saveFieldConfig(config: FieldRegistryData): { saved: boolean } {
  const configPath = path.join(toolRoot, "data", "field-config.json");
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2), "utf8");
  return { saved: true };
}

app.whenReady().then(() => {
  registerIpcHandlers();
  createMainWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});





