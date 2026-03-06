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