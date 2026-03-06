export type BatchPreviewWriteMode = "preview" | "in-place" | "mirrored-output";

export interface BatchPreviewChange {
  xmlPath: string;
  attribute?: string;
  beforeValue: string;
  afterValue: string;
  sourceLine: number;
  changed: boolean;
}

export interface BatchPreviewFile {
  sourceFile: string;
  outputFile: string;
  writeMode: BatchPreviewWriteMode;
  updates: number;
  changedValues: number;
  changes: BatchPreviewChange[];
}

export interface BatchPreviewReport {
  projectConfigPath?: string;
  inputPath?: string;
  generatedAt: string;
  operations: number;
  changedValues: number;
  files: BatchPreviewFile[];
}

export interface BatchUpdatePayload {
  filePath: string;
  xmlPath: string;
  value: string;
  attribute?: string;
}

export interface EditorRow {
  id: string;
  sourceFile: string;
  outputFile: string;
  writeMode: BatchPreviewWriteMode;
  xmlPath: string;
  attribute?: string;
  beforeValue: string;
  suggestedValue: string;
  stagedValue: string;
  sourceLine: number;
}

export interface EditorSummary {
  files: number;
  operations: number;
  changedValues: number;
}

export interface EditorFileDiffChange {
  id: string;
  xmlPath: string;
  attribute?: string;
  beforeValue: string;
  stagedValue: string;
  sourceLine: number;
}

export interface EditorFileDiffSummary {
  sourceFile: string;
  outputFile: string;
  writeMode: BatchPreviewWriteMode;
  totalRows: number;
  changedRows: number;
  changes: EditorFileDiffChange[];
}

export function createEditorRows(report: BatchPreviewReport): EditorRow[] {
  return report.files.flatMap((file, fileIndex) =>
    file.changes.map((change, changeIndex) => {
      const row: EditorRow = {
        id: `${fileIndex}:${changeIndex}:${change.xmlPath}:${change.attribute ?? "text"}`,
        sourceFile: file.sourceFile,
        outputFile: file.outputFile,
        writeMode: file.writeMode,
        xmlPath: change.xmlPath,
        beforeValue: change.beforeValue,
        suggestedValue: change.afterValue,
        stagedValue: change.afterValue,
        sourceLine: change.sourceLine
      };

      if (change.attribute) {
        row.attribute = change.attribute;
      }

      return row;
    })
  );
}

export function isRowChanged(row: EditorRow): boolean {
  return row.stagedValue !== row.beforeValue;
}

export function summarizeEditorRows(rows: EditorRow[]): EditorSummary {
  const changedRows = rows.filter(isRowChanged);
  const changedFiles = new Set(changedRows.map((row) => row.sourceFile));

  return {
    files: changedFiles.size,
    operations: rows.length,
    changedValues: changedRows.length
  };
}

export function summarizeEditorRowsByFile(rows: EditorRow[]): EditorFileDiffSummary[] {
  const summaries = new Map<string, EditorFileDiffSummary>();

  for (const row of rows) {
    const existingSummary = summaries.get(row.sourceFile);
    const summary =
      existingSummary ??
      {
        sourceFile: row.sourceFile,
        outputFile: row.outputFile,
        writeMode: row.writeMode,
        totalRows: 0,
        changedRows: 0,
        changes: []
      };

    summary.totalRows += 1;

    if (isRowChanged(row)) {
      summary.changedRows += 1;

      const change: EditorFileDiffChange = {
        id: row.id,
        xmlPath: row.xmlPath,
        beforeValue: row.beforeValue,
        stagedValue: row.stagedValue,
        sourceLine: row.sourceLine
      };

      if (row.attribute) {
        change.attribute = row.attribute;
      }

      summary.changes.push(change);
    }

    if (!existingSummary) {
      summaries.set(row.sourceFile, summary);
    }
  }

  return Array.from(summaries.values())
    .filter((summary) => summary.changedRows > 0)
    .sort(
      (left, right) =>
        right.changedRows - left.changedRows || left.sourceFile.localeCompare(right.sourceFile)
    );
}

