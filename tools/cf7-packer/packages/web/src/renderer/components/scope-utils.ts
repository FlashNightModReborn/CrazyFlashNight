import type { FileEntry } from "../../shared/ipc-types.js";

export interface ScopeBreadcrumb {
  label: string;
  path: string | null;
  layer: string | null;
  active: boolean;
}

export function buildScopeBreadcrumbs(path: string | null, layer: string | null): ScopeBreadcrumb[] {
  const breadcrumbs: ScopeBreadcrumb[] = [
    { label: "全部", path: null, layer: null, active: !path && !layer }
  ];

  if (path) {
    const segments = path.split("/");
    let currentPath = "";
    for (const segment of segments) {
      currentPath = currentPath ? `${currentPath}/${segment}` : segment;
      breadcrumbs.push({
        label: segment,
        path: currentPath,
        layer,
        active: currentPath === path
      });
    }
    return breadcrumbs;
  }

  if (layer) {
    breadcrumbs.push({
      label: layer,
      path: null,
      layer,
      active: true
    });
  }

  return breadcrumbs;
}

export function resolveLayerScopePath(files: FileEntry[], layer: string | null): string | null {
  if (!layer) return null;
  const matching = files.filter((file) => file.layer === layer);
  if (matching.length === 0) return null;

  const directMatch = matching.find((file) => file.path === layer || file.path.startsWith(`${layer}/`));
  if (directMatch) return layer;
  return null;
}

export function resolveLayerForPath(files: FileEntry[], path: string | null): string | null {
  if (!path) return null;
  const match = files.find((file) => isFileInsideScope(file.path, path));
  return match?.layer ?? null;
}

export function getParentScopePath(path: string): string | null {
  const lastSlash = path.lastIndexOf("/");
  if (lastSlash < 0) return null;
  return path.slice(0, lastSlash);
}

export function isFileInsideScope(path: string, scopePath: string): boolean {
  return path === scopePath || path.startsWith(`${scopePath}/`);
}
