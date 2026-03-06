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
  buildBatchUpdatesPayload,
  createEditorRows,
  filterEditorRows,
  isRowChanged,
  restoreAllRowsToOriginal,
  restoreAllRowsToSuggested,
  restoreRowToOriginal,
  restoreRowToSuggested,
  summarizeEditorRows,
  updateRowStagedValue,
  type BatchPreviewReport,
  type EditorRow
} from "./editor-model";

const fieldUsageReport = rawFieldUsageReport as FieldScanReport;
const batchPreviewReport = rawBatchPreviewReport as BatchPreviewReport;
const initialEditorRows = createEditorRows(batchPreviewReport);

const TEXT = {
  title: "\u6570\u503c\u5e73\u8861\u5de5\u4f5c\u53f0",
  intro:
    "\u9762\u5411 XML \u6570\u636e\u3001CLI \u81ea\u52a8\u5316\u548c\u684c\u9762\u7f16\u8f91\u5668\u7684\u7edf\u4e00\u5165\u53e3\u3002\u5f53\u524d\u754c\u9762\u5df2\u63a5\u5165\u5b57\u6bb5\u626b\u63cf\u3001round-trip \u6821\u9a8c\u548c\u6279\u91cf\u53d8\u66f4\u9884\u89c8\uff0c\u5e76\u652f\u6301\u5728\u9875\u9762\u5185\u4e34\u65f6\u8c03\u6574\u66f4\u65b0\u503c\u3002",
  runtimeDesktop: "\u684c\u9762\u6a21\u5f0f",
  runtimePreview: "\u6e32\u67d3\u5668\u9884\u89c8",
  pending: "\u5f85\u63a5\u7ebf",
  fieldReportTime: "\u5b57\u6bb5\u62a5\u544a\u65f6\u95f4",
  previewReportTime: "\u9884\u89c8\u62a5\u544a\u65f6\u95f4",
  runtimeHint:
    "\u9875\u9762\u76f4\u63a5\u8bfb\u53d6 reports/field-usage-report.json \u548c reports/batch-preview-report.json\u3002",
  lockedDecisions: "\u5df2\u9501\u5b9a\u8fb9\u754c",
  currentV1: "\u5f53\u524d v1 \u5171\u8bc6",
  fieldScan: "\u5b57\u6bb5\u626b\u63cf",
  firstBaseline: "\u9996\u8f6e\u6570\u636e\u57fa\u7ebf",
  scanNote:
    "\u5f53\u524d\u5b57\u6bb5\u626b\u63cf\u5668\u4ecd\u662f Phase 0 \u7684\u8bcd\u6cd5\u76d8\u70b9\u5c42\uff0c\u9002\u5408\u5feb\u901f\u53d1\u73b0\u672a\u5206\u7c7b\u5b57\u6bb5\u3002\u771f\u6b63\u7684 XML \u8bfb\u5199\u4e0e round-trip \u6821\u9a8c\u5df2\u7531\u72ec\u7acb\u8bfb\u5199\u5c42\u627f\u62c5\u3002",
  editorPanel: "\u6279\u91cf\u7f16\u8f91\u53f0",
  editorTitle: "\u5728\u9884\u89c8\u7ed3\u679c\u4e0a\u7ee7\u7eed\u8c03\u6574",
  editorHint:
    "\u5f53\u524d\u4ecd\u662f\u524d\u7aef\u6682\u5b58\u7f16\u8f91\uff0c\u4e0d\u76f4\u63a5\u6539\u5199\u672c\u5730\u6587\u4ef6\u3002\u4e0b\u65b9 JSON \u53ef\u76f4\u63a5\u4f9b CLI \u4f7f\u7528\u3002",
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
  reviewPanel: "\u786e\u8ba4\u9762\u677f",
  reviewTitle: "\u5bfc\u51fa JSON \u4e0e\u547d\u4ee4\u6a21\u677f",
  visibleRows: "\u5f53\u524d\u53ef\u89c1\u884c",
  activeFiles: "\u6709\u6548\u6587\u4ef6",
  stagedChanges: "\u6682\u5b58\u53d8\u66f4",
  outputMode: "\u8f93\u51fa\u6a21\u5f0f",
  selectedDetail: "\u9009\u4e2d\u884c\u8be6\u60c5",
  commandTemplate: "\u547d\u4ee4\u6a21\u677f",
  exportPayload: "\u5bfc\u51fa JSON",
  exportNote:
    "\u5bfc\u51fa payload \u9ed8\u8ba4\u4f7f\u7528\u7edd\u5bf9\u8def\u5f84\uff0c\u4fdd\u8bc1 CLI \u4ece\u4efb\u610f\u4f4d\u7f6e\u6267\u884c\u65f6\u4e0d\u4f1a\u4e22\u5931\u76ee\u6807\u6587\u4ef6\u3002",
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
    description: "\u5df2\u7ecf\u6709 before / after / \u884c\u53f7 / \u8f93\u51fa\u8def\u5f84\u3002"
  },
  {
    title: "\u7f16\u8f91\u9762\u677f",
    status: "\u672c\u8f6e\u63a5\u5165",
    description: "\u652f\u6301\u641c\u7d22\u3001\u7b5b\u9009\u3001\u6682\u5b58\u8c03\u6574\u548c JSON \u5bfc\u51fa\u3002"
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
  const [editorRows, setEditorRows] = useState(initialEditorRows);
  const [searchText, setSearchText] = useState("");
  const [showChangedOnly, setShowChangedOnly] = useState(false);
  const deferredSearchText = useDeferredValue(searchText);
  const filteredRows = filterEditorRows(editorRows, deferredSearchText, showChangedOnly);
  const [selectedRowId, setSelectedRowId] = useState<string | undefined>(
    initialEditorRows[0]?.id
  );

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

  const selectedRow =
    filteredRows.find((row) => row.id === selectedRowId) ??
    editorRows.find((row) => row.id === selectedRowId);
  const editorSummary = summarizeEditorRows(editorRows);
  const payload = buildBatchUpdatesPayload(editorRows);
  const payloadText = JSON.stringify(payload, null, 2);
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
    { label: TEXT.activeFiles, value: formatNumber(editorSummary.files) },
    { label: TEXT.stagedChanges, value: formatNumber(payload.length) },
    {
      label: TEXT.outputMode,
      value: translateWriteMode(batchPreviewReport.files[0]?.writeMode ?? "preview")
    }
  ] as const;

  function handleSearchChange(event: ChangeEvent<HTMLInputElement>): void {
    const nextValue = event.currentTarget.value;
    startTransition(() => {
      setSearchText(nextValue);
    });
  }

  function handleRowValueChange(rowId: string, nextValue: string): void {
    setEditorRows((currentRows) => updateRowStagedValue(currentRows, rowId, nextValue));
  }

  function handleRestoreRowSuggested(rowId: string): void {
    setEditorRows((currentRows) => restoreRowToSuggested(currentRows, rowId));
  }

  function handleRestoreRowOriginal(rowId: string): void {
    setEditorRows((currentRows) => restoreRowToOriginal(currentRows, rowId));
  }

  function handleRestoreAllSuggested(): void {
    setEditorRows((currentRows) => restoreAllRowsToSuggested(currentRows));
  }

  function handleRestoreAllOriginal(): void {
    setEditorRows((currentRows) => restoreAllRowsToOriginal(currentRows));
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
              <dd>{formatDateTime(batchPreviewReport.generatedAt)}</dd>
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

      <section className="content-grid content-grid-wide">
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
            <pre className="code-block">{buildCommandTemplate()}</pre>
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
            value={row.stagedValue}
            onChange={(event) => onValueChange(row.id, event.currentTarget.value)}
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
  const marker = "CrazyFlashNight\\";
  const markerIndex = value.indexOf(marker);

  if (markerIndex >= 0) {
    return value.slice(markerIndex + marker.length).replaceAll("\\", "/");
  }

  return value.replaceAll("\\", "/");
}

function buildCommandTemplate(): string {
  return [
    "npm run batch-preview -- --project ./project.json --input ./reports/manual-updates.json --output ./reports/batch-preview-report.json --output-dir ./reports/batch-output",
    "npm run batch-set -- --project ./project.json --input ./reports/manual-updates.json --output ./reports/batch-set-report.json --output-dir ./reports/batch-output"
  ].join("\n");
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("zh-CN").format(value);
}

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}