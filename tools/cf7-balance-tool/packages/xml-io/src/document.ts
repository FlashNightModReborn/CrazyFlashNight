import fs from "node:fs";

export interface XmlDocumentAttribute {
  name: string;
  value: string;
  quote: `"` | `'`;
  valueStart: number;
  valueEnd: number;
}

export interface XmlDocumentNode {
  name: string;
  attributes: XmlDocumentAttribute[];
  children: XmlDocumentNode[];
  startTagStart: number;
  startTagEnd: number;
  innerStart: number;
  innerEnd: number;
  endTagStart?: number;
  endTagEnd?: number;
  selfClosing: boolean;
}

interface XmlDocumentPatch {
  start: number;
  end: number;
  value: string;
}

interface PathSegmentSelector {
  name: string;
  index: number;
}

const XML_TOKEN_REGEX =
  /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[[\s\S]*?\]\]>|<\/?[^>]+?>/g;

export class XmlDocument {
  readonly filePath: string | undefined;
  readonly root: XmlDocumentNode;

  readonly #originalSource: string;
  readonly #patches = new Map<string, XmlDocumentPatch>();

  constructor(source: string, root: XmlDocumentNode, filePath?: string) {
    this.#originalSource = source;
    this.root = root;
    this.filePath = filePath;
  }

  static parse(source: string, filePath?: string): XmlDocument {
    return new XmlDocument(source, parseXmlTree(source), filePath);
  }

  get originalSource(): string {
    return this.#originalSource;
  }

  findNode(pathValue: string): XmlDocumentNode | undefined {
    const selectors = parsePath(pathValue);
    let currentNode = this.root;

    for (const selector of selectors) {
      const matchingChildren = currentNode.children.filter(
        (child) => child.name === selector.name
      );
      currentNode = matchingChildren[selector.index] as XmlDocumentNode;

      if (!currentNode) {
        return undefined;
      }
    }

    return currentNode;
  }

  getNodeText(pathValue: string): string | undefined {
    const node = this.findNode(pathValue);

    if (!node || node.selfClosing || node.children.length > 0) {
      return undefined;
    }

    return this.#readRange(node.innerStart, node.innerEnd);
  }

  setNodeText(pathValue: string, value: string): void {
    const node = this.#requireNode(pathValue);

    if (node.selfClosing) {
      throw new Error(`Cannot set text on self-closing node: ${pathValue}`);
    }

    if (node.children.length > 0) {
      throw new Error(`Cannot set text on non-leaf node: ${pathValue}`);
    }

    this.#writeRange(node.innerStart, node.innerEnd, value);
  }

  getAttribute(pathValue: string, attributeName: string): string | undefined {
    const node = this.findNode(pathValue);
    const attribute = node?.attributes.find((item) => item.name === attributeName);

    if (!attribute) {
      return undefined;
    }

    return this.#readRange(attribute.valueStart, attribute.valueEnd);
  }

  setAttribute(pathValue: string, attributeName: string, value: string): void {
    const node = this.#requireNode(pathValue);
    const attribute = node.attributes.find((item) => item.name === attributeName);

    if (!attribute) {
      throw new Error(`Attribute not found: ${pathValue}@${attributeName}`);
    }

    this.#writeRange(attribute.valueStart, attribute.valueEnd, value);
  }

  serialize(): string {
    return applyPatches(this.#originalSource, [...this.#patches.values()]);
  }

  save(outputPath?: string): string {
    const targetPath = outputPath ?? this.filePath;

    if (!targetPath) {
      throw new Error("Cannot save XML document without an output path.");
    }

    fs.writeFileSync(targetPath, this.serialize(), "utf8");
    return targetPath;
  }

  #requireNode(pathValue: string): XmlDocumentNode {
    const node = this.findNode(pathValue);

    if (!node) {
      throw new Error(`XML path not found: ${pathValue}`);
    }

    return node;
  }

  #readRange(start: number, end: number): string {
    const directPatch = this.#patches.get(getPatchKey(start, end));
    return directPatch ? directPatch.value : this.#originalSource.slice(start, end);
  }

  #writeRange(start: number, end: number, value: string): void {
    for (const [key, patch] of this.#patches.entries()) {
      if (rangesOverlap(start, end, patch.start, patch.end)) {
        this.#patches.delete(key);
      }
    }

    this.#patches.set(getPatchKey(start, end), { start, end, value });
  }
}

