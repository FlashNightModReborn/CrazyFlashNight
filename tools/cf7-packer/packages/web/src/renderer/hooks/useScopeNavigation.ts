import { useState, useCallback, useEffect } from "react";
import type { FileEntry } from "../../shared/ipc-types.js";
import {
  getParentScopePath,
  isFileInsideScope,
  resolveLayerForPath,
  resolveLayerScopePath
} from "../components/scope-utils.js";

export type DetailTab = "tree" | "diff";

export function useScopeNavigation(
  previewFiles: FileEntry[],
  setExpandedLayer: React.Dispatch<React.SetStateAction<string | null>>,
  setDetailTab: React.Dispatch<React.SetStateAction<DetailTab>>
) {
  const [selectedScopeLayer, setSelectedScopeLayer] = useState<string | null>(null);
  const [selectedScopePath, setSelectedScopePath] = useState<string | null>(null);

  const applyScopeSelection = useCallback((nextPath: string | null, nextLayer: string | null) => {
    setSelectedScopePath(nextPath);
    setSelectedScopeLayer(nextLayer);
    setExpandedLayer(nextLayer);
    setDetailTab("tree");
  }, [setExpandedLayer, setDetailTab]);

  const handleLayerScopeChange = useCallback((nextLayer: string | null) => {
    applyScopeSelection(resolveLayerScopePath(previewFiles, nextLayer), nextLayer);
  }, [applyScopeSelection, previewFiles]);

  const handleTreemapScopeChange = useCallback((nextPath: string | null, nextLayer: string | null) => {
    applyScopeSelection(nextPath, nextLayer);
  }, [applyScopeSelection]);

  const handleScopeNavigate = useCallback((nextPath: string | null, nextLayer: string | null) => {
    applyScopeSelection(nextPath, nextLayer);
  }, [applyScopeSelection]);

  const handleResetScope = useCallback(() => {
    applyScopeSelection(null, null);
  }, [applyScopeSelection]);

  const handleNavigateUp = useCallback(() => {
    if (selectedScopePath) {
      const parentPath = getParentScopePath(selectedScopePath);
      if (!parentPath) {
        applyScopeSelection(null, null);
        return;
      }
      applyScopeSelection(parentPath, resolveLayerForPath(previewFiles, parentPath) ?? selectedScopeLayer);
      return;
    }

    if (selectedScopeLayer) {
      applyScopeSelection(null, null);
    }
  }, [applyScopeSelection, previewFiles, selectedScopeLayer, selectedScopePath]);

  // Validate scope against current file list
  useEffect(() => {
    if (!selectedScopeLayer && !selectedScopePath) return;

    const hasLayer = selectedScopeLayer
      ? previewFiles.some((file) => file.layer === selectedScopeLayer)
      : true;
    const hasPath = selectedScopePath
      ? previewFiles.some((file) => isFileInsideScope(file.path, selectedScopePath))
      : true;

    if (hasLayer && hasPath) return;

    if (!hasLayer) {
      setExpandedLayer(null);
      setSelectedScopeLayer(null);
    }
    if (!hasPath) {
      setSelectedScopePath(resolveLayerScopePath(previewFiles, hasLayer ? selectedScopeLayer : null));
    }
  }, [previewFiles, selectedScopeLayer, selectedScopePath, setExpandedLayer]);

  return {
    selectedScopeLayer,
    selectedScopePath,
    handleLayerScopeChange,
    handleTreemapScopeChange,
    handleScopeNavigate,
    handleResetScope,
    handleNavigateUp
  };
}
