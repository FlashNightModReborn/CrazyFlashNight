/**
 * AS2 文件写入器 — UTF-8 BOM + CRLF
 */

import { writeFileSync } from "node:fs";

const BOM = "\uFEFF";

/** 将内容写入 .as 文件，确保 UTF-8 BOM + CRLF */
export function writeAS2(filePath: string, content: string): void {
  // 统一换行为 CRLF
  const crlf = content.replace(/\r\n/g, "\n").replace(/\n/g, "\r\n");
  // 确保 BOM 开头
  const withBom = crlf.startsWith(BOM) ? crlf : BOM + crlf;
  writeFileSync(filePath, withBom, "utf-8");
}
