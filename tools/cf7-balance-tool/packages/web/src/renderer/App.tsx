import {
  startTransition,
  useDeferredValue,
  useEffect,
  useState,
  type ChangeEvent
} from "react";
import rawBatchPreviewReport from "../../../../reports/batch-preview-report.json";
import rawFieldUsageReport from "../../../../reports/field-usage-report.json";

import type { FieldScanReport, FieldUsageRecord } from "@cf7-balance-tool/core";

import {
  applyImportedBatchUpdates,
  buildBatchUpdatesPayload,
  createEditorRows,
  filterEditorRows,
  isRowChanged,
  restoreAllRowsToOriginal,
  restoreAllRowsToSuggested,
  restoreRowToOriginal,
  restoreRowToSuggested,
  summarizeEditorRowsByFile,
  updateRowStagedValue,
  type BatchPreviewReport,
  type BatchUpdatePayload,
  type EditorFileDiffSummary,
  type EditorRow
} from "./editor-model";
import { DataGrid, sortRows, type SortDir, type SortKey } from "./data-grid";
import { ChangelogPanel } from "./changelog-panel";
import { FormulaBar } from "./formula-bar";
import { HistoryPanel } from "./history-panel";
import { OutputPathPanel } from "./output-path-panel";
import type { ReportHistoryEntry } from "./report-history";
import { Sidebar } from "./sidebar";
import { FieldConfigPanel } from "./field-config-panel";
import { TierView } from "./tier-view";
import { ValidationPanel } from "./validation-panel";
import { useUndoRedo } from "./use-undo-redo";
import {
  buildBatchCommandTemplate,
  DEFAULT_OUTPUT_PATH_SETTINGS,
  type OutputPathSettings
} from "../shared/output-path-settings";

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

interface BridgeActionResult {
  savedTo: string;
  reportPath?: string;
  report?: BatchPreviewReport;
  count: number;
  artifacts?: ArtifactState;
}

interface OutputPathState {
  settings: OutputPathSettings;
  resolved: OutputPathSettings;
  settingsFile: string;
}

interface OutputPathBridgeResult {
  outputSettings: OutputPathState;
  artifacts: ArtifactState;
  history: ReportHistoryEntry[];
  previewReport?: BatchPreviewReport;
}

interface ImportedPreviewReportResult {
  canceled: boolean;
  path?: string;
  report?: BatchPreviewReport;
}

interface ImportedBatchUpdatesResult {
  canceled: boolean;
  path?: string;
  updates?: BatchUpdatePayload[];
  count?: number;
}

const fieldUsageReport = rawFieldUsageReport as FieldScanReport;
const initialPreviewReport = rawBatchPreviewReport as BatchPreviewReport;
const initialEditorRows = createEditorRows(initialPreviewReport);
const placeholderArtifacts: ArtifactState = {
  generatedInput: {
    path: DEFAULT_OUTPUT_PATH_SETTINGS.generatedInputPath,
    exists: false,
    kind: "file"
  },
  previewReport: {
    path: DEFAULT_OUTPUT_PATH_SETTINGS.previewReportPath,
    exists: false,
    kind: "file"
  },
  batchSetReport: {
    path: DEFAULT_OUTPUT_PATH_SETTINGS.batchSetReportPath,
    exists: false,
    kind: "file"
  },
  batchOutputDir: {
    path: DEFAULT_OUTPUT_PATH_SETTINGS.batchOutputDir,
    exists: false,
    kind: "directory"
  }
};

const defaultOutputPathState: OutputPathState = {
  settings: { ...DEFAULT_OUTPUT_PATH_SETTINGS },
  resolved: { ...DEFAULT_OUTPUT_PATH_SETTINGS },
  settingsFile: "settings/output-paths.json"
};

