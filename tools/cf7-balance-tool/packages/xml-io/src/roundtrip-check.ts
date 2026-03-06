import fs from "node:fs";
import path from "node:path";

import { loadXmlDocument } from "./document.js";

export interface XmlRoundtripFailure {
  file: string;
  reason: string;
}

export interface XmlRoundtripReport {
  generatedAt: string;
  checkedFiles: number;
  passed: number;
  failed: number;
  failures: XmlRoundtripFailure[];
}

export function runXmlRoundtripCheck(filePaths: string[]): XmlRoundtripReport {
  const failures: XmlRoundtripFailure[] = [];
  let passed = 0;

  for (const inputFilePath of filePaths) {
    const filePath = path.resolve(inputFilePath);

    try {
      const originalSource = fs.readFileSync(filePath, "utf8");
      const document = loadXmlDocument(filePath);
      const serialized = document.serialize();

      if (serialized !== originalSource) {
        failures.push({
          file: filePath,
          reason: "Serialized XML differs from original source."
        });
        continue;
      }

      passed += 1;
    } catch (error) {
      failures.push({
        file: filePath,
        reason: error instanceof Error ? error.message : String(error)
      });
    }
  }

  return {
    generatedAt: new Date().toISOString(),
    checkedFiles: filePaths.length,
    passed,
    failed: failures.length,
    failures
  };
}