export function parseXmlDocument(source: string, filePath?: string): XmlDocument {
  return XmlDocument.parse(source, filePath);
}

export function loadXmlDocument(filePath: string): XmlDocument {
  return XmlDocument.parse(fs.readFileSync(filePath, "utf8"), filePath);
}

function parseXmlTree(source: string): XmlDocumentNode {
  const documentNode: XmlDocumentNode = {
    name: "#document",
    attributes: [],
    children: [],
    startTagStart: 0,
    startTagEnd: 0,
    innerStart: 0,
    innerEnd: source.length,
    selfClosing: false
  };

  const stack: XmlDocumentNode[] = [documentNode];

  for (const match of source.matchAll(XML_TOKEN_REGEX)) {
    const token = match[0];
    const tokenIndex = match.index ?? 0;

    if (
      token.startsWith("<!--") ||
      token.startsWith("<?") ||
      token.startsWith("<![CDATA[")
    ) {
      continue;
    }

    if (token.startsWith("</")) {
      const closingTagName = token.slice(2, -1).trim();

      while (stack.length > 1) {
        const currentNode = stack.pop();

        if (!currentNode) {
          break;
        }

        currentNode.innerEnd = tokenIndex;
        currentNode.endTagStart = tokenIndex;
        currentNode.endTagEnd = tokenIndex + token.length;

        if (currentNode.name === closingTagName) {
          break;
        }
      }

      continue;
    }

    const openingMatch = /^<([^\s/>]+)/.exec(token);

    if (!openingMatch?.[1]) {
      continue;
    }

    const selfClosing = token.endsWith("/>");
    const node: XmlDocumentNode = {
      name: openingMatch[1],
      attributes: parseAttributes(token, tokenIndex),
      children: [],
      startTagStart: tokenIndex,
      startTagEnd: tokenIndex + token.length,
      innerStart: tokenIndex + token.length,
      innerEnd: tokenIndex + token.length,
      selfClosing
    };

    stack[stack.length - 1]?.children.push(node);

    if (!selfClosing) {
      stack.push(node);
    }
  }

  return documentNode;
}

function parseAttributes(token: string, tokenStart: number): XmlDocumentAttribute[] {
  const attributes: XmlDocumentAttribute[] = [];
  const attributeRegex = /([^\s=/>]+)(\s*=\s*)("[^"]*"|'[^']*')/g;

  for (const match of token.matchAll(attributeRegex)) {
    const name = match[1];
    const quotedValue = match[3];
    const tokenOffset = match.index ?? 0;

    if (!name || !quotedValue) {
      continue;
    }

    const quote = quotedValue[0] as XmlDocumentAttribute["quote"];
    const quotedValueOffset = match[0].lastIndexOf(quotedValue);
    const valueStart = tokenStart + tokenOffset + quotedValueOffset + 1;
    const valueEnd = valueStart + quotedValue.length - 2;

    attributes.push({
      name,
      value: quotedValue.slice(1, -1),
      quote,
      valueStart,
      valueEnd
    });
  }

  return attributes;
}

function parsePath(pathValue: string): PathSegmentSelector[] {
  return pathValue
    .split(".")
    .filter(Boolean)
    .map((segment) => {
      const match = /^(.*?)(?:\[(\d+)\])?$/.exec(segment);

      if (!match?.[1]) {
        throw new Error(`Invalid XML path segment: ${segment}`);
      }

      return {
        name: match[1],
        index: Number(match[2] ?? "0")
      };
    });
}

function applyPatches(source: string, patches: XmlDocumentPatch[]): string {
  return [...patches]
    .sort((left, right) => right.start - left.start)
    .reduce(
      (currentSource, patch) =>
        `${currentSource.slice(0, patch.start)}${patch.value}${currentSource.slice(patch.end)}`,
      source
    );
}

function getPatchKey(start: number, end: number): string {
  return `${start}:${end}`;
}

function rangesOverlap(
  leftStart: number,
  leftEnd: number,
  rightStart: number,
  rightEnd: number
): boolean {
  return leftStart < rightEnd && rightStart < leftEnd;
}