const TEXT = {
  title: "\u6570\u503c\u5e73\u8861\u5de5\u4f5c\u53f0",
  intro:
    "\u9762\u5411 XML \u6570\u636e\u3001CLI \u81ea\u52a8\u5316\u548c\u684c\u9762\u7f16\u8f91\u5668\u7684\u7edf\u4e00\u5165\u53e3\u3002\u5f53\u524d\u754c\u9762\u5df2\u63a5\u5165\u5b57\u6bb5\u626b\u63cf\u3001round-trip \u6821\u9a8c\u548c\u6279\u91cf\u53d8\u66f4\u9884\u89c8\uff0c\u5e76\u53ef\u4ee5\u5728\u9875\u9762\u5185\u76f4\u63a5\u4fdd\u5b58 JSON \u6216\u5237\u65b0 preview\u3002",
  runtimeDesktop: "\u684c\u9762\u6a21\u5f0f",
  runtimePreview: "\u6e32\u67d3\u5668\u9884\u89c8",
  pending: "\u5f85\u63a5\u7ebf",
  fieldReportTime: "\u5b57\u6bb5\u62a5\u544a\u65f6\u95f4",
  previewReportTime: "\u9884\u89c8\u62a5\u544a\u65f6\u95f4",
  runtimeHint:
    "\u5f53\u524d\u9875\u9762\u76f4\u63a5\u8bfb\u53d6 reports/field-usage-report.json \u548c reports/batch-preview-report.json\u3002",
  lockedDecisions: "\u5df2\u9501\u5b9a\u8fb9\u754c",
  currentV1: "\u5f53\u524d v1 \u5171\u8bc6",
  fieldScan: "\u5b57\u6bb5\u626b\u63cf",
  firstBaseline: "\u9996\u8f6e\u6570\u636e\u57fa\u7ebf",
  scanNote:
    "\u5f53\u524d\u5b57\u6bb5\u626b\u63cf\u5668\u4ecd\u662f Phase 0 \u7684\u8bcd\u6cd5\u76d8\u70b9\u5c42\uff0c\u9002\u5408\u5feb\u901f\u53d1\u73b0\u672a\u5206\u7c7b\u5b57\u6bb5\u3002",
  editorPanel: "\u6279\u91cf\u7f16\u8f91\u53f0",
  editorTitle: "\u5728 preview \u7ed3\u679c\u4e0a\u7ee7\u7eed\u8c03\u6574",
  editorHint:
    "\u6682\u5b58\u503c\u4ec5\u5b58\u5728\u5f53\u524d\u754c\u9762\u3002\u901a\u8fc7\u53f3\u4fa7\u6309\u94ae\u53ef\u4fdd\u5b58 payload\u3001\u5237\u65b0 preview \u6216\u8f93\u51fa\u955c\u50cf XML\u3002",
  searchLabel: "\u641c\u7d22\u8def\u5f84\u3001\u6587\u4ef6\u3001\u503c",
  changedOnly: "\u4ec5\u770b\u5df2\u53d8\u66f4",
  resetSuggested: "\u6062\u590d\u62a5\u544a\u5efa\u8bae",
  resetOriginal: "\u5168\u90e8\u56de\u9000\u539f\u503c",
  selected: "\u5df2\u9009\u4e2d",
  staged: "\u6682\u5b58\u4e2d",
  unchanged: "\u65e0\u53d8\u66f4",
  beforeLabel: "\u539f\u503c",
  suggestedLabel: "\u62a5\u544a\u5efa\u8bae",
  stagedLabel: "\u5f53\u524d\u6682\u5b58",
  restoreSuggested: "\u6062\u590d\u5efa\u8bae",
  restoreOriginal: "\u8fd8\u539f\u539f\u503c",
  linePrefix: "\u7b2c",
  lineSuffix: "\u884c",
  outputPath: "\u8f93\u51fa\u4f4d\u7f6e",
  reviewPanel: "\u684c\u9762\u52a8\u4f5c",
  reviewTitle: "\u4fdd\u5b58\u3001\u5bfc\u5165\u3001\u9884\u89c8\u3001\u8f93\u51fa",
  importTitle: "\u5bfc\u5165\u5916\u90e8\u6587\u4ef6",
  importHint:
    "\u5f53\u524d\u53ef\u4ece\u4efb\u610f JSON \u5bfc\u5165 preview \u62a5\u544a\u6216 payload\u3002\u5bfc\u5165 preview \u4f1a\u66ff\u6362\u5de5\u4f5c\u53f0\uff0cpayload \u53ea\u4f1a\u8986\u76d6\u5339\u914d\u884c\u7684\u6682\u5b58\u503c\u3002",
  importPreview: "\u5bfc\u5165 preview",
  importPayload: "\u5bfc\u5165 payload",
  visibleRows: "\u5f53\u524d\u53ef\u89c1\u884c",
  activeFiles: "\u6709\u6548\u6587\u4ef6",
  stagedChanges: "\u6682\u5b58\u53d8\u66f4",
  outputMode: "\u8f93\u51fa\u6a21\u5f0f",
  fileScope: "\u5f53\u524d\u6587\u4ef6\u8303\u56f4",
  fileScopeAll: "\u6240\u6709\u6587\u4ef6",
  filterActive: "\u5f53\u524d\u7b5b\u9009",
  diffTitle: "\u6309\u6587\u4ef6\u5ba1\u9605",
  diffHint: "\u70b9\u51fb\u201c\u53ea\u770b\u6b64\u6587\u4ef6\u201d\u53ef\u4ee5\u628a\u5de6\u4fa7\u7f16\u8f91\u533a\u6536\u655b\u5230\u5355\u6587\u4ef6\u3002",
  diffEmpty: "\u5f53\u524d\u6ca1\u6709\u4ecd\u9700\u5199\u51fa\u7684\u53d8\u66f4\u3002",
  diffChangedRows: "\u53d8\u66f4\u9879",
  diffTotalRows: "\u603b\u6761\u76ee",
  diffMore: "\u8fd8\u6709",
  filterThisFile: "\u53ea\u770b\u6b64\u6587\u4ef6",
  clearFileFilter: "\u6e05\u9664\u7b5b\u9009",
  artifactTitle: "\u8f93\u51fa\u72b6\u6001",
  artifactHint: "\u684c\u9762\u6a21\u5f0f\u4f1a\u5b9e\u65f6\u56de\u8bfb\u5f53\u524d\u914d\u7f6e\u7684\u8f93\u51fa\u4f4d\u7f6e\uff1b\u9884\u89c8\u6a21\u5f0f\u53ea\u5c55\u793a\u9ed8\u8ba4\u8def\u5f84\u3002",
  artifactReady: "\u5df2\u5c31\u7eea",
  artifactMissing: "\u672a\u751f\u6210",
  artifactPlanned: "\u6807\u51c6\u8def\u5f84",
  artifactFile: "\u6587\u4ef6",
  artifactDirectory: "\u76ee\u5f55",
  modifiedAt: "\u66f4\u65b0\u65f6\u95f4",
  artifactSize: "\u5927\u5c0f",
  artifactFiles: "\u6587\u4ef6\u6570",
  generatedInput: "\u624b\u52a8 payload",
  previewArtifact: "preview \u62a5\u544a",
  batchSetArtifact: "batch-set \u62a5\u544a",
  outputDirectoryArtifact: "\u955c\u50cf\u8f93\u51fa\u76ee\u5f55",
  outputSettingsSaved: "\u8f93\u51fa\u8def\u5f84\u5df2\u4fdd\u5b58",
  outputSettingsReset: "\u5df2\u6062\u590d\u9ed8\u8ba4\u8f93\u51fa\u8def\u5f84",
  outputSettingsSaveFailed: "\u4fdd\u5b58\u8f93\u51fa\u8def\u5f84\u5931\u8d25",
  outputSettingsResetFailed: "\u6062\u590d\u9ed8\u8ba4\u8f93\u51fa\u8def\u5f84\u5931\u8d25",
  outputPathPicked: "\u5df2\u9009\u62e9\u8f93\u51fa\u8def\u5f84",
  outputPathPickFailed: "\u9009\u62e9\u8f93\u51fa\u8def\u5f84\u5931\u8d25",
  copyPath: "\u590d\u5236\u8def\u5f84",
  revealPath: "\u5b9a\u4f4d\u4ea7\u7269",
  copyDone: "\u5df2\u590d\u5236\u8def\u5f84",
  copyFailed: "\u590d\u5236\u8def\u5f84\u5931\u8d25",
  revealDone: "\u5df2\u5b9a\u4f4d",
  revealFailed: "\u5b9a\u4f4d\u4ea7\u7269\u5931\u8d25",
  selectedDetail: "\u9009\u4e2d\u884c\u8be6\u60c5",
  commandTemplate: "\u547d\u4ee4\u6a21\u677f",
  exportPayload: "\u5bfc\u51fa JSON",
  exportNote:
    "\u5bfc\u51fa payload \u9ed8\u8ba4\u4f7f\u7528\u7edd\u5bf9\u8def\u5f84\uff0c\u4fbf\u4e8e CLI \u4ece\u4efb\u610f\u76ee\u5f55\u6267\u884c\u3002",
  bridgeModeDesktop: "\u684c\u9762\u6a21\u5f0f\u53ef\u76f4\u63a5\u89e6\u53d1\u672c\u5730\u52a8\u4f5c\u3002",
  bridgeModePreview:
    "\u5f53\u524d\u662f\u6e32\u67d3\u5668\u9884\u89c8\u6a21\u5f0f\uff0c\u53ea\u663e\u793a\u547d\u4ee4\u6a21\u677f\uff0c\u4e0d\u76f4\u63a5\u5199\u78c1\u76d8\u3002",
  saveJson: "\u4fdd\u5b58 JSON",
  refreshPreview: "\u5237\u65b0 preview",
  applyMirror: "\u8f93\u51fa\u955c\u50cf XML",
  workingSave: "\u6b63\u5728\u4fdd\u5b58...",
  workingPreview: "\u6b63\u5728\u5237\u65b0 preview...",
  workingApply: "\u6b63\u5728\u8f93\u51fa\u955c\u50cf XML...",
  workingImportPreview: "\u6b63\u5728\u5bfc\u5165 preview...",
  workingImportPayload: "\u6b63\u5728\u5bfc\u5165 payload...",
  saveDone: "\u5df2\u4fdd\u5b58",
  previewDone: "preview \u5df2\u5237\u65b0",
  applyDone: "\u955c\u50cf XML \u5df2\u8f93\u51fa",
  importPreviewDone: "\u5df2\u5bfc\u5165 preview \u62a5\u544a",
  importPayloadDone: "\u5df2\u5bfc\u5165 payload",
  saveFailed: "\u4fdd\u5b58\u5931\u8d25",
  previewFailed: "preview \u5237\u65b0\u5931\u8d25",
  applyFailed: "\u955c\u50cf XML \u8f93\u51fa\u5931\u8d25",
  importPreviewFailed: "\u5bfc\u5165 preview \u5931\u8d25",
  importPayloadFailed: "\u5bfc\u5165 payload \u5931\u8d25",
  matchedUpdates: "\u5339\u914d",
  unmatchedUpdates: "\u672a\u5339\u914d",
  emptySelection: "\u5f53\u524d\u7b5b\u9009\u4e0b\u6ca1\u6709\u53ef\u7f16\u8f91\u884c\u3002",
  emptyPayload: "\u5f53\u524d\u6240\u6709\u6682\u5b58\u503c\u90fd\u5df2\u56de\u9000\u5230\u539f\u503c\u3002",
  unknownPanel: "\u5f85\u7ee7\u7eed\u6536\u655b",
  unknownTitle: "\u9ad8\u9891\u672a\u5206\u7c7b\u5b57\u6bb5",
  knownPanel: "\u5df2\u8bc6\u522b\u6837\u672c",
  knownTitle: "\u9ad8\u9891\u5b57\u6bb5\u53c2\u8003",
  occurrences: "\u51fa\u73b0",
  occurrencesSuffix: "\u6b21",
  unclassified: "\u672a\u5206\u7c7b"
} as const;

