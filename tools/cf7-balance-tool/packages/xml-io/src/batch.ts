import fs from "node:fs";
import path from "node:path";

import { loadXmlDocument } from "./document.js";

export interface XmlBatchUpdate {
  filePath: string;
  xmlPath: string;
  value: string;
  attribute?: string;
}

export interface XmlBatchOptions {
  baseDir?: string;
  inPlace?: boolean;
  outputDir?: string;
}

export type XmlBatchWriteMode = "preview" | "in-place" | "mirrored-output";

export interface XmlBatchChange {
  xmlPath: string;
  attribute?: string;
  beforeValue: string;
  afterValue: string;
  sourceLine: number;
  changed: boolean;
}

export interface XmlBatchFileResult {
  sourceFile: string;
  outputFile: string;
  writeMode: XmlBatchWriteMode;
  updates: number;
  changedValues: number;
  changes: XmlBatchChange[];
}

export interface XmlBatchPreviewResult {
  generatedAt: string;
  operations: number;
  changedValues: number;
  files: XmlBatchFileResult[];
}

export interface XmlBatchApplyResult extends XmlBatchPreviewResult {}

interface PreparedXmlBatchFile {
  result: XmlBatchFileResult;
  serialized: string;
}

export function previewXmlBatchUpdates(
  updates: XmlBatchUpdate[],
  options: XmlBatchOptions = {}
): XmlBatchPreviewResult {
  return buildXmlBatchResult(updates, options).report;
}

export function applyXmlBatchUpdates(
  updates: XmlBatchUpdate[],
  options: XmlBatchOptions = {}
): XmlBatchApplyResult {
  if (!options.inPlace && !options.outputDir) {
    throw new Error("Batch updates require --in-place or --output-dir.");
  }

  const prepared = buildXmlBatchResult(updates, options);

  for (const file of prepared.files) {
    fs.mkdirSync(path.dirname(file.result.outputFile), { recursive: true });
    fs.writeFileSync(file.result.outputFile, file.serialized, "utf8");
  }

  return prepared.report;
}

function buildXmlBatchResult(
  updates: XmlBatchUpdate[],
  options: XmlBatchOptions
): {
  report: XmlBatchPreviewResult;
  files: PreparedXmlBatchFile[];
} {
  const groupedUpdates = new Map<string, XmlBatchUpdate[]>();

  for (const update of updates) {
    const filePath = path.resolve(update.filePath);
    const fileUpdates = groupedUpdates.get(filePath);

    if (fileUpdates) {
      fileUpdates.push({ ...update, filePath });
      continue;
    }

    groupedUpdates.set(filePath, [{ ...update, filePath }]);
  }

  const files: PreparedXmlBatchFile[] = [];
  let changedValues = 0;

  for (const [sourceFile, fileUpdates] of groupedUpdates.entries()) {
    const document = loadXmlDocument(sourceFile);
    const changes = fileUpdates.map((update) => applyXmlBatchChange(document, update));
    const fileChangedValues = changes.filter((change) => change.changed).length;
    const outputTarget = resolveBatchOutputTarget(sourceFile, options);

    changedValues += fileChangedValues;
    files.push({
      result: {
        sourceFile,
        outputFile: outputTarget.outputFile,
        writeMode: outputTarget.writeMode,
        updates: fileUpdates.length,
        changedValues: fileChangedValues,
        changes
      },
      serialized: document.serialize()
    });
  }

  return {
    report: {
      generatedAt: new Date().toISOString(),
      operations: updates.length,
      changedValues,
      files: files.map((file) => file.result)
    },
    files
  };
}

function applyXmlBatchChange(document: ReturnType<typeof loadXmlDocument>, update: XmlBatchUpdate): XmlBatchChange {
  if (update.attribute) {
    const node = document.findNode(update.xmlPath);
    if (!node) {
      throw new Error(`XML path not found: ${update.xmlPath}`);
    }

    const attribute = node.attributes.find((item) => item.name === update.attribute);
    if (!attribute) {
      throw new Error(`Attribute not found: ${update.xmlPath}@${update.attribute}`);
    }

    const beforeValue = document.getAttribute(update.xmlPath, update.attribute);
    if (beforeValue === undefined) {
      throw new Error(`XML attribute not found: ${update.xmlPath}@${update.attribute}`);
    }

    document.setAttribute(update.xmlPath, update.attribute, update.value);

    return {
      xmlPath: update.xmlPath,
      attribute: update.attribute,
      beforeValue,
      afterValue: update.value,
      sourceLine: getLineNumber(document.originalSource, attribute.valueStart),
      changed: beforeValue !== update.value
    };
  }

  const node = document.findNode(update.xmlPath);
  if (!node) {
    throw new Error(`XML path not found: ${update.xmlPath}`);
  }

  const beforeValue = document.getNodeText(update.xmlPath);
  if (beforeValue === undefined) {
    throw new Error(`XML value not found: ${update.xmlPath}`);
  }

  document.setNodeText(update.xmlPath, update.value);

  return {
    xmlPath: update.xmlPath,
    beforeValue,
    afterValue: update.value,
    sourceLine: getLineNumber(document.originalSource, node.innerStart),
    changed: beforeValue !== update.value
  };
}

function resolveBatchOutputTarget(
  sourceFile: string,
  options: XmlBatchOptions
): {
  outputFile: string;
  writeMode: XmlBatchWriteMode;
} {
  if (options.inPlace) {
    return {
      outputFile: sourceFile,
      writeMode: "in-place"
    };
  }

  if (options.outputDir) {
    return {
      outputFile: resolveBatchOutputPath(sourceFile, options.outputDir, options.baseDir),
      writeMode: "mirrored-output"
    };
  }

  return {
    outputFile: sourceFile,
    writeMode: "preview"
  };
}

function resolveBatchOutputPath(
  sourceFile: string,
  outputDir: string,
  baseDir?: string
): string {
  const absoluteOutputDir = path.resolve(outputDir);

  if (baseDir) {
    const relativePath = path.relative(path.resolve(baseDir), sourceFile);

    if (
      relativePath.length > 0 &&
      !relativePath.startsWith("..") &&
      !path.isAbsolute(relativePath)
    ) {
      return path.join(absoluteOutputDir, relativePath);
    }
  }

  return path.join(absoluteOutputDir, path.basename(sourceFile));
}

function getLineNumber(source: string, offset: number): number {
  let lineNumber = 1;

  for (let index = 0; index < offset; index += 1) {
    if (source.charCodeAt(index) === 10) {
      lineNumber += 1;
    }
  }

  return lineNumber;
}