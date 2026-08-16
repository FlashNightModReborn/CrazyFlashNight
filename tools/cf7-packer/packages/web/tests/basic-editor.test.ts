/**
 * Basic editor coverage for path-level minify preservation rules.
 * @vitest-environment happy-dom
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { createElement } from "react";
import { parse as parseYaml } from "yaml";
import BasicEditor from "../src/renderer/components/BasicEditor.js";

const CONFIG_YAML = `
version: 1
meta:
  name: test
source:
  mode: worktree
  repoRoot: .
output:
  dir: ./out
  clean: true
  minify:
    enabled: true
    extensions: [".json", ".xml"]
    exclude:
      - "runtime/**"
layers:
  - name: all
    source: .
    include: ["**/*"]
    exclude: []
globalExclude: []
`;

afterEach(cleanup);

describe("BasicEditor minify preservation rules", () => {
  it("shows and edits minify.exclude without turning it into a package exclusion", () => {
    const onChange = vi.fn();
    render(createElement(BasicEditor, { rawYaml: CONFIG_YAML, onChange }));

    expect(screen.getByText("致密化字节保真")).toBeTruthy();
    expect(screen.getByText("runtime/**")).toBeTruthy();
    expect(screen.getByText(/仍会进入包，但不会改写原始字节/)).toBeTruthy();

    const input = screen.getByPlaceholderText("输入需保持原始字节的规则，例: runtime/**");
    fireEvent.change(input, { target: { value: "config/build/runtime-release-consensus.json" } });
    fireEvent.keyDown(input, { key: "Enter" });

    expect(onChange).toHaveBeenCalledTimes(1);
    const updated = parseYaml(onChange.mock.calls[0]![0] as string);
    expect(updated.output.minify.exclude).toEqual([
      "runtime/**",
      "config/build/runtime-release-consensus.json"
    ]);
  });
});
