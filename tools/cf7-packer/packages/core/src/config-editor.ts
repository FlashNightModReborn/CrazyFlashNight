import { Scalar, parseDocument } from "yaml";
import type { PackConfig, LayerRule } from "./types.js";
import { normalizeLayerSource, normalizeRepoRelativePath } from "./path-utils.js";

export interface ExcludeTarget {
  filePath: string;
  isDir: boolean;
  layer?: string | undefined;
}

export interface ExcludeMutationResult {
  layerName: string;
  pattern: string;
  normalizedPath: string;
  alreadyPresent: boolean;
}

function scoreLayerMatch(rule: LayerRule, filePath: string): { score: number; relativePath: string } | null {
  const { isRoot, prefix, sourceRoot } = normalizeLayerSource(rule.source);

  if (isRoot) {
    return { score: 0, relativePath: filePath };
  }
  if (filePath === sourceRoot) {
    return { score: sourceRoot.length, relativePath: "" };
  }
  if (!filePath.startsWith(prefix)) {
    return null;
  }
  return {
    score: sourceRoot.length,
    relativePath: filePath.slice(prefix.length)
  };
}

function buildExcludePattern(relativePath: string, isDir: boolean): string {
  if (!isDir) {
    return relativePath;
  }
  return relativePath ? `${relativePath}/**` : "**";
}

function matchesRequestedLayer(rule: LayerRule, requestedLayer: string | undefined, filePath: string): { score: number; relativePath: string } | null {
  if (!requestedLayer || rule.name !== requestedLayer) {
    return null;
  }
  return scoreLayerMatch(rule, filePath);
}

function quote(value: string): Scalar {
  const scalar = new Scalar(value);
  scalar.type = "QUOTE_DOUBLE";
  return scalar;
}

function seqHasValue(seq: { items?: unknown[] } | null | undefined, value: string): boolean {
  return !!seq?.items?.some((item) => {
    if (item && typeof item === "object" && "value" in item) {
      return (item as { value: unknown }).value === value;
    }
    return item === value;
  });
}

function createQuotedArray(value: string): unknown[] {
  return [quote(value)];
}

export function resolveExcludeMutation(config: PackConfig, target: ExcludeTarget): ExcludeMutationResult {
  const normalizedPath = normalizeRepoRelativePath(target.filePath);

  let matchedLayer: LayerRule | null = null;
  let matchedRelativePath = normalizedPath;
  let bestScore = -1;

  for (const rule of config.layers) {
    const forcedMatch = matchesRequestedLayer(rule, target.layer, normalizedPath);
    if (forcedMatch) {
      matchedLayer = rule;
      matchedRelativePath = forcedMatch.relativePath;
      bestScore = Number.MAX_SAFE_INTEGER;
      break;
    }

    if (target.layer) continue;

    const candidate = scoreLayerMatch(rule, normalizedPath);
    if (!candidate) continue;
    if (candidate.score <= bestScore) continue;

    matchedLayer = rule;
    matchedRelativePath = candidate.relativePath;
    bestScore = candidate.score;
  }

  if (!matchedLayer) {
    return {
      layerName: "__global__",
      pattern: buildExcludePattern(normalizedPath, target.isDir),
      normalizedPath,
      alreadyPresent: config.globalExclude.includes(buildExcludePattern(normalizedPath, target.isDir))
    };
  }

  const pattern = buildExcludePattern(matchedRelativePath, target.isDir);
  return {
    layerName: matchedLayer.name,
    pattern,
    normalizedPath,
    alreadyPresent: matchedLayer.exclude.includes(pattern)
  };
}

export function applyExcludeMutation(configContent: string, config: PackConfig, target: ExcludeTarget): {
  content: string;
  result: ExcludeMutationResult;
} {
  const result = resolveExcludeMutation(config, target);
  const doc = parseDocument(configContent);

  if (result.layerName === "__global__") {
    const globalExclude = doc.get("globalExclude", true) as { add?: (value: unknown) => void; items?: unknown[] } | undefined;
    if (!globalExclude) {
      doc.set("globalExclude", createQuotedArray(result.pattern));
    } else if (!seqHasValue(globalExclude, result.pattern)) {
      globalExclude.add?.(quote(result.pattern));
    }
    return { content: doc.toString(), result };
  }

  const layersNode = doc.get("layers", true) as { items?: Array<{ get?: (key: string) => unknown; set?: (key: string, value: unknown) => void }> } | undefined;
  if (!layersNode?.items) {
    throw new Error("配置文件缺少 layers 节点");
  }

  for (const layerNode of layersNode.items) {
    if (layerNode?.get?.("name") !== result.layerName) continue;

    const excludeNode = layerNode.get?.("exclude") as { add?: (value: unknown) => void; items?: unknown[] } | undefined;
    if (!excludeNode) {
      layerNode.set?.("exclude", createQuotedArray(result.pattern));
    } else if (!seqHasValue(excludeNode, result.pattern)) {
      excludeNode.add?.(quote(result.pattern));
    }

    return { content: doc.toString(), result };
  }

  throw new Error(`配置文件中找不到 layer: ${result.layerName}`);
}
