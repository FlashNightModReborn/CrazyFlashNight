import { useState, useMemo, useCallback, useRef, useEffect } from "react";
import type { FileEntry, ExcludeRequest } from "../../shared/ipc-types.js";
import { buildTree, formatSize, type TreeNode } from "./tree-utils.js";

interface Props {
  files: FileEntry[];
  layerFilter: string | null;
  focusPath?: string | null;
  onExcluded?: () => void;
}

interface ContextMenu {
  x: number;
  y: number;
  node: TreeNode;
}

export default function FileTreePanel({ files, layerFilter, focusPath = null, onExcluded }: Props) {
  const [searchQuery, setSearchQuery] = useState("");
  const [debouncedQuery, setDebouncedQuery] = useState("");
  const [contextMenu, setContextMenu] = useState<ContextMenu | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  // 防抖搜索
  useEffect(() => {
    clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setDebouncedQuery(searchQuery), 200);
    return () => clearTimeout(timerRef.current);
  }, [searchQuery]);

  // 先按层过滤，再按搜索词过滤
  const scopedFiles = useMemo(() => {
    let result = layerFilter ? files.filter((f) => f.layer === layerFilter) : files;
    if (focusPath) {
      result = result.filter((f) => isPathWithinScope(f.path, focusPath));
    }
    return result;
  }, [files, focusPath, layerFilter]);

  const filteredFiles = useMemo(() => {
    let result = scopedFiles;
    if (debouncedQuery.length >= 2) {
      const q = debouncedQuery.toLowerCase();
      result = result.filter((f) => f.path.toLowerCase().includes(q));
    }
    return result;
  }, [debouncedQuery, scopedFiles]);

  const tree = useMemo(() => buildTree(filteredFiles), [filteredFiles]);

  // 点击外部关闭菜单
  useEffect(() => {
    if (!contextMenu) return;
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setContextMenu(null);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [contextMenu]);

  const handleContextMenu = useCallback((e: React.MouseEvent, node: TreeNode) => {
    e.preventDefault();
    e.stopPropagation();
    setContextMenu({ x: e.clientX, y: e.clientY, node });
  }, []);

  const handleOpen = useCallback(() => {
    if (!contextMenu) return;
    const api = window.cf7Packer;
    if (api) void api.openFile(contextMenu.node.fullPath);
    setContextMenu(null);
  }, [contextMenu]);

  const handleReveal = useCallback(() => {
    if (!contextMenu) return;
    const api = window.cf7Packer;
    if (api) void api.revealFile(contextMenu.node.fullPath);
    setContextMenu(null);
  }, [contextMenu]);

  const doExclude = useCallback(async (deleteFromDisk: boolean) => {
    if (!contextMenu) return;
    const api = window.cf7Packer;
    if (!api) return;
    const node = contextMenu.node;
    const req: ExcludeRequest = {
      filePath: node.fullPath,
      isDir: node.isDir,
      layer: node.layer,
      deleteFromDisk
    };
    setContextMenu(null);
    const result = await api.excludeFile(req);
    if (result.success) {
      onExcluded?.();
    }
  }, [contextMenu, onExcluded]);

  const handleExclude = useCallback(() => { void doExclude(false); }, [doExclude]);
  const handleDeleteAndExclude = useCallback(() => { void doExclude(true); }, [doExclude]);

  const totalFiles = scopedFiles.length;
  const scopeLabel = focusPath ?? layerFilter ?? "全部";

  return (
    <div className="file-tree-panel">
      <div className="file-tree-header">
        <span className="file-tree-scope" title={scopeLabel}>{scopeLabel}</span>
        <div className="file-tree-search">
          <input
            type="text"
            placeholder="搜索文件..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="file-tree-search-input"
          />
          {searchQuery && (
            <button className="file-tree-search-clear" onClick={() => setSearchQuery("")}>✕</button>
          )}
        </div>
        <span className="file-tree-count">
          {debouncedQuery.length >= 2
            ? `${tree.fileCount} / ${totalFiles} 文件`
            : `${tree.fileCount} 个文件, ${formatSize(tree.size)}`
          }
        </span>
      </div>
      <div className="file-tree-body">
        {tree.fileCount === 0 ? (
          <div className="file-tree-empty">{debouncedQuery ? "无匹配文件" : "无文件"}</div>
        ) : (
          tree.children.map((child) => (
            <TreeNodeView
              key={child.fullPath || child.name}
              node={child}
              depth={0}
              onContextMenu={handleContextMenu}
              searchQuery={debouncedQuery}
              defaultExpanded={debouncedQuery.length >= 2}
              focusPath={focusPath ?? null}
            />
          ))
        )}
      </div>

      {contextMenu && (
        <div ref={menuRef} className="ctx-menu" style={{ left: contextMenu.x, top: contextMenu.y }}>
          <div className="ctx-menu-item" onClick={handleOpen}>
            {contextMenu.node.isDir ? "📂 打开文件夹" : "📄 打开文件"}
          </div>
          <div className="ctx-menu-item" onClick={handleReveal}>
            📁 在资源管理器中显示
          </div>
          <div className="ctx-menu-divider" />
          <div className="ctx-menu-item" onClick={handleExclude}>
            🚫 {contextMenu.node.isDir ? "排除此文件夹" : "排除此文件"}
          </div>
          <div className="ctx-menu-item ctx-menu-danger" onClick={handleDeleteAndExclude}>
            🗑️ 删除并排除
          </div>
          <div className="ctx-menu-divider" />
          <div className="ctx-menu-item ctx-menu-path">{contextMenu.node.fullPath}</div>
        </div>
      )}
    </div>
  );
}