const decisions = [
  ["\u63d2\u4ef6\u8303\u56f4", "v1 \u53ea\u505a CRUD\uff0c\u4e0d\u505a\u63d2\u4ef6\u6570\u503c\u516c\u5f0f"],
  ["\u516c\u5f0f\u8f93\u51fa", "\u4fdd\u7559\u53ea\u8bfb\u53c2\u8003\u503c\uff0c\u4e0d\u56de\u5199 XML"],
  ["\u524d\u7aef\u8bed\u8a00", "\u4e2d\u6587\u4f18\u5148\uff0c\u5148\u670d\u52a1\u5185\u90e8\u5f00\u53d1\u534f\u4f5c"],
  ["\u53d8\u66f4\u8ffd\u8e2a", "\u4ee5 Git diff \u4e3a\u4e3b\uff0c\u5de5\u5177\u8f93\u51fa\u7ed3\u6784\u5316\u62a5\u544a"]
] as const;

const moduleCards = [
  {
    title: "\u5b57\u6bb5\u76d8\u70b9",
    status: "\u5df2\u63a5\u901a",
    description: `\u5b57\u6bb5\u626b\u63cf\u5df2\u8986\u76d6 ${formatNumber(fieldUsageReport.totals.files)} \u4e2a XML\u3002`
  },
  {
    title: "XML Round-Trip",
    status: "\u5df2\u9a8c\u8bc1",
    description: "\u9879\u76ee\u7ea7 no-op \u6821\u9a8c 89/89 \u901a\u8fc7\u3002"
  },
  {
    title: "\u6279\u91cf\u9884\u89c8",
    status: "\u53ef\u5ba1\u9605",
    description: "\u5df2\u6709 before / after / \u884c\u53f7 / \u8f93\u51fa\u8def\u5f84\u3002"
  },
  {
    title: "Electron \u6865\u63a5",
    status: "\u672c\u8f6e\u63a5\u5165",
    description: "\u53ef\u76f4\u63a5\u4fdd\u5b58 JSON\u3001\u5237\u65b0 preview \u548c\u8f93\u51fa\u955c\u50cf XML\u3002"
  }
] as const;

const topUnknownFields = fieldUsageReport.usage
  .filter((item) => item.classification === "unknown")
  .slice(0, 6);

const topKnownFields = fieldUsageReport.usage
  .filter((item) => item.classification !== "unknown")
  .slice(0, 6);

