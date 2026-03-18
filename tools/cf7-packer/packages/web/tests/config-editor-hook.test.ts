/**
 * Tests for useConfigEditor hook state machine.
 * @vitest-environment happy-dom
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useConfigEditor } from "../src/renderer/hooks/useConfigEditor.js";
import type { PackerIpcApi, RawConfigResult, SaveConfigResult, ConfigChangedEvent } from "../src/shared/ipc-types.js";

/** Creates a mock API with controllable config-changed / config-mutated event firing */
function createMockApi(initialYaml = "version: 1\n") {
  let changedCb: ((e: ConfigChangedEvent) => void) | null = null;
  let mutatedCb: ((e: ConfigChangedEvent) => void) | null = null;
  let readVersion = 0;
  let diskContent = initialYaml;

  const api: Pick<PackerIpcApi, "readRawConfig" | "saveConfig" | "onConfigChanged" | "onConfigMutated"> = {
    readRawConfig: vi.fn(async (): Promise<RawConfigResult> => ({
      content: diskContent,
      version: ++readVersion
    })),
    saveConfig: vi.fn(async ({ content }): Promise<SaveConfigResult> => {
      diskContent = content;
      return { success: true };
    }),
    onConfigChanged: vi.fn((cb) => {
      changedCb = cb;
      return () => { changedCb = null; };
    }),
    onConfigMutated: vi.fn((cb) => {
      mutatedCb = cb;
      return () => { mutatedCb = null; };
    })
  };

  return {
    api: api as unknown as PackerIpcApi,
    /** Simulate an external file change event */
    fireConfigChanged: () => changedCb?.({ version: ++readVersion }),
    /** Simulate an internal mutation event (e.g. right-click exclude) */
    fireConfigMutated: () => mutatedCb?.({ version: ++readVersion }),
    /** Update what readRawConfig will return next */
    setDiskContent: (content: string) => { diskContent = content; }
  };
}

describe("useConfigEditor", () => {
  let mock: ReturnType<typeof createMockApi>;
  const onSaveAndRefresh = vi.fn(async () => {});

  beforeEach(() => {
    mock = createMockApi("key: value\n");
    onSaveAndRefresh.mockClear();
  });

  it("loads from disk on mount, isDirty=false", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    // Wait for initial async loadFromDisk
    await act(async () => {});

    expect(result.current.rawYaml).toBe("key: value\n");
    expect(result.current.isDirty).toBe(false);
    expect(result.current.loading).toBe(false);
    expect(mock.api.readRawConfig).toHaveBeenCalledTimes(1);
  });

  it("marks dirty after editing", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});

    act(() => { result.current.setRawYaml("modified: true\n"); });

    expect(result.current.isDirty).toBe(true);
    expect(result.current.rawYaml).toBe("modified: true\n");
  });

  it("saveAndRefresh clears dirty and calls onSaveAndRefresh", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});

    act(() => { result.current.setRawYaml("new: content\n"); });
    expect(result.current.isDirty).toBe(true);

    await act(async () => { await result.current.saveAndRefresh(); });

    expect(result.current.isDirty).toBe(false);
    expect(mock.api.saveConfig).toHaveBeenCalledWith({ content: "new: content\n" });
    expect(onSaveAndRefresh).toHaveBeenCalledTimes(1);
  });

  it("saveAndRefresh shows errors on validation failure", async () => {
    (mock.api.saveConfig as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      success: false,
      errors: [{ path: "meta.name", message: "Required" }]
    });

    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});

    act(() => { result.current.setRawYaml("bad config"); });
    await act(async () => { await result.current.saveAndRefresh(); });

    expect(result.current.errors).toHaveLength(1);
    expect(result.current.errors[0]!.path).toBe("meta.name");
    expect(result.current.isDirty).toBe(true); // still dirty — save failed
    expect(onSaveAndRefresh).not.toHaveBeenCalled();
  });

  it("external change + no dirty → auto reload", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});
    expect(result.current.isDirty).toBe(false);

    mock.setDiskContent("externally: changed\n");
    await act(async () => { mock.fireConfigChanged(); });

    expect(result.current.rawYaml).toBe("externally: changed\n");
    expect(result.current.isDirty).toBe(false);
    expect(result.current.hasExternalConflict).toBe(false);
  });

  it("external change + dirty → conflict flag, no auto reload", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});

    act(() => { result.current.setRawYaml("local edits\n"); });
    expect(result.current.isDirty).toBe(true);

    const callsBefore = (mock.api.readRawConfig as ReturnType<typeof vi.fn>).mock.calls.length;
    act(() => { mock.fireConfigChanged(); });

    expect(result.current.hasExternalConflict).toBe(true);
    // Should NOT have reloaded from disk
    expect((mock.api.readRawConfig as ReturnType<typeof vi.fn>).mock.calls.length).toBe(callsBefore);
    // Local content preserved
    expect(result.current.rawYaml).toBe("local edits\n");
  });

  it("dismissConflict clears the conflict flag", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});

    act(() => { result.current.setRawYaml("local\n"); });
    act(() => { mock.fireConfigChanged(); });
    expect(result.current.hasExternalConflict).toBe(true);

    act(() => { result.current.dismissConflict(); });
    expect(result.current.hasExternalConflict).toBe(false);
    expect(result.current.rawYaml).toBe("local\n"); // preserved
  });

  it("R14: internal mutated event → unconditional reload even when dirty", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});

    act(() => { result.current.setRawYaml("user edits\n"); });
    expect(result.current.isDirty).toBe(true);

    mock.setDiskContent("after-exclude: true\n");
    await act(async () => { mock.fireConfigMutated(); });

    // Should have reloaded regardless of dirty state
    expect(result.current.rawYaml).toBe("after-exclude: true\n");
    expect(result.current.isDirty).toBe(false);
  });

  it("loadFromDisk resets all state", async () => {
    const { result } = renderHook(() =>
      useConfigEditor(mock.api, onSaveAndRefresh)
    );
    await act(async () => {});

    // Dirty it up
    act(() => { result.current.setRawYaml("dirty\n"); });

    // Force a conflict
    act(() => { mock.fireConfigChanged(); });
    expect(result.current.isDirty).toBe(true);
    expect(result.current.hasExternalConflict).toBe(true);

    mock.setDiskContent("fresh: content\n");
    await act(async () => { await result.current.loadFromDisk(); });

    expect(result.current.rawYaml).toBe("fresh: content\n");
    expect(result.current.isDirty).toBe(false);
    expect(result.current.hasExternalConflict).toBe(false);
    expect(result.current.errors).toHaveLength(0);
  });
});
