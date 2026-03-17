/**
 * 文件致密化：去除 JSON/XML 中的非必要空白。
 * 只处理文本内容，不引入额外依赖。
 */

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
    cdataSlots.push(match);
    return `__CDATA_${cdataSlots.length - 1}__`;
  });

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
