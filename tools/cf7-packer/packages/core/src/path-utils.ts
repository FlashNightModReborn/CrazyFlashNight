import path from "node:path";

/**
 * 规范化 repoRoot 相对路径。
 * - 统一使用正斜杠
 * - 去掉前导 ./
 * - 拒绝绝对路径与 .. 逃逸
 */
export function normalizeRepoRelativePath(input: string): string {
  const normalized = input.replace(/\\/g, "/").replace(/^\.\/+/, "");

  if (!normalized) {
    throw new Error("路径不能为空");
  }
  if (path.posix.isAbsolute(normalized) || /^[a-zA-Z]:[\\/]/.test(input)) {
    throw new Error("路径必须是相对于仓库根目录的相对路径");
  }

  const parts = normalized.split("/").filter(Boolean);
  const cleanParts: string[] = [];

  for (const part of parts) {
    if (part === ".") continue;
    if (part === "..") {
      throw new Error("路径不能包含 ..");
    }
    cleanParts.push(part);
  }

  if (cleanParts.length === 0) {
    throw new Error("路径不能为空");
  }

  return cleanParts.join("/");
}

export function normalizeLayerSource(source: string): { isRoot: boolean; prefix: string; sourceRoot: string } {
  const normalized = source.replace(/\\/g, "/");
  const isRoot = normalized === "." || normalized === "./";
  if (isRoot) {
    return { isRoot: true, prefix: "", sourceRoot: "" };
  }

  const prefix = normalized.endsWith("/") ? normalized : `${normalized}/`;
  return {
    isRoot: false,
    prefix,
    sourceRoot: prefix.slice(0, -1)
  };
}

export function isPathInsideRoot(rootDir: string, targetPath: string): boolean {
  const relative = path.relative(path.resolve(rootDir), path.resolve(targetPath));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}
