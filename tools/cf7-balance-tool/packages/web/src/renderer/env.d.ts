import type { OutputPathSettings } from "../shared/output-path-settings";

export {};

declare global {
  interface Window {
    cf7Balance?: {
      runtime: string;
      versions: Record<string, string>;
      getArtifactState?: () => Promise<{
        generatedInput: ArtifactStateEntry;
        previewReport: ArtifactStateEntry;
        batchSetReport: ArtifactStateEntry;
        batchOutputDir: ArtifactStateEntry;
      }>;
      getReportHistory?: () => Promise<ReportHistoryEntry[]>;
      getOutputSettings?: () => Promise<OutputPathBridgeResponse>;
      saveOutputSettings?: (settings: OutputPathSettings) => Promise<OutputPathBridgeResponse>;
      resetOutputSettings?: () => Promise<OutputPathBridgeResponse>;
      pickOutputPath?: (
        key: keyof OutputPathSettings,
        currentValue?: string
      ) => Promise<{
        canceled: boolean;
        path?: string;
      }>; 
      pickPreviewReport?: () => Promise<{
        canceled: boolean;
        path?: string;
        report?: unknown;
      }>; 
      pickBatchUpdates?: () => Promise<{
        canceled: boolean;
        path?: string;
        updates?: BatchUpdateRequest[];
        count?: number;
      }>;
      revealPath?: (targetPath: string) => Promise<{
        path: string;
      }>;
      saveBatchUpdates?: (updates: BatchUpdateRequest[]) => Promise<BridgeActionResponse>;
      runBatchPreview?: (updates: BatchUpdateRequest[]) => Promise<BridgeActionResponse>;
      runBatchSet?: (updates: BatchUpdateRequest[]) => Promise<BridgeActionResponse>;
      getChangelog?: () => Promise<ChangelogEntry[]>;
      runValidation?: () => Promise<ValidationReport>;
      getFieldConfig?: () => Promise<FieldRegistryData>;
      saveFieldConfig?: (config: FieldRegistryData) => Promise<{ saved: boolean }>;
    };
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
}

interface BatchUpdateRequest {
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

interface OutputPathBridgeResponse {
  outputSettings: OutputPathState;
  artifacts: {
    generatedInput: ArtifactStateEntry;
    previewReport: ArtifactStateEntry;
    batchSetReport: ArtifactStateEntry;
    batchOutputDir: ArtifactStateEntry;
  };
  history: ReportHistoryEntry[];
  previewReport?: unknown;
}

interface ChangelogEntry {
  timestamp: string;
  action: string;
  inputFile: string;
  summary: Record<string, unknown>;
  outputDir: string | null;
}

interface BridgeActionResponse {
  savedTo: string;
  reportPath?: string;
  report?: unknown;
  count: number;
  artifacts: {
    generatedInput: ArtifactStateEntry;
    previewReport: ArtifactStateEntry;
    batchSetReport: ArtifactStateEntry;
    batchOutputDir: ArtifactStateEntry;
  };
}