function TreeNodeView({ node, depth, onContextMenu, searchQuery, defaultExpanded, focusPath }: {
  node: TreeNode; depth: number;
  onContextMenu: (e: React.MouseEvent, node: TreeNode) => void;
  searchQuery: string;
  defaultExpanded: boolean;
  focusPath?: string | null;
}) {
  const isFocusBranch = Boolean(focusPath) && isPathWithinScope(focusPath!, node.fullPath);
  const isFocusedNode = Boolean(focusPath) && node.fullPath === focusPath;
  const [expanded, setExpanded] = useState(defaultExpanded || depth < 1 || isFocusBranch);

  // 搜索时自动展开
  useEffect(() => {
    if (defaultExpanded || isFocusBranch) setExpanded(true);
  }, [defaultExpanded, isFocusBranch]);

  if (!node.isDir) {
    return (
      <div className={`tree-file ${isFocusedNode ? "tree-focused" : ""}`} style={{ paddingLeft: `${depth * 16 + 20}px` }}
        onContextMenu={(e) => onContextMenu(e, node)}>
        <span className="tree-icon">📄</span>
        <span className="tree-name">
          {searchQuery.length >= 2 ? highlightMatch(node.name, searchQuery) : node.name}
        </span>
        <span className="tree-size">{formatSize(node.size)}</span>
      </div>
    );
  }

  return (
    <div className="tree-dir-group">
      <div className={`tree-dir ${isFocusedNode ? "tree-focused" : ""}`} style={{ paddingLeft: `${depth * 16 + 4}px` }}
        onClick={() => setExpanded(!expanded)}
        onContextMenu={(e) => onContextMenu(e, node)}>
        <span className="tree-toggle">{expanded ? "▼" : "▶"}</span>
        <span className="tree-icon">📁</span>
        <span className="tree-name">{node.name}/</span>
        <span className="tree-meta">{node.fileCount} 文件</span>
        <span className="tree-size">{formatSize(node.size)}</span>
      </div>
      {expanded && node.children.map((child) => (
        <TreeNodeView key={child.fullPath || child.name} node={child} depth={depth + 1}
          onContextMenu={onContextMenu} searchQuery={searchQuery} defaultExpanded={defaultExpanded} focusPath={focusPath ?? null} />
      ))}
    </div>
  );
}

function highlightMatch(text: string, query: string): React.ReactNode {
  const idx = text.toLowerCase().indexOf(query.toLowerCase());
  if (idx < 0) return text;
  return (
    <>
      {text.slice(0, idx)}
      <mark className="file-search-highlight">{text.slice(idx, idx + query.length)}</mark>
      {text.slice(idx + query.length)}
    </>
  );
}

function isPathWithinScope(path: string, scopePath: string): boolean {
  return path === scopePath || path.startsWith(`${scopePath}/`);
}
