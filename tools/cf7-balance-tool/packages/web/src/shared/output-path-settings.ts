export interface OutputPathSettings {
  generatedInputPath: string;
  previewReportPath: string;
  batchSetReportPath: string;
  batchOutputDir: string;
}

export type OutputPathSettingKey = keyof OutputPathSettings;

export interface OutputPathFieldDefinition {
  key: OutputPathSettingKey;
  label: string;
  kind: "file" | "directory";
}

export const DEFAULT_OUTPUT_PATH_SETTINGS: OutputPathSettings = {
  generatedInputPath: "reports/manual-updates.generated.json",
  previewReportPath: "reports/batch-preview-report.json",
  batchSetReportPath: "reports/batch-set-report.json",
  batchOutputDir: "reports/batch-output"
};

export const OUTPUT_PATH_FIELDS: OutputPathFieldDefinition[] = [
  {
    key: "generatedInputPath",
    label: "\u624b\u52a8 payload",
    kind: "file"
  },
  {
    key: "previewReportPath",
    label: "preview \u62a5\u544a",
    kind: "file"
  },
  {
    key: "batchSetReportPath",
    label: "batch-set \u62a5\u544a",
    kind: "file"
  },
  {
    key: "batchOutputDir",
    label: "\u955c\u50cf\u8f93\u51fa\u76ee\u5f55",
    kind: "directory"
  }
];

export function normalizeOutputPathSettings(
  value?: Partial<OutputPathSettings> | null
): OutputPathSettings {
  return {
    generatedInputPath: normalizeSettingValue(
      value?.generatedInputPath,
      DEFAULT_OUTPUT_PATH_SETTINGS.generatedInputPath
    ),
    previewReportPath: normalizeSettingValue(
      value?.previewReportPath,
      DEFAULT_OUTPUT_PATH_SETTINGS.previewReportPath
    ),
    batchSetReportPath: normalizeSettingValue(
      value?.batchSetReportPath,
      DEFAULT_OUTPUT_PATH_SETTINGS.batchSetReportPath
    ),
    batchOutputDir: normalizeSettingValue(
      value?.batchOutputDir,
      DEFAULT_OUTPUT_PATH_SETTINGS.batchOutputDir
    )
  };
}

export function buildBatchCommandTemplate(settings: OutputPathSettings): string {
  const normalized = normalizeOutputPathSettings(settings);

  return [
    `npm run batch-preview -- --project ./project.json --input ${formatCommandPath(normalized.generatedInputPath)} --output ${formatCommandPath(normalized.previewReportPath)} --output-dir ${formatCommandPath(normalized.batchOutputDir)}`,
    `npm run batch-set -- --project ./project.json --input ${formatCommandPath(normalized.generatedInputPath)} --output ${formatCommandPath(normalized.batchSetReportPath)} --output-dir ${formatCommandPath(normalized.batchOutputDir)}`
  ].join("\n");
}

function formatCommandPath(value: string): string {
  return /\s/.test(value) ? `"${value}"` : value;
}

function normalizeSettingValue(value: string | undefined, fallback: string): string {
  const trimmedValue = value?.trim();
  return trimmedValue ? trimmedValue.replaceAll("\\", "/") : fallback;
}