export function App() {
  const runtimeLabel =
    window.cf7Balance?.runtime === "electron"
      ? TEXT.runtimeDesktop
      : TEXT.runtimePreview;
  const versions = window.cf7Balance?.versions;
  const [previewReport, setPreviewReport] = useState(initialPreviewReport);
  const editorHistory = useUndoRedo(initialEditorRows);
  const editorRows = editorHistory.state;
  const [artifactState, setArtifactState] = useState<ArtifactState>();
  const [reportHistory, setReportHistory] = useState<ReportHistoryEntry[]>([]);
  const [outputPathState, setOutputPathState] = useState<OutputPathState>(defaultOutputPathState);
  const [outputPathDraft, setOutputPathDraft] = useState<OutputPathSettings>(
    defaultOutputPathState.settings
  );
  const [searchText, setSearchText] = useState("");
  const [showChangedOnly, setShowChangedOnly] = useState(false);
  const [selectedSourceFile, setSelectedSourceFile] = useState<string | undefined>();
  const [selectedRowId, setSelectedRowId] = useState<string | undefined>(
    initialEditorRows[0]?.id
  );
  const [activityMessage, setActivityMessage] = useState("");
  const [busyAction, setBusyAction] = useState<"save" | "preview" | "apply" | null>(null);
  const [busyImportAction, setBusyImportAction] = useState<"preview" | "payload" | null>(null);
  const [busyOutputAction, setBusyOutputAction] = useState<"save" | "reset" | null>(null);
  const [viewMode, setViewMode] = useState<"card" | "table">("table");
  const [sortKey, setSortKey] = useState<SortKey>("file");
  const [sortDir, setSortDir] = useState<SortDir>("asc");
  const [sidebarVisible, setSidebarVisible] = useState(true);
  const [batchReplaceVisible, setBatchReplaceVisible] = useState(false);
  const [batchFindText, setBatchFindText] = useState("");
  const [batchReplaceText, setBatchReplaceText] = useState("");
  const [batchField, setBatchField] = useState<"staged" | "before">("staged");
  const deferredSearchText = useDeferredValue(searchText);
  const canSave = typeof window.cf7Balance?.saveBatchUpdates === "function";
  const canPreview = typeof window.cf7Balance?.runBatchPreview === "function";
  const canApply = typeof window.cf7Balance?.runBatchSet === "function";
  const canInspectArtifacts = typeof window.cf7Balance?.getArtifactState === "function";
  const canReadReportHistory = typeof window.cf7Balance?.getReportHistory === "function";
  const canManageOutputPaths =
    typeof window.cf7Balance?.getOutputSettings === "function" &&
    typeof window.cf7Balance?.saveOutputSettings === "function" &&
    typeof window.cf7Balance?.resetOutputSettings === "function";
  const canPickOutputPath = typeof window.cf7Balance?.pickOutputPath === "function";
  const canImportPreviewReport = typeof window.cf7Balance?.pickPreviewReport === "function";
  const canImportBatchUpdates = typeof window.cf7Balance?.pickBatchUpdates === "function";
  const canRevealPath = typeof window.cf7Balance?.revealPath === "function";
  const canCopyPath =
    typeof navigator !== "undefined" && typeof navigator.clipboard?.writeText === "function";
  const hasBusyBridgeAction = busyAction !== null || busyImportAction !== null;

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if ((e.ctrlKey || e.metaKey) && !e.shiftKey && e.key === "z") {
        if ((e.target as HTMLElement)?.tagName === "INPUT") return;
        e.preventDefault();
        editorHistory.undo();
      }
      if (
        (e.ctrlKey || e.metaKey) &&
        (e.key === "y" || (e.shiftKey && e.key === "z" || e.key === "Z"))
      ) {
        if ((e.target as HTMLElement)?.tagName === "INPUT") return;
        e.preventDefault();
        editorHistory.redo();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [editorHistory.undo, editorHistory.redo]);

  useEffect(() => {
    if (!canInspectArtifacts || !window.cf7Balance?.getArtifactState) {
      return;
    }

    let active = true;

    void window.cf7Balance
      .getArtifactState()
      .then((nextArtifacts) => {
        if (active) {
          setArtifactState(nextArtifacts as ArtifactState);
        }
      })
      .catch(() => {
        if (active) {
          setArtifactState(undefined);
        }
      });

    return () => {
      active = false;
    };
  }, [canInspectArtifacts]);

  useEffect(() => {
    if (!canReadReportHistory || !window.cf7Balance?.getReportHistory) {
      return;
    }

    let active = true;

    void window.cf7Balance
      .getReportHistory()
      .then((nextHistory) => {
        if (active) {
          setReportHistory(nextHistory as ReportHistoryEntry[]);
        }
      })
      .catch(() => {
        if (active) {
          setReportHistory([]);
        }
      });

    return () => {
      active = false;
    };
  }, [canReadReportHistory]);

  useEffect(() => {
    if (!canManageOutputPaths || !window.cf7Balance?.getOutputSettings) {
      return;
    }

    let active = true;

    void window.cf7Balance
      .getOutputSettings()
      .then((result) => {
        if (active) {
          applyOutputPathBridgeResult(result as OutputPathBridgeResult);
        }
      })
      .catch(() => {
        if (active) {
          setOutputPathState(defaultOutputPathState);
          setOutputPathDraft(defaultOutputPathState.settings);
        }
      });

    return () => {
      active = false;
    };
  }, [canManageOutputPaths]);

  const fileDiffs = summarizeEditorRowsByFile(editorRows);
  const scopedRows = selectedSourceFile
    ? editorRows.filter((row) => row.sourceFile === selectedSourceFile)
    : editorRows;
  const filteredRows = filterEditorRows(scopedRows, deferredSearchText, showChangedOnly);
  const sortedFilteredRows = viewMode === "table" ? sortRows(filteredRows, sortKey, sortDir) : filteredRows;
  const selectedRow =
    filteredRows.find((row) => row.id === selectedRowId) ??
    scopedRows.find((row) => row.id === selectedRowId) ??
    editorRows.find((row) => row.id === selectedRowId);
  const visibleFileDiffs = selectedSourceFile
    ? fileDiffs.filter((summary) => summary.sourceFile === selectedSourceFile)
    : fileDiffs;
  const payload = buildBatchUpdatesPayload(editorRows);
  const payloadText = JSON.stringify(payload, null, 2);
  const artifactEntries = buildArtifactEntries(artifactState);
  const hasPendingOutputPathChanges =
    JSON.stringify(outputPathDraft) !== JSON.stringify(outputPathState.settings);
  const visibleFileCount = new Set(filteredRows.map((row) => row.sourceFile)).size;
  const scanMetrics = [
    { label: "\u626b\u63cf\u6587\u4ef6", value: formatNumber(fieldUsageReport.totals.files) },
    { label: "\u5b57\u6bb5\u540d", value: formatNumber(fieldUsageReport.totals.fields) },
    {
      label: "\u5b57\u6bb5\u51fa\u73b0\u6b21\u6570",
      value: formatNumber(fieldUsageReport.totals.occurrences)
    },
    {
      label: "\u672a\u5206\u7c7b\u5b57\u6bb5",
      value: formatNumber(fieldUsageReport.totals.unknownFields)
    }
  ] as const;
  const reviewMetrics = [
    { label: TEXT.visibleRows, value: formatNumber(filteredRows.length) },
    { label: TEXT.activeFiles, value: formatNumber(visibleFileCount) },
    { label: TEXT.stagedChanges, value: formatNumber(payload.length) },
    {
      label: TEXT.outputMode,
      value: translateWriteMode(previewReport.files[0]?.writeMode ?? "preview")
    }
  ] as const;
  useEffect(() => {
    if (filteredRows.length === 0) {
      if (selectedRowId !== undefined) {
        setSelectedRowId(undefined);
      }
      return;
    }

    const selectedRowStillVisible = filteredRows.some((row) => row.id === selectedRowId);

    if (!selectedRowStillVisible) {
      setSelectedRowId(filteredRows[0]?.id);
    }
  }, [filteredRows, selectedRowId]);

  function handleSearchChange(event: ChangeEvent<HTMLInputElement>): void {
    const nextValue = event.currentTarget.value;
    startTransition(() => {
      setSearchText(nextValue);
    });
  }

  function handleRowValueChange(rowId: string, nextValue: string): void {
    editorHistory.update((currentRows) => updateRowStagedValue(currentRows, rowId, nextValue));
  }

  function handleRestoreRowSuggested(rowId: string): void {
    editorHistory.update((currentRows) => restoreRowToSuggested(currentRows, rowId));
  }

  function handleRestoreRowOriginal(rowId: string): void {
    editorHistory.update((currentRows) => restoreRowToOriginal(currentRows, rowId));
  }

  function handleRestoreAllSuggested(): void {
    editorHistory.update((currentRows) => restoreAllRowsToSuggested(currentRows));
  }

  function handleRestoreAllOriginal(): void {
    editorHistory.update((currentRows) => restoreAllRowsToOriginal(currentRows));
  }

  function handleBatchReplace(): void {
    if (!batchFindText) return;
    editorHistory.update((currentRows) =>
      currentRows.map((row) => {
        const source = batchField === "before" ? row.beforeValue : row.stagedValue;
        if (source !== batchFindText) return row;
        return { ...row, stagedValue: batchReplaceText };
      })
    );
  }

  function handleSortChange(key: SortKey): void {
    if (key === sortKey) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDir("asc");
    }
  }

  function handleToggleSourceFile(sourceFile: string): void {
    setSelectedSourceFile((currentValue) =>
      currentValue === sourceFile ? undefined : sourceFile
    );
  }

  function clearSourceFileFilter(): void {
    setSelectedSourceFile(undefined);
  }

  function applyPreviewReport(nextReport: BatchPreviewReport): void {
    const nextRows = createEditorRows(nextReport);
    setPreviewReport(nextReport);
    editorHistory.reset(nextRows);
    setSelectedSourceFile(undefined);
    setSelectedRowId(nextRows[0]?.id);
  }

  function applyOutputPathBridgeResult(result: OutputPathBridgeResult): void {
    setOutputPathState(result.outputSettings);
    setOutputPathDraft(result.outputSettings.settings);
    syncArtifacts(result.artifacts);
    setReportHistory(result.history);

    if (result.previewReport) {
      applyPreviewReport(result.previewReport);
    }
  }

  async function handleImportPreviewReport(): Promise<void> {
    if (!canImportPreviewReport || !window.cf7Balance?.pickPreviewReport) {
      return;
    }

    setBusyImportAction("preview");
    setActivityMessage(TEXT.workingImportPreview);

    try {
      const result =
        (await window.cf7Balance.pickPreviewReport()) as ImportedPreviewReportResult;

      if (result.canceled || !result.report || !result.path) {
        return;
      }

      applyPreviewReport(result.report);
      setActivityMessage(`${TEXT.importPreviewDone}: ${shortenPath(result.path)}`);
    } catch (error) {
      setActivityMessage(`${TEXT.importPreviewFailed}: ${toErrorMessage(error)}`);
    } finally {
      setBusyImportAction(null);
    }
  }

  async function handleImportBatchUpdates(): Promise<void> {
    if (!canImportBatchUpdates || !window.cf7Balance?.pickBatchUpdates) {
      return;
    }

    setBusyImportAction("payload");
    setActivityMessage(TEXT.workingImportPayload);

    try {
      const result =
        (await window.cf7Balance.pickBatchUpdates()) as ImportedBatchUpdatesResult;

      if (result.canceled || !result.updates || !result.path) {
        return;
      }

      const appliedResult = applyImportedBatchUpdates(editorRows, result.updates);
      editorHistory.set(appliedResult.rows);
      setSelectedSourceFile(undefined);
      setActivityMessage(
        `${TEXT.importPayloadDone}: ${TEXT.matchedUpdates} ${formatNumber(
          appliedResult.matchedUpdates
        )}, ${TEXT.unmatchedUpdates} ${formatNumber(
          appliedResult.unmatchedUpdates
        )} <- ${shortenPath(result.path)}`
      );
    } catch (error) {
      setActivityMessage(`${TEXT.importPayloadFailed}: ${toErrorMessage(error)}`);
    } finally {
      setBusyImportAction(null);
    }
  }

  function handleOutputPathDraftChange(
    key: keyof OutputPathSettings,
    value: string
  ): void {
    setOutputPathDraft((currentValue) => ({
      ...currentValue,
      [key]: value
    }));
  }

  async function handlePickOutputPath(
    key: keyof OutputPathSettings,
    currentValue: string
  ): Promise<void> {
    if (!canPickOutputPath || !window.cf7Balance?.pickOutputPath) {
      return;
    }

    try {
      const result = await window.cf7Balance.pickOutputPath(key, currentValue);

      if (result.canceled || !result.path) {
        return;
      }

      handleOutputPathDraftChange(key, result.path);
      setActivityMessage(`${TEXT.outputPathPicked}\uff1a${shortenPath(result.path)}`);
    } catch (error) {
      setActivityMessage(`${TEXT.outputPathPickFailed}\uff1a${toErrorMessage(error)}`);
    }
  }

  async function refreshReportHistory(): Promise<void> {
    if (!canReadReportHistory || !window.cf7Balance?.getReportHistory) {
      return;
    }

    try {
      const nextHistory = await window.cf7Balance.getReportHistory();
      setReportHistory(nextHistory as ReportHistoryEntry[]);
    } catch {
      setReportHistory([]);
    }
  }

  async function handleSaveOutputPaths(): Promise<void> {
    if (!canManageOutputPaths || !window.cf7Balance?.saveOutputSettings) {
      return;
    }

    setBusyOutputAction("save");

    try {
      const result =
        (await window.cf7Balance.saveOutputSettings(outputPathDraft)) as OutputPathBridgeResult;
      applyOutputPathBridgeResult(result);
      setActivityMessage(
        `${TEXT.outputSettingsSaved}\uff1a${shortenPath(result.outputSettings.settingsFile)}`
      );
    } catch (error) {
      setActivityMessage(`${TEXT.outputSettingsSaveFailed}\uff1a${toErrorMessage(error)}`);
    } finally {
      setBusyOutputAction(null);
    }
  }

  async function handleResetOutputPaths(): Promise<void> {
    if (!canManageOutputPaths || !window.cf7Balance?.resetOutputSettings) {
      return;
    }

    setBusyOutputAction("reset");

    try {
      const result = (await window.cf7Balance.resetOutputSettings()) as OutputPathBridgeResult;
      applyOutputPathBridgeResult(result);
      setActivityMessage(
        `${TEXT.outputSettingsReset}\uff1a${shortenPath(result.outputSettings.settingsFile)}`
      );
    } catch (error) {
      setActivityMessage(`${TEXT.outputSettingsResetFailed}\uff1a${toErrorMessage(error)}`);
    } finally {
      setBusyOutputAction(null);
    }
  }

  async function handleCopyPath(targetPath: string): Promise<void> {
    if (!canCopyPath) {
      return;
    }

    try {
      await navigator.clipboard.writeText(targetPath);
      setActivityMessage(`${TEXT.copyDone}\uff1a${shortenPath(targetPath)}`);
    } catch (error) {
      setActivityMessage(`${TEXT.copyFailed}\uff1a${toErrorMessage(error)}`);
    }
  }

  async function handleRevealPath(targetPath: string): Promise<void> {
    if (!canRevealPath || !window.cf7Balance?.revealPath) {
      return;
    }

    try {
      const result = await window.cf7Balance.revealPath(targetPath);
      setActivityMessage(`${TEXT.revealDone}\uff1a${shortenPath(result.path)}`);
    } catch (error) {
      setActivityMessage(`${TEXT.revealFailed}\uff1a${toErrorMessage(error)}`);
    }
  }

  function syncArtifacts(nextArtifacts?: ArtifactState): void {
    if (nextArtifacts) {
      setArtifactState(nextArtifacts);
    }
  }

  async function handleSaveJson(): Promise<void> {
    if (!canSave || !window.cf7Balance?.saveBatchUpdates) {
      return;
    }

    setBusyAction("save");
    setActivityMessage(TEXT.workingSave);

    try {
      const result = (await window.cf7Balance.saveBatchUpdates(payload)) as BridgeActionResult;
      syncArtifacts(result.artifacts);
      await refreshReportHistory();
      setActivityMessage(
        `${TEXT.saveDone}\uff1a${formatNumber(result.count)} \u6761 -> ${shortenPath(result.savedTo)}`
      );
    } catch (error) {
      setActivityMessage(`${TEXT.saveFailed}\uff1a${toErrorMessage(error)}`);
    } finally {
      setBusyAction(null);
    }
  }

  async function handleRefreshPreview(): Promise<void> {
    if (!canPreview || !window.cf7Balance?.runBatchPreview) {
      return;
    }

    setBusyAction("preview");
    setActivityMessage(TEXT.workingPreview);

    try {
      const result = (await window.cf7Balance.runBatchPreview(payload)) as BridgeActionResult;
      const nextReport = result.report;

      if (nextReport) {
        applyPreviewReport(nextReport);
      }

      syncArtifacts(result.artifacts);
      await refreshReportHistory();
      setActivityMessage(
        `${TEXT.previewDone}\uff1a${shortenPath(result.reportPath ?? result.savedTo)}`
      );
    } catch (error) {
      setActivityMessage(`${TEXT.previewFailed}\uff1a${toErrorMessage(error)}`);
    } finally {
      setBusyAction(null);
    }
  }

  async function handleApplyMirror(): Promise<void> {
    if (!canApply || !window.cf7Balance?.runBatchSet) {
      return;
    }

    setBusyAction("apply");
    setActivityMessage(TEXT.workingApply);

    try {
      const result = (await window.cf7Balance.runBatchSet(payload)) as BridgeActionResult;
      const nextReport = result.report;

      if (nextReport) {
        applyPreviewReport(nextReport);
      }

      syncArtifacts(result.artifacts);
      await refreshReportHistory();
      setActivityMessage(
        `${TEXT.applyDone}\uff1a${shortenPath(result.reportPath ?? result.savedTo)}`
      );
    } catch (error) {
      setActivityMessage(`${TEXT.applyFailed}\uff1a${toErrorMessage(error)}`);
    } finally {
      setBusyAction(null);
    }
  }

  return (
    <main className="app-shell">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">CF7 MERCENARY EMPIRE</p>
          <h1>{TEXT.title}</h1>
          <p className="lede">{TEXT.intro}</p>
        </div>

        <div className="runtime-panel">
          <span className="runtime-badge">{runtimeLabel}</span>
          <dl>
            <div>
              <dt>Node</dt>
              <dd>{versions?.node ?? TEXT.pending}</dd>
            </div>
            <div>
              <dt>Electron</dt>
              <dd>{versions?.electron ?? TEXT.pending}</dd>
            </div>
            <div>
              <dt>{TEXT.fieldReportTime}</dt>
              <dd>{formatDateTime(fieldUsageReport.generatedAt)}</dd>
            </div>
            <div>
              <dt>{TEXT.previewReportTime}</dt>
              <dd>{formatDateTime(previewReport.generatedAt)}</dd>
            </div>
          </dl>
          <p className="runtime-hint">{TEXT.runtimeHint}</p>
        </div>
      </section>

      <section className="module-grid">
        {moduleCards.map((card) => (
          <article className="module-card" key={card.title}>
            <div className="module-topline">
              <h2>{card.title}</h2>
              <span>{card.status}</span>
            </div>
            <p>{card.description}</p>
          </article>
        ))}
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel-header">
            <p>{TEXT.lockedDecisions}</p>
            <h3>{TEXT.currentV1}</h3>
          </div>
          <div className="decision-table">
            {decisions.map(([label, value]) => (
              <div className="decision-row" key={label}>
                <span>{label}</span>
                <strong>{value}</strong>
              </div>
            ))}
          </div>
        </article>

        <article className="panel">
          <div className="panel-header">
            <p>{TEXT.fieldScan}</p>
            <h3>{TEXT.firstBaseline}</h3>
          </div>
          <div className="metric-grid">
            {scanMetrics.map((metric) => (
              <div className="metric-card" key={metric.label}>
                <span>{metric.label}</span>
                <strong>{metric.value}</strong>
              </div>
            ))}
          </div>
          <p className="report-note">{TEXT.scanNote}</p>
        </article>
      </section>

      <section className={`content-grid ${sidebarVisible ? "content-grid-with-sidebar" : "content-grid-wide"}`}>
        {sidebarVisible && (
          <Sidebar
            rows={editorRows}
            selectedFile={selectedSourceFile}
            onSelectFile={setSelectedSourceFile}
          />
        )}
        <article className="panel">
          <div className="panel-header">
            <p>{TEXT.editorPanel}</p>
            <h3>{TEXT.editorTitle}</h3>
          </div>
          <p className="panel-caption">{TEXT.editorHint}</p>
          <div className="editor-toolbar">
            <label className="search-field">
              <span>{TEXT.searchLabel}</span>
              <input
                value={searchText}
                onChange={handleSearchChange}
                placeholder={TEXT.searchLabel}
              />
            </label>
            <label className="toggle-field">
              <input
                type="checkbox"
                checked={showChangedOnly}
                onChange={(event) => setShowChangedOnly(event.currentTarget.checked)}
              />
              <span>{TEXT.changedOnly}</span>
            </label>
            <button className="action-button" onClick={handleRestoreAllSuggested} type="button">
              {TEXT.resetSuggested}
            </button>
            <button className="action-button action-button-ghost" onClick={handleRestoreAllOriginal} type="button">
              {TEXT.resetOriginal}
            </button>
          </div>
          <div className="editor-secondary-toolbar">
            <div className="toolbar-group">
              <button
                className={`mini-button ${viewMode === "card" ? "mini-button-active" : "mini-button-ghost"}`}
                onClick={() => setViewMode("card")}
                type="button"
              >
                卡片
              </button>
              <button
                className={`mini-button ${viewMode === "table" ? "mini-button-active" : "mini-button-ghost"}`}
                onClick={() => setViewMode("table")}
                type="button"
              >
                表格
              </button>
            </div>
            <div className="toolbar-group">
              <button
                className="mini-button mini-button-ghost"
                onClick={() => setSidebarVisible((v) => !v)}
                type="button"
              >
                {sidebarVisible ? "隐藏侧栏" : "显示侧栏"}
              </button>
              <button
                className="mini-button"
                disabled={!editorHistory.canUndo}
                onClick={editorHistory.undo}
                type="button"
              >
                撤销
              </button>
              <button
                className="mini-button"
                disabled={!editorHistory.canRedo}
                onClick={editorHistory.redo}
                type="button"
              >
                重做
              </button>
              <button
                className={`mini-button ${batchReplaceVisible ? "mini-button-active" : "mini-button-ghost"}`}
                onClick={() => setBatchReplaceVisible((v) => !v)}
                type="button"
              >
                批量替换
              </button>
            </div>
          </div>
          {batchReplaceVisible && (
            <div className="batch-replace-bar">
              <select
                className="batch-replace-select"
                value={batchField}
                onChange={(e) => setBatchField(e.currentTarget.value as "staged" | "before")}
              >
                <option value="staged">匹配暂存值</option>
                <option value="before">匹配原值</option>
              </select>
              <input
                className="batch-replace-input"
                value={batchFindText}
                onChange={(e) => setBatchFindText(e.currentTarget.value)}
                placeholder="查找值..."
              />
              <span className="batch-replace-arrow">→</span>
              <input
                className="batch-replace-input"
                value={batchReplaceText}
                onChange={(e) => setBatchReplaceText(e.currentTarget.value)}
                placeholder="替换为..."
              />
              <button
                className="mini-button"
                disabled={!batchFindText}
                onClick={handleBatchReplace}
                type="button"
              >
                全部替换
              </button>
            </div>
          )}
          <div className="scope-summary">
            <span>
              {selectedSourceFile
                ? `${TEXT.filterActive}\uff1a${shortenPath(selectedSourceFile)}`
                : `${TEXT.fileScope}\uff1a${TEXT.fileScopeAll}`}
            </span>
            {selectedSourceFile ? (
              <button
                className="mini-button mini-button-ghost"
                onClick={clearSourceFileFilter}
                type="button"
              >
                {TEXT.clearFileFilter}
              </button>
            ) : null}
          </div>

          {viewMode === "table" ? (
            <DataGrid
              rows={sortedFilteredRows}
              selectedRowId={selectedRowId}
              sortKey={sortKey}
              sortDir={sortDir}
              onSelect={setSelectedRowId}
              onValueChange={handleRowValueChange}
              onSortChange={handleSortChange}
            />
          ) : (
            <div className="editor-row-list">
              {filteredRows.length === 0 ? (
                <div className="empty-state">{TEXT.emptySelection}</div>
              ) : (
                filteredRows.map((row) => (
                  <EditorRowCard
                    key={row.id}
                    row={row}
                    selected={row.id === selectedRowId}
                    onSelect={() => setSelectedRowId(row.id)}
                    onValueChange={handleRowValueChange}
                    onRestoreSuggested={handleRestoreRowSuggested}
                    onRestoreOriginal={handleRestoreRowOriginal}
                  />
                ))
              )}
            </div>
          )}
        </article>

        <article className="panel">
          <div className="panel-header">
            <p>{TEXT.reviewPanel}</p>
            <h3>{TEXT.reviewTitle}</h3>
          </div>
          <div className="metric-grid metric-grid-compact">
            {reviewMetrics.map((metric) => (
              <div className="metric-card" key={metric.label}>
                <span>{metric.label}</span>
                <strong>{metric.value}</strong>
              </div>
            ))}
          </div>

          <div className="bridge-actions">
            <button
              className="action-button"
              disabled={!canSave || hasBusyBridgeAction}
              onClick={() => void handleSaveJson()}
              type="button"
            >
              {busyAction === "save" ? TEXT.workingSave : TEXT.saveJson}
            </button>
            <button
              className="action-button"
              disabled={!canPreview || hasBusyBridgeAction}
              onClick={() => void handleRefreshPreview()}
              type="button"
            >
              {busyAction === "preview" ? TEXT.workingPreview : TEXT.refreshPreview}
            </button>
            <button
              className="action-button action-button-ghost"
              disabled={!canApply || hasBusyBridgeAction}
              onClick={() => void handleApplyMirror()}
              type="button"
            >
              {busyAction === "apply" ? TEXT.workingApply : TEXT.applyMirror}
            </button>
          </div>
          <p className="panel-caption">
            {activityMessage || (canSave ? TEXT.bridgeModeDesktop : TEXT.bridgeModePreview)}
          </p>

          <OutputPathPanel
            canCopyPath={canCopyPath}
            canManage={canManageOutputPaths}
            canRevealPath={canRevealPath}
            draftSettings={outputPathDraft}
            resolvedSettings={outputPathState.resolved}
            settingsFile={outputPathState.settingsFile}
            busyAction={busyOutputAction}
            hasPendingChanges={hasPendingOutputPathChanges}
            onChange={handleOutputPathDraftChange}
            onBrowse={handlePickOutputPath}
            onCopyPath={handleCopyPath}
            onRevealPath={handleRevealPath}
            onReset={handleResetOutputPaths}
            onSave={handleSaveOutputPaths}
            formatPath={shortenPath}
          />

          <section className="detail-section">
            <div className="detail-section-header">
              <h4>{TEXT.importTitle}</h4>
            </div>
            <p className="panel-caption">{TEXT.importHint}</p>
            <div className="bridge-actions">
              <button
                className="action-button"
                disabled={!canImportPreviewReport || hasBusyBridgeAction}
                onClick={() => void handleImportPreviewReport()}
                type="button"
              >
                {busyImportAction === "preview" ? TEXT.workingImportPreview : TEXT.importPreview}
              </button>
              <button
                className="action-button action-button-ghost"
                disabled={!canImportBatchUpdates || hasBusyBridgeAction}
                onClick={() => void handleImportBatchUpdates()}
                type="button"
              >
                {busyImportAction === "payload" ? TEXT.workingImportPayload : TEXT.importPayload}
              </button>
            </div>
          </section>

          <section className="detail-section">
            <div className="detail-section-header">
              <h4>{TEXT.diffTitle}</h4>
            </div>
            <p className="panel-caption">
              {selectedSourceFile
                ? `${TEXT.filterActive}\uff1a${shortenPath(selectedSourceFile)}`
                : TEXT.diffHint}
            </p>
            {visibleFileDiffs.length === 0 ? (
              <div className="empty-state">{TEXT.diffEmpty}</div>
            ) : (
              <div className="diff-file-list">
                {visibleFileDiffs.map((summary) => (
                  <DiffSummaryCard
                    key={summary.sourceFile}
                    summary={summary}
                    selected={summary.sourceFile === selectedSourceFile}
                    onToggleFile={handleToggleSourceFile}
                  />
                ))}
              </div>
            )}
          </section>

          <section className="detail-section">
            <div className="detail-section-header">
              <h4>{TEXT.artifactTitle}</h4>
            </div>
            <div className="artifact-list">
              {artifactEntries.map((artifact) => (
                <ArtifactCard
                  key={artifact.key}
                  title={artifact.title}
                  entry={artifact.entry}
                  canInspect={canInspectArtifacts}
                  canCopyPath={canCopyPath}
                  canRevealPath={canRevealPath}
                  onCopyPath={handleCopyPath}
                  onRevealPath={handleRevealPath}
                />
              ))}
            </div>
            <p className="panel-caption">{TEXT.artifactHint}</p>
          </section>
          <HistoryPanel
            entries={reportHistory}
            canCopyPath={canCopyPath}
            canRevealPath={canRevealPath}
            canRefresh={canReadReportHistory}
            onCopyPath={handleCopyPath}
            onRevealPath={handleRevealPath}
            onRefresh={refreshReportHistory}
          />
          <ChangelogPanel />
          <FormulaBar />
          <ValidationPanel />
          <TierView />
          <FieldConfigPanel />

          <section className="detail-section">
            <div className="detail-section-header">
              <h4>{TEXT.selectedDetail}</h4>
            </div>
            {selectedRow ? (
              <article className="detail-card">
                <div className="detail-card-topline">
                  <strong>{formatChangeLabel(selectedRow.xmlPath, selectedRow.attribute)}</strong>
                  <span>{translateRowStatus(selectedRow)}</span>
                </div>
                <p className="detail-path">{shortenPath(selectedRow.sourceFile)}</p>
                <div className="detail-meta">
                  <span>
                    {TEXT.linePrefix} {selectedRow.sourceLine} {TEXT.lineSuffix}
                  </span>
                  <span>{translateWriteMode(selectedRow.writeMode)}</span>
                </div>
                <div className="detail-values">
                  <div>
                    <label>{TEXT.beforeLabel}</label>
                    <strong>{selectedRow.beforeValue}</strong>
                  </div>
                  <div>
                    <label>{TEXT.stagedLabel}</label>
                    <strong>{selectedRow.stagedValue}</strong>
                  </div>
                </div>
              </article>
            ) : (
              <div className="empty-state">{TEXT.emptySelection}</div>
            )}
          </section>

          <section className="detail-section">
            <div className="detail-section-header">
              <h4>{TEXT.commandTemplate}</h4>
            </div>
            <pre className="code-block">{buildBatchCommandTemplate(outputPathState.settings)}</pre>
          </section>

          <section className="detail-section">
            <div className="detail-section-header">
              <h4>{TEXT.exportPayload}</h4>
            </div>
            {payload.length === 0 ? (
              <div className="empty-state">{TEXT.emptyPayload}</div>
            ) : (
              <pre className="code-block code-block-payload">{payloadText}</pre>
            )}
            <p className="panel-caption">{TEXT.exportNote}</p>
          </section>
        </article>
      </section>

      <section className="content-grid content-grid-lower">
        <article className="panel">
          <div className="panel-header">
            <p>{TEXT.unknownPanel}</p>
            <h3>{TEXT.unknownTitle}</h3>
          </div>
          <div className="field-list">
            {topUnknownFields.map((item) => (
              <FieldRecordCard key={item.field} item={item} emphasize="warning" />
            ))}
          </div>
        </article>

        <article className="panel">
          <div className="panel-header">
            <p>{TEXT.knownPanel}</p>
            <h3>{TEXT.knownTitle}</h3>
          </div>
          <div className="field-list">
            {topKnownFields.map((item) => (
              <FieldRecordCard key={item.field} item={item} emphasize="normal" />
            ))}
          </div>
        </article>
      </section>
    </main>
  );
}

