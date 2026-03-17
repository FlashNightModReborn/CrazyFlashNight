import type { FileEntry } from "../../shared/ipc-types.js";

export interface TreeNode {
  name: string;
  fullPath: string;
  isDir: boolean;
  size: number;
  children: TreeNode[];
  fileCount: number;
  layer?: string;
}

/** 从 FileEntry[] 构建虚拟文件树 */
export function buildTree(entries: FileEntry[], layerFilter?: string): TreeNode {
  const root: TreeNode = { name: "root", fullPath: "", isDir: true, size: 0, children: [], fileCount: 0 };

  const filtered = layerFilter ? entries.filter((e) => e.layer === layerFilter) : entries;

  for (const entry of filtered) {
    const parts = entry.path.split("/");
    let current = root;

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i]!;
      const isLast = i === parts.length - 1;

      if (isLast) {
        current.children.push({
          name: part,
          fullPath: entry.path,
          isDir: false,
          size: entry.size ?? 0,
          children: [],
          fileCount: 0,
          layer: entry.layer
        });
      } else {
        let child = current.children.find((c) => c.isDir && c.name === part);
        if (!child) {
          child = {
            name: part,
            fullPath: parts.slice(0, i + 1).join("/"),
            isDir: true,
            size: 0,
            children: [],
            fileCount: 0
          };
          current.children.push(child);
        }
        current = child;
      }
    }
  }

  // 递归计算目录大小和文件数
  computeStats(root);
  // 排序：目录在前，文件在后，各自按名称排序
  sortTree(root);
  return root;
}

function computeStats(node: TreeNode): void {
  if (!node.isDir) return;
  let size = 0;
  let count = 0;
  for (const child of node.children) {
    computeStats(child);
    if (child.isDir) {
      size += child.size;
      count += child.fileCount;
    } else {
      size += child.size;
      count += 1;
    }
  }
  node.size = size;
  node.fileCount = count;
}

function sortTree(node: TreeNode): void {
  if (!node.isDir) return;
  node.children.sort((a, b) => {
    if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  for (const child of node.children) sortTree(child);
}

/** 格式化文件大小 */
export function formatSize(bytes: number): string {
  if (bytes === 0) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/** 为 Sunburst 构建层级数据结构 */
export interface SunburstNode {
  name: string;
  value?: number;
  children?: SunburstNode[];
  layer?: string | undefined;
}

export function buildSunburstData(entries: FileEntry[]): SunburstNode {
  const tree = buildTree(entries);
  return toSunburst(tree);
}

function toSunburst(node: TreeNode): SunburstNode {
  if (!node.isDir) {
    return { name: node.name, value: Math.max(node.size, 1), layer: node.layer };
  }
  return {
    name: node.name,
    children: node.children.map(toSunburst)
  };
}
