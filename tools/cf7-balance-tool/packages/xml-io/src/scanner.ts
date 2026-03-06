import fs from "node:fs";
import path from "node:path";

import {
  classifyField,
  sortFieldUsage,
  uniquePreservingOrder
} from "@cf7-balance-tool/core";
import type {
  DiscoveredXmlFile,
  FieldOccurrence,
  FieldRegistry,
  FieldScanReport,
  FieldUsageRecord,
  XmlEntityKind
} from "@cf7-balance-tool/core";

import {
  loadProjectContext,
  type LoadedProjectContext
} from "./project-context.js";

interface XmlNode {
  name: string;
  attributes: string[];
  children: XmlNode[];
  textSegments: string[];
}

const XML_TOKEN_REGEX =
  /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[[\s\S]*?\]\]>|<\/?[^>]+?>/g;

export function discoverXmlFiles(
  projectConfigPath: string
): DiscoveredXmlFile[] {
  const context = loadProjectContext(projectConfigPath);
  return discoverXmlFilesFromContext(context);
}

export function discoverXmlFilesFromContext(
  context: LoadedProjectContext
): DiscoveredXmlFile[] {
  const roots = [
    context.resolvedDirs.items,
    context.resolvedDirs.mods,
    context.resolvedDirs.enemies
  ].filter((value): value is string => Boolean(value));

  const discovered: DiscoveredXmlFile[] = [];

  for (const currentRoot of roots) {
    if (!fs.existsSync(currentRoot)) {
      continue;
    }

    visitDirectory(currentRoot, currentRoot);
  }

  return discovered.sort((left, right) =>
    left.relativePath.localeCompare(right.relativePath)
  );

  function visitDirectory(root: string, currentDir: string): void {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });

    for (const entry of entries) {
      const absoluteEntryPath = path.join(currentDir, entry.name);

      if (
        entry.isDirectory() &&
        roots.some(
          (otherRoot) =>
            otherRoot !== root && isSameOrNestedPath(absoluteEntryPath, otherRoot)
        )
      ) {
        continue;
      }

      if (entry.isDirectory()) {
        visitDirectory(root, absoluteEntryPath);
        continue;
      }

      if (!entry.name.toLowerCase().endsWith(".xml")) {
        continue;
      }

      discovered.push({
        absolutePath: absoluteEntryPath,
        relativePath: toPosixPath(path.relative(context.projectRoot, absoluteEntryPath)),
        entityKind: classifyXmlFile(absoluteEntryPath)
      });
    }
  }
}

export function scanProjectFields(projectConfigPath: string): FieldScanReport {
  const context = loadProjectContext(projectConfigPath);
  const files = discoverXmlFilesFromContext(context);
  const occurrences = files.flatMap((file) =>
    scanXmlFile(file, context.fieldRegistry, context.projectRoot)
  );

  const usageByField = new Map<string, FieldUsageRecord>();

  for (const occurrence of occurrences) {
    const existing = usageByField.get(occurrence.field);

    if (existing) {
      existing.occurrences += 1;
      existing.files = uniquePreservingOrder([...existing.files, occurrence.file]);
      existing.samplePaths = uniquePreservingOrder([
        ...existing.samplePaths,
        occurrence.path
      ]).slice(0, 8);
      existing.entityKinds = uniquePreservingOrder([
        ...existing.entityKinds,
        occurrence.entityKind
      ]) as XmlEntityKind[];
      continue;
    }

    usageByField.set(occurrence.field, {
      field: occurrence.field,
      classification: occurrence.classification,
      occurrences: 1,
      files: [occurrence.file],
      samplePaths: [occurrence.path],
      entityKinds: [occurrence.entityKind]
    });
  }

  const usage = sortFieldUsage([...usageByField.values()]);
  const unknownFields = usage
    .filter((record) => record.classification === "unknown")
    .map((record) => record.field);

  return {
    generatedAt: new Date().toISOString(),
    projectConfigPath: context.projectConfigPath,
    projectRoot: context.projectRoot,
    totals: {
      files: files.length,
      fields: usage.length,
      occurrences: occurrences.length,
      unknownFields: unknownFields.length
    },
    files,
    usage,
    unknownFields
  };
}

export function scanXmlContent(
  xml: string,
  file: string,
  entityKind: XmlEntityKind,
  fieldRegistry: FieldRegistry
): FieldOccurrence[] {
  const rootNode = parseXmlTree(xml);
  const occurrences: FieldOccurrence[] = [];

  collectOccurrences(rootNode, [], file, entityKind, fieldRegistry, occurrences);

  return occurrences;
}

