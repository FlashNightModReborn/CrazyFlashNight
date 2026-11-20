import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { buildWeaponSummaryParityReport } from "@cf7-balance-tool/xml-io";

/** Offline only. An explicit destination avoids adding generated reports to production. */
export function runWeaponSummaryParity(args: string[]): void {
  const values = new Map<string, string>();
  let check = false;
  for (let index = 0; index < args.length; index++) {
    const key = args[index]!;
    if (key === "--check") { check = true; continue; }
    if (!["--repo", "--output"].includes(key) || !args[index + 1] || values.has(key)) {
      throw new Error("usage: weapon-summary-parity --repo <game-repo> --output <report.json> [--check]");
    }
    values.set(key, args[++index]!);
  }
  const repo = values.get("--repo");
  const output = values.get("--output");
  if (!repo || !output) throw new Error("--repo and --output are required");
  const report = buildWeaponSummaryParityReport(repo);
  const bytes = JSON.stringify(report, null, 2) + "\n";
  const destination = path.resolve(output);
  if (check) {
    if (!fs.existsSync(destination) || fs.readFileSync(destination, "utf8") !== bytes) {
      throw new Error(`parity report missing or stale: ${destination}`);
    }
  } else {
    if (!destination.endsWith(".json")) throw new Error("report output must end in .json");
    const relative = path.relative(path.resolve(repo), destination).split(path.sep).join("/");
    if (!(relative.startsWith("tmp/") || relative.startsWith("../"))) {
      throw new Error("report output must be outside the game repo or under its tmp directory");
    }
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, bytes, { flag: "w" });
  }
  process.stdout.write(JSON.stringify({ mode: check ? "check" : "write", ...report.summary }) + "\n");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { runWeaponSummaryParity(process.argv.slice(2)); }
  catch (error) { console.error(error instanceof Error ? error.message : String(error)); process.exitCode = 1; }
}