function EditorRowCard({
  row,
  selected,
  onSelect,
  onValueChange,
  onRestoreSuggested,
  onRestoreOriginal
}: {
  row: EditorRow;
  selected: boolean;
  onSelect: () => void;
  onValueChange: (rowId: string, nextValue: string) => void;
  onRestoreSuggested: (rowId: string) => void;
  onRestoreOriginal: (rowId: string) => void;
}) {
  const [localValue, setLocalValue] = useState(row.stagedValue);
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    if (!editing) setLocalValue(row.stagedValue);
  }, [row.stagedValue, editing]);

  return (
    <article
      className={`editor-row-card ${selected ? "editor-row-card-selected" : ""}`}
      onClick={onSelect}
    >
      <div className="editor-row-topline">
        <div>
          <h4>{formatChangeLabel(row.xmlPath, row.attribute)}</h4>
          <p className="editor-row-path">{shortenPath(row.sourceFile)}</p>
        </div>
        <span className={`status-pill ${isRowChanged(row) ? "status-pill-active" : "status-pill-muted"}`}>
          {selected ? `${TEXT.selected} / ${translateRowStatus(row)}` : translateRowStatus(row)}
        </span>
      </div>
      <div className="editor-row-meta">
        <span>
          {TEXT.linePrefix} {row.sourceLine} {TEXT.lineSuffix}
        </span>
        <span>{TEXT.outputPath}\uff1a{shortenPath(row.outputFile)}</span>
      </div>
      <div className="editor-value-grid">
        <div className="value-box">
          <label>{TEXT.beforeLabel}</label>
          <strong>{row.beforeValue}</strong>
        </div>
        <div className="value-box">
          <label>{TEXT.suggestedLabel}</label>
          <strong>{row.suggestedValue}</strong>
        </div>
        <label className="value-editor" onClick={(event) => event.stopPropagation()}>
          <span>{TEXT.stagedLabel}</span>
          <input
            value={editing ? localValue : row.stagedValue}
            onFocus={() => setEditing(true)}
            onChange={(event) => setLocalValue(event.currentTarget.value)}
            onBlur={() => {
              setEditing(false);
              if (localValue !== row.stagedValue) {
                onValueChange(row.id, localValue);
              }
            }}
            onKeyDown={(e) => {
              if (e.key === "Enter") e.currentTarget.blur();
              if (e.key === "Escape") {
                setLocalValue(row.stagedValue);
                setEditing(false);
                e.currentTarget.blur();
              }
              if ((e.key === "z" || e.key === "y") && (e.ctrlKey || e.metaKey)) {
                e.stopPropagation();
              }
            }}
          />
        </label>
      </div>
      <div className="editor-row-actions" onClick={(event) => event.stopPropagation()}>
        <button className="mini-button" type="button" onClick={() => onRestoreSuggested(row.id)}>
          {TEXT.restoreSuggested}
        </button>
        <button
          className="mini-button mini-button-ghost"
          type="button"
          onClick={() => onRestoreOriginal(row.id)}
        >
          {TEXT.restoreOriginal}
        </button>
      </div>
    </article>
  );
}

