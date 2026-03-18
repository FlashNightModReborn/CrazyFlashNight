/**
 * Tests for useAutoDetailTab — detail tab auto-switching logic.
 * @vitest-environment happy-dom
 */
import { describe, it, expect } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useAutoDetailTab } from "../src/renderer/hooks/useAutoDetailTab.js";

describe("useAutoDetailTab", () => {
  it("defaults to 'config' when no preview", () => {
    const { result } = renderHook(() => useAutoDetailTab(false));
    expect(result.current[0]).toBe("config");
  });

  it("auto-switches to 'tree' when preview first becomes available", () => {
    const { result, rerender } = renderHook(
      ({ hasPreview }) => useAutoDetailTab(hasPreview),
      { initialProps: { hasPreview: false } }
    );
    expect(result.current[0]).toBe("config");

    // Preview arrives
    rerender({ hasPreview: true });
    expect(result.current[0]).toBe("tree");
  });

  it("does NOT auto-switch a second time after preview reloads", () => {
    const { result, rerender } = renderHook(
      ({ hasPreview }) => useAutoDetailTab(hasPreview),
      { initialProps: { hasPreview: false } }
    );

    // First preview → switch to tree
    rerender({ hasPreview: true });
    expect(result.current[0]).toBe("tree");

    // User manually switches to diff
    act(() => { result.current[1]("diff"); });
    expect(result.current[0]).toBe("diff");

    // Preview reloads (e.g. fullReload clears then re-sets)
    rerender({ hasPreview: false });
    rerender({ hasPreview: true });

    // Should stay on diff — no second auto-switch
    expect(result.current[0]).toBe("diff");
  });

  it("respects manual tab changes", () => {
    const { result } = renderHook(() => useAutoDetailTab(false));
    expect(result.current[0]).toBe("config");

    act(() => { result.current[1]("diff"); });
    expect(result.current[0]).toBe("diff");
  });

  it("stays on config if preview never arrives", () => {
    const { result, rerender } = renderHook(
      ({ hasPreview }) => useAutoDetailTab(hasPreview),
      { initialProps: { hasPreview: false } }
    );

    // Multiple re-renders without preview
    rerender({ hasPreview: false });
    rerender({ hasPreview: false });
    expect(result.current[0]).toBe("config");
  });

  it("starts on 'tree' if preview is already available on mount", () => {
    const { result } = renderHook(() => useAutoDetailTab(true));
    // First render with hasPreview=true → auto-switch fires immediately
    expect(result.current[0]).toBe("tree");
  });
});
