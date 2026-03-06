import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { applyXmlBatchUpdates, previewXmlBatchUpdates } from "../src/batch.js";
import { runXmlRoundtripCheck } from "../src/roundtrip-check.js";

const tempDirectories: string[] = [];

function createTempWorkspace(): string {
  const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-balance-tool-"));
  tempDirectories.push(tempDirectory);
  return tempDirectory;
}

afterEach(() => {
  for (const tempDirectory of tempDirectories.splice(0)) {
    fs.rmSync(tempDirectory, { recursive: true, force: true });
  }
});

describe("runXmlRoundtripCheck", () => {
  it("passes for valid XML files parsed by the current document object", () => {
    const workspace = createTempWorkspace();
    const filePath = path.join(workspace, "sample.xml");
    fs.writeFileSync(filePath, "<root><item><power>40</power></item></root>", "utf8");

    const report = runXmlRoundtripCheck([filePath]);

    expect(report.checkedFiles).toBe(1);
    expect(report.passed).toBe(1);
    expect(report.failed).toBe(0);
  });
});

describe("previewXmlBatchUpdates", () => {
  it("returns structured change records without mutating the source file", () => {
    const workspace = createTempWorkspace();
    const repoRoot = path.join(workspace, "repo");
    const sourceDir = path.join(repoRoot, "data", "items");
    const outputDir = path.join(workspace, "preview-output");
    const sourceFile = path.join(sourceDir, "sample.xml");

    fs.mkdirSync(sourceDir, { recursive: true });
    fs.writeFileSync(
      sourceFile,
      [
        "<root>",
        "  <item weaponType=\"old-type\">",
        "    <data>",
        "      <power>40</power>",
        "    </data>",
        "  </item>",
        "</root>"
      ].join("\n"),
      "utf8"
    );

    const result = previewXmlBatchUpdates(
      [
        {
          filePath: sourceFile,
          xmlPath: "root.item.data.power",
          value: "55"
        },
        {
          filePath: sourceFile,
          xmlPath: "root.item",
          attribute: "weaponType",
          value: "new-type"
        }
      ],
      {
        outputDir,
        baseDir: repoRoot
      }
    );

    expect(result.operations).toBe(2);
    expect(result.changedValues).toBe(2);
    expect(result.files[0]?.writeMode).toBe("mirrored-output");
    expect(result.files[0]?.outputFile).toBe(
      path.join(outputDir, "data", "items", "sample.xml")
    );
    expect(result.files[0]?.changes).toEqual([
      {
        xmlPath: "root.item.data.power",
        beforeValue: "40",
        afterValue: "55",
        sourceLine: 4,
        changed: true
      },
      {
        xmlPath: "root.item",
        attribute: "weaponType",
        beforeValue: "old-type",
        afterValue: "new-type",
        sourceLine: 2,
        changed: true
      }
    ]);
    expect(fs.readFileSync(sourceFile, "utf8")).toContain("<power>40</power>");
  });
});

describe("applyXmlBatchUpdates", () => {
  it("writes grouped updates to mirrored output files", () => {
    const workspace = createTempWorkspace();
    const repoRoot = path.join(workspace, "repo");
    const sourceDir = path.join(repoRoot, "data", "items");
    const outputDir = path.join(workspace, "output");
    const sourceFile = path.join(sourceDir, "sample.xml");

    fs.mkdirSync(sourceDir, { recursive: true });
    fs.writeFileSync(
      sourceFile,
      [
        "<root>",
        "  <item weaponType=\"old-type\">",
        "    <data>",
        "      <power>40</power>",
        "    </data>",
        "  </item>",
        "</root>"
      ].join("\n"),
      "utf8"
    );

    const result = applyXmlBatchUpdates(
      [
        {
          filePath: sourceFile,
          xmlPath: "root.item.data.power",
          value: "55"
        },
        {
          filePath: sourceFile,
          xmlPath: "root.item",
          attribute: "weaponType",
          value: "new-type"
        }
      ],
      {
        outputDir,
        baseDir: repoRoot
      }
    );

    const outputFile = path.join(outputDir, "data", "items", "sample.xml");
    const outputContent = fs.readFileSync(outputFile, "utf8");
    const sourceContent = fs.readFileSync(sourceFile, "utf8");

    expect(result.operations).toBe(2);
    expect(result.changedValues).toBe(2);
    expect(result.files[0]?.outputFile).toBe(outputFile);
    expect(result.files[0]?.changes[0]?.afterValue).toBe("55");
    expect(outputContent).toContain("<power>55</power>");
    expect(outputContent).toContain('weaponType="new-type"');
    expect(sourceContent).toContain("<power>40</power>");
  });
});