import picomatch from "picomatch";
import type { PackConfig, FileEntry, FilterResult, LayerSummary, LayerRule } from "./types.js";

interface CompiledLayer {
  rule: LayerRule;
  /** source 前缀，已 normalize（末尾带 /），"." 特殊处理 */
  sourcePrefix: string;
  isRoot: boolean;
  includeMatcher: picomatch.Matcher;
  excludeMatcher: picomatch.Matcher | null;
}

function compileLayer(rule: LayerRule): CompiledLayer {
  const isRoot = rule.source === "." || rule.source === "./";
  const sourcePrefix = isRoot ? "" : normalizePrefix(rule.source);

  const includeMatcher = picomatch(rule.include, { dot: true });
  const excludeMatcher = rule.exclude.length > 0
    ? picomatch(rule.exclude, { dot: true })
    : null;

  return { rule, sourcePrefix, isRoot, includeMatcher, excludeMatcher };
}

function normalizePrefix(source: string): string {
  let s = source.replace(/\\/g, "/");
  if (!s.endsWith("/")) s += "/";
  return s;
}

/**
 * 对文件列表应用打包配置的层级过滤规则。
 *
 * 每个文件按 layers 顺序匹配:
 * 1. 文件路径必须以 layer.source 为前缀
 * 2. 去掉前缀后的相对路径必须匹配 layer.include 中的至少一个 glob
 * 3. 不能匹配 layer.exclude 中的任何 glob
 * 4. 不能匹配 globalExclude 中的任何 glob（基于完整路径）
 *
 * 第一个命中的 layer 获得该文件归属权，后续 layer 不再检查。
 */
export function filterFiles(files: string[], config: PackConfig): FilterResult {
  const compiled = config.layers.map(compileLayer);

  const globalExcludeMatcher = config.globalExclude.length > 0
    ? picomatch(config.globalExclude, { dot: true })
    : null;

  const included: FileEntry[] = [];
  const excluded: FileEntry[] = [];
  const layerIncluded = new Map<string, number>();
  const layerExcluded = new Map<string, number>();
  let unmatchedCount = 0;

  for (const layer of compiled) {
    layerIncluded.set(layer.rule.name, 0);
    layerExcluded.set(layer.rule.name, 0);
  }

  for (const filePath of files) {
    const normalized = filePath.replace(/\\/g, "/");

    // 全局排除检查
    if (globalExcludeMatcher?.(normalized)) {
      excluded.push({ path: filePath, layer: "__global__" });
      continue;
    }

    let matched = false;

    for (const layer of compiled) {
      const { sourcePrefix, isRoot, includeMatcher, excludeMatcher, rule } = layer;

      // 检查文件是否属于此 layer 的 source 前缀
      let relativePath: string;
      if (isRoot) {
        // root layer: 文件不能在任何子目录 layer 的 source 下
        // 但这里我们用 include 规则来限定
        relativePath = normalized;
      } else {
        if (!normalized.startsWith(sourcePrefix)) continue;
        relativePath = normalized.slice(sourcePrefix.length);
      }

      // include 检查
      if (!includeMatcher(relativePath)) continue;

      // exclude 检查
      if (excludeMatcher?.(relativePath)) {
        excluded.push({ path: filePath, layer: rule.name });
        layerExcluded.set(rule.name, (layerExcluded.get(rule.name) ?? 0) + 1);
        matched = true;
        break;
      }

      // 通过所有规则
      included.push({ path: filePath, layer: rule.name });
      layerIncluded.set(rule.name, (layerIncluded.get(rule.name) ?? 0) + 1);
      matched = true;
      break;
    }

    if (!matched) {
      unmatchedCount++;
    }
  }

  const layers: LayerSummary[] = compiled.map(({ rule }) => {
    const summary: LayerSummary = {
      name: rule.name,
      includedCount: layerIncluded.get(rule.name) ?? 0,
      excludedCount: layerExcluded.get(rule.name) ?? 0
    };
    if (rule.description !== undefined) {
      summary.description = rule.description;
    }
    return summary;
  });

  return { included, excluded, layers, unmatchedCount };
}
