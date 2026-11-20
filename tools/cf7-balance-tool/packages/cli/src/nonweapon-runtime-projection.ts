import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildNonWeaponRuntimeProjection,
  writeNonWeaponRuntimeProjection
} from "@cf7-balance-tool/xml-io";

const args = process.argv.slice(2);
let repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../../..");
let output: string | undefined;
let check = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--check") check = true;
  else if ((args[i] === "--repo-root" || args[i] === "--output") && args[i + 1]) {
    if (args[i] === "--repo-root") repoRoot = path.resolve(args[++i]!);
    else output = path.resolve(args[++i]!);
  } else throw new Error(`Unknown argument: ${args[i]}`);
}
if (!output) throw new Error("Usage: nonweapon-runtime-projection --output <dedicated directory> [--repo-root <repo>] [--check]");
const revision = execFileSync("git", ["-C", repoRoot, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
const projection = buildNonWeaponRuntimeProjection(repoRoot, revision);
writeNonWeaponRuntimeProjection(repoRoot, output, projection, check);
const manifestBytes = Buffer.byteLength(JSON.stringify(projection.manifest, null, 2) + "\n");
console.log(JSON.stringify({ mode: check ? "check" : "generate", sourceRevision: revision,
  output, inputBytes: projection.manifest.inputBytes, outputBytes: projection.manifest.outputBytes,
  netSavedXmlBytes: projection.manifest.netSavedBytes, manifestBytes,
  netSavedArtifactBytes: Number(projection.manifest.netSavedBytes) - manifestBytes,
  removedNodes: projection.manifest.removedNodes,
  itemCount: projection.manifest.itemCount, productionLoadingChanged: false }, null, 2));
