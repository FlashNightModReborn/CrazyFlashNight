import { useMemo, useState } from "react";
import type { EditorRow } from "./editor-model";

export interface SidebarProps {
  rows: EditorRow[];
  selectedFile: string | undefined;
  onSelectFile: (file: string | undefined) => void;
}

interface FileNode {
  name: string;
  fullPath: string;
  rowCount: number;
  changedCount: number;
}

interface FolderNode {
  name: string;
  files: FileNode[];
  totalRows: number;
  totalChanged: number;
}

export function Sidebar({ rows, selectedFile, onSelectFile }: SidebarProps) {
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");

  const folders = useMemo(() => buildFolderTree(rows), [rows]);

  const filtered = useMemo(() => {
    if (!search.trim()) return folders;
    const q = search.trim().toLowerCase();
    return folders
      .map((folder) => ({
        ...folder,
        files: folder.files.filter(
          (f) =>
            f.name.toLowerCase().includes(q) ||
            f.fullPath.toLowerCase().includes(q)
        )
      }))
      .filter((folder) => folder.files.length > 0);
  }, [folders, search]);

  function toggleFolder(name: string) {
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  }

  return (
    <aside className="sidebar">
      <div className="sidebar-header">
        <h3>文件导航</h3>
        <span className="sidebar-count">
          {folders.reduce((s, f) => s + f.files.length, 0)} 个文件
        </span>
      </div>
      <input
        className="sidebar-search"
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
        placeholder="搜索文件..."
      />
      <button
        className={`sidebar-all-btn ${selectedFile === undefined ? "sidebar-all-btn-active" : ""}`}
        onClick={() => onSelectFile(undefined)}
        type="button"
      >
        全部文件
        <span>{rows.length} 行</span>
      </button>
      <div className="sidebar-tree">
        {filtered.map((folder) => (
          <div className="sidebar-folder" key={folder.name}>
            <button
              className="sidebar-folder-btn"
              onClick={() => toggleFolder(folder.name)}
              type="button"
            >
              <span className="sidebar-folder-icon">
                {collapsed.has(folder.name) ? "▸" : "▾"}
              </span>
              <span className="sidebar-folder-name">{folder.name}</span>
              <span className="sidebar-folder-count">
                {folder.totalChanged > 0
                  ? `${folder.totalChanged}/${folder.totalRows}`
                  : folder.totalRows.toString()}
              </span>
            </button>
            {!collapsed.has(folder.name) && (
              <div className="sidebar-file-list">
                {folder.files.map((file) => (
                  <button
                    key={file.fullPath}
                    className={`sidebar-file-btn ${
                      selectedFile === file.fullPath
                        ? "sidebar-file-btn-active"
                        : ""
                    }`}
                    onClick={() =>
                      onSelectFile(
                        selectedFile === file.fullPath
                          ? undefined
                          : file.fullPath
                      )
                    }
                    type="button"
                    title={file.fullPath}
                  >
                    <span className="sidebar-file-name">{file.name}</span>
                    <span className="sidebar-file-count">
                      {file.changedCount > 0
                        ? `${file.changedCount}/${file.rowCount}`
                        : file.rowCount.toString()}
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </aside>
  );
}

function buildFolderTree(rows: EditorRow[]): FolderNode[] {
  const fileMap = new Map<
    string,
    { rowCount: number; changedCount: number }
  >();

  for (const row of rows) {
    const entry = fileMap.get(row.sourceFile);
    const changed = row.stagedValue !== row.beforeValue ? 1 : 0;
    if (entry) {
      entry.rowCount += 1;
      entry.changedCount += changed;
    } else {
      fileMap.set(row.sourceFile, { rowCount: 1, changedCount: changed });
    }
  }

  const folderMap = new Map<string, FileNode[]>();

  for (const [fullPath, stats] of fileMap) {
    const normalized = fullPath.replaceAll("\\", "/");
    const lastSlash = normalized.lastIndexOf("/");
    const folderName =
      lastSlash >= 0 ? shortenFolder(normalized.slice(0, lastSlash)) : "(root)";
    const fileName =
      lastSlash >= 0 ? normalized.slice(lastSlash + 1) : normalized;

    const files = folderMap.get(folderName) ?? [];
    files.push({
      name: fileName,
      fullPath,
      rowCount: stats.rowCount,
      changedCount: stats.changedCount
    });
    folderMap.set(folderName, files);
  }

  return Array.from(folderMap.entries())
    .map(([name, files]) => {
      files.sort((a, b) => a.name.localeCompare(b.name));
      return {
        name,
        files,
        totalRows: files.reduce((s, f) => s + f.rowCount, 0),
        totalChanged: files.reduce((s, f) => s + f.changedCount, 0)
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

function shortenFolder(path: string): string {
  const marker = "data/items/";
  const idx = path.indexOf(marker);
  if (idx >= 0) return path.slice(idx);

  const marker2 = "data/";
  const idx2 = path.indexOf(marker2);
  if (idx2 >= 0) return path.slice(idx2);

  return path;
}