function scanXmlFile(
  file: DiscoveredXmlFile,
  fieldRegistry: FieldRegistry,
  projectRoot: string
): FieldOccurrence[] {
  const xml = fs.readFileSync(file.absolutePath, "utf8");

  return scanXmlContent(
    xml,
    toPosixPath(path.relative(projectRoot, file.absolutePath)),
    file.entityKind,
    fieldRegistry
  );
}

function parseXmlTree(xml: string): XmlNode {
  const documentNode: XmlNode = {
    name: "#document",
    attributes: [],
    children: [],
    textSegments: []
  };

  const stack: XmlNode[] = [documentNode];
  let lastTokenIndex = 0;

  for (const match of xml.matchAll(XML_TOKEN_REGEX)) {
    const token = match[0];
    const tokenIndex = match.index ?? 0;
    const textSegment = xml.slice(lastTokenIndex, tokenIndex).trim();

    if (textSegment.length > 0) {
      stack[stack.length - 1]?.textSegments.push(textSegment);
    }

    if (
      token.startsWith("<!--") ||
      token.startsWith("<?") ||
      token.startsWith("<!")
    ) {
      lastTokenIndex = tokenIndex + token.length;
      continue;
    }

    if (token.startsWith("</")) {
      const closingTag = token.slice(2, -1).trim();

      while (stack.length > 1) {
        const current = stack.pop();

        if (current?.name === closingTag) {
          break;
        }
      }

      lastTokenIndex = tokenIndex + token.length;
      continue;
    }

    const openingMatch = /^<([^\s/>]+)/.exec(token);

    if (!openingMatch) {
      lastTokenIndex = tokenIndex + token.length;
      continue;
    }

    const nodeName = openingMatch[1];

    if (!nodeName) {
      lastTokenIndex = tokenIndex + token.length;
      continue;
    }

    const node: XmlNode = {
      name: nodeName,
      attributes: parseAttributes(token),
      children: [],
      textSegments: []
    };

    stack[stack.length - 1]?.children.push(node);

    if (!token.endsWith("/>")) {
      stack.push(node);
    }

    lastTokenIndex = tokenIndex + token.length;
  }

  return documentNode;
}

function parseAttributes(token: string): string[] {
  const attributes: string[] = [];
  const attributeRegex = /([^\s=/>]+)\s*=\s*(?:"[^"]*"|'[^']*')/g;

  for (const match of token.matchAll(attributeRegex)) {
    if (match[1]) {
      attributes.push(match[1]);
    }
  }

  return attributes;
}

function collectOccurrences(
  node: XmlNode,
  parentSegments: string[],
  file: string,
  entityKind: XmlEntityKind,
  fieldRegistry: FieldRegistry,
  occurrences: FieldOccurrence[]
): void {
  for (const child of node.children) {
    const pathSegments = [...parentSegments, child.name];
    const currentPath = pathSegments.join(".");

    for (const attribute of child.attributes) {
      const field = `@${attribute}`;
      occurrences.push({
        field,
        path: `${currentPath}.${field}`,
        file,
        entityKind,
        classification: classifyField(field, fieldRegistry, [...pathSegments, field])
      });
    }

    if (child.children.length === 0 || child.textSegments.length > 0) {
      occurrences.push({
        field: child.name,
        path: currentPath,
        file,
        entityKind,
        classification: classifyField(child.name, fieldRegistry, pathSegments)
      });
    }

    collectOccurrences(
      child,
      pathSegments,
      file,
      entityKind,
      fieldRegistry,
      occurrences
    );
  }
}

function classifyXmlFile(absolutePath: string): XmlEntityKind {
  const normalizedPath = toPosixPath(absolutePath);
  const fileName = path.basename(absolutePath);

  if (fileName === "list.xml") {
    return "list";
  }

  if (normalizedPath.includes("/equipment_mods/")) {
    return "mod";
  }

  if (normalizedPath.includes("/enemy_properties/")) {
    return "enemy";
  }

  if (fileName === "bullets_cases.xml") {
    return "bullet-case";
  }

  if (fileName.startsWith("武器_") || fileName.startsWith("防具_")) {
    return "equipment";
  }

  if (fileName.startsWith("消耗品_")) {
    return "consumable";
  }

  return "misc";
}

function isSameOrNestedPath(candidate: string, target: string): boolean {
  const normalizedCandidate = path.resolve(candidate);
  const normalizedTarget = path.resolve(target);

  if (normalizedCandidate === normalizedTarget) {
    return true;
  }

  const relativePath = path.relative(normalizedTarget, normalizedCandidate);
  return (
    relativePath.length > 0 &&
    !relativePath.startsWith("..") &&
    !path.isAbsolute(relativePath)
  );
}

function toPosixPath(value: string): string {
  return value.split(path.sep).join("/");
}