function DiffSummaryCard({
  summary,
  selected,
  onToggleFile
}: {
  summary: EditorFileDiffSummary;
  selected: boolean;
  onToggleFile: (sourceFile: string) => void;
}) {
  const visibleChanges = summary.changes.slice(0, 3);
  const hiddenChangeCount = summary.changes.length - visibleChanges.length;

  return (
    <article className={`diff-file-card ${selected ? "diff-file-card-selected" : ""}`}>
      <div className="detail-card-topline">
        <strong>{shortenPath(summary.sourceFile)}</strong>
        <div className="card-actions-inline">
          <span>{translateWriteMode(summary.writeMode)}</span>
          <button
            className={`mini-button ${selected ? "mini-button-ghost" : ""}`}
            onClick={() => onToggleFile(summary.sourceFile)}
            type="button"
          >
            {selected ? TEXT.clearFileFilter : TEXT.filterThisFile}
          </button>
        </div>
      </div>
      <p className="detail-path">{shortenPath(summary.outputFile)}</p>
      <div className="diff-file-meta">
        <span>
          {TEXT.diffChangedRows}\uff1a{formatNumber(summary.changedRows)}
        </span>
        <span>
          {TEXT.diffTotalRows}\uff1a{formatNumber(summary.totalRows)}
        </span>
      </div>
      <div className="diff-change-list">
        {visibleChanges.map((change) => (
          <div className="diff-change-row" key={change.id}>
            <span>{formatChangeLabel(change.xmlPath, change.attribute)}</span>
            <strong>
              {change.beforeValue} -&gt; {change.stagedValue}
            </strong>
          </div>
        ))}
      </div>
      {hiddenChangeCount > 0 ? (
        <p className="diff-more">
          {TEXT.diffMore} {formatNumber(hiddenChangeCount)} \u9879
        </p>
      ) : null}
    </article>
  );
}