export function filterEditorRows(
  rows: EditorRow[],
  query: string,
  changedOnly: boolean
): EditorRow[] {
  const normalizedQuery = query.trim().toLowerCase();

  return rows.filter((row) => {
    if (changedOnly && !isRowChanged(row)) {
      return false;
    }

    if (normalizedQuery.length === 0) {
      return true;
    }

    const searchableText = [
      row.xmlPath,
      row.attribute ?? "",
      row.sourceFile,
      row.beforeValue,
      row.suggestedValue,
      row.stagedValue
    ]
      .join("\n")
      .toLowerCase();

    return searchableText.includes(normalizedQuery);
  });
}

export function buildBatchUpdatesPayload(rows: EditorRow[]): BatchUpdatePayload[] {
  return rows.flatMap((row) => {
    if (!isRowChanged(row)) {
      return [];
    }

    const payload: BatchUpdatePayload = {
      filePath: row.sourceFile,
      xmlPath: row.xmlPath,
      value: row.stagedValue
    };

    if (row.attribute) {
      payload.attribute = row.attribute;
    }

    return [payload];
  });
}

export function applyImportedBatchUpdates(
  rows: EditorRow[],
  updates: BatchUpdatePayload[]
): {
  rows: EditorRow[];
  matchedUpdates: number;
  unmatchedUpdates: number;
} {
  const candidates = new Map<string, number[]>();
  const nextRows = rows.map((row) => ({ ...row }));
  let matchedUpdates = 0;

  nextRows.forEach((row, index) => {
    const candidateKey = buildChangeKey(row.xmlPath, row.attribute);
    const currentIndexes = candidates.get(candidateKey) ?? [];
    currentIndexes.push(index);
    candidates.set(candidateKey, currentIndexes);
  });

  for (const update of updates) {
    const candidateIndexes = candidates.get(buildChangeKey(update.xmlPath, update.attribute));

    if (!candidateIndexes) {
      continue;
    }

    const matchedIndex = candidateIndexes.find((index) =>
      filePathsMatch(nextRows[index]!.sourceFile, update.filePath)
    );

    if (matchedIndex === undefined) {
      continue;
    }

    nextRows[matchedIndex] = {
      ...nextRows[matchedIndex]!,
      stagedValue: update.value
    };
    matchedUpdates += 1;
  }

  return {
    rows: nextRows,
    matchedUpdates,
    unmatchedUpdates: updates.length - matchedUpdates
  };
}

export function updateRowStagedValue(
  rows: EditorRow[],
  rowId: string,
  nextValue: string
): EditorRow[] {
  return rows.map((row) =>
    row.id === rowId
      ? {
          ...row,
          stagedValue: nextValue
        }
      : row
  );
}

export function restoreRowToSuggested(rows: EditorRow[], rowId: string): EditorRow[] {
  return rows.map((row) =>
    row.id === rowId
      ? {
          ...row,
          stagedValue: row.suggestedValue
        }
      : row
  );
}

export function restoreRowToOriginal(rows: EditorRow[], rowId: string): EditorRow[] {
  return rows.map((row) =>
    row.id === rowId
      ? {
          ...row,
          stagedValue: row.beforeValue
        }
      : row
  );
}

export function restoreAllRowsToSuggested(rows: EditorRow[]): EditorRow[] {
  return rows.map((row) => ({
    ...row,
    stagedValue: row.suggestedValue
  }));
}

export function restoreAllRowsToOriginal(rows: EditorRow[]): EditorRow[] {
  return rows.map((row) => ({
    ...row,
    stagedValue: row.beforeValue
  }));
}
function buildChangeKey(xmlPath: string, attribute?: string): string {
  return `${xmlPath}::${attribute ?? "text"}`;
}

function filePathsMatch(leftPath: string, rightPath: string): boolean {
  const normalizedLeft = normalizeFilePath(leftPath);
  const normalizedRight = normalizeFilePath(rightPath);

  return (
    normalizedLeft === normalizedRight ||
    normalizedLeft.endsWith(`/${normalizedRight}`) ||
    normalizedRight.endsWith(`/${normalizedLeft}`)
  );
}

function normalizeFilePath(value: string): string {
  return value.replaceAll("\\", "/").toLowerCase();
}
