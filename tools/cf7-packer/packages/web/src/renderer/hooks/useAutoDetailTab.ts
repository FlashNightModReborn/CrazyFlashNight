import { useState, useEffect, useRef } from "react";
import type { DetailTab } from "./useScopeNavigation.js";

/**
 * Manages the detail-tab selection with auto-switch logic:
 * - Defaults to "config" (always useful, even when preview hasn't loaded yet)
 * - Auto-switches to "tree" the first time preview data arrives
 * - Never auto-switches again after that (user's manual choice is respected)
 */
export function useAutoDetailTab(hasPreview: boolean) {
  const [detailTab, setDetailTab] = useState<DetailTab>("config");
  const firstPreviewDone = useRef(false);

  useEffect(() => {
    if (hasPreview && !firstPreviewDone.current) {
      firstPreviewDone.current = true;
      setDetailTab("tree");
    }
  }, [hasPreview]);

  return [detailTab, setDetailTab] as const;
}
