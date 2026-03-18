/**
 * Git 输入校验：在 API 边界统一拒绝畸形 ref/path，防止被 git 误解。
 *
 * 采用黑名单模式：拒绝已知危险模式，允许合法的中文 tag、HEAD、SHA 等。
 */

/** 拒绝以 - 开头、含 ..、含控制字符、空字符串 */
const DANGEROUS_REF_PATTERNS = [
  /^$/,               // 空字符串
  /^\s*$/,            // 纯空白
  /^-/,               // 以 - 开头（会被 git 解析为选项）
  /\.\./,             // 含 ..（range 表达式注入如 tag1..tag2）
  // eslint-disable-next-line no-control-regex
  /[\x00-\x1f]/       // 含控制字符
];

/**
 * 校验 git ref（tag、branch、HEAD、SHA 等）是否安全。
 *
 * 允许: HEAD, HEAD~N, HEAD^N, 40/64 位 SHA, 中文 tag, 分支名(含 /)
 * 拒绝: 以 - 开头, 含 .., 含控制字符, 空字符串
 */
export function validateGitRef(ref: string): void {
  for (const pattern of DANGEROUS_REF_PATTERNS) {
    if (pattern.test(ref)) {
      throw new Error(`不安全的 git 引用: "${ref}"`);
    }
  }
}

/**
 * 校验 git 文件路径是否安全。
 */
export function validateGitPath(filePath: string): void {
  if (!filePath) {
    throw new Error("git 路径不能为空");
  }
  if (filePath.startsWith("-")) {
    throw new Error(`不安全的 git 路径（以 - 开头）: "${filePath}"`);
  }
  if (filePath.includes("..")) {
    throw new Error(`不安全的 git 路径（含 ..）: "${filePath}"`);
  }
  if (/[\x00]/.test(filePath)) {
    throw new Error(`不安全的 git 路径（含 NUL）: "${filePath}"`);
  }
}
