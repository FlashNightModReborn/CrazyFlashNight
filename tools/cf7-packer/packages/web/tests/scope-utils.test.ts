import { describe, expect, it } from "vitest";
import {
  buildScopeBreadcrumbs,
  getParentScopePath,
  isFileInsideScope,
  resolveLayerForPath,
  resolveLayerScopePath
} from "../src/renderer/components/scope-utils.js";
import type { FileEntry } from "../src/shared/ipc-types.js";

const SAMPLE_FILES: FileEntry[] = [
  { path: "data/maps/arena.xml", layer: "data", size: 12 },
  { path: "data/maps/castle.xml", layer: "data", size: 12 },
  { path: "flashswf/ui/menu.swf", layer: "flashswf", size: 12 },
  { path: "0.docs/readme.txt", layer: "root-dirs", size: 12 }
];

describe("scope-utils", () => {
  it("builds breadcrumbs from the focused path", () => {
    expect(buildScopeBreadcrumbs("data/maps", "data")).toEqual([
      { label: "全部", path: null, layer: null, active: false },
      { label: "data", path: "data", layer: "data", active: false },
      { label: "maps", path: "data/maps", layer: "data", active: true }
    ]);
  });

  it("builds a layer-only breadcrumb when no path root exists", () => {
    expect(buildScopeBreadcrumbs(null, "root-dirs")).toEqual([
      { label: "全部", path: null, layer: null, active: false },
      { label: "root-dirs", path: null, layer: "root-dirs", active: true }
    ]);
  });

  it("resolves layer roots only when the layer has a matching top-level path", () => {
    expect(resolveLayerScopePath(SAMPLE_FILES, "data")).toBe("data");
    expect(resolveLayerScopePath(SAMPLE_FILES, "root-dirs")).toBeNull();
  });

  it("resolves the owning layer from a scope path", () => {
    expect(resolveLayerForPath(SAMPLE_FILES, "data/maps")).toBe("data");
    expect(resolveLayerForPath(SAMPLE_FILES, "0.docs")).toBe("root-dirs");
    expect(resolveLayerForPath(SAMPLE_FILES, "missing")).toBeNull();
  });

  it("detects parent paths and scoped membership", () => {
    expect(getParentScopePath("data/maps/arena")).toBe("data/maps");
    expect(getParentScopePath("data")).toBeNull();
    expect(isFileInsideScope("data/maps/arena.xml", "data/maps")).toBe(true);
    expect(isFileInsideScope("flashswf/ui/menu.swf", "data/maps")).toBe(false);
  });
});
