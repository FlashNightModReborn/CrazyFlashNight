import path from "node:path";
import picomatch from "picomatch";
import type { MinifyConfig } from "./types.js";

/**
 * 文件致密化：去除 JSON/XML 中的非必要空白。
 * 只处理文本内容，不引入额外依赖。
 */

/**
 * 编译路径级致密化策略。
 * exclude 使用 repoRoot 相对 glob；命中的文件仍会进入包，只跳过内容变换。
 */
export function createMinifyPathMatcher(config?: MinifyConfig): (repoRelativePath: string) => boolean {
  if (!config?.enabled) return () => false;

  const extensions = new Set(config.extensions.map((extension) => extension.toLowerCase()));
  const excludes = config.exclude ?? [];
  const excludeMatcher = excludes.length > 0
    ? picomatch(excludes, { dot: true })
    : null;

  return (repoRelativePath: string): boolean => {
    const normalizedPath = repoRelativePath.replace(/\\/g, "/");
    const extension = path.posix.extname(normalizedPath).toLowerCase();
    return extensions.has(extension) && !(excludeMatcher?.(normalizedPath) ?? false);
  };
}

/** 致密化 JSON：parse + stringify 无缩进 */
export function minifyJson(content: string): string {
  return JSON.stringify(JSON.parse(content));
}

/**
 * 致密化 XML：去除标签间的纯空白文本节点、缩进、多余换行。
 * 保留属性值和 CDATA 内容中的空白。
 */
export function minifyXml(content: string): string {
  // 保护 CDATA 段
  const cdataSlots: string[] = [];
  let protected_ = content.replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, (match) => {
    const placeholder = `__CDATA_${cdataSlots.length}__`;
    // 碰撞检测：占位符已存在于原文时直接返回原内容（不致密化）
    if (content.includes(placeholder)) {
      return match; // 标记碰撞，后续检测
    }
    cdataSlots.push(match);
    return placeholder;
  });

  // 碰撞检测：如果有 CDATA 段未被替换（占位符碰撞），回退返回原内容
  if (/<!\[CDATA\[/.test(protected_)) {
    return content;
  }

  // 去除标签之间的纯空白
  protected_ = protected_.replace(/>\s+</g, "><");
  // 去除开头和末尾空白
  protected_ = protected_.trim();

  // 恢复 CDATA
  for (let i = 0; i < cdataSlots.length; i++) {
    protected_ = protected_.replace(`__CDATA_${i}__`, cdataSlots[i]!);
  }

  return protected_;
}

/** 根据扩展名选择致密化函数，不支持的返回 null */
export function minifyByExtension(content: string, ext: string): string | null {
  switch (ext.toLowerCase()) {
    case ".json":
      try { return minifyJson(content); } catch { return null; }
    case ".xml":
      return minifyXml(content);
    default:
      return null;
  }
}