function ArtifactCard({
  title,
  entry,
  canInspect,
  canCopyPath,
  canRevealPath,
  onCopyPath,
  onRevealPath
}: {
  title: string;
  entry: ArtifactStateEntry;
  canInspect: boolean;
  canCopyPath: boolean;
  canRevealPath: boolean;
  onCopyPath: (targetPath: string) => Promise<void>;
  onRevealPath: (targetPath: string) => Promise<void>;
}) {
  return (
    <article className="artifact-card">
      <div className="detail-card-topline">
        <strong>{title}</strong>
        <span>{resolveArtifactStatus(entry, canInspect)}</span>
      </div>
      <p className="detail-path">{shortenPath(entry.path)}</p>
      <div className="artifact-meta">
        <span>{entry.kind === "directory" ? TEXT.artifactDirectory : TEXT.artifactFile}</span>
        {entry.updatedAt ? <span>{TEXT.modifiedAt}\uff1a{formatDateTime(entry.updatedAt)}</span> : null}
        {typeof entry.size === "number" ? <span>{TEXT.artifactSize}\uff1a{formatBytes(entry.size)}</span> : null}
        {typeof entry.fileCount === "number" ? <span>{TEXT.artifactFiles}\uff1a{formatNumber(entry.fileCount)}</span> : null}
      </div>
      <div className="artifact-actions">
        <button
          className="mini-button mini-button-ghost"
          disabled={!canCopyPath}
          onClick={() => void onCopyPath(entry.path)}
          type="button"
        >
          {TEXT.copyPath}
        </button>
        <button
          className="mini-button"
          disabled={!canRevealPath || !canInspect || !entry.exists}
          onClick={() => void onRevealPath(entry.path)}
          type="button"
        >
          {TEXT.revealPath}
        </button>
      </div>
    </article>
  );
}

