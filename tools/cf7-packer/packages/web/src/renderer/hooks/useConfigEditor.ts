import { useState, useEffect, useCallback, useRef } from "react";
import type { PackerIpcApi, SaveConfigResult } from "../../shared/ipc-types.js";

export interface UseConfigEditorResult {
  rawYaml: string;
  isDirty: boolean;
  hasExternalConflict: boolean;
  errors: Array<{ path: string; message: string }>;
  loading: boolean;
  loadFromDisk: () => Promise<void>;
  saveAndRefresh: () => Promise<void>;
  setRawYaml: (yaml: string) => void;
  dismissConflict: () => void;
}

export function useConfigEditor(
  api: PackerIpcApi | undefined,
  onSaveAndRefresh: () => Promise<void>
): UseConfigEditorResult {
  const [rawYaml, setRawYamlState] = useState("");
  const [savedYaml, setSavedYaml] = useState("");
  const [isDirty, setIsDirty] = useState(false);
  const [hasExternalConflict, setHasExternalConflict] = useState(false);
  const [errors, setErrors] = useState<Array<{ path: string; message: string }>>([]);
  const [loading, setLoading] = useState(false);

  const mountedRef = useRef(true);
  useEffect(() => () => { mountedRef.current = false; }, []);

  const loadFromDisk = useCallback(async () => {
    if (!api) return;
    setLoading(true);
    try {
      const result = await api.readRawConfig();
      if (!mountedRef.current) return;
      setRawYamlState(result.content);
      setSavedYaml(result.content);
      setIsDirty(false);
      setHasExternalConflict(false);
      setErrors([]);
    } finally {
      if (mountedRef.current) setLoading(false);
    }
  }, [api]);

  const saveAndRefresh = useCallback(async () => {
    if (!api) return;
    setLoading(true);
    try {
      const result: SaveConfigResult = await api.saveConfig({ content: rawYaml });
      if (!mountedRef.current) return;
      if (!result.success) {
        setErrors(result.errors ?? []);
        return;
      }
      setErrors([]);
      setSavedYaml(rawYaml);
      setIsDirty(false);
      setHasExternalConflict(false);
      await onSaveAndRefresh();
    } finally {
      if (mountedRef.current) setLoading(false);
    }
  }, [api, rawYaml, onSaveAndRefresh]);

  const setRawYaml = useCallback((yaml: string) => {
    setRawYamlState(yaml);
    setIsDirty(true);
    setErrors([]);
  }, []);

  const dismissConflict = useCallback(() => {
    setHasExternalConflict(false);
  }, []);

  // Initial load
  useEffect(() => {
    void loadFromDisk();
  }, [loadFromDisk]);

  // External change listener (fs.watch)
  useEffect(() => {
    if (!api?.onConfigChanged) return;
    return api.onConfigChanged(() => {
      if (isDirty) {
        setHasExternalConflict(true);
      } else {
        void loadFromDisk();
      }
    });
  }, [api, isDirty, loadFromDisk]);

  // Internal mutation listener (R14: right-click exclude etc.)
  // Unconditional reload — same app, user expects ConfigPanel to sync
  useEffect(() => {
    if (!api?.onConfigMutated) return;
    return api.onConfigMutated(() => {
      void loadFromDisk();
    });
  }, [api, loadFromDisk]);

  return {
    rawYaml,
    isDirty,
    hasExternalConflict,
    errors,
    loading,
    loadFromDisk,
    saveAndRefresh,
    setRawYaml,
    dismissConflict
  };
}
