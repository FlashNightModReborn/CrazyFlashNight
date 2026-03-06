import { describe, expect, it } from "vitest";

import {
  buildBatchCommandTemplate,
  DEFAULT_OUTPUT_PATH_SETTINGS,
  OUTPUT_PATH_FIELDS,
  normalizeOutputPathSettings
} from "../src/shared/output-path-settings";

describe("normalizeOutputPathSettings", () => {
  it("fills missing values with defaults", () => {
    expect(normalizeOutputPathSettings()).toEqual(DEFAULT_OUTPUT_PATH_SETTINGS);
  });

  it("trims user input and normalizes separators", () => {
    expect(
      normalizeOutputPathSettings({
        generatedInputPath: "  custom\\payload.json  ",
        batchOutputDir: " out\\mirror "
      })
    ).toEqual({
      generatedInputPath: "custom/payload.json",
      previewReportPath: DEFAULT_OUTPUT_PATH_SETTINGS.previewReportPath,
      batchSetReportPath: DEFAULT_OUTPUT_PATH_SETTINGS.batchSetReportPath,
      batchOutputDir: "out/mirror"
    });
  });
});

describe("OUTPUT_PATH_FIELDS", () => {
  it("keeps a stable field order for the settings panel", () => {
    expect(OUTPUT_PATH_FIELDS.map((item) => item.key)).toEqual([
      "generatedInputPath",
      "previewReportPath",
      "batchSetReportPath",
      "batchOutputDir"
    ]);
  });
});

describe("buildBatchCommandTemplate", () => {
  it("uses the current output paths when building CLI examples", () => {
    expect(
      buildBatchCommandTemplate({
        generatedInputPath: "tmp/input.json",
        previewReportPath: "tmp/preview.json",
        batchSetReportPath: "tmp/apply.json",
        batchOutputDir: "tmp/output"
      })
    ).toContain("--output-dir tmp/output");
  });

  it("quotes paths that contain spaces", () => {
    expect(
      buildBatchCommandTemplate({
        generatedInputPath: "C:/Program Files/cf7/input.json",
        previewReportPath: "C:/Program Files/cf7/preview.json",
        batchSetReportPath: "C:/Program Files/cf7/apply.json",
        batchOutputDir: "C:/Program Files/cf7/output"
      })
    ).toContain('"C:/Program Files/cf7/output"');
  });
});