function buildArtifactEntries(state?: ArtifactState): Array<{
  key: keyof ArtifactState;
  title: string;
  entry: ArtifactStateEntry;
}> {
  const source = state ?? placeholderArtifacts;

  return [
    {
      key: "generatedInput",
      title: TEXT.generatedInput,
      entry: source.generatedInput
    },
    {
      key: "previewReport",
      title: TEXT.previewArtifact,
      entry: source.previewReport
    },
    {
      key: "batchSetReport",
      title: TEXT.batchSetArtifact,
      entry: source.batchSetReport
    },
    {
      key: "batchOutputDir",
      title: TEXT.outputDirectoryArtifact,
      entry: source.batchOutputDir
    }
  ];
}

function resolveArtifactStatus(entry: ArtifactStateEntry, canInspect: boolean): string {
  if (!canInspect) {
    return TEXT.artifactPlanned;
  }

  return entry.exists ? TEXT.artifactReady : TEXT.artifactMissing;
}
function FieldRecordCard({
  item,
  emphasize
}: {
  item: FieldUsageRecord;
  emphasize: "warning" | "normal";
}) {
  return (
    <article className={`field-card field-card-${emphasize}`}>
      <div className="field-card-topline">
        <h4>{item.field}</h4>
        <span>
          {item.classification === "unknown"
            ? TEXT.unclassified
            : translateClassification(item.classification)}
        </span>
      </div>
      <div className="field-meta">
        <span>
          {TEXT.occurrences} {formatNumber(item.occurrences)} {TEXT.occurrencesSuffix}
        </span>
        <span>{item.entityKinds.join(" / ")}</span>
      </div>
      <p className="field-sample">{item.samplePaths[0]}</p>
    </article>
  );
}

function translateClassification(value: FieldUsageRecord["classification"]): string {
  switch (value) {
    case "numeric":
      return "\u6570\u503c";
    case "nested-numeric":
      return "\u5d4c\u5957\u6570\u503c";
    case "string":
      return "\u5b57\u7b26\u4e32";
    case "boolean":
      return "\u5e03\u5c14";
    case "attribute":
      return "\u5c5e\u6027";
    case "item-level":
      return "\u7269\u54c1\u7ea7\u5b57\u6bb5";
    case "passthrough":
      return "\u900f\u4f20";
    case "computed":
      return "\u6d3e\u751f";
    default:
      return "\u672a\u77e5";
  }
}

function translateWriteMode(value: BatchPreviewReport["files"][number]["writeMode"]): string {
  switch (value) {
    case "in-place":
      return "\u539f\u5730\u5199\u5165";
    case "mirrored-output":
      return "\u955c\u50cf\u8f93\u51fa";
    default:
      return "\u4ec5\u9884\u89c8";
  }
}

function translateRowStatus(row: EditorRow): string {
  return isRowChanged(row) ? TEXT.staged : TEXT.unchanged;
}

function formatChangeLabel(xmlPath: string, attribute?: string): string {
  return attribute ? `${xmlPath}@${attribute}` : xmlPath;
}

function shortenPath(value: string): string {
  const normalizedValue = value.replaceAll("/", "\\");
  const marker = "CrazyFlashNight\\";
  const markerIndex = normalizedValue.indexOf(marker);

  if (markerIndex >= 0) {
    return normalizedValue.slice(markerIndex + marker.length).replaceAll("\\", "/");
  }

  return value.replaceAll("\\", "/");
}


function formatNumber(value: number): string {
  return new Intl.NumberFormat("zh-CN").format(value);
}

function formatDateTime(value: string): string {
  if (!value) {
    return "—";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function formatBytes(value: number): string {
  if (value < 1024) {
    return `${formatNumber(value)} B`;
  }

  if (value < 1024 * 1024) {
    return `${new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 1 }).format(
      value / 1024
    )} KB`;
  }

  return `${new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 1 }).format(
    value / (1024 * 1024)
  )} MB`;
}

function toErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

